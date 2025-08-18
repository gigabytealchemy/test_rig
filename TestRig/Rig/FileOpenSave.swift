import AppKit
import UniformTypeIdentifiers

enum FileOpenSave {
    static func presentOpen(_ onLoad: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                onLoad(s)
            }
        }
    }

    static func presentSave(text: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
