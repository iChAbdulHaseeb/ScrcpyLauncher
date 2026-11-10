import AppKit
import Foundation
import SwiftUI

// MARK: - External tools

enum Tools {
    static let home = NSHomeDirectory()
    static func first(_ paths: [String]) -> String? {
        paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static let scrcpy = first(["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"])
    static let adb = first([
        "\(home)/Library/Android/sdk/platform-tools/adb",
        "/opt/homebrew/bin/adb", "/usr/local/bin/adb",
    ])

    /// Apps opened from Finder get a minimal PATH, so build one explicitly.
    static let env: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        var dirs = ["/opt/homebrew/bin", "/usr/local/bin"]
        if let a = adb {
            dirs.insert((a as NSString).deletingLastPathComponent, at: 0)
            e["ADB"] = a
        }
        e["PATH"] = (dirs + [e["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        return e
    }()

    /// Run a command synchronously and return its raw output (call off the main thread).
    static func runData(_ exe: String, _ args: [String], timeout: TimeInterval = 20) -> (Int32, Data) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return (-1, Data(error.localizedDescription.utf8)) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, data)
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 20) -> (Int32, String) {
        let (c, d) = runData(exe, args, timeout: timeout)
        return (c, String(decoding: d, as: UTF8.self))
    }

    /// Start the adb daemon detached so later pipes don't get held open by it.
    static func startAdbServer() {
        guard let adb else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: adb)
        p.arguments = ["start-server"]
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}

func timestamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return f.string(from: Date())
}

// MARK: - Devices

struct Device: Identifiable, Hashable {
    let serial: String      // adb serial (changes between USB and Wi-Fi)
    let state: String
    let model: String
    let wireless: Bool
    var hwid: String        // hardware serial (ro.serialno): stable key for per-device settings
    var id: String { serial }
    var ready: Bool { state == "device" }
}

func parseDevices(_ out: String) -> [Device] {
    out.split(separator: "\n").compactMap { line in
        if line.hasPrefix("List of") || line.hasPrefix("*") { return nil }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2 else { return nil }
        let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") }
        let usb = parts.contains { $0.hasPrefix("usb:") }
        return Device(serial: parts[0], state: parts[1], model: model ?? parts[0],
                      wireless: !usb && (parts[0].contains(":") || parts[0].contains("._adb")),
                      hwid: parts[0])
    }
}

// MARK: - Running scrcpy sessions

final class Session: ObservableObject, Identifiable {
    enum Kind { case view, record }
    let id = UUID()
    let kind: Kind
    let serial: String
    let name: String
    let command: String
    let file: URL?
    let started = Date()
    let process = Process()
    @Published var log = ""
    @Published var running = true
    @Published var exitCode: Int32 = 0
    var stoppedByUser = false

    init(kind: Kind, serial: String, name: String, command: String, file: URL?) {
        self.kind = kind; self.serial = serial; self.name = name; self.command = command; self.file = file
    }

    /// SIGTERM lets scrcpy finish writing the recording properly.
    func stop() {
        stoppedByUser = true
        guard process.isRunning else { return }
        process.terminate()
        // If scrcpy is stuck, force it so the button never hangs. Recordings get much
        // longer, because a force-kill loses the file (it's only finalized on a clean exit).
        let p = process
        DispatchQueue.global().asyncAfter(deadline: .now() + (kind == .record ? 30 : 6)) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
}

/// Where a setting is being edited: the global defaults, or one phone's overrides.
enum Scope: Hashable {
    case global
    case device(String)   // hwid
}

/// Options that only make sense for a visible window; dropped from background recordings.
private let windowOnlyKeys: Set<String> = [
    "window-title", "always-on-top", "fullscreen", "window-borderless", "window-x", "window-y",
    "window-width", "window-height", "no-window-aspect-ratio-lock", "background-color", "render-driver",
    "render-fit", "no-mipmaps", "no-window", "no-playback", "no-video-playback", "no-audio-playback",
    "no-control", "keyboard", "mouse", "gamepad", "mouse-bind", "otg", "flex-display", "print-fps",
]

// MARK: - App state

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var devices: [Device] = []
    @Published var views: [String: Session] = [:]        // running, by adb serial
    @Published var recordings: [String: Session] = [:]   // running, by adb serial
    @Published var lastSession: [String: Session] = [:]  // most recent of any kind, for logs
    @Published var status = ""
    @Published var busy = false
    @Published var showPair = false
    @Published var pairCode = ""
    @Published var infoText: InfoText?
    @Published var logSession: Session?
    @Published var editing: Device?

