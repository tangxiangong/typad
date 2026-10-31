import SwiftUI
import UIKit

@main
struct EditorTestHost: App {
    var body: some Scene {
        WindowGroup { ClipboardFixtureView() }
    }
}

// Only built into the isolated test host, never the TyPad product.
private struct ClipboardFixtureView: View {
    private let fixture = "中文 PasteMenu English\n$1 + 2 = 3$\n"
    private let backup = URL.documentsDirectory.appendingPathComponent("clipboard-backup.archive")
    @State private var status = "Ready"

    var body: some View {
        VStack(spacing: 24) {
            Text("TyPad paste-menu test fixture")
            Button("Prepare clipboard fixture", action: prepare)
            Button("Restore original clipboard", action: restore)
            Text(status).accessibilityIdentifier("clipboard.status")
        }
    }

    private func prepare() {
        do {
            guard !FileManager.default.fileExists(atPath: backup.path) else {
                status = "Restore the pending backup first"; return
            }
            let data = try NSKeyedArchiver.archivedData(withRootObject: UIPasteboard.general.items,
                                                      requiringSecureCoding: false)
            try data.write(to: backup, options: [.atomic, .completeFileProtection])
            UIPasteboard.general.setItems([["public.utf8-plain-text": Data(fixture.utf8)]], options: [.localOnly: true])
            status = "Fixture ready; original clipboard backed up"
        } catch { status = "Backup failed: \(error.localizedDescription)" }
    }

    private func restore() {
        do {
            let data = try Data(contentsOf: backup)
            guard let items = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? [[String: Any]] else {
                status = "Invalid backup; not changing clipboard"; return
            }
            guard UIPasteboard.general.string == fixture else {
                status = "Clipboard changed externally; preserved it and kept backup"; return
            }
            UIPasteboard.general.setItems(items, options: [.localOnly: true])
            guard NSArray(array: UIPasteboard.general.items).isEqual(to: items) else {
                status = "Restore verification failed; kept backup"; return
            }
            try FileManager.default.removeItem(at: backup)
            status = "Original clipboard restored and verified"
        } catch { status = "Restore failed: \(error.localizedDescription)" }
    }
}
