import GameController
import SwiftUI

enum PadMap {
    static let key = "padMap"
    static let savesKey = "padMapSaves"

    static let controls: [(id: String, name: String)] = [
        ("a", "A (✕)"), ("b", "B (○)"), ("x", "X (□)"), ("y", "Y (△)"),
        ("lb", "Left Bumper (L1)"), ("rb", "Right Bumper (R1)"), ("lt", "Left Trigger (L2)"), ("rt", "Right Trigger (R2)"),
        ("up", "D-Pad Up"), ("down", "D-Pad Down"), ("left", "D-Pad Left"), ("right", "D-Pad Right"),
        ("ls", "Left Stick Click (L3)"), ("rs", "Right Stick Click (R3)"), ("back", "View (Create)"), ("start", "Menu (Options)"),
    ]
    static let leftGroups: [(title: String, ids: [String])] = [
        ("Left Bumper and Trigger", ["lb", "lt"]),
        ("D-Pad", ["up", "down", "left", "right"]),
        ("Left Stick and View", ["lstick", "ls", "back"]),
    ]
    static let rightGroups: [(title: String, ids: [String])] = [
        ("Right Bumper and Trigger", ["rb", "rt"]),
        ("Buttons", ["y", "x", "b", "a"]),
        ("Right Stick and Menu", ["rstick", "rs", "start"]),
    ]

    static func name(_ id: String) -> String {
        if id == "lstick" { return "Left Stick" }
        if id == "rstick" { return "Right Stick" }
        return controls.first { $0.id == id }?.name ?? id
    }

    static func targets(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, controls.contains(where: { $0.id == parts[0] }) { out[parts[0]] = parts[1] }
        }
        return out
    }

    static func text(_ targets: [String: String]) -> String {
        controls.compactMap { c in targets[c.id].flatMap { $0 == c.id ? nil : "\(c.id):\($0)" } }.joined(separator: ",")
    }

    static var current: String { UserDefaults.standard.string(forKey: key) ?? "" }

    static func binding(_ game: String, in text: String) -> String? {
        let t = targets(text)
        return controls.first { (t[$0.id] ?? $0.id) == game }?.id
    }

    static func bind(_ game: String, to physical: String, in text: String) -> String {
        var t = targets(text)
        for c in controls where c.id != physical && (t[c.id] ?? c.id) == game { t[c.id] = "none" }
        t[physical] = game
        return Self.text(t)
    }

    static func clear(_ game: String, in text: String) -> String {
        var t = targets(text)
        for c in controls where (t[c.id] ?? c.id) == game { t[c.id] = "none" }
        return Self.text(t)
    }
}

enum PadKeys {
    static let key = "padKeys"
    static let onKey = "padKeysOn"
    static let defaults = "a:k39,b:k2E,x:k13,y:k12,lb:k10,rb:k21,lt:m2,rt:m1,up:k02,down:k03,left:k04,right:k05,"
        + "ls:k2A,rs:k2F,back:k0F,start:k01,lstick:wasd,rstick:mouse,speed:8"

    static var current: String { UserDefaults.standard.string(forKey: key) ?? defaults }
    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }

    static func binds(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in text.split(separator: ",") {
            let parts = pair.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { out[parts[0]] = parts[1] }
        }
        return out
    }

    static func text(_ binds: [String: String]) -> String {
        (PadMap.controls.map(\.id) + ["lstick", "rstick", "speed"])
            .compactMap { id in binds[id].map { "\(id):\($0)" } }.joined(separator: ",")
    }

    static let mouseNames = ["m1": "Left Click", "m2": "Right Click", "m3": "Middle Click", "wu": "Wheel Up", "wd": "Wheel Down"]

    static func label(_ bind: String?) -> String? {
        guard let bind else { return nil }
        if let mouse = mouseNames[bind] { return mouse }
        guard bind.hasPrefix("k"), let code = Int(bind.dropFirst(), radix: 16) else { return nil }
        return KeyboardKey.all.first { $0.code == code }?.name
    }

    static func code(_ bind: String?) -> Int? {
        guard let bind, bind.hasPrefix("k") else { return nil }
        return Int(bind.dropFirst(), radix: 16)
    }
}

struct KeyboardKey {
    let code: Int
    let mac: UInt16
    let label: String
    let fullName: String?
    let row: Int
    let width: CGFloat
    var name: String { fullName ?? label }

