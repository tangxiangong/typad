//! Snapshot compilation with embedded fonts and project-local resources.
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Instant;
use typst::diag::{FileError, FileResult, Severity, SourceDiagnostic};
use typst::foundations::{Bytes, Datetime, Duration};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World, WorldExt};
use typst_kit::{
    datetime::Time,
    fonts::{FontPath, FontStore},
};
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

static FONTS: OnceLock<FontStore> = OnceLock::new();

/// Initialize the snapshot compiler with fonts discovered by the native platform.
/// Call before the first compilation; subsequent calls keep the existing store.
pub fn initialize_fonts(paths: &[String]) {
    FONTS.get_or_init(|| {
        let mut store = FontStore::new();
        store.extend(typst_kit::fonts::embedded());
        for path in paths {
            let Ok(data) = std::fs::read(path) else {
                continue;
            };
            for font in Font::iter(Bytes::new(data)) {
                if !has_drawable_glyph_data(&font) {
                    continue;
                }
                store.push((
                    FontPath {
                        path: PathBuf::from(path),
                        index: font.index(),
                    },
                    font.info().clone(),
                ));
            }
        }
        store
    });
}

// Some Apple fonts expose a cmap and metrics but use proprietary `hvgl` outlines.
// Accepting them produces invisible Type 3 glyphs instead of usable PDF text.
fn has_drawable_glyph_data(font: &Font) -> bool {
    // Inspect the already-parsed SFNT directory without instantiating/caching every system font.
    let data = font.data();
    let u32_at = |offset: usize| -> Option<u32> {
        Some(u32::from_be_bytes(
            data.get(offset..offset + 4)?.try_into().ok()?,
        ))
    };
    let offset = if data.starts_with(b"ttcf") {
        let Some(offset) = u32_at(12 + font.index() as usize * 4) else {
            return false;
        };
        offset as usize
    } else {
        0
    };
    let Some(count) = data.get(offset + 4..offset + 6) else {
        return false;
    };
    let count = u16::from_be_bytes([count[0], count[1]]) as usize;
    (0..count).any(|index| {
        let record = offset + 12 + index * 16;
        matches!(
            data.get(record..record + 4),
            Some(
                b"glyf"
                    | b"CFF "
                    | b"CFF2"
                    | b"sbix"
                    | b"CBDT"
                    | b"bdat"
                    | b"EBDT"
                    | b"COLR"
                    | b"SVG "
            )
        ) && u32_at(record + 12).is_some_and(|length| length > 0)
    })
}

fn fonts() -> &'static FontStore {
    FONTS.get_or_init(|| {
        let mut store = FontStore::new();
        store.extend(typst_kit::fonts::embedded());
        store.extend(typst_kit::fonts::system());
        store
    })
}

/// Native file-provider reads, called only for validated project-local resources.
pub type ResourceReader = dyn Fn(&Path) -> Result<Vec<u8>, String> + Send + Sync;

struct SnapshotWorld {
    reader: Option<Arc<ResourceReader>>,
    library: LazyHash<Library>,
    main: Source,
    root: Option<PathBuf>,
    files: Mutex<HashMap<FileId, FileResult<Bytes>>>,
    time: Time,
}

impl SnapshotWorld {
    #[cfg(test)]
    fn new(source: &str, path: Option<&Path>) -> Result<Self, String> {
        Self::project(source, path, None, &HashMap::new())
    }

