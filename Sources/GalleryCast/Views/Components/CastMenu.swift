import SwiftUI

/// The Cast menu: devices found on the network, the current casting
/// state, and stop. Appears in the grid toolbar (labeled) and in the
/// viewer control bar (compact, chrome-styled).
struct CastMenu: View {
    @Environment(AppModel.self) private var model

    /// Render in viewer-chrome style: icon-only, borderless.
    var chromeStyle = false

    var body: some View {
        if chromeStyle {
            menu
                .menuStyle(.borderlessButton)
                .fixedSize()
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            content
        } label: {
            label
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.casting.isActive {
            Section {
                Button {
                    model.casting.stop()
                } label: {
                    Label("Stop Casting", systemImage: "stop.fill")
                }
            } header: {
                Text("Casting to \(model.casting.deviceName ?? "device")")
            }
        } else {
            Section("Devices") {
                if model.castDiscovery.devices.isEmpty {
                    if model.castDiscovery.isBrowsing {
                        Text("Searching for devices…")
                    } else if let error = model.castDiscovery.lastError {
                        Text(error)
                    } else {
                        Text("No devices found")
                    }
                } else {
                    ForEach(model.castDiscovery.devices) { device in
                        Button(device.name) {
                            model.startCasting(device)
                        }
                    }
                }
            }
        }

        if let error = model.casting.lastError {
            Text(error)
        }
    }

    @ViewBuilder
    private var label: some View {
        if chromeStyle {
            Image(systemName: model.casting.isActive ? "tv.fill" : "tv")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(
                    model.casting.isActive ? Token.Accent.primary : Token.Ink.onChrome
                )
        } else {
            Label("Cast", systemImage: model.casting.isActive ? "tv.fill" : "tv")
        }
    }
}
