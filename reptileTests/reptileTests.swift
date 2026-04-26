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

        #expect(ExerciseCatalog.all.count == 2)
    }

    @Test func exerciseCatalog_resolvesByID() {
        #expect(ExerciseCatalog.definition(for: "squat")?.id == "squat")
        #expect(ExerciseCatalog.definition(for: "bicepCurl")?.id == "bicepCurl")
        #expect(ExerciseCatalog.definition(for: "benchPress") == nil)
        #expect(ExerciseCatalog.definition(for: "unknown") == nil)
    }

    @Test func defaultRepTuning_usesExpectedCurlThresholds() {
        let curl = LiveCameraCoordinator.defaultRepTuning(for: "bicepCurl")

        #expect(curl.upThreshold == 0.60)
        #expect(curl.downThreshold == 0.35)
        #expect(curl.minAmplitude == 0.25)
        #expect(curl.minTimeBetweenReps == 0.5)
        #expect(curl.curlTopFlexionDegrees == 128)
        #expect(curl.curlLockoutFlexionDegrees == 34)
    }

    @Test func defaultRepTuning_usesExpectedSquatThresholds() {
        let squat = LiveCameraCoordinator.defaultRepTuning(for: "squat")

        #expect(squat.downThreshold == 0.82)
        #expect(squat.squatDescendEntryThreshold == 0.18)
        #expect(squat.squatStandLockoutThreshold == 0.10)
        #expect(squat.squatKneeBottomFlexionDegrees == 72)
        #expect(squat.squatHipBottomFlexionDegrees == 52)
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
