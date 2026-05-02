import Testing
import CameraKit
import CoreGraphics
@testable import reptile

@MainActor
struct ReptileTests {
    @Test func exerciseCatalog_mapsProfileAndSoundConfiguration() {
        #expect(ExerciseCatalog.squat.id == "squat")
        #expect(ExerciseCatalog.squat.repSound?.resourceName == "ah")
        #expect(ExerciseCatalog.squat.repSound?.fileExtension == "wav")

        #expect(ExerciseCatalog.bicepCurl.id == "bicepCurl")
        #expect(ExerciseCatalog.bicepCurl.repSound == nil)

        #expect(ExerciseCatalog.benchPress.id == "benchPress")
        #expect(ExerciseCatalog.benchPress.repSound == nil)

        #expect(ExerciseCatalog.all.count == 3)
    }

    @Test func exerciseCatalog_resolvesByID() {
        #expect(ExerciseCatalog.definition(for: "squat")?.id == "squat")
        #expect(ExerciseCatalog.definition(for: "bicepCurl")?.id == "bicepCurl")
        #expect(ExerciseCatalog.definition(for: "benchPress")?.id == "benchPress")
        #expect(ExerciseCatalog.definition(for: "unknown") == nil)
    }

    @Test func defaultRepTuning_usesExpectedCurlThresholds() {
        let curl = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")

        #expect(curl.gates.upThreshold == 0.60)
        #expect(curl.gates.downThreshold == 0.35)
        #expect(curl.gates.minAmplitude == 0.25)
        #expect(curl.gates.minTimeBetweenReps == 0.5)
        #expect(curl.curl.topFlexionDegrees == 128)
        #expect(curl.curl.lockoutFlexionDegrees == 34)
    }

    @Test func defaultRepTuning_usesExpectedSquatThresholds() {
        let squat = LiveCameraCoordinator.defaultRepTuning(for: "squat")

        #expect(squat.gates.downThreshold == 0.70)
        #expect(squat.squat.descendEntryThreshold == 0.18)
        #expect(squat.squat.standLockoutThreshold == 0.12)
        #expect(squat.squat.kneeBottomFlexionDegrees == 72)
        #expect(squat.squat.hipBottomFlexionDegrees == 52)
    }

    @Test func defaultRepTuning_usesExpectedBenchThresholds() {
        let bench = LiveCameraCoordinator.defaultRepTuning(for: "benchPress")

        #expect(bench.gates.upThreshold == 0.60)
        #expect(bench.gates.downThreshold == 0.30)
        #expect(bench.gates.minAmplitude == 0.20)
        #expect(bench.gates.minTimeBetweenReps == 0.5)
        #expect(bench.bench.bottomElbowFlexionDegrees == 45)
        #expect(bench.bench.bottomShoulderFlexionDegrees == 45)
        #expect(bench.bench.lockoutElbowFlexionDegrees == 12)
        #expect(bench.bench.lockoutShoulderFlexionDegrees == 12)
    }

    @Test func squatTuningControls_areLeanAndTransparent() {
        let controls = ExerciseCatalog.squat.tuningControls

        #expect(controls.count == 4)
        #expect(controls.map(\.id) == [
            "squat-knee-bottom",
            "squat-hip-bottom",
            "squat-bottom-gate",
            "squat-lockout-gate",
        ])

        #expect(controls.allSatisfy { !$0.hint.isEmpty })
    }

    @Test func curlTuningControls_areLeanAndTransparent() {
        let controls = ExerciseCatalog.bicepCurl.tuningControls

        #expect(controls.count == 4)
        #expect(controls.map(\.id) == [
            "curl-top-flexion",
            "curl-lockout-flexion",
            "curl-top-gate",
            "curl-lockout-gate",
        ])

        #expect(controls.allSatisfy { !$0.hint.isEmpty })
    }

    @Test func benchTuningControls_areLeanAndTransparent() {
        let controls = ExerciseCatalog.benchPress.tuningControls

        #expect(controls.count == 4)
        #expect(controls.map(\.id) == [
            "bench-bottom-elbow",
            "bench-lockout-elbow",
            "bench-bottom-shoulder",
            "bench-lockout-shoulder",
        ])

        #expect(controls.allSatisfy { !$0.hint.isEmpty })
    }

    @Test func exerciseNodePickerLayout_selectsNearestNode() {
        let nodes: [ExerciseNodePickerLayout.Node] = [
            .init(id: "squat", center: CGPoint(x: 20, y: 20), radius: 10),
            .init(id: "bicepCurl", center: CGPoint(x: 60, y: 20), radius: 10),
            .init(id: "alt", center: CGPoint(x: 100, y: 20), radius: 10),
        ]

        let layout = ExerciseNodePickerLayout(nodes: nodes)

        #expect(layout.nearestNodeID(to: CGPoint(x: 24, y: 22)) == "squat")
        #expect(layout.nearestNodeID(to: CGPoint(x: 59, y: 19)) == "bicepCurl")
        #expect(layout.nearestNodeID(to: CGPoint(x: 96, y: 23)) == "alt")
    }

    @Test func exerciseNodePickerLayout_returnsNilWhenTouchIsFarFromNodes() {
        let nodes: [ExerciseNodePickerLayout.Node] = [
            .init(id: "squat", center: CGPoint(x: 20, y: 20), radius: 10),
            .init(id: "bicepCurl", center: CGPoint(x: 60, y: 20), radius: 10),
            .init(id: "alt", center: CGPoint(x: 100, y: 20), radius: 10),
        ]

        let layout = ExerciseNodePickerLayout(nodes: nodes)
        #expect(layout.nearestNodeID(to: CGPoint(x: 200, y: 120)) == nil)
    }

    @Test func exerciseRepSound_initializesWithExpectedValues() {
        let a = ExerciseRepSound(resourceName: "ah", fileExtension: "wav")
        #expect(a.resourceName == "ah")
        #expect(a.fileExtension == "wav")
    }

    @Test func unknownProfileID_impliesSilentFeedbackSelection() {
        let sound = ExerciseCatalog.definition(for: "not-real")?.repSound
        #expect(sound == nil)
    }

    @Test func tuningStoragePrefix_isVersion6() {
        #expect(LiveCameraViewController.tuningStoragePrefix == "repTuning.v6")
    }
}
