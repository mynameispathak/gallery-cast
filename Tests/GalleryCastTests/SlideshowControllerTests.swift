import Foundation
import Testing
@testable import GalleryCast

@MainActor
@Suite
struct SlideshowControllerTests {

    // MARK: Phase

    @Test func initialPhaseIsIdle() {
        let controller = SlideshowController()
        #expect(controller.phase == .idle)
        #expect(!controller.isRunning)
    }

    @Test func startTransitionsToPlaying() {
        let controller = SlideshowController()
        controller.start()
        #expect(controller.phase == .playing)
        #expect(controller.isRunning)
    }

    @Test func pauseThenResumeRoundTrips() {
        let controller = SlideshowController()
        controller.start()
        controller.pause()
        #expect(controller.phase == .paused)
        controller.resume()
        #expect(controller.phase == .playing)
    }

    @Test func pauseWhileIdleIsNoOp() {
        let controller = SlideshowController()
        controller.pause()
        #expect(controller.phase == .idle)
    }

    @Test func resumeWhileIdleIsNoOp() {
        let controller = SlideshowController()
        controller.resume()
        #expect(controller.phase == .idle)
    }

    @Test func stopReturnsToIdleFromAnyState() {
        let controller = SlideshowController()

        controller.start()
        controller.stop()
        #expect(controller.phase == .idle)

        controller.start()
        controller.pause()
        controller.stop()
        #expect(controller.phase == .idle)

        controller.stop()
        #expect(controller.phase == .idle)
    }

    @Test func toggleCyclesIdlePlayingPaused() {
        let controller = SlideshowController()

        controller.toggle()
        #expect(controller.phase == .playing)

        controller.toggle()
        #expect(controller.phase == .paused)

        controller.toggle()
        #expect(controller.phase == .playing)
    }

    // MARK: Advance

    @Test func ticksAdvanceOnlyWhilePlaying() {
        let controller = SlideshowController()
        var ticks = 0
        controller.onAdvance = { ticks += 1 }

        controller.handleTick()
        #expect(ticks == 0)

        controller.start()
        controller.handleTick()
        #expect(ticks == 1)

        controller.pause()
        controller.handleTick()
        #expect(ticks == 1)

        controller.stop()
        controller.handleTick()
        #expect(ticks == 1)
    }

    // MARK: Interval

    @Test func intervalClampsToSaneRange() {
        let controller = SlideshowController()

        controller.interval = 0
        #expect(controller.interval >= 1)

        controller.interval = 10_000
        #expect(controller.interval <= 300)

        controller.interval = 7
        #expect(controller.interval == 7)
    }
}
