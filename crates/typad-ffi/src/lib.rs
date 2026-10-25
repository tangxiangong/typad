//! Thin Swift adapter; application behavior belongs in typad-service.
use typad_service::records::{CompileDiagnostic, CompileOutput, SourceSummary};

uniffi::setup_scaffolding!();

#[uniffi::remote(Record)]
struct SourceSummary {
    pub line_count: u64,
    pub scalar_count: u64,
}

/// Create a new document through the shared service.
#[uniffi::export]
pub fn new_document() -> String {
    typad_service::api::new_document()
}

/// Summarize an immutable source snapshot.
#[uniffi::export]
pub fn summarize_source(source: String) -> SourceSummary {
    typad_service::api::summarize_source(&source)
}

#[uniffi::remote(Record)]
struct CompileDiagnostic {
    pub warning: bool,
    pub message: String,
    pub file: Option<String>,
    pub line: Option<u64>,
    pub column: Option<u64>,
    pub utf16_offset: Option<u64>,
}

#[uniffi::remote(Record)]
struct CompileOutput {
    pub revision: u64,
    pub pdf: Option<Vec<u8>>,
    pub diagnostics: Vec<CompileDiagnostic>,
    pub elapsed_ms: u64,
    pub page_count: u64,
}

/// Compile a source snapshot without blocking the client's UI thread.
#[uniffi::export]
pub fn compile_document(source: String, path: Option<String>, revision: u64) -> CompileOutput {
    typad_service::api::compile_document(&source, path.as_deref(), revision)
}
