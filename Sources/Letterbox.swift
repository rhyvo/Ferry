import CoreGraphics

enum Letterbox {
    static func needsBackdrop(window: CGRect, screen: CGRect, tolerance: CGFloat = 1.5) -> Bool {
        let w = window.intersection(screen)
        guard !w.isNull, w.width * w.height >= 0.5 * screen.width * screen.height else { return false }
        let left = w.minX - screen.minX, right = screen.maxX - w.maxX
        let top = w.minY - screen.minY, bottom = screen.maxY - w.maxY
        let fullWidth = left <= tolerance && right <= tolerance
        let fullHeight = top <= tolerance && bottom <= tolerance
        if fullWidth && fullHeight { return true }
        if fullWidth { return abs(top - bottom) <= tolerance }
        if fullHeight { return abs(left - right) <= tolerance }
        return false
    }
}