    static let all: [KeyboardKey] = {
        var keys: [KeyboardKey] = []
        func add(_ row: Int, _ list: [(Int, UInt16, String, String?, CGFloat)]) {
            keys += list.map { KeyboardKey(code: $0.0, mac: $0.1, label: $0.2, fullName: $0.3, row: row, width: $0.4) }
        }
        var fRow: [(Int, UInt16, String, String?, CGFloat)] = [(0x01, 53, "esc", "Escape", 1.25)]
        let fCodes = [0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x57, 0x58]
        let fMac: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        for i in 0..<12 { fRow.append((fCodes[i], fMac[i], "F\(i + 1)", nil, 1)) }
        add(0, fRow)
        var numbers: [(Int, UInt16, String, String?, CGFloat)] = [(0x29, 50, "`", nil, 1)]
        let numberMac: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for i in 0..<10 { numbers.append((0x02 + i, numberMac[i], String((i + 1) % 10), nil, 1)) }
        numbers += [(0x0C, 27, "-", nil, 1), (0x0D, 24, "=", nil, 1), (0x0E, 51, "⌫", "Backspace", 2)]
        add(1, numbers)
        add(2, [(0x0F, 48, "tab", "Tab", 1.5)] + letters("QWERTYUIOP", Array(0x10...0x19), [12, 13, 14, 15, 17, 16, 32, 34, 31, 35])
            + [(0x1A, 33, "[", nil, 1), (0x1B, 30, "]", nil, 1), (0x2B, 42, "\\", nil, 1.5)])
        add(3, [(0x3A, 57, "caps", "Caps Lock", 1.75)] + letters("ASDFGHJKL", Array(0x1E...0x26), [0, 1, 2, 3, 5, 4, 38, 40, 37])
            + [(0x27, 41, ";", nil, 1), (0x28, 39, "'", nil, 1), (0x1C, 36, "enter", "Enter", 2.25)])
        add(4, [(0x2A, 56, "shift", "Left Shift", 2.25)] + letters("ZXCVBNM", Array(0x2C...0x32), [6, 7, 8, 9, 11, 45, 46])
            + [(0x33, 43, ",", nil, 1), (0x34, 47, ".", nil, 1), (0x35, 44, "/", nil, 1), (0x36, 60, "shift", "Right Shift", 2.75)])
        add(5, [(0x1D, 59, "ctrl", "Left Ctrl", 1.5), (0x38, 58, "alt", "Left Alt", 1.5), (0x39, 49, "space", "Space", 6.5),
                (0xE038, 61, "alt", "Right Alt", 1.5), (0xE04B, 123, "←", "Left Arrow", 1), (0xE048, 126, "↑", "Up Arrow", 1),
                (0xE050, 125, "↓", "Down Arrow", 1), (0xE04D, 124, "→", "Right Arrow", 1)])
        add(-1, [(0xE01D, 62, "ctrl", "Right Ctrl", 1), (0xE053, 117, "del", "Delete", 1), (0xE047, 115, "home", "Home", 1),
                 (0xE04F, 119, "end", "End", 1), (0xE049, 116, "pgup", "Page Up", 1), (0xE051, 121, "pgdn", "Page Down", 1)])
        return keys
    }()

    private static func letters(_ s: String, _ codes: [Int], _ mac: [UInt16]) -> [(Int, UInt16, String, String?, CGFloat)] {
        zip(zip(s.map(String.init), codes), mac).map { ($0.0.1, $0.1, $0.0.0, nil, 1.0) }
    }
}

struct PadSave: Codable, Hashable {
    var name: String
    var map: String
    var keys: String? = nil
    var keysOn: Bool? = nil
}

struct ControllerView: View {
    enum Mode: String { case controller, keyboard }

    @AppStorage(PadMap.key) private var map = ""
    @AppStorage(PadKeys.key) private var keys = PadKeys.defaults
    @AppStorage(PadKeys.onKey) private var keysOn = false
    @AppStorage(PadMap.savesKey) private var savesData = Data()
    @AppStorage("controllerMode") private var mode = Mode.controller
    @State private var saveName = ""
    @State private var confirmOverwrite = false
    @State private var confirmDelete = false
    @State private var listening: String? = nil
    @State private var listenTimeout: Task<Void, Never>? = nil
    @State private var keyMonitor: Any? = nil
    @StateObject private var input = PadInput()