    fn project(
        source: &str,
        path: Option<&Path>,
        project_root: Option<&Path>,
        snapshots: &HashMap<String, String>,
    ) -> Result<Self, String> {
        let root = match project_root.or_else(|| path.and_then(Path::parent)) {
            Some(root) if root.is_absolute() => {
                Some(root.canonicalize().map_err(|err| err.to_string())?)
            }
            Some(_) => return Err("Project root must be absolute".into()),
            None => None,
        };
        let relative = |path: &Path| -> Result<PathBuf, String> {
            if !path.is_absolute()
                || path
                    .components()
                    .any(|part| matches!(part, std::path::Component::ParentDir))
            {
                return Err("Snapshot path must be absolute and inside the project".into());
            }
            let canonical = if path.exists() {
                path.canonicalize().map_err(|err| err.to_string())?
            } else {
                path.parent()
                    .ok_or("Snapshot has no parent")?
                    .canonicalize()
                    .map_err(|err| err.to_string())?
                    .join(path.file_name().ok_or("Snapshot has no filename")?)
            };
            canonical
                .strip_prefix(root.as_ref().ok_or("Snapshot requires a project root")?)
                .map(Path::to_path_buf)
                .map_err(|_| "Snapshot is outside the project".into())
        };
        let name = match path {
            Some(path) => relative(path)?,
            None => PathBuf::from("untitled.typ"),
        };
        let vpath = VirtualPath::new(name.to_str().ok_or("Invalid snapshot filename")?)
            .map_err(|err| err.to_string())?;
        let mut files = HashMap::new();
        for (path, source) in snapshots {
            let name = relative(Path::new(path))?;
            let vpath = VirtualPath::new(name.to_str().ok_or("Invalid snapshot filename")?)
                .map_err(|err| err.to_string())?;
            let id = RootedPath::new(VirtualRoot::Project, vpath).intern();
            files.insert(id, Ok(Bytes::new(source.as_bytes().to_vec())));
        }
        let id = RootedPath::new(VirtualRoot::Project, vpath).intern();
        Ok(Self {
            reader: None,
            library: LazyHash::new(Library::default()),
            main: Source::new(id, source.into()),
            root,
            files: Mutex::new(files),
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
        if let Some(reader) = &self.reader {
            return reader(&canonical)
                .map(Bytes::new)
                .map_err(|message| FileError::Other(Some(message.into())));
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
    compile_project(source, path, None, &HashMap::new(), revision)
}

/// Compile immutable open buffers within an explicit project root.
pub fn compile_project(
    source: &str,
    path: Option<&Path>,
    root: Option<&Path>,
    snapshots: &HashMap<String, String>,
    revision: u64,
) -> CompileOutput {
    compile_project_with_reader(source, path, root, snapshots, revision, None)
}

/// Compile with a native coordinator for disk resources not supplied as open buffers.
pub fn compile_project_with_reader(
    source: &str,
    path: Option<&Path>,
    root: Option<&Path>,
    snapshots: &HashMap<String, String>,
    revision: u64,
    reader: Option<Arc<ResourceReader>>,
) -> CompileOutput {
    let started = Instant::now();
    let mut result = CompileOutput {
        revision,
        pdf: None,
        diagnostics: Vec::new(),
        elapsed_ms: 0,
        page_count: 0,
    };
    match SnapshotWorld::project(source, path, root, snapshots) {
        Ok(mut world) => {
            world.reader = reader;
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

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;
    use typst::layout::{Frame, FrameItem};
    use typst::text::TextItem;

    #[test]
    fn project_snapshot_overrides_disk_and_does_not_leak_between_compiles() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir(root.join("src")).unwrap();
        let main = root.join("src/main.typ");
        let child = root.join("child.typ");
        std::fs::write(&main, "").unwrap();
        std::fs::write(&child, "#let broken =").unwrap();
        let files = HashMap::from([(
            child.to_string_lossy().into_owned(),
            "Snapshot child".into(),
        )]);
        let output = compile_project(
            "#include \"/child.typ\"",
            Some(&main),
            Some(root),
            &files,
            7,
        );
        assert!(output.pdf.is_some(), "{:?}", output.diagnostics);
        let output = compile_project(
            "#include \"/child.typ\"",
            Some(&main),
            Some(root),
            &HashMap::new(),
            8,
        );
        assert!(output.pdf.is_none());
    }

    #[test]
    fn native_reader_supplies_unopened_resources_and_reports_read_errors() {
        let dir = tempfile::tempdir().unwrap();
        let main = dir.path().join("main.typ");
        let child = dir.path().join("child.typ");
        std::fs::write(&main, "").unwrap();
        std::fs::write(&child, "#let invalid =").unwrap();
        let reader: Arc<ResourceReader> = Arc::new(move |path| {
            assert_eq!(path.file_name().unwrap(), "child.typ");
            Ok(b"Native coordinated contents".to_vec())
        });
        let result = compile_project_with_reader(
            "#include \"child.typ\"",
            Some(&main),
            Some(dir.path()),
            &HashMap::new(),
            0,
            Some(reader),
        );
        assert!(result.pdf.is_some(), "{:?}", result.diagnostics);
        let result = compile_project_with_reader(
            "#include \"child.typ\"",
            Some(&main),
            Some(dir.path()),
            &HashMap::new(),
            0,
            Some(Arc::new(|_| Err("Provider refused access".into()))),
        );
        assert!(
            result
                .diagnostics
                .iter()
                .any(|item| item.message.contains("Provider refused access"))
        );
    }

    #[test]
    fn project_snapshots_reject_outside_and_traversal_paths() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        let main = root.join("main.typ");
        std::fs::write(&main, "").unwrap();
        for path in [
            root.join("../escape.typ"),
            PathBuf::from("relative.typ"),
            std::env::temp_dir().join("outside.typ"),
        ] {
            let files = HashMap::from([(path.to_string_lossy().into_owned(), "forbidden".into())]);
            assert!(
                compile_project("Hello", Some(&main), Some(root), &files, 0)
                    .pdf
                    .is_none()
            );
        }
    }

    fn text_items(frame: &Frame) -> Vec<&TextItem> {
        let mut items = Vec::new();
        for (_, item) in frame.items() {
            match item {
                FrameItem::Text(text) => items.push(text),
                FrameItem::Group(group) => items.extend(text_items(&group.frame)),
                _ => {}
            }
        }
        items
    }

    #[test]
    fn bundled_chinese_fonts_have_real_outlines_and_metrics_only_fonts_are_rejected() {
        let sources: [&[u8]; 2] = [
            include_bytes!("../../../ipad/Resources/Fonts/NotoSansSC-Regular.otf"),
            include_bytes!("../../../ipad/Resources/Fonts/NotoSansSC-Bold.otf"),
        ];
        for data in sources {
            let font = Font::new(Bytes::new(data.to_vec()), 0).unwrap();
            assert!(has_drawable_glyph_data(&font));
            let instance = font.clone().instantiate(
                Default::default(),
                typst::layout::Abs::pt(12.0),
                &Default::default(),
            );
            for ch in "中文简体繁體身上".chars() {
                let glyph = instance.ttf().glyph_index(ch).unwrap();
                assert!(
                    instance.ttf().glyph_bounding_box(glyph).is_some(),
                    "No outline for {ch}"
                );
            }
            let mut metrics_only = data.to_vec();
            let count = u16::from_be_bytes([data[4], data[5]]) as usize;
            for index in 0..count {
                let offset = 12 + 16 * index;
                if &metrics_only[offset..offset + 4] == b"CFF " {
                    metrics_only[offset..offset + 4].copy_from_slice(b"hvgl");
                }
            }
            let font = Font::new(Bytes::new(metrics_only), 0).unwrap();
            assert!(
                !has_drawable_glyph_data(&font),
                "Metrics without supported outlines must not win font fallback"
            );
        }
    }

    #[test]
    fn native_font_files_render_chinese_heading_without_missing_glyphs() {
        let paths = typst_kit::fonts::system()
            .map(|(path, _)| path.path.to_string_lossy().into_owned())
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        assert!(!paths.is_empty());
        initialize_fonts(&paths);
        let world = SnapshotWorld::new("= 身上\n\n中文 English $x^2$", None).unwrap();
        let document = typst::compile::<PagedDocument>(&world).output.unwrap();
        let items = text_items(&document.pages()[0].frame);
        assert!(items.iter().any(|item| item.text.contains('身')));
        for item in &items {
            assert!(
                item.glyphs.iter().all(|glyph| glyph.id != 0),
                "missing glyph in {:?}",
                item.text
            );
        }
        let heading = items.iter().find(|item| item.text.contains('身')).unwrap();
        let body = items.iter().find(|item| item.text.contains('中')).unwrap();
        assert!(
            heading.size > body.size,
            "heading must be larger than body text"
        );
        assert!(!items.iter().any(|item| item.text.contains('=')));

        let literal = SnapshotWorld::new("=身上", None).unwrap();
        let document = typst::compile::<PagedDocument>(&literal).output.unwrap();
        assert!(
            text_items(&document.pages()[0].frame)
                .iter()
                .any(|item| item.text.contains('='))
        );
    }
}
