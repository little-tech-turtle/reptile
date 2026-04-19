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
    }

    @Test func exerciseCatalog_resolvesByID() {
        #expect(ExerciseCatalog.definition(for: "squat")?.id == "squat")
        #expect(ExerciseCatalog.definition(for: "bicepCurl")?.id == "bicepCurl")
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

        #expect(squat.downThreshold == 0.92)
        #expect(squat.squatDescendEntryThreshold == 0.18)
        #expect(squat.squatStandLockoutThreshold == 0.10)
        #expect(squat.squatKneeBottomFlexionDegrees == 80)
        #expect(squat.squatHipBottomFlexionDegrees == 60)
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
}