    private var saves: [PadSave] { (try? JSONDecoder().decode([PadSave].self, from: savesData)) ?? [] }
    private func store(_ saves: [PadSave]) {
        savesData = (try? JSONEncoder().encode(saves.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) ?? Data()
    }
    private var trimmedName: String { saveName.trimmingCharacters(in: .whitespaces) }
    private var named: PadSave? { saves.first { $0.name == trimmedName } }
    private var keyBinds: [String: String] { PadKeys.binds(keys) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            keybinds
            HStack(alignment: .top, spacing: 16) {
                column(PadMap.leftGroups)
                VStack(spacing: 12) {
                    if mode == .controller {
                        ControllerDrawing(input: input)
                    } else {
                        KeyboardMouseDrawing(input: input, binds: keyBinds)
                    }
                    Picker("Keybinds for", selection: Binding(get: { mode }, set: { mode = $0; stopListening() })) {
                        Label("Controller", systemImage: "gamecontroller").tag(Mode.controller)
                        Label("Keyboard & Mouse", systemImage: "keyboard").tag(Mode.keyboard)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    if mode == .keyboard {
                        Toggle("Play with the controller as a keyboard and mouse", isOn: $keysOn)
                            .help("For games that don't support controllers. Turn it off for games that do, or they get both.")
                        HStack {
                            Text("Mouse speed")
                            Slider(value: Binding(get: { Double(keyBinds["speed"] ?? "8") ?? 8 },
                                                  set: { var b = keyBinds; b["speed"] = String(Int($0.rounded())); keys = PadKeys.text(b) }),
                                   in: 1...20)
                        }
                        .frame(width: 300)
                        .help("How fast a stick set to Mouse moves the pointer")
                    }
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 320)
                }
                column(PadMap.rightGroups)
            }
            Spacer(minLength: 0)
            HStack {
                Text(mode == .controller
                     ? "Click a button's box, then press the button on your controller that should do it in games. Right-click a box to clear it. Applies to every game and app the next time it starts, for games that read the controller as an Xbox controller (most do). Not used for games with anti-cheat."
                     : "Click a box, then press the key or mouse button (or turn the scroll wheel) that control should send. Right-click a box to clear it. While on, applies to every game and app the next time it starts. Not used for games with anti-cheat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Reset to Default") {
                    stopListening()
                    if mode == .controller { map = "" } else { keys = PadKeys.defaults }
                }
                .disabled(mode == .controller ? map.isEmpty : keys == PadKeys.defaults)
                .help(mode == .controller ? "Every button does what it normally does" : "Go back to Ferry's usual keyboard and mouse binds")
            }
        }
        .padding(18)
        .frame(minWidth: 1080, minHeight: 560)
        .onAppear { input.start() }
        .onDisappear { input.stop(); stopListening() }
        .onChange(of: input.pressed) { old, new in
            guard mode == .controller, let game = listening else { return }
            let fresh = new.subtracting(old)
            if let physical = PadMap.controls.map(\.id).first(where: fresh.contains) {
                map = PadMap.bind(game, to: physical, in: map)
                stopListening()
            }
        }
        .confirmationDialog("Replace the saved keybinds \"\(trimmedName)\"?", isPresented: $confirmOverwrite) {
            Button("Replace") { save() }
        }
        .confirmationDialog("Delete the saved keybinds \"\(trimmedName)\"?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store(saves.filter { $0.name != trimmedName })
                saveName = ""
            }
        } message: {
            Text("This can't be undone. The binds in use now don't change.")
        }
    }

    private var status: String {
        if let listening {
            return mode == .controller
                ? "Press the button for \(PadMap.name(listening))…"
                : "Press the key or mouse button for \(PadMap.name(listening))…"
        }
        guard let name = input.name else {
            return "Connect a controller to see its buttons light up as you press them"
        }
        return mode == .controller ? "\(name): press its buttons to see them light up"
            : "\(name): press its buttons to see the keys they send"
    }

    private var keybinds: some View {
        HStack {
            Text("Keybinds")
            TextField("Name", text: $saveName)
                .frame(maxWidth: 220)
                .onSubmit { if let named { load(named) } }
            Menu {
                if saves.isEmpty { Text("No saved keybinds yet") }
                ForEach(saves, id: \.name) { s in
                    Button(s.name) { saveName = s.name; load(s) }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Pick saved keybinds to use them")
            Button("Load") { if let named { load(named) } }
                .disabled(named == nil)
                .help("Use the saved keybinds with this name")
            Button("Save") { named == nil ? save() : (confirmOverwrite = true) }
                .disabled(trimmedName.isEmpty)
                .help("Save the controller and keyboard and mouse binds under this name")
            Button("Delete") { confirmDelete = true }
                .disabled(named == nil)
                .help("Delete the saved keybinds with this name")
        }
    }

    private func load(_ s: PadSave) {
        stopListening()
        map = s.map
        if let k = s.keys { keys = k }
        if let on = s.keysOn { keysOn = on }
    }

    private func save() {
        store(saves.filter { $0.name != trimmedName } + [PadSave(name: trimmedName, map: map, keys: keys, keysOn: keysOn)])
        saveName = trimmedName
    }

    private func column(_ groups: [(title: String, ids: [String])]) -> some View {
        VStack(spacing: 12) {
            ForEach(groups, id: \.title) { group in
                GroupBox(group.title) {
                    VStack(spacing: 4) {
                        ForEach(group.ids.filter { mode == .keyboard || !$0.hasSuffix("stick") }, id: \.self) { id in
                            if id.hasSuffix("stick") { stickRow(id) } else { row(id) }
                        }
                    }
                    .padding(2)
                }
            }
        }
        .frame(width: 330)
    }

    private func row(_ id: String) -> some View {
        let controller = mode == .controller
        let bound = controller ? PadMap.binding(id, in: map) : nil
        let text = controller ? bound.map(PadMap.name) : PadKeys.label(keyBinds[id])
        let lit = controller ? bound.map(input.pressed.contains) ?? false : input.pressed.contains(id)
        let waiting = listening == id
        let clash = clashes(id)
        return HStack {
            Text(PadMap.name(id))
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !clash.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Also sent by \(clash.joined(separator: ", ")). Letting go of one can release the key while the other is still held.")
                    .accessibilityLabel("Also sent by \(clash.joined(separator: ", "))")
            }
            Button {
                waiting ? stopListening() : listen(id)
            } label: {
                Text(waiting ? "Press…" : text ?? "Not set")
                    .font(.callout)
                    .foregroundStyle(waiting ? Color.white : text == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(waiting ? Color.accentColor : Color.primary.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(waiting ? Color.accentColor : !clash.isEmpty ? Color.orange : Color.primary.opacity(0.15)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 172)
            .contextMenu {
                Button("Clear") {
                    if controller { map = PadMap.clear(id, in: map) } else { var b = keyBinds; b[id] = nil; keys = PadKeys.text(b) }
                }
                if controller {
                    Button("Default (\(PadMap.name(id)))") { map = PadMap.bind(id, to: id, in: map) }
                }
            }
            .accessibilityLabel("\(PadMap.name(id)): \(text ?? "not set")")
            .accessibilityHint(controller ? "Click, then press a button on your controller" : "Click, then press a key or mouse button")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(lit ? Color.accentColor : .primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(lit ? 0.28 : 0)))
        .help(controller ? "Click, then press the button on your controller that should be \(PadMap.name(id)) in games"
                         : "Click, then press the key or mouse button \(PadMap.name(id)) should send")
    }

    private func clashes(_ id: String) -> [String] {
        guard mode == .keyboard, let mine = keyBinds[id] else { return [] }
        var out = PadMap.controls.map(\.id).filter { $0 != id && keyBinds[$0] == mine }.map(PadMap.name)
        if let code = PadKeys.code(mine) {
            for stick in ["lstick", "rstick"] {
                let codes = keyBinds[stick] == "wasd" ? [0x11, 0x1F, 0x1E, 0x20]
                    : keyBinds[stick] == "arrows" ? [0xE048, 0xE050, 0xE04B, 0xE04D] : []
                if codes.contains(code) { out.append(PadMap.name(stick)) }
            }
        }
        return out
    }

    private func stickRow(_ id: String) -> some View {
        let binding = Binding<String>(
            get: { keyBinds[id] ?? "off" },
            set: { var b = keyBinds; b[id] = $0; keys = PadKeys.text(b) }
        )
        return HStack {
            Text(PadMap.name(id))
                .font(.callout)
            Spacer(minLength: 8)
            Picker(PadMap.name(id), selection: binding) {
                Text("WASD").tag("wasd")
                Text("Arrows").tag("arrows")
                Text("Mouse").tag("mouse")
                Text("Off").tag("off")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 186)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .help("What \(PadMap.name(id)) does: walk with W A S D or the arrow keys, move the mouse, or nothing")
    }

    private func listen(_ id: String) {
        stopListening()
        listening = id
        if mode == .keyboard {
            keyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { event in
                guard let bind = Self.bind(for: event) else { return event }
                var b = keyBinds
                b[id] = bind
                keys = PadKeys.text(b)
                stopListening()
                return nil
            }
        }
        listenTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, listening == id { stopListening() }
        }
    }

    private func stopListening() {
        listening = nil
        listenTimeout?.cancel()
        listenTimeout = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private static func bind(for event: NSEvent) -> String? {
        switch event.type {
        case .keyDown, .flagsChanged:
            guard let key = KeyboardKey.all.first(where: { $0.mac == event.keyCode }) else { return nil }
            if event.type == .flagsChanged {
                let flag: NSEvent.ModifierFlags? = [56: .shift, 60: .shift, 59: .control, 62: .control, 58: .option,
                                                    61: .option, 57: .capsLock][event.keyCode]
                guard let flag, event.modifierFlags.contains(flag) else { return nil }
            }
            return "k" + String(key.code, radix: 16, uppercase: true)
        case .leftMouseDown: return "m1"
        case .rightMouseDown: return "m2"
        case .otherMouseDown: return event.buttonNumber == 2 ? "m3" : nil
        case .scrollWheel:
            guard abs(event.scrollingDeltaY) > 0.5 else { return nil }
            return event.scrollingDeltaY > 0 ? "wu" : "wd"
        default: return nil
        }
    }
}

struct KeyboardMouseDrawing: View {
    @ObservedObject var input: PadInput
    let binds: [String: String]

    private var litKeys: Set<Int> {
        var lit = Set(input.pressed.compactMap { PadKeys.code(binds[$0]) })
        for (stick, at) in [("lstick", input.sticks.left), ("rstick", input.sticks.right)] {
            let codes: [Int]
            switch binds[stick] {
            case "wasd": codes = [0x11, 0x1F, 0x1E, 0x20]
            case "arrows": codes = [0xE048, 0xE050, 0xE04B, 0xE04D]
            default: continue
            }
            let edge = 12000.0 / 32767.0
            if at.y > edge { lit.insert(codes[0]) }
            if at.y < -edge { lit.insert(codes[1]) }
            if at.x < -edge { lit.insert(codes[2]) }
            if at.x > edge { lit.insert(codes[3]) }
        }
        return lit
    }
    private var litMouse: Set<String> { Set(input.pressed.compactMap { binds[$0] }.filter { $0.hasPrefix("m") || $0.hasPrefix("w") }) }
    private var pointer: CGPoint {
        if binds["rstick"] == "mouse" { return input.sticks.right }
        if binds["lstick"] == "mouse" { return input.sticks.left }
        return .zero
    }

    var body: some View {
        let lit = litKeys, mouse = litMouse
        VStack(spacing: 18) {
            keyboard(lit)
            HStack(alignment: .center, spacing: 28) {
                mouseBody(mouse)
                pointerArrow
            }
        }
        .frame(width: 360, height: 290)
        .animation(.easeOut(duration: 0.06), value: lit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard and mouse")
    }

    private func keyboard(_ lit: Set<Int>) -> some View {
        let unit: CGFloat = 22.5
        return VStack(alignment: .leading, spacing: 2.5) {
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 2.5) {
                    ForEach(KeyboardKey.all.filter { $0.row == row }, id: \.code) { key in
                        let on = lit.contains(key.code)
                        Text(key.label)
                            .font(.system(size: key.label.count > 2 ? 7 : 9, weight: .medium))
                            .foregroundStyle(on ? Color.white : Color(white: 0.75))
                            .frame(width: unit * key.width - 2.5, height: row == 0 ? 14 : 20)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(on ? Color.accentColor : Color(white: 0.16)))
                            .shadow(color: on ? Color.accentColor.opacity(0.8) : .clear, radius: 5)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.27)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    private func mouseBody(_ lit: Set<String>) -> some View {
        let shell = Color(white: 0.27), off = Color(white: 0.2)
        func button(_ id: String, left: Bool) -> some View {
            UnevenRoundedRectangle(topLeadingRadius: left ? 30 : 0, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                   topTrailingRadius: left ? 0 : 30)
                .fill(lit.contains(id) ? Color.accentColor : off)
                .frame(width: 30, height: 42)
        }
        let wheelOn = lit.contains("m3") || lit.contains("wu") || lit.contains("wd")
        return ZStack(alignment: .top) {
            Capsule().fill(shell).frame(width: 66, height: 104)
            HStack(spacing: 2) {
                button("m1", left: true)
                button("m2", left: false)
            }
            .padding(.top, 2)
            Capsule()
                .fill(wheelOn ? Color.accentColor : Color(white: 0.45))
                .frame(width: 7, height: 16)
                .offset(y: lit.contains("wd") ? 17 : lit.contains("wu") ? 9 : 13)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
    }

    private var pointerArrow: some View {
        let p = pointer
        let moving = hypot(p.x, p.y) > 0.27
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 70, height: 70)
            Image(systemName: "cursorarrow")
                .font(.system(size: 20))
                .foregroundStyle(moving ? Color.accentColor : Color.secondary)
                .offset(x: p.x * 26, y: -p.y * 26)
        }
        .frame(width: 70, height: 70)
        .help("The pointer moves this way while a stick set to Mouse is pushed")
    }
}

@MainActor
final class PadInput: ObservableObject {
    @Published var name: String? = nil
    @Published var playStation = false
    @Published var pressed: Set<String> = []
    @Published var triggers = (left: Float(0), right: Float(0))
    @Published var sticks = (left: CGPoint.zero, right: CGPoint.zero)
    @Published var touches: [CGPoint] = []
    @Published var touchpadPressed = false
    private var observers: [NSObjectProtocol] = []
    private var quickButtons: [GCControllerElement] = []

    func start() {
        guard observers.isEmpty else { return }
        for note in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent] {
            observers.append(NotificationCenter.default.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.attach() }
            })
        }
        attach()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        GCController.controllers().forEach { $0.extendedGamepad?.valueChangedHandler = nil }
        releaseQuickButtons()
    }

    private func releaseQuickButtons() {
        quickButtons.forEach { $0.preferredSystemGestureState = .enabled }
        quickButtons = []
    }

    private func attach() {
        releaseQuickButtons()
        let controller = GCController.current?.extendedGamepad != nil ? GCController.current
            : GCController.controllers().first { $0.extendedGamepad != nil }
        guard let controller, let pad = controller.extendedGamepad else {
            name = nil
            pressed = []
            triggers = (0, 0)
            sticks = (.zero, .zero)
            touches = []
            touchpadPressed = false
            return
        }
        name = controller.vendorName ?? "Controller"
        playStation = pad is GCDualSenseGamepad || pad is GCDualShockGamepad
        quickButtons = [pad.buttonOptions, pad.buttonHome].compactMap { $0 }
        quickButtons.forEach { $0.preferredSystemGestureState = .disabled }
        pad.valueChangedHandler = { [weak self] pad, _ in MainActor.assumeIsolated { self?.read(pad) } }
        read(pad)
    }

    private func read(_ p: GCExtendedGamepad) {
        let buttons: [(String, GCControllerButtonInput?)] = [
            ("a", p.buttonA), ("b", p.buttonB), ("x", p.buttonX), ("y", p.buttonY),
            ("lb", p.leftShoulder), ("rb", p.rightShoulder), ("up", p.dpad.up), ("down", p.dpad.down),
            ("left", p.dpad.left), ("right", p.dpad.right), ("ls", p.leftThumbstickButton), ("rs", p.rightThumbstickButton),
            ("back", p.buttonOptions), ("start", p.buttonMenu), ("guide", p.buttonHome),
        ]
        var held = Set(buttons.filter { $0.1?.isPressed == true }.map(\.0))
        if p.leftTrigger.value > 0.12 { held.insert("lt") }
        if p.rightTrigger.value > 0.12 { held.insert("rt") }
        if held != pressed { pressed = held }
        triggers = (p.leftTrigger.value, p.rightTrigger.value)
        sticks = (CGPoint(x: CGFloat(p.leftThumbstick.xAxis.value), y: CGFloat(p.leftThumbstick.yAxis.value)),
                  CGPoint(x: CGFloat(p.rightThumbstick.xAxis.value), y: CGFloat(p.rightThumbstick.yAxis.value)))

        let pad: (button: GCControllerButtonInput, fingers: [GCControllerDirectionPad])?
        if let ds = p as? GCDualSenseGamepad {
            pad = (ds.touchpadButton, [ds.touchpadPrimary, ds.touchpadSecondary])
        } else if let ds4 = p as? GCDualShockGamepad {
            pad = (ds4.touchpadButton, [ds4.touchpadPrimary, ds4.touchpadSecondary])
        } else {
            pad = nil
        }
        let fingers = (pad?.fingers ?? []).map { CGPoint(x: CGFloat($0.xAxis.value), y: CGFloat($0.yAxis.value)) }
            .filter { $0 != .zero }
        if fingers != touches { touches = fingers }
        let down = pad?.button.isPressed ?? false
        if down != touchpadPressed { touchpadPressed = down }
    }
}

struct ControllerDrawing: View {
    @ObservedObject var input: PadInput

    private var ps: Bool { input.playStation }
    private func on(_ id: String) -> Bool { input.pressed.contains(id) }

    private var shell: LinearGradient {
        LinearGradient(colors: ps ? [Color(white: 0.98), Color(white: 0.83)] : [Color(white: 0.27), Color(white: 0.13)],
                       startPoint: .top, endPoint: .bottom)
    }
    private var key: Color { ps ? Color(white: 0.87) : Color(white: 0.09) }
    private var keyEdge: Color { ps ? Color(white: 0.68) : Color(white: 0.32) }

    private struct Spots { var dpad, face, leftStick, rightStick, back, start, guide: CGPoint }
    private var spots: Spots {
        ps ? Spots(dpad: .init(x: 66, y: 112), face: .init(x: 294, y: 112), leftStick: .init(x: 130, y: 160),
                   rightStick: .init(x: 230, y: 160), back: .init(x: 96, y: 68), start: .init(x: 264, y: 68),
                   guide: .init(x: 180, y: 148))
           : Spots(dpad: .init(x: 134, y: 168), face: .init(x: 270, y: 118), leftStick: .init(x: 92, y: 118),
                   rightStick: .init(x: 228, y: 168), back: .init(x: 154, y: 122), start: .init(x: 206, y: 122),
                   guide: .init(x: 180, y: 86))
    }

    var body: some View {
        ZStack {
            trigger(input.triggers.left, lit: on("lt")).position(x: 82, y: 16)
            trigger(input.triggers.right, lit: on("rt")).position(x: 278, y: 16)
            bumper(on("lb"), left: true).position(x: 80, y: 48)
            bumper(on("rb"), left: false).position(x: 280, y: 48)
            Group {
                if ps { DualSenseShape().fill(shell) } else { XboxShape().fill(shell) }
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            if ps { dualSenseMiddle }
            dpad.position(spots.dpad)
            stick(input.sticks.left, lit: on("ls")).position(spots.leftStick)
            stick(input.sticks.right, lit: on("rs")).position(spots.rightStick)
            face.position(spots.face)
            menuButton(on("back"), tall: ps).position(spots.back)
            menuButton(on("start"), tall: ps).position(spots.start)
            guide.position(spots.guide)
        }
        .frame(width: 360, height: 290)
        .animation(.easeOut(duration: 0.06), value: input.pressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ps ? "PlayStation controller" : "Xbox controller")
    }

    private var dualSenseMiddle: some View {
        let pad = CGRect(x: 110, y: 57, width: 140, height: 56)
        return ZStack {
            DualSensePanelShape().fill(Color(white: 0.11))
            TouchpadShape()
                .fill(input.touchpadPressed ? Color.accentColor.opacity(0.35) : Color(white: 0.93))
                .overlay(TouchpadShape().stroke(Color(white: 0.72), lineWidth: 1))
            ForEach(Array(input.touches.enumerated()), id: \.offset) { _, finger in
                let size: CGFloat = input.touchpadPressed ? 26 : 18
                Circle()
                    .fill(Color.accentColor.opacity(0.85))
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: Color.accentColor.opacity(0.8), radius: 6)
                    .frame(width: size, height: size)
                    .position(x: pad.midX + finger.x * pad.width / 2, y: pad.midY - finger.y * pad.height / 2)
            }
            HStack(spacing: 3) {
                ForEach(0..<6, id: \.self) { _ in Circle().fill(Color(white: 0.3)).frame(width: 3, height: 3) }
            }
            .position(x: 180, y: 126)
            Capsule().fill(Color(white: 0.3)).frame(width: 14, height: 5).position(x: 180, y: 176)
        }
        .animation(.easeOut(duration: 0.05), value: input.touches)
    }

    private var face: some View {
        let buttons: [(id: String, xbox: String, playStation: String, color: Color, offset: CGSize)] = [
            ("y", "Y", "△", ps ? Color(red: 0.2, green: 0.75, blue: 0.6) : .yellow, CGSize(width: 0, height: -23)),
            ("x", "X", "□", ps ? Color(red: 0.85, green: 0.45, blue: 0.7) : .blue, CGSize(width: -23, height: 0)),
            ("b", "B", "○", ps ? Color(red: 0.9, green: 0.3, blue: 0.3) : .red, CGSize(width: 23, height: 0)),
            ("a", "A", "✕", ps ? Color(red: 0.35, green: 0.55, blue: 0.95) : .green, CGSize(width: 0, height: 23)),
        ]
        return ZStack {
            ForEach(buttons, id: \.id) { b in
                let lit = on(b.id)
                ZStack {
                    Circle().fill(lit ? b.color : key)
                        .overlay(Circle().stroke(lit ? b.color : keyEdge, lineWidth: 1))
                    Text(ps ? b.playStation : b.xbox)
                        .font(.system(size: ps ? 13 : 12, weight: ps ? .regular : .heavy))
                        .foregroundStyle(lit ? Color.white : (ps ? Color(white: 0.5) : b.color))
                }
                .frame(width: 24, height: 24)
                .shadow(color: lit ? b.color.opacity(0.8) : .clear, radius: 5)
                .offset(b.offset)
            }
        }
    }

    private var dpad: some View {
        let arms: [(id: String, offset: CGSize, size: CGSize)] = [
            ("up", CGSize(width: 0, height: -15), CGSize(width: 15, height: 18)),
            ("down", CGSize(width: 0, height: 15), CGSize(width: 15, height: 18)),
            ("left", CGSize(width: -15, height: 0), CGSize(width: 18, height: 15)),
            ("right", CGSize(width: 15, height: 0), CGSize(width: 18, height: 15)),
        ]
        return ZStack {
            if !ps {
                Circle().fill(Color(white: 0.06)).frame(width: 52, height: 52)
            }
            ForEach(arms, id: \.id) { arm in
                RoundedRectangle(cornerRadius: 4)
                    .fill(on(arm.id) ? Color.accentColor : key)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(on(arm.id) ? Color.accentColor : keyEdge, lineWidth: 1))
                    .shadow(color: on(arm.id) ? Color.accentColor.opacity(0.8) : .clear, radius: 5)
                    .frame(width: arm.size.width, height: arm.size.height)
                    .offset(arm.offset)
            }
        }
    }

    private func stick(_ at: CGPoint, lit: Bool) -> some View {
        ZStack {
            Circle().fill(Color(white: ps ? 0.05 : 0.07))
                .frame(width: 50, height: 50)
            Circle()
                .fill(lit ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.32), Color(white: 0.14)],
                                                         center: .center, startRadius: 2, endRadius: 18)))
                .overlay(Circle().stroke(Color(white: 0.4), lineWidth: 1))
                .shadow(color: lit ? Color.accentColor.opacity(0.8) : .black.opacity(0.5), radius: lit ? 6 : 2)
                .frame(width: 34, height: 34)
                .offset(x: at.x * 9, y: -at.y * 9)
        }
    }

    private func bumper(_ lit: Bool, left: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: left ? 14 : 5, bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                               topTrailingRadius: left ? 5 : 14)
            .fill(lit ? Color.accentColor : (ps ? Color(white: 0.85) : Color(white: 0.2)))
            .shadow(color: lit ? Color.accentColor.opacity(0.8) : .clear, radius: 5)
            .frame(width: 84, height: 16)
    }

    private func trigger(_ value: Float, lit: Bool) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8).fill(ps ? Color(white: 0.8) : Color(white: 0.17))
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(lit ? 1 : 0.6))
                .frame(height: 26 * CGFloat(value))
        }
        .frame(width: 60, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func menuButton(_ lit: Bool, tall: Bool) -> some View {
        Capsule()
            .fill(lit ? Color.accentColor : (ps ? Color(white: 0.75) : Color(white: 0.08)))
            .overlay(Capsule().stroke(lit ? Color.accentColor : keyEdge, lineWidth: 1))
            .shadow(color: lit ? Color.accentColor.opacity(0.8) : .clear, radius: 5)
            .frame(width: tall ? 7 : 14, height: tall ? 16 : 14)
    }

    private var guide: some View {
        let lit = on("guide")
        return Circle()
            .fill(lit ? Color.accentColor : (ps ? Color(white: 0.2) : Color(white: 0.12)))
            .overlay(Circle().stroke(ps ? Color(white: 0.4) : Color.white.opacity(0.75), lineWidth: ps ? 1 : 2))
            .shadow(color: lit ? Color.accentColor.opacity(0.9) : .clear, radius: 6)
            .frame(width: ps ? 16 : 24, height: ps ? 16 : 24)
    }
}

