import AppKit
import SwiftUI

@main
struct ScrcpyLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Window("Scrcpy Launcher", id: "main") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 420)
        }
        .defaultSize(width: 900, height: 560)
        .commands {
            CommandGroup(after: .newItem) {
                Button("View All Devices") { model.viewAll() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Refresh Devices") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Stop Everything") { model.stopAll() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            GlobalSettingsView()
                .environmentObject(model)
                .frame(width: 760, height: 620)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.stopAll() }
        Thread.sleep(forTimeInterval: 0.5)   // let recordings flush
    }
}

// MARK: - Main window

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()
            if Tools.scrcpy == nil || Tools.adb == nil {
                Text(Tools.scrcpy == nil ? "scrcpy not found. Install it with: brew install scrcpy"
                                         : "adb not found. Install it with: brew install --cask android-platform-tools")
                    .font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.15))
            }
            if m.devices.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "iphone.slash").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No devices connected").font(.title3.weight(.medium))
                    Text("Plug in your phone with USB, turn on Developer options ▸ USB debugging,\nand accept the prompt on the phone. Or connect over Wi-Fi above.")
                        .multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(m.devices) { d in DeviceCard(device: d) }
                    }
                    .padding(14)
                }
            }
            Divider()
            HStack {
                if m.busy { ProgressView().controlSize(.small) }
                Text(m.status.isEmpty ? "\(m.devices.filter(\.ready).count) device(s) ready" : m.status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                Spacer()
                if let f = m.lastFile {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                        .controlSize(.small)
                }
                Menu {
                    Button("Recordings Folder") { m.openFolder("recDir") }
                    Button("Screenshots Folder") { m.openFolder("shotDir") }
                } label: { Label("Open Folder", systemImage: "folder") }
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .onReceive(timer) { _ in m.refresh() }
        .sheet(item: $m.infoText) { info in InfoSheet(info: info) }
        .sheet(item: $m.logSession) { s in LogSheet(session: s) }
        .sheet(item: $m.editing) { d in DeviceSettingsSheet(device: d).environmentObject(m) }
    }
}

