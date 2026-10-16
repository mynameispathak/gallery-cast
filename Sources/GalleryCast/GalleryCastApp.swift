import SwiftUI

@main
struct GalleryCastApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("Gallery Cast") {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") {
                    model.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Slideshow") {
                Button(
                    model.slideshow.phase == .playing
                        ? "Pause Slideshow" : "Play Slideshow"
                ) {
                    model.toggleSlideshow()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.filteredPhotos.isEmpty)

                Button("Stop Slideshow") {
                    model.slideshow.stop()
                }
                .disabled(!model.slideshow.isRunning)

                Divider()

                ForEach(Token.Slideshow.intervals, id: \.self) { seconds in
                    Button {
                        model.slideshow.interval = seconds
                    } label: {
                        if model.slideshow.interval == seconds {
                            Label("\(Int(seconds)) Seconds", systemImage: "checkmark")
                        } else {
                            Text("\(Int(seconds)) Seconds")
                        }
                    }
                }
            }
        }
    }
}