struct DualSenseShape: Shape {
    func path(in r: CGRect) -> Path {
        mirrored([
            (.init(x: 290, y: 54), nil, nil),
            (.init(x: 344, y: 90), .init(x: 320, y: 54), .init(x: 338, y: 66)),
            (.init(x: 350, y: 245), .init(x: 352, y: 125), .init(x: 358, y: 190)),
            (.init(x: 300, y: 282), .init(x: 346, y: 280), .init(x: 318, y: 292)),
            (.init(x: 252, y: 214), .init(x: 284, y: 274), .init(x: 268, y: 226)),
            (.init(x: 232, y: 206), .init(x: 246, y: 208), .init(x: 240, y: 206)),
            (.init(x: 180, y: 206), .init(x: 214, y: 206), .init(x: 198, y: 206)),
        ])
    }
}

struct DualSensePanelShape: Shape {
    func path(in r: CGRect) -> Path {
        mirrored([
            (.init(x: 244, y: 110), nil, nil),
            (.init(x: 266, y: 168), .init(x: 258, y: 122), .init(x: 268, y: 142)),
            (.init(x: 330, y: 300), .init(x: 266, y: 206), .init(x: 296, y: 254)),
            (.init(x: 180, y: 300), .init(x: 270, y: 300), .init(x: 220, y: 300)),
        ])
        .intersection(DualSenseShape().path(in: r))
    }
}

