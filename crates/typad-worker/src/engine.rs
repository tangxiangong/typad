use crate::Request;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use lsp_types::{HoverContents, MarkedString};
use serde_json::{Value, json};
use std::path::PathBuf;
use tinymist_project::{LspUniverse, WorldProvider};
use tinymist_query::{
    CompletionRequest, HoverRequest, PositionEncoding, SemanticRequest, analysis::Analysis,
};
use tinymist_world::{ShadowApi, args::CompileOnceArgs};
use typst::{World, foundations::Bytes, syntax::Source};

#[derive(Default)]
pub(super) struct Engine {
    universe: Option<(PathBuf, LspUniverse)>,
    analysis: Analysis,
}

impl Engine {
    pub fn execute(&mut self, request: &Request) -> Result<Value, String> {
        let path = request
            .path
            .as_ref()
            .map(PathBuf::from)
            .unwrap_or_else(|| std::env::temp_dir().join("typad-unsaved/untitled.typ"));
        if !path.is_absolute() {
            return Err("Document path must be absolute".into());
        }
        if self.universe.as_ref().is_none_or(|(old, _)| old != &path) {
            let args = CompileOnceArgs {
                input: Some(path.to_string_lossy().into_owned()),
                root: path.parent().map(PathBuf::from),
                ..Default::default()
            };
            self.universe = Some((path.clone(), args.resolve().map_err(|e| e.to_string())?));
            self.analysis = Analysis {
                position_encoding: PositionEncoding::Utf16,
                ..Default::default()
            };
        }
        let (_, universe) = self
            .universe
            .as_mut()
            .ok_or("Missing document environment")?;
        universe.reset();
        universe
            .map_shadow(&path, Bytes::new(request.source.as_bytes().to_vec()))
            .map_err(|e| e.to_string())?;
        let graph = universe.computation();
        let world = graph.world();
        let source = world.source(world.main()).map_err(|e| e.to_string())?;
        if request.operation == "compile" {
            let compiled = typad_core::compiler::compile_world(world, request.revision);
            return Ok(json!({"pdf":compiled.pdf.map(|pdf| STANDARD.encode(pdf)),
                "pageCount":compiled.page_count,"elapsedMs":compiled.elapsed_ms,
                "diagnostics":compiled.diagnostics.iter().map(|d| json!({
                    "warning":d.warning,"message":d.message,"file":d.file,"line":d.line,
                    "column":d.column,"utf16Offset":d.utf16_offset
                })).collect::<Vec<_>>() }));
        }
        let byte = source
            .lines()
            .utf16_to_byte(request.offset)
            .ok_or("Invalid UTF-16 cursor")?;
        if !source.text().is_char_boundary(byte) {
            return Err("Cursor splits a Unicode scalar".into());
        }
        let position = tinymist_query::to_lsp_position(byte, PositionEncoding::Utf16, &source);
        let mut context = self.analysis.enter(graph);
        match request.operation.as_str() {
            "complete" => {
                let result = CompletionRequest {
                    path,
                    position,
                    explicit: true,
                    trigger_character: None,
                }
                .request(&mut context);
                // CompletionRequest returns candidates; an LSP client normally filters them.
                // Filter before the response cap so a typed prefix cannot lose its matches.
                let prefix: String = source.text()[..byte]
                    .chars()
                    .rev()
                    .take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '-')
                    .collect::<String>()
                    .chars()
                    .rev()
                    .collect();
                let prefix = prefix.to_lowercase();
                let items = result.into_iter().flat_map(|list| list.items).filter_map(|item| {
                    let item: lsp_types::CompletionItem = serde_json::from_value(serde_json::to_value(item).ok()?).ok()?;
                    if !item.filter_text.as_deref().unwrap_or(&item.label).to_lowercase().starts_with(&prefix) {
                        return None;
                    }
                    let (range, text) = match item.text_edit {
                        Some(lsp_types::CompletionTextEdit::Edit(edit)) => (edit.range, edit.new_text),
                        Some(lsp_types::CompletionTextEdit::InsertAndReplace(edit)) => (edit.replace, edit.new_text),
                        None => (lsp_types::Range::new(position,position), item.insert_text.unwrap_or_else(|| item.label.clone())),
                    };
                    let text = if item.insert_text_format == Some(lsp_types::InsertTextFormat::SNIPPET) {
                        plain_snippet(&text)?
                    } else { text.to_string() };
                    let mut edits = vec![edit_value(&source, range, text)?];
                    for edit in item.additional_text_edits.unwrap_or_default() {
                        edits.push(edit_value(&source, edit.range, edit.new_text.to_string())?);
                    }
                    Some(json!({"label":item.label,"detail":item.detail.unwrap_or_default(),"edits":edits}))
                }).take(100).collect::<Vec<_>>();
                Ok(json!({"completions":items}))
            }
            "hover" => {
                let result = HoverRequest { path, position }.request(&mut context);
                let text = result
                    .map(|hover| match hover.contents {
                        HoverContents::Markup(content) => content.value,
                        HoverContents::Scalar(value) => marked(value),
                        HoverContents::Array(values) => values
                            .into_iter()
                            .map(marked)
                            .collect::<Vec<_>>()
                            .join("\n\n"),
                    })
                    .unwrap_or_default();
                Ok(json!({"documentation":text}))
            }
            _ => Err("Unknown worker operation".into()),
        }
    }
}

fn marked(value: MarkedString) -> String {
    match value {
        MarkedString::String(value) => value,
        MarkedString::LanguageString(value) => value.value,
    }
}

fn edit_value(source: &Source, range: lsp_types::Range, text: String) -> Option<Value> {
    let range = tinymist_query::to_typst_range(range, PositionEncoding::Utf16, source)?;
    let start = source.lines().byte_to_utf16(range.start)?;
    let end = source.lines().byte_to_utf16(range.end)?;
    Some(json!({"start":start,"length":end.checked_sub(start)?,"text":text}))
}

// Native editor inserts plain text. Expand numbered placeholders; reject variables,
// choices and transforms rather than silently inserting invalid Typst source.
fn plain_snippet(input: &str) -> Option<String> {
    let mut out = String::new();
    let mut chars = input.chars().peekable();
    while let Some(ch) = chars.next() {
        match ch {
            '\\' => out.push(chars.next()?),
            '$' => {
                if chars.peek()?.is_ascii_digit() {
                    while chars.peek().is_some_and(char::is_ascii_digit) {
                        chars.next();
                    }
                } else if chars.next()? == '{' {
                    let mut digits = 0;
                    while chars.peek().is_some_and(char::is_ascii_digit) {
                        chars.next();
                        digits += 1;
                    }
                    if digits == 0 {
                        return None;
                    }
                    match chars.next()? {
                        '}' => {}
                        ':' => {
                            let mut default = String::new();
                            let mut depth = 1;
                            loop {
                                match chars.next()? {
                                    '{' => {
                                        depth += 1;
                                        default.push('{');
                                    }
                                    '}' => {
                                        depth -= 1;
                                        if depth == 0 {
                                            break;
                                        }
                                        default.push('}');
                                    }
                                    c => default.push(c),
                                }
                            }
                            out.push_str(&plain_snippet(&default)?);
                        }
                        _ => return None,
                    }
                } else {
                    return None;
                }
            }
            c => out.push(c),
        }
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn expands_placeholders_without_inserting_snippet_markup() {
        assert_eq!(
            plain_snippet("text(${1:hello})$0"),
            Some("text(hello)".into())
        );
        assert_eq!(plain_snippet("${TM_FILENAME}"), None);
        assert_eq!(plain_snippet("${1|a,b|}"), None);
    }
}
