import SwiftUI

struct CompletionPanel: View {
    let items: [WorkerCompletion]
    let selected: Int
    let documentation: String
    let status: String
    let busy: Bool
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if busy {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Looking up suggestions…") }
                    .font(.callout).foregroundStyle(.secondary).padding(14)
            } else if !items.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                                Button { choose(index) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "diamond").font(.caption).frame(width: 22)
                                        Text(item.label).font(.system(size: 13, design: .monospaced)).lineLimit(1)
                                        Spacer(minLength: 4)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(index == selected ? Color.white : Color.primary)
                                    .background(index == selected ? Color.accentColor : Color.clear)
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).id(index)
                            }
                        }
                    }
                    .frame(height: CGFloat(min(items.count, 7)) * 25)
                    .onChange(of: selected) { value in proxy.scrollTo(value, anchor: .center) }
                }
                if items.indices.contains(selected), !items[selected].detail.isEmpty {
                    Divider()
                    Text(items[selected].detail).font(.callout).foregroundStyle(.secondary)
                        .lineLimit(4).padding(12).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack { Text("↑ ↓ Select"); Spacer(); Text("Tab Insert"); Text("Esc Close") }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            } else if !documentation.isEmpty {
                HStack { Image(systemName: "book.closed"); Text("Quick help").fontWeight(.medium) }
                    .font(.callout).padding(12)
                Divider()
                ScrollView { DocumentationText(text: documentation).padding(14) }.frame(maxHeight: 340)
            } else {
                Text(status).font(.callout).foregroundStyle(.secondary).padding(16)
            }
        }
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .modifier(CompletionGlass())
    }
}

private struct DocumentationText: View {
    let text: String
    var body: some View {
        let blocks = text.components(separatedBy: "```")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if index % 2 == 1 {
                    let code = block.components(separatedBy: "\n").dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(code).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 5))
                } else {
                    ForEach(Array(block.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                        let value = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            let heading = value.hasPrefix("#")
                            let content = heading ? String(value.drop(while: { $0 == "#" || $0 == " " })) : value
                            Text((try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content))
                                .font(heading ? .headline : .callout).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

/// Suggestions are an app-specific floating surface; the system supplies its material.
private struct CompletionGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
