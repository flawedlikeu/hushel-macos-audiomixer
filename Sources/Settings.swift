import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

/// Название и иконка приложения по bundle id (работает и для незапущенных).
func appInfo(for bundleID: String) -> (name: String, icon: NSImage) {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        return (name, NSWorkspace.shared.icon(forFile: url.path))
    }
    let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    return (fallback, NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage())
}

struct SettingsView: View {
    @EnvironmentObject var mixer: Mixer

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorText: String?
    @State private var selected: String?
    @State private var tab: Tab = .general
    @State private var language = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    @State private var languageChanged = false

    private enum Tab { case general, equalizer }

    private let bandLabels = ["60", "250", "1k", "4k", "12k"]

    private var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    private var configured: [String] {
        mixer.eq.keys.sorted {
            appInfo(for: $0).name.localizedCaseInsensitiveCompare(appInfo(for: $1).name) == .orderedAscending
        }
    }

    private var runningApps: [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("General").tag(Tab.general)
                Text("Equalizer").tag(Tab.equalizer)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.top, 16)

            switch tab {
            case .general: generalTab
            case .equalizer: equalizerTab
            }
        }
        .frame(width: 460, height: 380)
        .onAppear {
            if selected == nil { selected = configured.first }
        }
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))

            HStack {
                Text("Language")
                Picker("", selection: $language) {
                    Text("System").tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "Русский").tag("ru")
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: language) { _, new in applyLanguage(new) }
            }

            if languageChanged {
                HStack {
                    Text("Restart Hushel to apply the language.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Restart") { relaunch() }
                }
            }

            if needsApproval {
                Text("Allow Hushel in General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Equalizer

    private var equalizerTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: $selected) {
                    Text("Choose an app").tag(String?.none)
                    ForEach(configured, id: \.self) { id in
                        Text(appInfo(for: id).name).tag(Optional(id))
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                Menu("Add…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) {
                            addApp(app.bundleIdentifier!)
                        }
                    }
                    Divider()
                    Button("Other app…") { pickApp() }
                }
                .fixedSize()

                Spacer()

                Button("Remove") {
                    if let id = selected {
                        mixer.removeEQ(for: id)
                        selected = configured.first
                    }
                }
                .disabled(selected == nil)
            }

            eqPanel
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var eqPanel: some View {
        if let id = selected, mixer.eq[id] != nil {
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<EQProcessor.bandCount, id: \.self) { band in
                        VStack(spacing: 6) {
                            Text(String(format: "%+.0f", mixer.eqGains(for: id)[band]))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            VerticalSlider(value: bandBinding(id, band))
                                .frame(width: 28, height: 130)
                            Text(bandLabels[band]).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Text("dB, frequencies in Hz").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        mixer.setEQ(Array(repeating: 0, count: EQProcessor.bandCount), for: id)
                    }
                }
            }
            .frame(height: 230)
        } else {
            Text("Add an app to set up its equalizer.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 230)
        }
    }

    private func bandBinding(_ id: String, _ band: Int) -> Binding<Double> {
        Binding(
            get: { mixer.eqGains(for: id)[band] },
            set: { value in
                var gains = mixer.eqGains(for: id)
                gains[band] = value
                mixer.setEQ(gains, for: id)
            }
        )
    }

    // MARK: Actions

    private func addApp(_ id: String) {
        if mixer.eq[id] == nil {
            mixer.setEQ(Array(repeating: 0, count: EQProcessor.bandCount), for: id)
        }
        selected = id
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url,
           let id = Bundle(url: url)?.bundleIdentifier {
            addApp(id)
        }
    }

    private func applyLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "appLanguage")
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        languageChanged = true
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Вертикальный ползунок −12…+12 дБ, нарисованный на SwiftUI
/// (повёрнутый системный Slider на macOS отображается ненадёжно).
struct VerticalSlider: View {
    @Binding var value: Double
    private let range: ClosedRange<Double> = -12...12

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let thumb: CGFloat = 16
            let span = height - thumb
            let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbTop = span * (1 - t)
            let thumbCenter = thumbTop + thumb / 2
            let center = height / 2

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 5, height: height)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 5, height: abs(thumbCenter - center))
                    .offset(y: min(thumbCenter, center))
                Rectangle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 12, height: 1)
                    .offset(y: center)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(y: thumbTop)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let ty = min(max((g.location.y - thumb / 2) / span, 0), 1)
                    let v = range.upperBound - ty * (range.upperBound - range.lowerBound)
                    value = v.rounded()
                }
            )
        }
    }
}
