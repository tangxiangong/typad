//! Snapshot compilation with embedded fonts and project-local resources.
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::Instant;
use typst::diag::{FileError, FileResult, Severity, SourceDiagnostic};
use typst::foundations::{Bytes, Datetime, Duration};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World, WorldExt};
use typst_kit::{datetime::Time, fonts::FontStore};
use typst_layout::PagedDocument;

/// A compiler message with a one-based source location, when available.
#[derive(Debug, Clone)]
pub struct CompileDiagnostic {
    /// True for a non-fatal warning.
    pub warning: bool,
    /// Human-readable message and compiler hints.
    pub message: String,
    /// Project-relative source name.
    pub file: Option<String>,
    /// One-based line.
    pub line: Option<u64>,
    /// One-based Unicode scalar column.
    pub column: Option<u64>,
    /// UTF-16 offset in the main source; absent for other files.
    pub utf16_offset: Option<u64>,
}

/// PDF and diagnostics for precisely one source revision.
pub struct CompileOutput {
    /// Client-supplied revision, echoed without modification.
    pub revision: u64,
    /// PDF bytes, absent on failure.
    pub pdf: Option<Vec<u8>>,
    /// Errors and warnings, including PDF export errors.
    pub diagnostics: Vec<CompileDiagnostic>,
    /// Total compiler wall time in milliseconds.
    pub elapsed_ms: u64,
    /// Number of typeset pages on success.
    pub page_count: u64,
}

fn fonts() -> &'static FontStore {
    static FONTS: OnceLock<FontStore> = OnceLock::new();
    FONTS.get_or_init(|| {
        let mut store = FontStore::new();
        store.extend(typst_kit::fonts::embedded());
        store.extend(typst_kit::fonts::system());
        store
    })
}

struct SnapshotWorld {
    library: LazyHash<Library>,
    main: Source,
    root: Option<PathBuf>,
    files: Mutex<HashMap<FileId, FileResult<Bytes>>>,
    time: Time,
}

impl SnapshotWorld {
    fn new(source: &str, path: Option<&Path>) -> Result<Self, String> {
        let (root, name) = match path {
            Some(path) if path.is_absolute() => {
                let parent = path.parent().ok_or("Document has no parent directory")?;
                let root = parent.canonicalize().map_err(|err| err.to_string())?;
                let name = path
                    .file_name()
                    .and_then(|s| s.to_str())
                    .ok_or("Invalid document name")?;
                (Some(root), name)
            }
            Some(_) => return Err("Document path must be absolute".into()),
            None => (None, "untitled.typ"),
        };
        let vpath = VirtualPath::new(name).map_err(|err| err.to_string())?;
        let id = RootedPath::new(VirtualRoot::Project, vpath).intern();
        Ok(Self {
            library: LazyHash::new(Library::default()),
            main: Source::new(id, source.into()),
            root,
            files: Mutex::new(HashMap::new()),
            time: Time::system(),
        })
    }

    fn read(&self, id: FileId) -> FileResult<Bytes> {
        if !matches!(id.root(), VirtualRoot::Project) {
            return Err(FileError::Other(Some(
                "Package imports are not supported yet".into(),
            )));
        }
        let root = self.root.as_ref().ok_or_else(|| {
            FileError::Other(Some(
                "Save the document before using local resources".into(),
            ))
        })?;
        let path = id.vpath().realize(root).map_err(FileError::Realize)?;
        let canonical = path
            .canonicalize()
            .map_err(|err| FileError::from_io(err, &path))?;
        if !canonical.starts_with(root) {
            return Err(FileError::AccessDenied);
        }
        std::fs::read(&canonical)
            .map(Bytes::new)
            .map_err(|err| FileError::from_io(err, &path))
    }
}