struct XboxShape: Shape {
    func path(in r: CGRect) -> Path {
        mirrored([
            (.init(x: 180, y: 64), nil, nil),
            (.init(x: 290, y: 56), .init(x: 220, y: 66), .init(x: 250, y: 50)),
            (.init(x: 350, y: 125), .init(x: 325, y: 62), .init(x: 345, y: 85)),
            (.init(x: 342, y: 268), .init(x: 356, y: 170), .init(x: 358, y: 230)),
            (.init(x: 288, y: 272), .init(x: 330, y: 292), .init(x: 300, y: 292)),
            (.init(x: 240, y: 210), .init(x: 276, y: 252), .init(x: 262, y: 220)),
            (.init(x: 180, y: 200), .init(x: 220, y: 202), .init(x: 200, y: 200)),
        ])
    }
}

private func mirrored(_ right: [(CGPoint, CGPoint?, CGPoint?)]) -> Path {
    func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: 360 - p.x, y: p.y) }
    var path = Path()
    path.move(to: flip(right[0].0))
    path.addLine(to: right[0].0)
    for (end, c1, c2) in right.dropFirst() { path.addCurve(to: end, control1: c1!, control2: c2!) }
    for i in stride(from: right.count - 1, to: 0, by: -1) {
        let (_, c1, c2) = right[i]
        path.addCurve(to: flip(right[i - 1].0), control1: flip(c2!), control2: flip(c1!))
    }
    path.closeSubpath()
    return path
}

struct TouchpadShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 114, y: 55))
        p.addLine(to: CGPoint(x: 246, y: 55))
        p.addQuadCurve(to: CGPoint(x: 255, y: 64), control: CGPoint(x: 255, y: 55))
        p.addLine(to: CGPoint(x: 250, y: 108))
        p.addQuadCurve(to: CGPoint(x: 240, y: 116), control: CGPoint(x: 248, y: 116))
        p.addQuadCurve(to: CGPoint(x: 120, y: 116), control: CGPoint(x: 180, y: 121))
        p.addQuadCurve(to: CGPoint(x: 110, y: 108), control: CGPoint(x: 112, y: 116))
        p.addLine(to: CGPoint(x: 105, y: 64))
        p.addQuadCurve(to: CGPoint(x: 114, y: 55), control: CGPoint(x: 105, y: 55))
        p.closeSubpath()
        return p
    }
}
