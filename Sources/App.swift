import SwiftUI

@main
struct HushelApp: App {
    @StateObject private var mixer = Mixer()

    var body: some Scene {
        MenuBarExtra("Hushel", systemImage: "slider.vertical.3") {
            ContentView().environmentObject(mixer)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @EnvironmentObject var mixer: Mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mixer.apps.isEmpty {
                Text("Сейчас ни одно приложение не воспроизводит звук")
                    .foregroundStyle(.secondary)
            }
            ForEach(mixer.apps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text(app.name)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { mixer.volume(for: app.id) },
                            set: { mixer.setVolume($0, for: app.id) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(mixer.volume(for: app.id) * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Divider()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 360)
    }
}
