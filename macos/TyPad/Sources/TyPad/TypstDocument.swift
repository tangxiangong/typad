import SwiftUI
import UniformTypeIdentifiers
import TyPadCore

extension UTType {
    static let typstSource = UTType(importedAs: "org.typst.source", conformingTo: .plainText)
}

struct TypstDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.typstSource] }
    var source: String

    init() { source = TyPadCore.newDocument() }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        source = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}