impl World for SnapshotWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }
    fn book(&self) -> &LazyHash<FontBook> {
        fonts().book()
    }
    fn main(&self) -> FileId {
        self.main.id()
    }
    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == self.main.id() {
            return Ok(self.main.clone());
        }
        let bytes = self.file(id)?;
        let text = std::str::from_utf8(&bytes).map_err(|_| FileError::InvalidUtf8)?;
        Ok(Source::new(id, text.trim_start_matches('\u{feff}').into()))
    }
    fn file(&self, id: FileId) -> FileResult<Bytes> {
        if id == self.main.id() {
            return Ok(Bytes::new(self.main.text().as_bytes().to_vec()));
        }
        let mut files = self
            .files
            .lock()
            .map_err(|_| FileError::Other(Some("Resource cache unavailable".into())))?;
        files.entry(id).or_insert_with(|| self.read(id)).clone()
    }
    fn font(&self, index: usize) -> Option<Font> {
        fonts().font(index)
    }
    fn today(&self, offset: Option<Duration>) -> Option<Datetime> {
        self.time.today(offset)
    }
}

/// Compile unsaved main-source text, resolving local resources relative to its saved path.
/// Unsaved documents can compile standalone content. Package downloads are not performed.
pub fn compile(source: &str, path: Option<&Path>, revision: u64) -> CompileOutput {
    let started = Instant::now();
    let mut result = CompileOutput {
        revision,
        pdf: None,
        diagnostics: Vec::new(),
        elapsed_ms: 0,
        page_count: 0,
    };
    match SnapshotWorld::new(source, path) {
        Ok(world) => {
            return compile_world(&world, revision);
        }
        Err(message) => result.diagnostics.push(CompileDiagnostic {
            warning: false,
            message,
            file: None,
            line: None,
            column: None,
            utf16_offset: None,
        }),
    }
    result.elapsed_ms = started.elapsed().as_millis() as u64;
    result
}

fn diagnostic(world: &dyn World, diagnostic: SourceDiagnostic) -> CompileDiagnostic {
    let id = diagnostic.span.id();
    let source = id.and_then(|id| world.source(id).ok());
    let offset = world.range(diagnostic.span).map(|range| range.start);
    let location = source
        .as_ref()
        .zip(offset)
        .and_then(|(source, offset)| source.lines().byte_to_line_column(offset));
    let utf16_offset = source
        .as_ref()
        .filter(|source| source.id() == world.main())
        .zip(offset)
        .and_then(|(source, offset)| source.lines().byte_to_utf16(offset));
    let mut message = diagnostic.message.to_string();
    for hint in diagnostic.hints {
        message.push_str("\nHint: ");
        message.push_str(&hint.v);
    }
    CompileDiagnostic {
        warning: diagnostic.severity == Severity::Warning,
        message,
        file: id.map(|id| id.vpath().get_without_slash().to_owned()),
        line: location.map(|(line, _)| line as u64 + 1),
        column: location.map(|(_, column)| column as u64 + 1),
        utf16_offset: utf16_offset.map(|offset| offset as u64),
    }
}

/// Compile a world owned by the caller, allowing Tinymist analysis to share its snapshot.
pub fn compile_world(world: &dyn World, revision: u64) -> CompileOutput {
    let started = Instant::now();
    let mut result = CompileOutput {
        revision,
        pdf: None,
        diagnostics: Vec::new(),
        elapsed_ms: 0,
        page_count: 0,
    };
    let compiled = typst::compile::<PagedDocument>(world);
    result
        .diagnostics
        .extend(compiled.warnings.into_iter().map(|d| diagnostic(world, d)));
    let output = compiled.output.and_then(|document| {
        let pdf = typst_pdf::pdf(&document, &typst_pdf::PdfOptions::default())?;
        Ok((pdf, document.pages().len() as u64))
    });
    match output {
        Ok((pdf, pages)) => {
            result.pdf = Some(pdf);
            result.page_count = pages;
        }
        Err(errors) => result
            .diagnostics
            .extend(errors.into_iter().map(|d| diagnostic(world, d))),
    }
    result.elapsed_ms = started.elapsed().as_millis() as u64;
    result
}
