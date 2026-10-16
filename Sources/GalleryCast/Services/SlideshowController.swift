import Foundation
import Observation

enum SlideshowPhase: Equatable, Sendable {
    case idle
    case playing
    case paused
}

/// Owns slideshow phase and timing.
///
/// The photo *list* stays in `AppModel`; this controller only asks its
/// owner to advance the selection when a photo's time slot elapses.
/// That keeps slideshow order identical to the visible grid order.
@MainActor
@Observable
final class SlideshowController {
    private(set) var phase: SlideshowPhase = .idle

    /// Seconds each photo stays on screen while playing. Clamped to
    /// a sane range so bad values can never produce a busy loop.
    var interval: TimeInterval = Token.Slideshow.defaultInterval {
        didSet {
            let clamped = min(max(interval, 1), 300)
            if clamped != interval {
                interval = clamped
                return // clamping assignment does not re-enter didSet
            }
            if phase == .playing { restartTicker() }
        }
    }

    /// Called each time the current photo's time slot elapses.
    var onAdvance: (() -> Void)?

    private var ticker: Task<Void, Never>?

    var isRunning: Bool { phase != .idle }

    // MARK: Transitions

    func start() {
        phase = .playing
        restartTicker()
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
        cancelTicker()
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .playing
        restartTicker()
    }

    func toggle() {
        switch phase {
        case .idle: start()
        case .playing: pause()
        case .paused: resume()
        }
    }

    func stop() {
        phase = .idle
        cancelTicker()
    }

    /// Fires one advance event. Called by the ticker, by tests, and by
    /// nothing else — manual navigation goes through the app model.
    func handleTick() {
        guard phase == .playing else { return }
        onAdvance?()
    }

    // MARK: Ticker

    /// The Task inherits the main-actor context, so sleep + tick run
    /// on the main actor; interval changes take effect on the next slot.
    private func restartTicker() {
        cancelTicker()
        ticker = Task { [weak self] in
            while let self, !Task.isCancelled {
                let seconds = self.interval
                try? await Task.sleep(for: .seconds(seconds))
                if Task.isCancelled { break }
                self.handleTick()
            }
        }
    }

    private func cancelTicker() {
        ticker?.cancel()
        ticker = nil
    }
}
