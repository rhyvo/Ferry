import AppKit
import UniformTypeIdentifiers

enum PEIconReader {
    static func largestIcon(in exe: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: exe, options: .alwaysMapped), data.count > 64 else { return nil }
        let base = data.startIndex
        func u8(_ o: Int) -> Int? { o >= 0 && o < data.count ? Int(data[base + o]) : nil }
        func u16(_ o: Int) -> Int? {
            guard let lo = u8(o), let hi = u8(o + 1) else { return nil }
            return lo | hi << 8
        }
        func u32(_ o: Int) -> Int? {
            guard let lo = u16(o), let hi = u16(o + 2) else { return nil }
            return lo | hi << 16
        }
        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x0000_4550,
              let sectionCount = u16(pe + 6), let optionalSize = u16(pe + 20), let magic = u16(pe + 24) else { return nil }
        let opt = pe + 24
        let dirs = opt + (magic == 0x20B ? 112 : 96)
        guard let resourceRVA = u32(dirs + 2 * 8), resourceRVA != 0 else { return nil }

        var sections: [(va: Int, size: Int, raw: Int)] = []
        for i in 0..<min(sectionCount, 96) {
            let s = opt + optionalSize + i * 40
            guard let vsize = u32(s + 8), let va = u32(s + 12), let rawSize = u32(s + 16), let raw = u32(s + 20) else { break }
            sections.append((va, vsize > 0 ? vsize : rawSize, raw))
        }
        func offset(_ rva: Int) -> Int? {
            for s in sections where rva >= s.va && rva < s.va + s.size { return rva - s.va + s.raw }
            return nil
        }
        guard let root = offset(resourceRVA) else { return nil }

        func entries(_ dir: Int) -> [(id: Int?, target: Int, isDir: Bool)] {
            guard let named = u16(dir + 12), let numbered = u16(dir + 14) else { return [] }
            var out: [(Int?, Int, Bool)] = []
            for i in 0..<min(named + numbered, 4096) {
                let e = dir + 16 + i * 8
                guard let name = u32(e), let target = u32(e + 4) else { break }
                out.append((name & 0x8000_0000 == 0 ? name : nil, target & 0x7FFF_FFFF, target & 0x8000_0000 != 0))
            }
            return out
        }
        func firstLeaf(_ target: Int, isDir: Bool, depth: Int = 0) -> Data? {
            if !isDir {
                guard let rva = u32(root + target), let size = u32(root + target + 4),
                      let start = offset(rva), size > 0, start + size <= data.count else { return nil }
                return data.subdata(in: (base + start)..<(base + start + size))
            }
            guard depth < 3, let first = entries(root + target).first else { return nil }
            return firstLeaf(first.target, isDir: first.isDir, depth: depth + 1)
        }
        let types = entries(root)
        guard let groupType = types.first(where: { $0.id == 14 && $0.isDir }),
              let iconType = types.first(where: { $0.id == 3 && $0.isDir }),
              let firstGroup = entries(root + groupType.target).first,
              let group = firstLeaf(firstGroup.target, isDir: firstGroup.isDir), group.count >= 6 else { return nil }

        let g = [UInt8](group)
        let count = Int(g[4]) | Int(g[5]) << 8
        var best: (size: Int, bits: Int, entry: [UInt8], id: Int)? = nil
        for i in 0..<count {
            let e = 6 + i * 14
            guard e + 14 <= g.count else { break }
            let size = g[e] == 0 ? 256 : Int(g[e])
            let bits = Int(g[e + 6]) | Int(g[e + 7]) << 8
            let id = Int(g[e + 12]) | Int(g[e + 13]) << 8
            if best == nil || (size, bits) > (best!.size, best!.bits) { best = (size, bits, Array(g[e..<(e + 12)]), id) }
        }
        guard let chosen = best,
              let match = entries(root + iconType.target).first(where: { $0.id == chosen.id }),
              let image = firstLeaf(match.target, isDir: match.isDir) else { return nil }

