import AppKit
import SwiftUI

struct ProjectNavigator: View {
    @ObservedObject var workspace: ProjectWorkspace
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let root = workspace.root { FileIcon(url: root, isDirectory: true, isExpanded: true, isRoot: true) }
                Text(workspace.root?.lastPathComponent ?? "").font(.headline).lineLimit(1)
                Spacer()
                Button { createFile() } label: {
                    Label("New file…", systemImage: "doc.badge.plus")
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
                Button { perform { try workspace.refresh() } } label: {
                    Label("Refresh files", systemImage: "arrow.clockwise")
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }.padding(10)
            List {
                ForEach(workspace.files) { file in
                    ProjectFileRow(file: file, workspace: workspace)
                }
            }.listStyle(.sidebar)
            if let main = workspace.mainURL {
                Text("Main: \(workspace.relativePath(main))").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).padding(8).help(workspace.relativePath(main))
            }
        }
    }
    private func createFile() {
        let panel = NSSavePanel()
        panel.directoryURL = workspace.root
        panel.nameFieldStringValue = "Untitled.typ"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            guard workspace.contains(url) else { throw ProjectFailure.outsideProject }
            try Data().write(to: url, options: .withoutOverwriting)
            try workspace.refresh()
            try workspace.open(url)
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { workspace.error = error.localizedDescription }
    }
}

private struct ProjectFileRow: View {
    let file: ProjectFile
    @ObservedObject var workspace: ProjectWorkspace
    @State private var expanded = false

    var body: some View {
        Group {
            if let children = file.children {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children) { child in
                        ProjectFileRow(file: child, workspace: workspace)
                    }
                } label: {
                    rowLabel
                }
            } else {
                Button {
                    do { try workspace.open(file.url) } catch { workspace.error = error.localizedDescription }
                } label: { rowLabel }
                    .buttonStyle(.plain)
            }
        }
        .help(workspace.relativePath(file.url))
        .contextMenu {
            if file.children == nil, file.url.pathExtension == "typ" {
                Button("Set as Main Document") {
                    do { try workspace.setMain(file.url) } catch { workspace.error = error.localizedDescription }
                }
            }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            FileIcon(url: file.url, isDirectory: file.children != nil, isExpanded: expanded)
            Text(file.url.lastPathComponent).lineLimit(1)
            if file.url == workspace.mainURL {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Main: \(file.url.lastPathComponent)"))
            }
        }.foregroundStyle(file.url == workspace.activeURL ? Color.accentColor : Color.primary)
    }
}

struct ProjectTabs: View {
    @ObservedObject var workspace: ProjectWorkspace
    let didClose: (URL) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(workspace.buffers) { buffer in
                    HStack(spacing: 6) {
                        Button { perform { try workspace.open(buffer.url) } } label: {
                            HStack(spacing: 4) {
                                FileIcon(url: buffer.url)
                                if buffer.isDirty { Image(systemName: "circle.fill").font(.system(size: 6)).accessibilityLabel("Unsaved changes") }
                                if buffer.url == workspace.mainURL { Image(systemName: "pin.fill") }
                                Text(buffer.url.lastPathComponent).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                        Button { close(buffer) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                            .buttonStyle(.plain).disabled(buffer.url == workspace.mainURL)
                            .help(buffer.url == workspace.mainURL ? String(localized: "Choose another main document before closing this tab.") : String(localized: "Close tab"))
                            .accessibilityLabel(Text("Close \(buffer.url.lastPathComponent)"))
                    }.font(.caption).padding(8)
                        .background(buffer.url == workspace.activeURL ? Color.accentColor.opacity(0.12) : Color.clear)
                        .help(workspace.relativePath(buffer.url))
                }
            }
        }.frame(height: 32)
    }
    private func close(_ buffer: ProjectBuffer) {
        if buffer.isDirty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Save changes to \(buffer.url.lastPathComponent)?")
            alert.addButton(withTitle: String(localized: "Save"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.addButton(withTitle: String(localized: "Don’t Save"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do { try workspace.save(buffer.url) } catch { workspace.error = error.localizedDescription; return }
            case .alertThirdButtonReturn: break
            default: return
            }
        }
        perform { try workspace.close(buffer.url); didClose(buffer.url) }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { workspace.error = error.localizedDescription }
    }
}
