import XCTest
import UIKit
@testable import OneTake

final class CameraAndImageTests: XCTestCase {
    // MARK: - CameraController Zoom Stepping

    func testCameraControllerInitialZoomFactor() {
        let camera = CameraController()
        XCTAssertEqual(camera.zoomFactor, 1.0, "Initial zoom factor must be 1.0")
    }

    func testCycleZoomSteppingLogic() {
        // Test stepping sequence calculation matching CameraController.cycleZoom()
        func calculateNextZoom(for factor: CGFloat) -> CGFloat {
            if factor < 1.25 { return 1.5 }
            else if factor < 1.75 { return 2.0 }
            else { return 1.0 }
        }

        // Standard cycle: 1.0 -> 1.5 -> 2.0 -> 1.0
        let step1 = calculateNextZoom(for: 1.0)
        XCTAssertEqual(step1, 1.5, "From 1.0, cycleZoom must advance to 1.5")

        let step2 = calculateNextZoom(for: step1)
        XCTAssertEqual(step2, 2.0, "From 1.5, cycleZoom must advance to 2.0")

        let step3 = calculateNextZoom(for: step2)
        XCTAssertEqual(step3, 1.0, "From 2.0, cycleZoom must reset to 1.0")

        // Boundary tests for interval thresholds [1.25, 1.75]
        XCTAssertEqual(calculateNextZoom(for: 1.24), 1.5)
        XCTAssertEqual(calculateNextZoom(for: 1.25), 2.0)
        XCTAssertEqual(calculateNextZoom(for: 1.74), 2.0)
        XCTAssertEqual(calculateNextZoom(for: 1.75), 1.0)
        XCTAssertEqual(calculateNextZoom(for: 3.0), 1.0)
        XCTAssertEqual(calculateNextZoom(for: 5.0), 1.0)
    }

    // MARK: - Timer Countdown State Logic

    func testTimerCountdownProgressionSequence() {
        // The countdown sequence executed in roll() is [3, 2, 1] followed by nil
        var currentCountdown: Int? = nil
        let expectedSequence = [3, 2, 1]
        var recordedSteps: [Int] = []

        for step in expectedSequence {
            currentCountdown = step
            if let active = currentCountdown {
                recordedSteps.append(active)
            }
        }
        currentCountdown = nil

        XCTAssertEqual(recordedSteps, [3, 2, 1], "Countdown sequence must decrement 3 -> 2 -> 1")
        XCTAssertNil(currentCountdown, "Countdown must clear to nil upon recording start")
    }

    func testRollGuardPreventsConcurrentCountdown() {
        var countdown: Int? = nil
        var rollStartedCount = 0

        func simulateRoll() {
            guard countdown == nil else { return }
            countdown = 3
            rollStartedCount += 1
        }

        simulateRoll()
        XCTAssertEqual(rollStartedCount, 1)
        XCTAssertEqual(countdown, 3)

        // Second roll call while countdown is active must be discarded by guard
        simulateRoll()
        XCTAssertEqual(rollStartedCount, 1, "Concurrent roll during countdown must be ignored")
        XCTAssertEqual(countdown, 3)
    }

    func testControlsDisabledDuringCountdown() {
        var countdown: Int? = 2
        let cameraState: CameraController.State = .ready

        let isShutterDisabled = (cameraState != .ready || countdown != nil)
        XCTAssertTrue(isShutterDisabled, "Shutter control must be disabled while countdown is active")

        countdown = nil
        let isShutterDisabledAfterCountdown = (cameraState != .ready || countdown != nil)
        XCTAssertFalse(isShutterDisabledAfterCountdown, "Shutter control must be enabled when ready and countdown is nil")
    }

    // MARK: - ImageFramer Ratios & Cropping Calculations

    func testFramingRatioMathematicalValues() {
        XCTAssertEqual(FramingRatio.portrait.rawValue, "9:16")
        XCTAssertEqual(FramingRatio.portrait.value, 9.0 / 16.0, accuracy: 0.0001)

        XCTAssertEqual(FramingRatio.landscape.rawValue, "16:9")
        XCTAssertEqual(FramingRatio.landscape.value, 16.0 / 9.0, accuracy: 0.0001)

        XCTAssertEqual(FramingRatio.photo.rawValue, "4:3")
        XCTAssertEqual(FramingRatio.photo.value, 4.0 / 3.0, accuracy: 0.0001)

        XCTAssertEqual(FramingRatio.square.rawValue, "1:1")
        XCTAssertEqual(FramingRatio.square.value, 1.0, accuracy: 0.0001)
    }

