//! Stateless document operations.
use crate::records::SourceSummary;

/// Create the initial source for a new document.
pub fn new_document() -> String {
    typad_core::NEW_DOCUMENT.to_owned()
}

/// Inspect a source snapshot without IO or mutable global state.
pub fn summarize_source(source: &str) -> SourceSummary {
    SourceSummary {
        line_count: typad_core::line_count(source),
        scalar_count: source.chars().count() as u64,
    }
}

/// Compile the current main-source snapshot; path is absent for an unsaved document.
pub fn compile_document(
    source: &str,
    path: Option<&str>,
    revision: u64,
) -> crate::records::CompileOutput {
    typad_core::compiler::compile(source, path.map(std::path::Path::new), revision)
}

/// Supply native platform font files before the first snapshot compilation.
pub fn initialize_fonts(paths: &[String]) {
    typad_core::compiler::initialize_fonts(paths);
}

/// Compile with native file-provider access for each on-disk dependency.
pub fn compile_project(
    source: &str,
    path: &str,
    root: &str,
    files: &std::collections::HashMap<String, String>,
    revision: u64,
    reader: std::sync::Arc<typad_core::compiler::ResourceReader>,
) -> crate::records::CompileOutput {
    typad_core::compiler::compile_project_with_reader(
        source,
        Some(std::path::Path::new(path)),
        Some(std::path::Path::new(root)),
        files,
        revision,
        Some(reader),
    )
}
