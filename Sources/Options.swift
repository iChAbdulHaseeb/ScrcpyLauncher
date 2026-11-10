import Foundation

/// How an option is edited in the UI and turned into a command-line flag.
enum OptKind {
    case toggle                         // --flag
    case text(String)                   // --flag=value   (placeholder)
    case combo(String, [String])        // free text + suggestions menu
    case choice([String])               // picker; "" = scrcpy default
    case optional(String)               // --flag  or  --flag=value
    case savePath(String)               // file picker (recording)
}

struct Opt: Identifiable {
    let flag: String
    let label: String
    let kind: OptKind
    let help: String
    var id: String { flag }
    init(_ flag: String, _ label: String, _ kind: OptKind, _ help: String = "") {
        self.flag = flag; self.label = label; self.kind = kind; self.help = help
    }
}

struct OptGroup: Identifiable {
    let title: String
    let opts: [Opt]
    var id: String { title }
}

struct OptTab: Identifiable {
    let name: String
    let icon: String
    let groups: [OptGroup]
    var id: String { name }
}

private let orients = ["0", "90", "180", "270", "flip0", "flip90", "flip180", "flip270"]

/// Every scrcpy 5.x option that makes sense on macOS.
let optionTabs: [OptTab] = [
    OptTab(name: "Video", icon: "film", groups: [
        OptGroup(title: "Quality", opts: [
            Opt("max-size", "Max resolution (px)", .combo("Original", ["720", "1024", "1280", "1600", "1920", "2400"]), "Limits the longer side; lower = faster"),
            Opt("max-fps", "Max FPS", .combo("Device default", ["15", "24", "30", "60", "90", "120"])),
            Opt("video-bit-rate", "Video bit rate", .combo("8M", ["2M", "4M", "8M", "12M", "16M", "24M", "32M"]), "Higher = sharper, more bandwidth"),
            Opt("video-codec", "Video codec", .choice(["h264", "h265", "av1"]), "h265 / av1 give better quality if your phone supports them"),
            Opt("video-encoder", "Video encoder", .text("auto"), "Use Device Info ▸ Encoders to list them"),
            Opt("video-codec-options", "Codec options", .text("key[:type]=value,…")),
            Opt("video-buffer", "Video buffer (ms)", .text("0"), "Adds latency but smooths out jitter"),
            Opt("min-size-alignment", "Min size alignment", .choice(["1", "2", "4", "8", "16"])),
        ]),
        OptGroup(title: "Source & geometry", opts: [
            Opt("video-source", "Video source", .choice(["display", "camera"]), "camera requires Android 12+ (see Camera tab)"),
            Opt("display-id", "Display ID", .text("0"), "Use Device Info ▸ Displays to list them"),
            Opt("orientation", "Orientation (display + record)", .choice(orients)),
            Opt("display-orientation", "Display orientation", .choice(orients)),
            Opt("capture-orientation", "Capture orientation", .choice(orients + orients.map { "@" + $0 }), "@ prefix locks it"),
            Opt("angle", "Rotate by angle (°)", .text("e.g. 15")),
            Opt("crop", "Crop", .text("width:height:x:y")),
            Opt("render-fit", "Render fit", .choice(["letterbox", "stretched", "unscaled"])),
        ]),
        OptGroup(title: "Virtual display", opts: [
            Opt("new-display", "Create new virtual display", .optional("1920x1080/420"), "Empty value = phone's own size and density"),
            Opt("flex-display", "Flex display (resizes with window)", .toggle),
            Opt("display-ime-policy", "Keyboard (IME) location", .choice(["local", "fallback", "hide"])),
            Opt("no-vd-destroy-content", "Keep apps when virtual display closes", .toggle),
            Opt("no-vd-system-decorations", "No system decorations on virtual display", .toggle),
        ]),
        OptGroup(title: "Decoding & misc", opts: [
            Opt("hwdec", "Hardware decoding", .choice(["auto", "videotoolbox", "disabled"])),
            Opt("no-video", "Disable video (audio only)", .toggle),
            Opt("no-video-playback", "Don't show video (e.g. record only)", .toggle),
            Opt("no-mipmaps", "Disable mipmaps", .toggle),
            Opt("no-downsize-on-error", "Don't auto-downsize on encoder error", .toggle),
            Opt("ignore-video-encoder-constraints", "Ignore encoder constraints", .toggle),
            Opt("print-fps", "Print FPS to log", .toggle),
        ]),
    ]),
    OptTab(name: "Audio", icon: "speaker.wave.2", groups: [
        OptGroup(title: "Audio", opts: [
            Opt("no-audio", "Disable audio", .toggle),
            Opt("no-audio-playback", "Don't play audio on Mac", .toggle),
            Opt("audio-source", "Audio source", .choice(["output", "playback", "mic", "mic-unprocessed", "mic-camcorder", "mic-voice-recognition", "mic-voice-communication", "voice-call", "voice-call-uplink", "voice-call-downlink", "voice-performance"])),
            Opt("audio-dup", "Keep playing audio on phone too", .toggle, "Needs Android 13+ and audio source 'playback'"),
            Opt("audio-codec", "Audio codec", .choice(["opus", "aac", "flac", "raw"])),
            Opt("audio-bit-rate", "Audio bit rate", .combo("128K", ["64K", "128K", "192K", "256K", "320K"])),
            Opt("audio-encoder", "Audio encoder", .text("auto")),
            Opt("audio-codec-options", "Codec options", .text("key[:type]=value,…")),
            Opt("audio-buffer", "Audio buffer (ms)", .text("50"), "Lower = less delay, may crackle"),
            Opt("audio-output-buffer", "Audio output buffer (ms)", .text("5")),
            Opt("require-audio", "Fail if audio can't be captured", .toggle),
        ]),
    ]),
    OptTab(name: "Input", icon: "keyboard", groups: [
        OptGroup(title: "Keyboard & mouse", opts: [
            Opt("no-control", "View only (no input to phone)", .toggle),
            Opt("keyboard", "Keyboard mode", .choice(["sdk", "uhid", "aoa", "disabled"]), "uhid = physical-keyboard emulation (best for games/typing)"),
            Opt("mouse", "Mouse mode", .choice(["sdk", "uhid", "aoa", "disabled"]), "uhid/aoa capture the Mac mouse"),
            Opt("gamepad", "Gamepad mode", .choice(["disabled", "uhid", "aoa"])),
            Opt("mouse-bind", "Mouse button bindings", .text("bhsn:++++"), "Right, middle, 4th, 5th click"),
            Opt("no-mouse-hover", "Disable mouse hover events", .toggle),
            Opt("prefer-text", "Prefer text injection", .toggle),
            Opt("raw-key-events", "Raw key events only", .toggle),
            Opt("no-key-repeat", "Disable key repeat", .toggle),
            Opt("shortcut-mod", "Shortcut modifier", .combo("lalt,lsuper", ["lalt,lsuper", "lsuper", "lctrl", "lalt", "rsuper", "lctrl,lsuper"])),
            Opt("otg", "OTG mode (control only, no mirroring)", .toggle),
        ]),
        OptGroup(title: "Clipboard", opts: [
            Opt("no-clipboard-autosync", "Disable clipboard sync", .toggle),
            Opt("legacy-paste", "Legacy paste (type text)", .toggle),
        ]),
    ]),
    OptTab(name: "Device", icon: "iphone", groups: [
        OptGroup(title: "Screen & power", opts: [
            Opt("turn-screen-off", "Turn phone screen off while mirroring", .toggle),
            Opt("stay-awake", "Keep phone awake (while plugged in)", .toggle),
            Opt("keep-active", "Keep screen on (simulate activity)", .toggle),
            Opt("screen-off-timeout", "Screen-off timeout (s)", .text("e.g. 300")),
            Opt("show-touches", "Show touches on phone", .toggle),
            Opt("power-off-on-close", "Turn phone screen off when closing", .toggle),
            Opt("no-power-on", "Don't wake phone on start", .toggle),
            Opt("disable-screensaver", "Disable Mac screensaver", .toggle),
        ]),
        OptGroup(title: "Apps & files", opts: [
            Opt("start-app", "Start app", .text("com.package.name or ?name"), "Use Device Info ▸ Apps to list them. Prefix + to force-stop first"),
            Opt("push-target", "Drag & drop target folder", .text("/sdcard/Download/")),
        ]),
        OptGroup(title: "Cleanup", opts: [
            Opt("no-cleanup", "Don't clean up on exit", .toggle),
            Opt("kill-adb-on-close", "Kill adb server on close", .toggle),
        ]),
    ]),
    OptTab(name: "Window", icon: "macwindow", groups: [
        OptGroup(title: "Window", opts: [
            Opt("window-title", "Window title", .text("phone model")),
            Opt("always-on-top", "Always on top", .toggle),
            Opt("fullscreen", "Start fullscreen", .toggle),
            Opt("window-borderless", "Borderless window", .toggle),
            Opt("no-window-aspect-ratio-lock", "Don't lock aspect ratio", .toggle),
            Opt("window-x", "Position X", .text("auto")),
            Opt("window-y", "Position Y", .text("auto")),
            Opt("window-width", "Width", .text("auto")),
            Opt("window-height", "Height", .text("auto")),
            Opt("background-color", "Background color", .text("#000000")),
            Opt("render-driver", "Render driver", .choice(["metal", "opengl", "opengles2", "software"])),
            Opt("no-window", "No window at all", .toggle),
            Opt("no-playback", "No playback (video + audio)", .toggle),
        ]),
    ]),
    OptTab(name: "Record", icon: "record.circle", groups: [
        OptGroup(title: "Recording (Record button)", opts: [
            Opt("record-orientation", "Record orientation", .choice(["0", "90", "180", "270"])),
            Opt("time-limit", "Time limit (s)", .text("unlimited"), "Stops viewing/recording automatically"),
        ]),
    ]),
    OptTab(name: "Camera", icon: "camera", groups: [
        OptGroup(title: "Camera (set Video ▸ Video source to camera)", opts: [
            Opt("camera-facing", "Camera", .choice(["back", "front", "external"])),
            Opt("camera-id", "Camera ID", .text("auto"), "Use Device Info ▸ Cameras to list them"),
            Opt("camera-size", "Camera size", .combo("auto", ["1280x720", "1920x1080", "3840x2160"])),
            Opt("camera-ar", "Aspect ratio", .combo("auto", ["sensor", "4:3", "16:9", "1:1"])),
            Opt("camera-fps", "Camera FPS", .combo("30", ["24", "30", "60", "120", "240"])),
            Opt("camera-zoom", "Zoom", .text("1.0")),
            Opt("camera-high-speed", "High-speed mode", .toggle),
            Opt("camera-torch", "Torch on", .toggle),
        ]),
    ]),
    OptTab(name: "Advanced", icon: "gearshape.2", groups: [
        OptGroup(title: "Connection", opts: [
            Opt("port", "Local port(s)", .text("27183:27199")),
            Opt("force-adb-forward", "Force adb forward", .toggle),
            Opt("tunnel-host", "Tunnel host", .text("localhost")),
            Opt("tunnel-port", "Tunnel port", .text("auto")),
        ]),
        OptGroup(title: "Debug", opts: [
            Opt("verbosity", "Log verbosity", .choice(["verbose", "debug", "info", "warn", "error"])),
            Opt("pause-on-exit", "Pause on exit", .choice(["true", "false", "if-error"])),
        ]),
    ]),
]

