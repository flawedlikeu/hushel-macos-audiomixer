import AppKit
import CoreAudio

struct AudioApp: Identifiable, Equatable {
    let id: String
    let name: String
    let icon: NSImage
    let processObjects: [AudioObjectID]

    static func == (a: AudioApp, b: AudioApp) -> Bool {
        a.id == b.id && a.processObjects == b.processObjects
    }
}

final class Mixer: ObservableObject {
    @Published private(set) var apps: [AudioApp] = []
    @Published private(set) var volumes: [String: Double]

    private var taps: [String: AppTap] = [:]
    private var timer: Timer?
    private let defaultsKey = "volumes"

    init() {
        volumes = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func volume(for id: String) -> Double {
        volumes[id] ?? 1.0
    }

    func setVolume(_ value: Double, for id: String) {
        volumes[id] = value
        UserDefaults.standard.set(volumes, forKey: defaultsKey)
        if let app = apps.first(where: { $0.id == id }) {
            apply(app)
        }
    }

    func refresh() {
        let own = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != nil }

        var objects: [String: [AudioObjectID]] = [:]
        var owners: [String: NSRunningApplication] = [:]
        var active: Set<String> = []

        for obj in audioProcessList() {
            guard let bid = stringProperty(obj, kAudioProcessPropertyBundleID),
                  !bid.isEmpty, bid != own else { continue }

            let owner = running
                .filter { app in
                    let b = app.bundleIdentifier!
                    return bid == b || bid.hasPrefix(b + ".")
                }
                .max { $0.bundleIdentifier!.count < $1.bundleIdentifier!.count }

            let key = owner?.bundleIdentifier ?? bid
            objects[key, default: []].append(obj)
            if let owner { owners[key] = owner }
            if uint32Property(obj, kAudioProcessPropertyIsRunningOutput) == 1 {
                active.insert(key)
            }
        }

        let newApps: [AudioApp] = objects.keys
            .filter { active.contains($0) || taps[$0] != nil }
            .map { key in
                let owner = owners[key]
                let fallbackName = key.split(separator: ".").last.map(String.init) ?? key
                let fallbackIcon = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil) ?? NSImage()
                return AudioApp(
                    id: key,
                    name: owner?.localizedName ?? fallbackName,
                    icon: owner?.icon ?? fallbackIcon,
                    processObjects: objects[key]!.sorted()
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if newApps != apps { apps = newApps }

        for key in Array(taps.keys) where objects[key] == nil {
            taps[key] = nil
        }
        for app in newApps {
            apply(app)
        }
    }

    private func apply(_ app: AudioApp) {
        let gain = Float(volume(for: app.id))
        if gain >= 0.999 {
            taps[app.id] = nil
            return
        }
        guard let uid = defaultOutputUID() else { return }

        if let tap = taps[app.id] {
            if tap.objects == app.processObjects && tap.outputUID == uid {
                tap.volume = gain
                return
            }
            taps[app.id] = nil
        }
        taps[app.id] = AppTap(objects: app.processObjects, outputUID: uid, volume: gain)
    }
}
