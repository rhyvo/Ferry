import Foundation

enum Naming {
    private static let generic: Set<String> = ["game", "launcher", "start", "play", "setup", "install", "installer", "main", "app",
                                                "client", "win64", "win32"]
    private static let placeFolders: Set<String> = ["program files", "program files (x86)", "drive_c", "c:", "games", "downloads",
                                                     "desktop", "documents", "applications", "steamapps", "common", "users"]
    private static let engineNames: Set<String> = ["unity", "unityplayer", "unity player", "bootstrappackagedgame", "game",
                                                    "launcher", "application", "setup"]

    static func friendlyName(for url: URL, productName: (URL) -> String? = { _ in nil }) -> String {
        let base = url.deletingPathExtension().lastPathComponent
        let cleaned = base.replacingOccurrences(of: "-Win64-Shipping", with: "").replacingOccurrences(of: "_", with: " ")
        let folder = ModLayout.gameRoot(exeFolder: url.deletingLastPathComponent()).lastPathComponent
        let usableFolder = folder.isEmpty || folder == "/" || placeFolders.contains(folder.lowercased()) ? nil : folder
        if generic.contains(base.lowercased()) { return usableFolder ?? cleaned }
        guard looksLikeCode(cleaned) || cleaned == cleaned.lowercased() else { return cleaned }
        if let product = productName(url).map(tidy), product.count >= 3, !looksLikeCode(product),
           !engineNames.contains(product.lowercased()) {
            return product
        }
        return usableFolder ?? cleaned
    }

    static func looksLikeCode(_ name: String) -> Bool {
        !name.contains(" ") && name.count <= 16 && (name.contains(where: \.isNumber) || name == name.lowercased())
    }

    static func tidy(_ product: String) -> String {
        var s = product
        for mark in ["(R)", "(TM)", "(C)", "®", "™", "©"] { s = s.replacingOccurrences(of: mark, with: "") }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
