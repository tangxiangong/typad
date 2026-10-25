import SwiftUI

struct DocumentHeading: Identifiable, Sendable {
    var id: Int { offset }
    let title: String
    let level: Int
    let offset: Int

    /// Lightweight navigation for plain Typst markup headings, excluding fenced raw blocks.
    static func scan(_ source: String) -> [Self] {
        var result: [Self] = [], offset = 0, inRaw = false
        for line in source.components(separatedBy: "\n") {
            defer { offset += line.utf16.count + 1 }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { inRaw.toggle(); continue }
            guard !inRaw else { continue }
            let marks = line.prefix(while: { $0 == "=" }).count
            guard marks > 0, line.dropFirst(marks).first?.isWhitespace == true else { continue }
            result.append(Self(title: String(line.dropFirst(marks)).trimmingCharacters(in: .whitespaces), level: marks, offset: offset))
        }
        return result
    }
}

struct WorkspaceSidebar: View {
    let filename: String
    let headings: [DocumentHeading]
    let diagnostics: [WorkerDiagnostic]
    @Binding var issues: Bool
    let navigate: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Navigator", selection: $issues) {
                Image(systemName: "list.bullet.indent").tag(false).help("Document outline")
                Image(systemName: "exclamationmark.triangle").tag(true).help("Compilation issues")
            }.labelsHidden().pickerStyle(.segmented).frame(width: 86).frame(maxWidth: .infinity).frame(height: 28)
            Divider()
            if issues {
                if diagnostics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.title2)
                        Text("No issues").font(.callout)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                        Button {
                            if let offset = diagnostic.utf16Offset { navigate(Int(offset)) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: diagnostic.warning ? "exclamationmark.triangle" : "xmark.circle")
                                    .foregroundStyle(diagnostic.warning ? Color.orange : Color.red)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(diagnostic.message).font(.callout).lineLimit(4)
                                    if let file = diagnostic.file {
                                        Text("\(file):\(diagnostic.line ?? 1)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(diagnostic.utf16Offset == nil).help(diagnostic.message)
                    }.listStyle(.sidebar)
                }
            } else {
                List {
                    Section("Document") {
                        Button { navigate(0) } label: { Label(filename, systemImage: "doc.text").lineLimit(1) }
                            .buttonStyle(.plain)
                    }
                    Section("Headings") {
                        if headings.isEmpty { Text("No headings yet").foregroundStyle(.secondary).font(.callout) }
                        ForEach(headings) { heading in
                            Button { navigate(heading.offset) } label: {
                                Text(heading.title).font(.callout).lineLimit(1)
                                    .padding(.leading, CGFloat(min(heading.level - 1, 4) * 10))
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(heading.title)
                        }
                    }
                }.listStyle(.sidebar)
            }
        }
    }
}
