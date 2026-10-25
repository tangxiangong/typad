import AppKit
import SwiftUI

struct WelcomeView: View {
    @State private var recent: [URL] = []
    @State private var filter = ""
    @State private var opening: URL?
    @State private var error: String?

    private var filtered: [URL] {
        recent.filter { filter.isEmpty || $0.path.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Image("TyPadMark").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 128, height: 128)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                    .frame(height: 162).padding(.top, 22)
                Text("TyPad").font(.system(size: 22, weight: .medium))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 5)
                Divider().padding(.horizontal, 24).padding(.vertical, 24)
                VStack(spacing: 18) {
                    Button { NSDocumentController.shared.openDocument(nil) } label: {
                        action("Open a document…", subtitle: "Choose a .typ file on your Mac", icon: "folder")
                    }
                    Button { NSDocumentController.shared.newDocument(nil) } label: {
                        action("New document", subtitle: "Start with a blank Typst document", icon: "doc.badge.plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                .buttonStyle(.plain).padding(.horizontal, 24)
                Spacer(minLength: 24)
            }
            .frame(width: 380)
            .background(.regularMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text("Recent documents").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).frame(height: 40)
                Divider()
                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: filter.isEmpty ? "clock" : "magnifyingglass").font(.system(size: 24, weight: .regular)).padding(.bottom, 12)
                        Text(filter.isEmpty ? String(localized: "No recent documents") : String(localized: "No matching documents")).font(.headline)
                        Text(filter.isEmpty ? String(localized: "Documents you open will appear in this list.") : String(localized: "Try another name or folder."))
                            .font(.callout).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered, id: \.self) { url in
                                Button { open(url) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 24, weight: .regular))
                                            .foregroundStyle(.secondary).frame(width: 30, height: 30)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        if opening == url { ProgressView().controlSize(.small) }
                                    }.padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(opening != nil).help(url.path)
                            }
                        }.padding(8)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Filter recent documents", text: $filter).textFieldStyle(.plain)
                }.padding(14)
            }

        }
        .frame(width: 780, height: 480)
        .background(Color(nsColor: .windowBackgroundColor)).ignoresSafeArea()
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in refresh() }
        .alert("Couldn’t open document", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func action(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .regular)).frame(width: 26).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.vertical, 6).contentShape(Rectangle())
    }

    private func refresh() { recent = NSDocumentController.shared.recentDocumentURLs }
    private func open(_ url: URL) {
        opening = url
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, failure in
            DispatchQueue.main.async {
                opening = nil
                error = failure?.localizedDescription
                refresh()
            }
        }
    }
}