    /// Global defaults for every phone.
    @Published var values: [String: String] {
        didSet { UserDefaults.standard.set(values, forKey: "options") }
    }
    /// Per-phone overrides, keyed by hardware serial.
    @Published var overrides: [String: [String: String]] {
        didSet { UserDefaults.standard.set(overrides, forKey: "deviceOptions") }
    }
    @Published var profiles: [String: [String: String]] {
        didSet { UserDefaults.standard.set(profiles, forKey: "profiles") }
    }

    struct InfoText: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var refreshing = false
    private var hwids: [String: String] = [:]   // adb serial -> hardware serial

    init() {
        let d = UserDefaults.standard
        values = d.dictionary(forKey: "options") as? [String: String] ?? [:]
        overrides = d.dictionary(forKey: "deviceOptions") as? [String: [String: String]] ?? [:]
        profiles = d.dictionary(forKey: "profiles") as? [String: [String: String]] ?? [:]
        d.register(defaults: [
            "shotDir": Tools.home + "/Pictures/Scrcpy",
            "recDir": Tools.home + "/Movies/Scrcpy",
            "revealFiles": true,
        ])
        DispatchQueue.global().async {
            Tools.startAdbServer()
            DispatchQueue.main.async { self.refresh() }
        }
    }

    // MARK: Settings access (global + per-device)

    func effective(_ hwid: String) -> [String: String] {
        var v = values
        for (k, x) in overrides[hwid] ?? [:] { v[k] = x }
        return v
    }

    func current(_ s: Scope) -> [String: String] {
        switch s {
        case .global: return values
        case .device(let h): return effective(h)
        }
    }

    func get(_ k: String, _ s: Scope) -> String {
        switch s {
        case .global: return values[k] ?? ""
        case .device(let h): return overrides[h]?[k] ?? values[k] ?? ""
        }
    }

    func set(_ k: String, _ v: String, _ s: Scope) {
        switch s {
        case .global:
            values[k] = v.isEmpty ? nil : v
        case .device(let h):
            var o = overrides[h] ?? [:]
            o[k] = (v == (values[k] ?? "")) ? nil : v   // same as global → inherit
            overrides[h] = o.isEmpty ? nil : o
        }
    }

    func isOverridden(_ k: String, _ s: Scope) -> Bool {
        if case .device(let h) = s { return overrides[h]?[k] != nil }
        return false
    }

    func reset(_ k: String, _ s: Scope) {
        if case .device(let h) = s {
            overrides[h]?[k] = nil
            if overrides[h]?.isEmpty == true { overrides[h] = nil }
        }
    }

    func text(_ k: String, _ s: Scope) -> Binding<String> {
        Binding(get: { self.get(k, s) }, set: { self.set(k, $0, s) })
    }

    func bool(_ k: String, _ s: Scope) -> Binding<Bool> {
        Binding(get: { self.get(k, s) == "1" }, set: { self.set(k, $0 ? "1" : "", s) })
    }

    func hasOverrides(_ d: Device) -> Bool { !(overrides[d.hwid] ?? [:]).isEmpty }

    func apply(_ preset: [String: String], _ s: Scope) {
        switch s {
        case .global:
            let extra = values["__extra"]
            values = preset
            if let extra { values["__extra"] = extra }
        case .device(let h):
            overrides[h] = nil
            for k in Set(values.keys).union(preset.keys) where k != "__extra" {
                set(k, preset[k] ?? "", s)
            }
        }
    }

    func resetAll(_ s: Scope) {
        switch s {
        case .global: apply([:], .global)
        case .device(let h): overrides[h] = nil
        }
    }

    func saveProfile(from s: Scope) {
        let alert = NSAlert()
        alert.messageText = "Save these settings as a profile"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "Profile name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profiles[name] = current(s)
        status = "Saved profile “\(name)”"
    }

    func commandPreview(_ s: Scope) -> String {
        var a = ["scrcpy"]
        if case .device(let h) = s, let d = devices.first(where: { $0.hwid == h }) { a += ["-s", d.serial] }
        return (a + buildArgs(current(s))).map(shellQuote).joined(separator: " ")
    }

    // MARK: Devices

