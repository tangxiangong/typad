import Foundation
import SwiftUI

/// Writing-oriented subset of Catppuccin Icons, pinned alongside the bundled license.
enum FileIconKind {
    private static func folderName(for name: String) -> String {
        switch name {
        case "asset", "assets": return "folder_assets"
        case "font", "fonts": return "folder_fonts"
        case "_images", "_image", "_imgs", "_img", "images", "image", "imgs", "img", "icons", "icon", "icos", "ico", "figures", "figure", "figs", "fig", "screenshot", "screenshots", "screengrab", "screengrabs", "pic", "pics", "picture", "pictures", "photo", "photos", "photograph", "photographs": return "folder_images"
        case "_post", "_posts", "doc", "docs", "document", "documents", "documentation", "post", "posts", "article", "articles": return "folder_docs"
        case "template", "templates": return "folder_templates"
        case "src", "srcs", "source", "sources", "code": return "folder_src"
        case "lib", "libs", "library", "libraries", ".lib", ".libs", ".library", ".libraries": return "folder_lib"
        case "cfg", "cfgs", "conf", "confs", ".config", "config", "configs", "configuration", "configurations", "setting", ".setting", "settings", ".settings", "meta-inf", "option", "options": return "folder_config"
        default: return "_folder"
        }
    }

    static func name(for url: URL, isDirectory: Bool = false, isExpanded: Bool = false, isRoot: Bool = false) -> String {
        if isDirectory {
            let base = isRoot ? "_root" : folderName(for: url.lastPathComponent.lowercased())
            return isExpanded ? base + "_open" : base
        }
        let filename = url.lastPathComponent.lowercased()
        if filename == "typst.toml" { return "typst" }
        if filename.hasSuffix(".xml.dist") || filename.hasSuffix(".xml.dist.sample") { return "xml" }
        switch url.pathExtension.lowercased() {
        case "typ": return "typst"
        case "lib", "bib", "bst": return "lib"
        case "pdf": return "pdf"
        case "png", "jpeg", "jpg", "gif", "ico", "tif", "tiff", "psb", "ami", "apx", "avif", "bmp", "bpg",
             "brk", "cur", "dds", "dng", "exr", "fpx", "gbr", "img", "jbig2", "jb2", "jng", "jxr", "pgf",
             "pic", "raw", "webp", "eps", "afphoto", "ase", "aseprite", "clip", "cpt", "heif", "heic",
             "kra", "mdp", "ora", "pdn", "reb", "sai", "tga", "xcf", "jfif", "ppm", "pbm", "pgm", "pnm",
             "icns": return "image"
        case "svg": return "svg"
        case "json", "jsonc", "tsbuildinfo", "json5", "jsonl", "ndjson", "hjson", "webmanifest": return "json"
        case "yml", "yaml": return "yaml"
        case "toml": return "toml"
        case "xml", "plist", "xsd", "dtd", "xsl", "xslt", "resx", "iml", "xquery", "tmlanguage", "manifest",
             "project", "dmn", "jrxml", "csl": return "xml"
        case "csv", "tsv", "psv": return "csv"
        case "woff", "woff2", "ttf", "eot", "suit", "otf", "bmap", "fnt", "odttf", "ttc", "font", "fonts",
             "sui", "ntf", "mrf": return "font"
        case "md", "markdown", "rst": return "markdown"
        case "txt": return "text"
        case "tex", "sty", "dtx", "ltx", "cls": return "latex"
        case "htm", "html", "xhtml", "html_vm", "asp": return "html"
        case "7z", "arj", "aseprite-extension", "bz", "bz2", "db", "gz", "paq8n", "paq8o", "pkg", "rar",
             "tar", "tbz", "tbz2", "tgz", "xz", "z", "zip", "zpaq", "zst": return "zip"
        default: return "_file"
        }
    }
}

struct FileIcon: View {
    let url: URL
    var isDirectory = false
    var isExpanded = false
    var isRoot = false

    var body: some View {
        Image("FileIcon-" + FileIconKind.name(for: url, isDirectory: isDirectory, isExpanded: isExpanded, isRoot: isRoot))
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}
