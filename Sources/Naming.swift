import Foundation

enum Naming {
    static func friendlyName(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let generic = ["game", "launcher", "start", "play", "setup", "install", "installer", "main", "app", "client", "win64", "win32"]
        let cleaned = base.replacingOccurrences(of: "-Win64-Shipping", with: "").replacingOccurrences(of: "_", with: " ")
        if generic.contains(base.lowercased()) {
            let folder = url.deletingLastPathComponent().lastPathComponent
            if !folder.isEmpty, folder != "/" { return folder }
        }
        return cleaned
    }
}
