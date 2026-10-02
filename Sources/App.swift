import SwiftUI
import AppKit

// MARK: - Entry point (чистый AppKit, без SwiftUI-сцен)

@main
enum HushelMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - Status item + popover

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let mixer = Mixer()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Hushel")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: ContentView(onOpenSettings: { [weak self] in self?.openSettings() }).environmentObject(mixer))
        host.sizingOptions = .preferredContentSize   // окно подстраивается под содержимое
        popover.contentViewController = host
        popover.behavior = .transient                // закрывается кликом снаружи
    }

    // Левый клик: поповер как раньше. Правый клик: маленькое меню.
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: NSLocalizedString("Settings…", comment: "Status item menu"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("Quit", comment: "Status item menu"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(mixer)))
            window.title = "Hushel"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - Main view

struct ContentView: View {
    @EnvironmentObject var mixer: Mixer
    var onOpenSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Hushel")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Quit")
            }
            .padding(.horizontal, 4)

            GlassGroup {
                VStack(spacing: 6) {
                    if mixer.apps.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.zzz.fill")
                                .foregroundStyle(.secondary)
                            Text("No app is playing audio right now")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .card(cornerRadius: 16)
                    } else {
                        ForEach(mixer.apps) { app in
                            AppRow(app: app)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}

// MARK: - App row

struct AppRow: View {
    let app: AudioApp
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)
                GlassSlider(value: Binding(
                    get: { mixer.volume(for: app.id) },
                    set: { mixer.setVolume($0, for: app.id) }
                ))
            }

            Text("\(Int((mixer.volume(for: app.id) * 100).rounded()))%")
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(10)
        .card(cornerRadius: 16)
    }
}

// MARK: - Slider

struct GlassSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumb: CGFloat = 16
            let x = (width - thumb) * value

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.15))
                    .frame(height: 5)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: x + thumb / 2, height: 5)
                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let v = min(max((g.location.x - thumb / 2) / (width - thumb), 0), 1)
                    value = v > 0.97 ? 1 : v   // лёгкая "липкость" у 100%
                }
            )
        }
        .frame(height: 18)
    }
}

// MARK: - Liquid Glass (macOS 26+) with fallback

extension View {
    @ViewBuilder
    func card(cornerRadius: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}

struct GlassGroup<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