struct TopBar: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("connectAddr") private var connectAddr = ""
    @AppStorage("pairAddr") private var pairAddr = ""

    var body: some View {
        HStack(spacing: 10) {
            Text("Devices").font(.title3.weight(.semibold))
            Button { m.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh (⌘R)")
            Spacer()
            TextField("Wi-Fi IP, e.g. 192.168.1.20:5555", text: $connectAddr)
                .textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit { m.connect(connectAddr) }
            Button("Connect") { m.connect(connectAddr) }
            Button("Pair…") { m.showPair.toggle() }
                .popover(isPresented: $m.showPair) { pairPopover }
                .help("Pair with Android 11+ wireless debugging")
            Divider().frame(height: 18)
            if m.views.isEmpty && m.recordings.isEmpty {
                Button { m.viewAll() } label: { Label("View All", systemImage: "rectangle.stack") }
                    .disabled(m.devices.filter(\.ready).isEmpty)
            } else {
                Button { m.stopAll() } label: { Label("Stop All", systemImage: "stop.fill") }
            }
            SettingsLink { Image(systemName: "gearshape") }
                .help("Default settings for all devices (⌘,)")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var pairPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wireless debugging pairing").font(.headline)
            Text("On the phone: Developer options ▸ Wireless debugging ▸ Pair device with pairing code.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("IP:port shown on phone", text: $pairAddr).textFieldStyle(.roundedBorder)
            TextField("6-digit code", text: $m.pairCode).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Pair") { m.pair(pairAddr, code: m.pairCode); m.showPair = false }
                    .keyboardShortcut(.defaultAction)
            }
            Text("After pairing, type the IP:port from the main Wireless debugging screen and press Connect.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 300)
    }
}

// MARK: - Device row

struct DeviceCard: View {
    let device: Device
    @EnvironmentObject var m: AppModel

    var body: some View {
        let viewing = m.views[device.serial] != nil
        let rec = m.recordings[device.serial]

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(device.ready ? 0.15 : 0.06))
                Image(systemName: "iphone").font(.system(size: 20))
                    .foregroundStyle(device.ready ? Color.accentColor : .secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(device.model).font(.body.weight(.semibold)).lineLimit(1)
                    if m.hasOverrides(device) {
                        Text("Custom settings").font(.caption2.weight(.medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }
                HStack(spacing: 6) {
                    Label(device.wireless ? "Wi-Fi" : "USB", systemImage: device.wireless ? "wifi" : "cable.connector")
                    Text("·")
                    Text(device.serial).font(.caption.monospaced()).lineLimit(1)
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !device.ready {
                Text(device.state == "unauthorized" ? "Unlock phone and allow USB debugging" : "State: \(device.state)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
            } else {
                if let rec {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let t = Int(ctx.date.timeIntervalSince(rec.started))
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text(String(format: "%d:%02d", t / 60, t % 60)).font(.caption.monospacedDigit())
                        }
                    }
                }

                Button { m.toggleView(device) } label: {
                    Label(viewing ? "Stop" : "View", systemImage: viewing ? "stop.fill" : "play.fill")
                        .frame(width: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(viewing ? .red : .accentColor)
                .help(viewing ? "Close the mirror window" : "Open the mirror window")

                Button { m.screenshot(device) } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                .help("Save a PNG of the phone's screen")

                Button { m.toggleRecord(device) } label: {
                    Label(rec != nil ? "Stop" : "Record", systemImage: rec != nil ? "stop.circle.fill" : "record.circle")
                        .frame(width: 62)
                }
                .tint(rec != nil ? .red : nil)
                .buttonStyle(.bordered)
                .help(rec != nil ? "Stop and save the recording" : "Record the phone's screen to an MP4")
            }

            Button { m.editing = device } label: { Image(systemName: "gearshape") }
                .help("Settings for this device")

            Menu {
                if device.ready {
                    Menu("Device Info") {
                        Button("Displays") { m.query("--list-displays", "Displays", device) }
                        Button("Cameras") { m.query("--list-cameras", "Cameras", device) }
                        Button("Camera sizes") { m.query("--list-camera-sizes", "Camera sizes", device) }
                        Button("Encoders") { m.query("--list-encoders", "Encoders", device) }
                        Button("Installed apps") { m.query("--list-apps", "Apps", device) }
                    }
                    if !device.wireless { Button("Switch to Wi-Fi") { m.goWireless(device) } }
                }
                if device.wireless { Button("Disconnect") { m.disconnect(device) } }
                if let s = m.lastSession[device.serial] { Button("Show Log") { m.logSession = s } }
                Divider()
                Button("Copy Serial") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.serial, forType: .string)
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
    }
}

// MARK: - Settings windows

struct GlobalSettingsView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("shotDir") private var shotDir = ""
    @AppStorage("recDir") private var recDir = ""
    @AppStorage("revealFiles") private var revealFiles = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default settings").font(.headline)
                    Text("Used by every device unless that device has its own setting (⚙︎ on its row).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 12)
            SettingsTabs(scope: .global) {
                Form {
                    Section("Saving") {
                        FolderRow(title: "Screenshots folder", path: $shotDir)
                        FolderRow(title: "Recordings folder", path: $recDir)
                        Toggle("Show files in Finder after saving", isOn: $revealFiles)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Label("General", systemImage: "folder") }
                .tag("General")
            }
        }
    }
}

struct DeviceSettingsSheet: View {
    let device: Device
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Settings for \(device.model)").font(.headline)
                    Text("Changes here apply only to this phone. Everything else follows the default settings. A ↺ button resets one setting to the default.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            SettingsTabs(scope: .device(device.hwid)) { EmptyView() }
        }
        .frame(width: 780, height: 640)
    }
}

/// The option tabs, toolbar and command preview, for either scope.
struct SettingsTabs<Extra: View>: View {
    let scope: Scope
    @ViewBuilder let extra: () -> Extra
    @EnvironmentObject var m: AppModel
    @AppStorage("settingsTab") private var tab = "Video"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                Menu {
                    Section("Presets") {
                        ForEach(builtinPresets, id: \.0) { p in Button(p.0) { m.apply(p.1, scope) } }
                    }
                    if !m.profiles.isEmpty {
                        Section("My profiles") {
                            ForEach(m.profiles.keys.sorted(), id: \.self) { k in
                                Button(k) { m.apply(m.profiles[k] ?? [:], scope) }
                            }
                        }
                        Menu("Delete profile") {
                            ForEach(m.profiles.keys.sorted(), id: \.self) { k in
                                Button(k) { m.profiles[k] = nil }
                            }
                        }
                    }
                    Divider()
                    Button("Save these settings as profile…") { m.saveProfile(from: scope) }
                } label: { Label("Presets & Profiles", systemImage: "slider.horizontal.3") }
                .fixedSize()
                Button(scope == .global ? "Reset All" : "Use Defaults for All") { m.resetAll(scope) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            TabView(selection: $tab) {
                extra()
                ForEach(optionTabs) { t in
                    Form {
                        ForEach(t.groups) { g in
                            Section(g.title) {
                                ForEach(g.opts) { o in OptionRow(opt: o, scope: scope) }
                            }
                        }
                        if t.name == "Advanced" {
                            Section("Extra arguments") {
                                TextEditor(text: m.text("__extra", scope))
                                    .font(.body.monospaced())
                                    .frame(minHeight: 60)
                                HStack {
                                    Text("Any additional scrcpy flags, e.g. --no-mouse-hover --print-fps")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    ResetButton(key: "__extra", scope: scope)
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .tabItem { Label(t.name, systemImage: t.icon) }
                    .tag(t.name)
                }
            }
            .padding(.horizontal, 8)

            HStack(alignment: .top) {
                Text(m.commandPreview(scope))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(m.commandPreview(scope), forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy command")
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06))
        }
    }
}

struct FolderRow: View {
    let title: String
    @Binding var path: String
    var body: some View {
        LabeledContent(title) {
            HStack {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choose…") {
                    let p = NSOpenPanel()
                    p.canChooseDirectories = true
                    p.canChooseFiles = false
                    p.canCreateDirectories = true
                    p.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                    if p.runModal() == .OK, let u = p.url { path = u.path }
                }
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .buttonStyle(.borderless).help("Open folder")
            }
        }
    }
}

struct ResetButton: View {
    let key: String
    let scope: Scope
    @EnvironmentObject var m: AppModel
    var body: some View {
        if m.isOverridden(key, scope) {
            Button { m.reset(key, scope) } label: { Image(systemName: "arrow.uturn.backward.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .help("Custom for this device. Click to use the default (\(m.values[key].map { $0.isEmpty ? "off" : $0 } ?? "off")).")
        }
    }
}

struct OptionRow: View {
    let opt: Opt
    let scope: Scope
    @EnvironmentObject var m: AppModel

    var body: some View {
        switch opt.kind {
        case .toggle:
            Toggle(isOn: m.bool(opt.flag, scope)) { label }
        case .text(let ph):
            LabeledContent { field(ph) } label: { label }
        case .combo(let ph, let items):
            LabeledContent {
                HStack(spacing: 4) {
                    field(ph)
                    Menu {
                        Button("Default") { m.set(opt.flag, "", scope) }
                        Divider()
                        ForEach(items, id: \.self) { i in Button(i) { m.set(opt.flag, i, scope) } }
                    } label: { EmptyView() }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            } label: { label }
        case .choice(let items):
            Picker(selection: m.text(opt.flag, scope)) {
                Text("Default").tag("")
                ForEach(items, id: \.self) { Text($0).tag($0) }
            } label: { label }
        case .optional(let ph):
            LabeledContent {
                HStack {
                    TextField("", text: m.text(opt.flag + "=", scope), prompt: Text(ph))
                        .textFieldStyle(.roundedBorder).frame(width: 150)
                        .disabled(m.get(opt.flag, scope) != "1")
                    Toggle("", isOn: m.bool(opt.flag, scope)).labelsHidden()
                }
            } label: { label }
        case .savePath(let ph):
            LabeledContent { field(ph) } label: { label }
        }
    }

    private func field(_ ph: String) -> some View {
        TextField("", text: m.text(opt.flag, scope), prompt: Text(ph))
            .textFieldStyle(.roundedBorder)
            .frame(width: 180)
    }

    private var label: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opt.label)
                Text("--\(opt.flag)" + (opt.help.isEmpty ? "" : " · \(opt.help)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ResetButton(key: opt.flag, scope: scope)
            if case .optional = opt.kind { ResetButton(key: opt.flag + "=", scope: scope) }
        }
    }
}

// MARK: - Sheets

struct InfoSheet: View {
    let info: AppModel.InfoText
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(info.title).font(.headline)
            ScrollView {
                Text(info.text).font(.callout.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            HStack {
                Text("Copy a value into the matching setting (e.g. --display-id, --camera-id, --start-app).")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 720, height: 500)
    }
}

struct LogSheet: View {
    @ObservedObject var session: Session
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(session.name) — \(session.kind == .view ? "View" : "Recording") — \(session.running ? "running" : "exited (\(session.exitCode))")")
                .font(.headline)
            Text(session.command).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            ScrollViewReader { proxy in
                ScrollView {
                    Text(session.log.isEmpty ? "(no output yet)" : session.log)
                        .font(.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("end")
                }
                .onAppear { proxy.scrollTo("end") }
                .onChange(of: session.log) { proxy.scrollTo("end") }
            }
            .padding(8).background(Color.secondary.opacity(0.08)).cornerRadius(6)
            HStack {
                Spacer()
                if session.running { Button("Stop") { session.stop() } }
                Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(width: 720, height: 480)
    }
}