/// Built-in quick presets (applied on top of defaults).
let builtinPresets: [(String, [String: String])] = [
    ("Default", [:]),
    ("Low latency", ["max-size": "1280", "max-fps": "60", "video-bit-rate": "6M", "audio-buffer": "30"]),
    ("High quality", ["max-fps": "60", "video-bit-rate": "20M", "video-codec": "h265"]),
    ("Gaming (120 fps)", ["max-fps": "120", "video-bit-rate": "16M", "keyboard": "uhid", "gamepad": "uhid", "audio-buffer": "30"]),
    ("Battery saver", ["max-size": "1024", "max-fps": "30", "video-bit-rate": "4M", "turn-screen-off": "1", "stay-awake": "1"]),
    ("Phone as webcam", ["video-source": "camera", "camera-facing": "back", "camera-size": "1920x1080", "no-audio": "1"]),
    ("Second screen (virtual display)", ["new-display": "1", "new-display=": "1920x1080/240", "no-audio": "1"]),
]

/// Turns stored values into scrcpy arguments.
func buildArgs(_ v: [String: String]) -> [String] {
    var a: [String] = []
    for tab in optionTabs {
        for g in tab.groups {
            for o in g.opts {
                switch o.kind {
                case .toggle:
                    if v[o.flag] == "1" { a.append("--\(o.flag)") }
                case .optional:
                    if v[o.flag] == "1" {
                        let s = (v[o.flag + "="] ?? "").trimmingCharacters(in: .whitespaces)
                        a.append(s.isEmpty ? "--\(o.flag)" : "--\(o.flag)=\(s)")
                    }
                case .savePath:
                    if var s = v[o.flag]?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                        s = s.replacingOccurrences(of: "%t", with: f.string(from: Date()))
                        a.append("--\(o.flag)=\((s as NSString).expandingTildeInPath)")
                    }
                default:
                    if let s = v[o.flag]?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
                        a.append("--\(o.flag)=\(s)")
                    }
                }
            }
        }
    }
    return a + splitArgs(v["__extra"] ?? "")
}

/// Minimal shell-like splitter for the "extra arguments" box.
func splitArgs(_ s: String) -> [String] {
    var out: [String] = [], cur = "", quote: Character? = nil, has = false
    for c in s {
        if let q = quote {
            if c == q { quote = nil } else { cur.append(c) }
        } else if c == "\"" || c == "'" {
            quote = c; has = true
        } else if c == " " || c == "\n" || c == "\t" {
            if has || !cur.isEmpty { out.append(cur); cur = ""; has = false }
        } else { cur.append(c) }
    }
    if has || !cur.isEmpty { out.append(cur) }
    return out
}

func shellQuote(_ s: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_=./:,@%+"))
    if !s.isEmpty && s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
