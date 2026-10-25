use typad_core::compiler::compile;

#[test]
fn unsaved_document_compiles_with_embedded_fonts_and_revision() {
    let result = compile("= Hello\n\nMath: $x^2$", None, 42);
    assert_eq!(result.revision, 42);
    assert_eq!(result.page_count, 1);
    assert!(
        result
            .pdf
            .as_ref()
            .is_some_and(|pdf| pdf.starts_with(b"%PDF-"))
    );
    assert!(!result.diagnostics.iter().any(|d| !d.warning));
}

#[test]
fn unicode_error_location_uses_utf16_offsets() {
    let source = "😀 中文 #unknown_name";
    let result = compile(source, None, 9);
    assert!(result.pdf.is_none());
    let error = result.diagnostics.iter().find(|d| !d.warning).unwrap();
    let byte_offset = source.find("unknown_name").unwrap();
    assert_eq!(error.line, Some(1));
    assert_eq!(
        error.column,
        Some(source[..byte_offset].chars().count() as u64 + 1)
    );
    assert_eq!(
        error.utf16_offset,
        Some(source[..byte_offset].encode_utf16().count() as u64)
    );
}

#[test]
fn current_source_overrides_disk_and_resources_refresh_between_compiles() {
    let dir = tempfile::tempdir().unwrap();
    let main = dir.path().join("main.typ");
    let child = dir.path().join("child.typ");
    std::fs::write(&main, "#invalid_disk_source").unwrap();
    std::fs::write(&child, "Included content").unwrap();
    let source = "#include \"child.typ\"";
    assert!(compile(source, Some(&main), 1).pdf.is_some());
    std::fs::write(&child, "#undefined_child").unwrap();
    let failed = compile(source, Some(&main), 2);
    assert!(failed.pdf.is_none());
    let error = failed.diagnostics.iter().find(|d| !d.warning).unwrap();
    assert_eq!(error.file.as_deref(), Some("child.typ"));
    assert_eq!(error.utf16_offset, None);
    std::fs::write(&child, "Repaired").unwrap();
    assert!(compile(source, Some(&main), 3).pdf.is_some());
}

#[test]
fn missing_resources_and_packages_report_actionable_errors() {
    let result = compile("#include \"child.typ\"", None, 0);
    assert!(
        result
            .diagnostics
            .iter()
            .any(|d| d.message.contains("Save the document"))
    );
    let result = compile("#import \"@preview/example:0.1.0\"", None, 0);
    assert!(
        result
            .diagnostics
            .iter()
            .any(|d| d.message.contains("Package imports are not supported"))
    );
}

#[test]
fn multiple_pages_and_empty_document_compile() {
    assert_eq!(compile("First#pagebreak()Second", None, 0).page_count, 2);
    assert!(compile("", None, 0).pdf.is_some());
}

#[cfg(unix)]
#[test]
fn symlink_cannot_escape_document_directory() {
    let dir = tempfile::tempdir().unwrap();
    let outside = tempfile::tempdir().unwrap();
    std::fs::write(outside.path().join("secret.typ"), "Private").unwrap();
    std::os::unix::fs::symlink(
        outside.path().join("secret.typ"),
        dir.path().join("link.typ"),
    )
    .unwrap();
    let result = compile(
        "#include \"link.typ\"",
        Some(&dir.path().join("main.typ")),
        0,
    );
    assert!(result.pdf.is_none());
    assert!(
        result
            .diagnostics
            .iter()
            .any(|d| d.message.contains("access denied"))
    );
}