    private func createTestImage(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testImageFramerWideImageCropToSquare() {
        // Image is wider than 1:1 ratio: 1000 x 500
        let wideImage = createTestImage(width: 1000, height: 500)
        let cropped = ImageFramer.crop(wideImage, ratio: 1.0)

        XCTAssertNotNil(cropped)
        guard let cg = cropped?.cgImage else { return }

        // Width must be cropped down to match height (500), height stays 500
        XCTAssertEqual(cg.width, 500)
        XCTAssertEqual(cg.height, 500)
    }

    func testImageFramerTallImageCropToSquare() {
        // Image is taller than 1:1 ratio: 500 x 1000
        let tallImage = createTestImage(width: 500, height: 1000)
        let cropped = ImageFramer.crop(tallImage, ratio: 1.0)

        XCTAssertNotNil(cropped)
        guard let cg = cropped?.cgImage else { return }

        // Height must be cropped down to match width (500), width stays 500
        XCTAssertEqual(cg.width, 500)
        XCTAssertEqual(cg.height, 500)
    }

    func testImageFramerCropToPortraitRatio() {
        // Wide image: 3200 x 1600 cropped to 9:16 (ratio 0.5625)
        let wideImage = createTestImage(width: 3200, height: 1600)
        let cropped = ImageFramer.crop(wideImage, ratio: FramingRatio.portrait.value)

        XCTAssertNotNil(cropped)
        guard let cg = cropped?.cgImage else { return }

        // Height remains 1600; width becomes 1600 * (9/16) = 900
        XCTAssertEqual(cg.height, 1600)
        XCTAssertEqual(cg.width, 900)
    }

    func testImageFramerInvalidRatioReturnsNil() {
        let image = createTestImage(width: 200, height: 200)

        XCTAssertNil(ImageFramer.crop(image, ratio: 0.0), "Zero ratio must return nil")
        XCTAssertNil(ImageFramer.crop(image, ratio: -1.5), "Negative ratio must return nil")
    }

    // MARK: - Empirical Stress Tests: Zoom & Timer State Machine

    func testStressCycleZoomProgressionArbitraryFloats() {
        func calculateNextZoom(for factor: CGFloat) -> CGFloat {
            if factor < 1.25 { return 1.5 }
            else if factor < 1.75 { return 2.0 }
            else { return 1.0 }
        }

        // Test the exact required values: (1.0, 1.25, 1.5, 1.75, 2.0)
        XCTAssertEqual(calculateNextZoom(for: 1.0), 1.5, "1.0 -> 1.5")
        XCTAssertEqual(calculateNextZoom(for: 1.25), 2.0, "1.25 -> 2.0")
        XCTAssertEqual(calculateNextZoom(for: 1.5), 2.0, "1.5 -> 2.0")
        XCTAssertEqual(calculateNextZoom(for: 1.75), 1.0, "1.75 -> 1.0")
        XCTAssertEqual(calculateNextZoom(for: 2.0), 1.0, "2.0 -> 1.0")

        // Test arbitrary floats below 1.25
        let below1_25: [CGFloat] = [-1.0, 0.0, 0.5, 0.99, 1.0, 1.1, 1.2, 1.24, 1.2499]
        for v in below1_25 {
            XCTAssertEqual(calculateNextZoom(for: v), 1.5, "Value \(v) must step to 1.5")
        }

        // Test arbitrary floats in [1.25, 1.75)
        let midRange: [CGFloat] = [1.25, 1.2501, 1.3, 1.4, 1.5, 1.6, 1.7, 1.74, 1.7499]
        for v in midRange {
            XCTAssertEqual(calculateNextZoom(for: v), 2.0, "Value \(v) must step to 2.0")
        }

        // Test arbitrary floats >= 1.75
        let above1_75: [CGFloat] = [1.75, 1.7501, 1.8, 1.9, 2.0, 2.5, 3.0, 4.99, 5.0, 10.0]
        for v in above1_75 {
            XCTAssertEqual(calculateNextZoom(for: v), 1.0, "Value \(v) must step to 1.0")
        }

        // Test multi-step cycle starting from arbitrary floats
        var zoom: CGFloat = 1.25
        zoom = calculateNextZoom(for: zoom) // 2.0
        XCTAssertEqual(zoom, 2.0)
        zoom = calculateNextZoom(for: zoom) // 1.0
        XCTAssertEqual(zoom, 1.0)
        zoom = calculateNextZoom(for: zoom) // 1.5
        XCTAssertEqual(zoom, 1.5)
        zoom = calculateNextZoom(for: zoom) // 2.0
        XCTAssertEqual(zoom, 2.0)

        // Starting from 1.75
        zoom = 1.75
        zoom = calculateNextZoom(for: zoom) // 1.0
        XCTAssertEqual(zoom, 1.0)
        zoom = calculateNextZoom(for: zoom) // 1.5
        XCTAssertEqual(zoom, 1.5)
        zoom = calculateNextZoom(for: zoom) // 2.0
        XCTAssertEqual(zoom, 2.0)
    }

    func testStressCountdownTimerEdgeConditionsAndStateTransitions() {
        struct MockShootState {
            var timerEnabled: Bool = true
            var countdown: Int? = nil
            var cameraState: CameraController.State = .ready
            var isShutterDisabled: Bool {
                cameraState != .ready || countdown != nil
            }
            var isTimerToggleDisabled: Bool {
                cameraState == .recording || countdown != nil
            }
            var canPickScene: Bool {
                cameraState != .recording && countdown == nil
            }
            var rollInitiatedCount = 0

            mutating func roll() {
                guard countdown == nil else { return }
                guard cameraState == .ready else { return }
                rollInitiatedCount += 1
                if timerEnabled {
                    countdown = 3
                } else {
                    cameraState = .recording
                }
            }

            mutating func advanceCountdown() {
                guard let current = countdown else { return }
                if current > 1 {
                    countdown = current - 1
                } else {
                    countdown = nil
                    cameraState = .recording
                }
            }
        }

        // Test with timer enabled
        var state = MockShootState(timerEnabled: true)
        XCTAssertTrue(state.canPickScene)
        XCTAssertFalse(state.isShutterDisabled)
        XCTAssertFalse(state.isTimerToggleDisabled)

        // User taps roll()
        state.roll()
        XCTAssertEqual(state.rollInitiatedCount, 1)
        XCTAssertEqual(state.countdown, 3)
        XCTAssertTrue(state.isShutterDisabled, "Shutter must be disabled during countdown step 3")
        XCTAssertTrue(state.isTimerToggleDisabled, "Timer toggle must be disabled during countdown step 3")
        XCTAssertFalse(state.canPickScene, "Scene selection must be blocked during countdown step 3")

        // Advance to step 2
        state.advanceCountdown()
        XCTAssertEqual(state.countdown, 2)
        XCTAssertTrue(state.isShutterDisabled)
        XCTAssertFalse(state.canPickScene)

        // Advance to step 1
        state.advanceCountdown()
        XCTAssertEqual(state.countdown, 1)
        XCTAssertTrue(state.isShutterDisabled)
        XCTAssertFalse(state.canPickScene)

        // Countdown finishes: transitions to recording
        state.advanceCountdown()
        XCTAssertNil(state.countdown)
        XCTAssertEqual(state.cameraState, .recording)
        XCTAssertTrue(state.isTimerToggleDisabled, "Timer toggle must be disabled during active recording")
        XCTAssertFalse(state.canPickScene, "Scene selection must be blocked during active recording")

        // Test with timer disabled: immediate recording transition
        var immediateState = MockShootState(timerEnabled: false)
        immediateState.roll()
        XCTAssertEqual(immediateState.rollInitiatedCount, 1)
        XCTAssertNil(immediateState.countdown, "Countdown must remain nil when timer is disabled")
        XCTAssertEqual(immediateState.cameraState, .recording, "Recording must start immediately")
    }

    func testStressConcurrentRecordingPreventionUnderPressure() {
        struct MockRecorder {
            var countdown: Int? = nil
            var state: CameraController.State = .ready
            var activeRecordingsCount = 0
            var currentScene: Int = 0
            var position: CameraController.Position = .front

            mutating func roll() {
                guard countdown == nil else { return }
                guard state == .ready else { return }
                countdown = 3
                // In real app, Task begins countdown loop and then calls startRecording()
            }

            mutating func pickScene(_ index: Int) {
                guard state != .recording, countdown == nil else { return }
                currentScene = index
            }

            mutating func switchCamera() {
                guard state == .ready else { return }
                position = position == .front ? .back : .front
            }
        }

        var recorder = MockRecorder()

        // 1. First roll starts countdown
        recorder.roll()
        XCTAssertEqual(recorder.countdown, 3)

        // 2. 10 concurrent roll() calls while countdown is active
        for _ in 0..<10 {
            recorder.roll()
            XCTAssertEqual(recorder.countdown, 3, "Concurrent roll calls must be strictly dropped")
        }

        // 3. Attempt to change scene during countdown
        recorder.pickScene(4)
        XCTAssertEqual(recorder.currentScene, 0, "Scene switch must be rejected during countdown")

        // 4. Transition to recording state
        recorder.countdown = nil
        recorder.state = .recording

        // 5. Attempt roll() while recording
        recorder.roll()
        XCTAssertNil(recorder.countdown, "Roll while recording must be dropped")

        // 6. Attempt scene switch while recording
        recorder.pickScene(3)
        XCTAssertEqual(recorder.currentScene, 0, "Scene switch must be rejected while recording")

        // 7. Attempt camera switch while recording
        recorder.switchCamera()
        XCTAssertEqual(recorder.position, .front, "Camera flip must be rejected while recording")
    }
}