    func refresh() {
        guard let adb = Tools.adb, !refreshing else { return }
        refreshing = true
        let known = hwids
        DispatchQueue.global().async {
            let (_, out) = Tools.run(adb, ["devices", "-l"], timeout: 8)
            var list = parseDevices(out)
            var map = known
            for i in list.indices where list[i].ready {
                if map[list[i].serial] == nil {
                    let id = Tools.run(adb, ["-s", list[i].serial, "shell", "getprop", "ro.serialno"], timeout: 5).1
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !id.isEmpty && !id.contains(" ") { map[list[i].serial] = id }
                }
                list[i].hwid = map[list[i].serial] ?? list[i].serial
            }
            DispatchQueue.main.async {
                self.refreshing = false
                self.hwids = map
                if list != self.devices { self.devices = list }
            }
        }
    }

    func adbTask(_ title: String, _ work: @escaping (String) -> String) {
        guard let adb = Tools.adb else { status = "adb not found"; return }
        busy = true
        status = title + "…"
        DispatchQueue.global().async {
            let msg = work(adb)
            DispatchQueue.main.async {
                self.busy = false
                self.status = msg
                self.refresh()
            }
        }
    }

    func connect(_ address: String) {
        let addr = address.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty else { return }
        adbTask("Connecting to \(addr)") { adb in
            Tools.run(adb, ["connect", addr.contains(":") ? addr : addr + ":5555"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func pair(_ address: String, code: String) {
        let addr = address.trimmingCharacters(in: .whitespaces)
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !addr.isEmpty, !c.isEmpty else { status = "Enter pairing IP:port and code"; return }
        adbTask("Pairing with \(addr)") { adb in
            Tools.run(adb, ["pair", addr, c], timeout: 30).1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func disconnect(_ d: Device) {
        adbTask("Disconnecting") { adb in
            Tools.run(adb, ["disconnect", d.serial]).1.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Switch a USB device to wireless adb (tcpip 5555) and connect to it.
    func goWireless(_ d: Device) {
        adbTask("Switching \(d.model) to Wi-Fi") { adb in
            let route = Tools.run(adb, ["-s", d.serial, "shell", "ip", "route"]).1
            var ip: String?
            for line in route.split(separator: "\n") where line.contains("wlan") || ip == nil {
                let w = line.split(separator: " ")
                if let i = w.firstIndex(of: "src"), i + 1 < w.count { ip = String(w[i + 1]) }
            }
            guard let ip else { return "Couldn't find the phone's Wi-Fi IP. Is Wi-Fi on?" }
            Tools.run(adb, ["-s", d.serial, "tcpip", "5555"])
            Thread.sleep(forTimeInterval: 2)
            let out = Tools.run(adb, ["connect", "\(ip):5555"]).1.trimmingCharacters(in: .whitespacesAndNewlines)
            return out + " — you can unplug the cable now."
        }
    }

    func query(_ flag: String, _ title: String, _ d: Device) {
        guard let scrcpy = Tools.scrcpy else { return }
        busy = true
        status = "Reading \(title.lowercased())…"
        DispatchQueue.global().async {
            let out = Tools.run(scrcpy, ["-s", d.serial, flag], timeout: 30).1
            let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.contains("1 file pushed") && !$0.hasPrefix("scrcpy ") }
            DispatchQueue.main.async {
                self.busy = false
                self.status = ""
                self.infoText = InfoText(title: "\(title) — \(d.model)", text: lines.joined(separator: "\n"))
            }
        }
    }

    // MARK: Output folders

    private func folder(_ key: String) -> URL? {
        let path = (UserDefaults.standard.string(forKey: key) ?? "") as NSString
        let url = URL(fileURLWithPath: path.expandingTildeInPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            status = "Can't use folder \(url.path): \(error.localizedDescription)"
            return nil
        }
    }

    private func fileName(_ d: Device, _ ext: String) -> String {
        let name = d.model.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return "\(name) \(timestamp()).\(ext)"
    }

    @Published var lastFile: URL?

    func openFolder(_ key: String) {
        if let dir = folder(key) { NSWorkspace.shared.open(dir) }
    }

    private func saved(_ url: URL, _ what: String) {
        lastFile = url
        status = "\(what) saved: \((url.path as NSString).abbreviatingWithTildeInPath)"
        if UserDefaults.standard.bool(forKey: "revealFiles") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: Actions

    func screenshot(_ d: Device) {
        guard let adb = Tools.adb, let dir = folder("shotDir") else { return }
        let url = dir.appendingPathComponent(fileName(d, "png"))
        status = "Taking screenshot of \(d.model)…"
        DispatchQueue.global().async {
            let (code, data) = Tools.runData(adb, ["-s", d.serial, "exec-out", "screencap", "-p"], timeout: 15)
            let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
            var err: String?
            if code == 0 && isPNG {
                do { try data.write(to: url) } catch { err = error.localizedDescription }
            } else {
                err = String(decoding: data.prefix(300), as: UTF8.self)
            }
            DispatchQueue.main.async {
                if let err { self.status = "Screenshot failed: \(err)" } else { self.saved(url, "Screenshot") }
            }
        }
    }

    func toggleView(_ d: Device) {
        if let s = views[d.serial] { s.stop() } else { launch(.view, d) }
    }

    func toggleRecord(_ d: Device) {
        if let s = recordings[d.serial] { s.stop() } else { launch(.record, d) }
    }

    func viewAll() { for d in devices where d.ready && views[d.serial] == nil { launch(.view, d) } }

    func stopAll() {
        views.values.forEach { $0.stop() }
        recordings.values.forEach { $0.stop() }
    }

    private func launch(_ kind: Session.Kind, _ d: Device) {
        guard let scrcpy = Tools.scrcpy else { status = "scrcpy not found — run: brew install scrcpy"; return }
        var v = effective(d.hwid)
        let other = kind == .view ? recordings[d.serial] : views[d.serial]

        // Two sessions on one phone can't both capture the default "output" audio:
        // the second one uses "playback" capture instead.
        if other != nil, (v["audio-source"] ?? "").isEmpty || v["audio-source"] == "output" {
            v["audio-source"] = "playback"
        }

        var file: URL?
        var args = ["-s", d.serial]
        switch kind {
        case .view:
            args += buildArgs(v)
            if (v["window-title"] ?? "").isEmpty { args.append("--window-title=\(d.model)") }
        case .record:
            guard let dir = folder("recDir") else { return }
            for k in windowOnlyKeys { v[k] = nil }
            if other != nil { v["start-app"] = nil; v["no-clipboard-autosync"] = "1" }
            let url = dir.appendingPathComponent(fileName(d, "mp4"))
            file = url
            args += buildArgs(v) + ["--no-window", "--record=\(url.path)"]
        }

        let s = Session(kind: kind, serial: d.serial, name: d.model,
                        command: (["scrcpy"] + args).map(shellQuote).joined(separator: " "), file: file)
        let p = s.process
        p.executableURL = URL(fileURLWithPath: scrcpy)
        p.arguments = args
        p.environment = Tools.env
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            let str = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { s.log += str }
        }
        p.terminationHandler = { proc in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AppModel.shared.finished(s, proc.terminationStatus) }
            }
        }
        do {
            try p.run()
            switch kind {
            case .view: views[d.serial] = s
            case .record: recordings[d.serial] = s
            }
            lastSession[d.serial] = s
            status = kind == .view ? "Viewing \(d.model)" : "Recording \(d.model)…"
        } catch {
            status = "Failed to start: \(error.localizedDescription)"
        }
    }

    private func finished(_ s: Session, _ code: Int32) {
        s.running = false
        s.exitCode = code
        switch s.kind {
        case .view: if views[s.serial] === s { views[s.serial] = nil }
        case .record: if recordings[s.serial] === s { recordings[s.serial] = nil }
        }
        if s.kind == .record, let f = s.file {
            let size = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int) ?? 0
            if size > 0 {
                saved(f, "Recording")
                if !s.stoppedByUser {
                    status = "Connection to \(s.name) ended — recording saved up to that point: \((f.path as NSString).abbreviatingWithTildeInPath)"
                }
                return
            }
            // Nothing was written: remove the empty file and show why.
            try? FileManager.default.removeItem(at: f)
            status = "Recording of \(s.name) failed — no video was received. See the log."
            logSession = s
            return
        }
        // Closing the window normally exits 0; anything else is an error worth showing.
        if code != 0 && !s.stoppedByUser {
            status = "\(s.name): scrcpy stopped with an error"
            logSession = s
        } else if s.kind == .view {
            status = "Stopped viewing \(s.name)"
        }
    }
}
