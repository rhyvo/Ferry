import CoreGraphics

func runLetterboxTests() {
    let screen = CGRect(x: 0, y: 0, width: 1408, height: 881)
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Bool {
        Letterbox.needsBackdrop(window: CGRect(x: x, y: y, width: w, height: h), screen: screen)
    }
    check(box(0, 1, 1408, 880), "16:10 game one point short of an odd-height screen")
    check(box(0, 0, 1408, 881), "a game window that fills the screen (Mach9 leaves its last row see-through)")
    check(box(0, 44, 1408, 792), "16:9 game with bars above and below")
    check(box(117, 0, 1174, 881), "4:3 game with bars at the sides")
    check(!box(0, 37, 1408, 844), "an ordinary window maximized under the menu bar")
    check(!box(200, 150, 1000, 600), "an ordinary window")
    check(!box(0, 0, 640, 480), "a small window in a corner")
    check(!box(0, 300, 1408, 200), "a wide strip that isn't a picture")
    let second = CGRect(x: 1408, y: 0, width: 1920, height: 1080)
    check(Letterbox.needsBackdrop(window: CGRect(x: 1648, y: 0, width: 1440, height: 1080), screen: second),
          "4:3 game on the second display")
}
