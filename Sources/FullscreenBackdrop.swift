import AppKit
import Darwin

@MainActor
final class FullscreenBackdrop {
    private var window: NSWindow?
    private let engines = Paths.root.appendingPathComponent("Runtimes").path + "/"

    func update(gamesRunning: Bool) {
        guard gamesRunning, let front = NSWorkspace.shared.frontmostApplication, runsFerryEngine(front.processIdentifier),
              let target = letterboxedWindow(of: front.processIdentifier) else {
            hide()
            return
        }
        show(on: target.screen, level: target.layer - 1)
    }

    private func runsFerryEngine(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).hasPrefix(engines)
    }

    private func letterboxedWindow(of pid: pid_t) -> (screen: NSScreen, layer: Int)? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { continue }
            for screen in NSScreen.screens {
                let f = screen.frame
                let screenRect = CGRect(x: f.minX, y: mainHeight - f.maxY, width: f.width, height: f.height)
                if Letterbox.needsBackdrop(window: bounds, screen: screenRect) { return (screen, layer) }
            }
            return nil
        }
        return nil
    }

    private func show(on screen: NSScreen, level: Int) {
        let backdrop = window ?? makeWindow()
        window = backdrop
        if backdrop.frame != screen.frame { backdrop.setFrame(screen.frame, display: false) }
        if backdrop.level.rawValue != level { backdrop.level = NSWindow.Level(rawValue: level) }
        if !backdrop.isVisible { backdrop.orderFrontRegardless() }
    }

    private func hide() {
        if window?.isVisible == true { window?.orderOut(nil) }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return w
    }
}
