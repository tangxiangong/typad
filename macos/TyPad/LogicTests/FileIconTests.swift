import Foundation

@main
struct FileIconTests {
    static func main() throws {
        let fixtures: [(String, String)] = [
            ("main.typ", "typst"), ("MAIN.TYP", "typst"), ("typst.toml", "typst"),
            ("settings.toml", "toml"), ("references.bib", "lib"), ("style.bst", "lib"),
            ("style.csl", "xml"), ("document.cls", "latex"), ("main.tex", "latex"),
            ("output.pdf", "pdf"), ("photo.HEIC", "image"), ("plot.svg", "svg"),
            ("data.json", "json"), ("references.yml", "yaml"), ("data.tsv", "csv"),
            ("font.woff2", "font"), ("notes.md", "markdown"), ("notes.txt", "text"),
            ("index.html", "html"), ("archive.zip", "zip"), ("unknown.xyz", "_file"),
            ("LICENSE", "_file"), ("grammar.tmLanguage", "xml"), ("settings.XML.DIST.SAMPLE", "xml")
        ]
        for (filename, expected) in fixtures {
            precondition(FileIconKind.name(for: URL(fileURLWithPath: filename)) == expected, filename)
        }
        precondition(FileIconKind.name(for: URL(fileURLWithPath: "folder.typ"), isDirectory: true) == "_folder")
        let folder = URL(fileURLWithPath: "folder.typ")
        precondition(FileIconKind.name(for: folder, isDirectory: true, isExpanded: true) == "_folder_open")
        precondition(FileIconKind.name(for: folder, isDirectory: true, isRoot: true) == "_root")
        precondition(FileIconKind.name(for: folder, isDirectory: true, isExpanded: true, isRoot: true) == "_root_open")
        let folders = ["asset": "assets", "assets": "assets", "ASSETS": "assets", "images": "images",
                       "figures": "images", "font": "fonts", "docs": "docs", "templates": "templates",
                       "src": "src", "config": "config", "lib": "lib"]
        for (name, icon) in folders {
            let url = URL(fileURLWithPath: name)
            precondition(FileIconKind.name(for: url, isDirectory: true) == "folder_" + icon)
            precondition(FileIconKind.name(for: url, isDirectory: true, isExpanded: true) == "folder_" + icon + "_open")
            precondition(FileIconKind.name(for: url) == "_file", "Folder-name rules must not apply to files")
            precondition(FileIconKind.name(for: url, isDirectory: true, isRoot: true) == "_root")
        }
        let folderAssets = Set(folders.values).flatMap { ["folder_" + $0, "folder_" + $0 + "_open"] }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let assets = root.appendingPathComponent("macos/TyPad/Resources/Assets.xcassets/FileIcons")
        for name in Set(fixtures.map(\.1) + ["_folder", "_folder_open", "_root", "_root_open"] + folderAssets) {
            let directory = assets.appendingPathComponent("FileIcon-\(name).imageset")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
            let images = catalog["images"] as! [[String: Any]]
            precondition(images.count == 2)
            precondition(images[0]["filename"] as? String == "latte.svg")
            precondition(images[1]["filename"] as? String == "mocha.svg")
            let appearance = images[1]["appearances"] as! [[String: String]]
            precondition(appearance == [["appearance": "luminosity", "value": "dark"]])
            let properties = catalog["properties"] as! [String: Any]
            precondition(properties["template-rendering-intent"] as? String == "original")
            for flavor in ["latte", "mocha"] {
                let svg = try String(contentsOf: directory.appendingPathComponent("\(flavor).svg"), encoding: .utf8)
                precondition(svg.contains("<svg") && svg.contains("viewBox=\"0 0 16 16\""), name)
            }
        }
        print("PASS: file icon associations, writing overrides, case handling, fallback and Latte/Mocha assets")
    }
}
