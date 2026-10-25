//! Thin Swift adapter; application behavior belongs in typad-service.
use typad_service::records::SourceSummary;

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
