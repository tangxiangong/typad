//! Values shared by native clients.

/// Source metrics, not typeset document statistics.
pub struct SourceSummary {
    /// Editable lines, including an empty final line.
    pub line_count: u64,
    /// Unicode scalar count; not grapheme clusters or UTF-16 offsets.
    pub scalar_count: u64,
}

/// Shared compiler result and diagnostic records.
pub use typad_core::compiler::{CompileDiagnostic, CompileOutput};
