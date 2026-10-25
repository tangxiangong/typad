//! Platform-independent document primitives. Typst compilation is a later milestone.
#![deny(missing_docs)]

/// Initial content for a new, unsaved Typst document.
pub const NEW_DOCUMENT: &str = "= Untitled\n\nStart writing with Typst.\n";

/// Number of editable lines, including the empty line after a trailing newline.
/// CRLF is counted as one line separator. An empty editor has one line.
pub fn line_count(source: &str) -> u64 {
    source.bytes().filter(|byte| *byte == b'\n').count() as u64 + 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_editor_has_one_line() {
        assert_eq!(line_count(""), 1);
    }

    #[test]
    fn trailing_crlf_preserves_final_empty_line() {
        assert_eq!(line_count("标题\r\n内容\r\n"), 3);
    }
}
