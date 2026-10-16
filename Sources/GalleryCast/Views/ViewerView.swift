import SwiftUI
import AppKit

/// Full-window photo presentation: zoom, pan, keyboard navigation,
/// slideshow controls that auto-hide while playing, filmstrip, and the
/// info panel — all floating over a fixed dark surface so the photo,
/// not the chrome, dominates.
struct ViewerView: View {
    @Environment(AppModel.self) private var model

    // Zoom & pan
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero

    // Chrome visibility
    @State private var chromeVisible = true
    @State private var hideChromeTask: Task<Void, Never>?

    // Image
    @State private var image: DecodedImage?

    private var playing: Bool { model.slideshow.phase == .playing }
    private var order: [Photo] { model.filteredPhotos }

    var body: some View {
        ZStack {
            Token.Surface.viewer.ignoresSafeArea()

            photoLayer

            VStack {
                Spacer()
                if model.showFilmstrip {
                    FilmstripView()
                        .padding(.bottom, Token.Space.sm)
                }
                controlBar
                    .padding(.bottom, Token.Space.xl)
            }
            .opacity(chromeVisible ? Token.Chrome.opacityVisible : Token.Chrome.opacityHidden)

            VStack {
                headerBar
                    .padding(.top, Token.Space.lg)
                Spacer()
            }
            .opacity(chromeVisible ? Token.Chrome.opacityVisible : Token.Chrome.opacityHidden)

            if model.showInfoPanel {
                InfoPanelView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(Token.Space.lg)
            }
        }
        .animation(.easeOut(duration: Token.Duration.base), value: chromeVisible)
        .animation(.easeInOut(duration: Token.Duration.base), value: model.showInfoPanel)
        .task(id: model.viewerPhoto) {
            resetViewport()
            await loadImage()
        }
        .onAppear {
            if playing { scheduleChromeHide() }
        }
        .onChange(of: model.slideshow.phase) { _, phase in
            if phase == .playing {
                scheduleChromeHide()
            } else {
                cancelChromeHide()
                withAnimation(.easeOut(duration: Token.Duration.base)) {
                    chromeVisible = true
                }
            }
        }
        .onContinuousHover { _ in registerActivity() }
        .modifier(GlobalKeyMonitor { keyCode, modifiers in
            handleKey(keyCode: keyCode, modifiers: modifiers)
        })
    }

    // MARK: Photo layer