        if image.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return NSImage(data: image) }
        var ico = Data([0, 0, 1, 0, 1, 0])
        ico.append(contentsOf: chosen.entry[0..<8])
        var size = UInt32(image.count).littleEndian, at = UInt32(22).littleEndian
        ico.append(Data(bytes: &size, count: 4))
        ico.append(Data(bytes: &at, count: 4))
        ico.append(image)
        return NSImage(data: ico)
    }

    static func findIcon(for exe: URL) -> NSImage? {
        if exe.pathExtension.lowercased() == "exe", let icon = largestIcon(in: exe) { return icon }
        let dir = exe.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let icos = files.filter { $0.pathExtension.lowercased() == "ico" }
            .sorted { FileManager.default.byteSize($0) > FileManager.default.byteSize($1) }
        return icos.lazy.compactMap { NSImage(contentsOf: $0) }.first
    }

    static func squarePNG(_ image: NSImage) -> Data? {
        let largest = image.representations.map { max($0.pixelsWide, $0.pixelsHigh) }.max() ?? 0
        let side = min(256, max(32, largest > 0 ? largest : Int(max(image.size.width, image.size.height))))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let w = image.size.width, h = image.size.height
        let scale = CGFloat(side) / max(w, h, 1)
        let rect = NSRect(x: (CGFloat(side) - w * scale) / 2, y: (CGFloat(side) - h * scale) / 2, width: w * scale, height: h * scale)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

@MainActor
private var iconCache: [String: NSImage] = [:]

extension AppModel {
    func iconURL(_ id: UUID, _ mode: IconMode) -> URL? {
        switch mode {
        case .standard: return nil
        case .auto: return Paths.icons.appendingPathComponent("\(id.uuidString)-auto.png")
        case .custom: return Paths.icons.appendingPathComponent("\(id.uuidString)-custom.png")
        }
    }

    func icon(for g: Game) -> NSImage? {
        _ = iconRevision
        guard let url = iconURL(g.id, g.iconMode), fm.exists(url) else { return nil }
        if let cached = iconCache[url.path] { return cached }
        let image = NSImage(contentsOf: url)
        iconCache[url.path] = image
        return image
    }

    private func iconChanged() {
        iconCache.removeAll()
        iconRevision += 1
    }

    func refreshMissingIcons() {
        for g in games where g.iconMode == .auto {
            if let url = iconURL(g.id, .auto), !fm.exists(url) { refreshAutoIcon(g) }
        }
    }

    func refreshAutoIcon(_ g: Game) {
        guard let url = iconURL(g.id, .auto) else { return }
        let exe = URL(fileURLWithPath: g.exePath)
        Task {
            let png = await Task.detached { PEIconReader.findIcon(for: exe).flatMap(PEIconReader.squarePNG) }.value
            try? fm.createDirectory(at: Paths.icons, withIntermediateDirectories: true)
            if let png { try? png.write(to: url, options: .atomic) } else { fm.removeIfPresent(url) }
            iconChanged()
        }
    }

    func chooseCustomIcon(for id: UUID) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .icns, .ico] + ["exe", "dll"].compactMap { UTType(filenameExtension: $0) }
        panel.message = "Choose a picture, or a Windows program to take its icon from"
        if let g = game(id) { panel.directoryURL = URL(fileURLWithPath: g.exePath).deletingLastPathComponent() }
        guard panel.runModal() == .OK, let url = panel.url, let target = iconURL(id, .custom) else { return false }
        let ext = url.pathExtension.lowercased()
        let image = ["exe", "dll"].contains(ext) ? PEIconReader.largestIcon(in: url) : NSImage(contentsOf: url)
        guard let image, let png = PEIconReader.squarePNG(image) else {
            errorMessage = "Ferry couldn't read a picture from \(url.lastPathComponent)."
            return false
        }
        try? fm.createDirectory(at: Paths.icons, withIntermediateDirectories: true)
        guard (try? png.write(to: target, options: .atomic)) != nil else { return false }
        iconChanged()
        return true
    }

    func removeIcons(_ id: UUID) {
        for mode in IconMode.allCases { if let url = iconURL(id, mode) { fm.removeIfPresent(url) } }
    }
}