    @ViewBuilder
    private var photoLayer: some View {
        if let photo = model.viewerPhoto {
            Group {
                if let image {
                    Image(decorative: image.cgImage, scale: 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                        .tint(Token.Ink.inverse)
                        .scaleEffect(1.2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Token.Space.xxl)
            .scaleEffect(zoom)
            .offset(pan)
            .transition(.opacity)
            .id(photo)
            .animation(.easeInOut(duration: Token.Duration.slow), value: photo)
            .simultaneousGesture(zoomGesture.simultaneously(with: panGesture))
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: Token.Duration.base)) {
                    if zoom > 1.01 {
                        resetViewport()
                    } else {
                        zoom = 2.5
                        zoomBase = 2.5
                    }
                }
            }
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = clampedZoom(zoomBase * value.magnification)
            }
            .onEnded { _ in zoomBase = zoom }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard zoom > 1.01 else { return }
                pan = CGSize(
                    width: panBase.width + value.translation.width,
                    height: panBase.height + value.translation.height
                )
            }
            .onEnded { _ in panBase = pan }
    }

    // MARK: Chrome

    private var headerBar: some View {
        VStack(spacing: Token.Space.xxs) {
            Text(model.viewerPhoto?.filename ?? "")
                .font(.callout.weight(.medium))
                .foregroundStyle(Token.Ink.onChrome)
                .lineLimit(1)
            if let index = model.viewerIndex, !order.isEmpty {
                Text("\(index + 1) of \(order.count)")
                    .font(.caption)
                    .foregroundStyle(Token.Ink.onChrome.opacity(0.6))
            }
        }
        .padding(.horizontal, Token.Space.lg)
        .padding(.vertical, Token.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .fill(Token.Surface.viewerChrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var controlBar: some View {
        HStack(spacing: Token.Space.lg) {
            chromeButton("chevron.left") { model.navigate(-1) }
                .disabled(order.count < 2)

            chromeButton(playing ? "pause.fill" : "play.fill") {
                model.toggleSlideshow()
            }

            chromeButton("chevron.right") { model.navigate(1) }
                .disabled(order.count < 2)

            chromeDivider

            intervalMenu

            chromeButton("rectangle.stack.fill", isActive: model.showFilmstrip) {
                model.showFilmstrip.toggle()
            }
            CastMenu(chromeStyle: true)
            chromeButton("info.circle", isActive: model.showInfoPanel) {
                model.showInfoPanel.toggle()
            }

            chromeDivider

            chromeButton("xmark") { model.closeViewer() }
        }
        .padding(.horizontal, Token.Chrome.padding)
        .padding(.vertical, Token.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .fill(Token.Surface.viewerChrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Token.Chrome.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var chromeDivider: some View {
        Divider()
            .frame(height: Token.Space.xl)
            .overlay(Token.Ink.onChrome.opacity(0.25))
    }

    private var intervalMenu: some View {
        @Bindable var slideshow = model.slideshow
        return Menu {
            Picker("Interval", selection: $slideshow.interval) {
                ForEach(Token.Slideshow.intervals, id: \.self) { seconds in
                    Text("\(Int(seconds)) sec").tag(seconds)
                }
            }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(Token.Ink.onChrome)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func chromeButton(
        _ symbol: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Token.Accent.primary : Token.Ink.onChrome)
        .background(
            Circle().fill(isActive ? Color.white.opacity(0.10) : Color.clear)
        )
    }

    // MARK: Behavior

    private func loadImage() async {
        guard let photo = model.viewerPhoto else { return }
        let maxPixel = screenLongestSide * 2
        image = await ImageProvider.shared.presentation(for: photo, maxPixel: maxPixel)
    }

    private var screenLongestSide: CGFloat {
        guard let screen = NSScreen.main else { return 2_560 }
        return max(screen.frame.width, screen.frame.height)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), 8)
    }

    private func resetViewport() {
        zoom = 1
        zoomBase = 1
        pan = .zero
        panBase = .zero
    }

    private func registerActivity() {
        chromeVisible = true
        if playing { scheduleChromeHide() }
    }

    private func scheduleChromeHide() {
        hideChromeTask?.cancel()
        hideChromeTask = Task {
            try? await Task.sleep(for: .seconds(Token.Duration.chromeAutoHide))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Token.Duration.base)) {
                chromeVisible = false
            }
        }
    }

    private func cancelChromeHide() {
        hideChromeTask?.cancel()
        hideChromeTask = nil
    }

    private func handleKey(keyCode: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
        // Menu bar owns anything with modifiers (⌘O, ⌘W, ⌘Q, …).
        if modifiers.contains(.command) || modifiers.contains(.option)
            || modifiers.contains(.control) {
            return false
        }

        switch keyCode {
        case 123: // left arrow
            model.navigate(-1)
            registerActivity()
            return true
        case 124: // right arrow
            model.navigate(1)
            registerActivity()
            return true
        case 49: // space
            model.toggleSlideshow()
            registerActivity()
            return true
        case 53: // escape
            if zoom > 1.01 {
                withAnimation { resetViewport() }
            } else {
                model.closeViewer()
            }
            return true
        case 34: // i
            model.showInfoPanel.toggle()
            return true
        case 3: // f
            NSApp.keyWindow?.toggleFullScreen(nil)
            return true
        case 29: // 0
            withAnimation { resetViewport() }
            return true
        case 24, 69: // = / keypad +
            withAnimation { zoom = clampedZoom(zoom * 1.25); zoomBase = zoom }
            registerActivity()
            return true
        case 27, 78: // - / keypad -
            withAnimation { zoom = clampedZoom(zoom / 1.25); zoomBase = zoom }
            registerActivity()
            return true
        default:
            return false
        }
    }
}
