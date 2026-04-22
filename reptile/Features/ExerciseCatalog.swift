import CameraKit
import Foundation
import UIKit

struct TuningControlDefinition {
    let id: String
    let title: String
    let hint: String
    let min: Float
    let max: Float
    let format: String
    let displayScale: Float
    let readValue: (RepCountingConfiguration) -> Float
    let writeValue: (inout RepCountingConfiguration, Float) -> Void
}

struct DebugThresholdDefinition {
    let label: String
    let color: UIColor
    let value: (RepCountingConfiguration) -> CGFloat
}

struct ExerciseDefinition {
    let id: String
    let title: String
    let shortTitle: String
    let repSound: ExerciseRepSound?
    let defaultTuning: RepCountingConfiguration
    let makeProfile: () -> any ExerciseProfile
    let tuningControls: [TuningControlDefinition]
    let thresholdDefinitions: [DebugThresholdDefinition]
    let diagnosticsText: (RepCounterOutput, RepCountingConfiguration) -> [String]
}

enum ExerciseCatalog {
    static let squat = ExerciseDefinition(
        id: "squat",
        title: "Squat",
        shortTitle: "Squat",
        repSound: ExerciseRepSound(resourceName: "ah", fileExtension: "wav"),
        defaultTuning: RepCountingConfiguration(
            armingThreshold: 0.5,
            minPeakHeight: 0.08,
            minValleyDepth: 0.08,
            peakWindowSize: 5,
            minTimeBetweenReps: 0.6,
            minAmplitude: 0.55,
            upThreshold: 0.20,
            downThreshold: 0.82,
            squatDescendEntryThreshold: 0.18,
            squatStandLockoutThreshold: 0.10,
            squatKneeBottomFlexionDegrees: 72,
            squatHipBottomFlexionDegrees: 52,
            squatKneeLockoutFlexionDegrees: 18,
            squatHipLockoutFlexionDegrees: 20,
            squatMaxSideAsymmetryDegrees: 25,
            inactivityResetSeconds: 3.0,
            activityDeltaThreshold: 0.015,
            spikeMaxDelta: 0.25,
            emaAlpha: 0.3
        ),
        makeProfile: { SquatExerciseProfile() },
        tuningControls: [
            .init(
                id: "squat-knee-bottom",
                title: "Knee bottom target",
                hint: "Lower = easier depth trigger.",
                min: 45,
                max: 130,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.squatKneeBottomFlexionDegrees) },
                writeValue: { $0.squatKneeBottomFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "squat-hip-bottom",
                title: "Hip bottom target",
                hint: "Lower = easier depth trigger.",
                min: 30,
                max: 120,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.squatHipBottomFlexionDegrees) },
                writeValue: { $0.squatHipBottomFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "squat-bottom-gate",
                title: "Bottom gate",
                hint: "Lower = easier to count at depth.",
                min: 0.60,
                max: 0.95,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.downThreshold) },
                writeValue: { $0.downThreshold = CGFloat($1) }
            ),
            .init(
                id: "squat-lockout-gate",
                title: "Stand lockout gate",
                hint: "Lower = stricter full-stand requirement.",
                min: 0.03,
                max: 0.30,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.squatStandLockoutThreshold) },
                writeValue: { $0.squatStandLockoutThreshold = CGFloat($1) }
            ),
        ],
        thresholdDefinitions: [
            .init(label: "lockout", color: .systemGreen, value: { $0.squatStandLockoutThreshold }),
            .init(label: "entry", color: .systemOrange, value: { $0.squatDescendEntryThreshold }),
            .init(label: "bottom", color: .systemRed, value: { $0.downThreshold }),
        ],
        diagnosticsText: { output, configuration in
            let scalars = output.exerciseDiagnostics?.scalars ?? [:]
            let knee = formatDegree(scalars["squat.kneeFlexionDegrees"])
            let hip = formatDegree(scalars["squat.hipFlexionDegrees"])
            let leftKnee = formatDegree(scalars["squat.leftKneeFlexionDegrees"])
            let rightKnee = formatDegree(scalars["squat.rightKneeFlexionDegrees"])
            let leftHip = formatDegree(scalars["squat.leftHipFlexionDegrees"])
            let rightHip = formatDegree(scalars["squat.rightHipFlexionDegrees"])
            return [
                "knee: \(knee)° (L\(leftKnee)/R\(rightKnee))  hip: \(hip)° (L\(leftHip)/R\(rightHip))",
                "bottom>= knee \(formatDegree(Double(configuration.squatKneeBottomFlexionDegrees)))° / hip \(formatDegree(Double(configuration.squatHipBottomFlexionDegrees)))°   lockout<= knee \(formatDegree(Double(configuration.squatKneeLockoutFlexionDegrees)))° / hip \(formatDegree(Double(configuration.squatHipLockoutFlexionDegrees)))°   amp: \(String(format: "%.2f", configuration.minAmplitude))",
            ]
        }
    )

    static let bicepCurl = ExerciseDefinition(
        id: "bicepCurl",
        title: "Bicep Curl",
        shortTitle: "Curl",
        repSound: nil,
        defaultTuning: RepCountingConfiguration(
            armingThreshold: 0.5,
            minPeakHeight: 0.08,
            minValleyDepth: 0.08,
            peakWindowSize: 5,
            minTimeBetweenReps: 0.5,
            minAmplitude: 0.25,
            upThreshold: 0.60,
            downThreshold: 0.35,
            squatDescendEntryThreshold: 0.18,
            squatStandLockoutThreshold: 0.10,
            squatKneeBottomFlexionDegrees: 80,
            squatHipBottomFlexionDegrees: 60,
            squatKneeLockoutFlexionDegrees: 18,
            squatHipLockoutFlexionDegrees: 20,
            squatMaxSideAsymmetryDegrees: 25,
            curlTopFlexionDegrees: 128,
            curlLockoutFlexionDegrees: 34,
            inactivityResetSeconds: 3.0,
            activityDeltaThreshold: 0.015,
            spikeMaxDelta: 0.25,
            emaAlpha: 0.3
        ),
        makeProfile: { BicepCurlExerciseProfile() },
        tuningControls: [
            .init(
                id: "curl-top-flexion",
                title: "Top flexion target",
                hint: "Lower = easier top detection.",
                min: 45,
                max: 140,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.curlTopFlexionDegrees) },
                writeValue: { $0.curlTopFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "curl-lockout-flexion",
                title: "Lockout flexion max",
                hint: "Higher = easier lockout recognition.",
                min: 0,
                max: 50,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.curlLockoutFlexionDegrees) },
                writeValue: { $0.curlLockoutFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "curl-top-gate",
                title: "Top gate",
                hint: "Lower = easier to hit top phase.",
                min: 0.40,
                max: 0.95,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.upThreshold) },
                writeValue: { $0.upThreshold = CGFloat($1) }
            ),
            .init(
                id: "curl-lockout-gate",
                title: "Lockout gate",
                hint: "Higher = easier lockout completion.",
                min: 0.05,
                max: 0.60,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.downThreshold) },
                writeValue: { $0.downThreshold = CGFloat($1) }
            ),
        ],
        thresholdDefinitions: [
            .init(label: "lockout", color: .systemGreen, value: { $0.downThreshold }),
            .init(label: "top", color: .systemRed, value: { $0.upThreshold }),
        ],
        diagnosticsText: { output, configuration in
            let scalars = output.exerciseDiagnostics?.scalars ?? [:]
            let labels = output.exerciseDiagnostics?.labels ?? [:]
            let elbow = formatDegree(scalars["curl.elbowFlexionDegrees"])
            let left = formatDegree(scalars["curl.leftElbowFlexionDegrees"])
            let right = formatDegree(scalars["curl.rightElbowFlexionDegrees"])
            let active = labels["curl.activeSide"] ?? "--"
            return [
                "elbow: \(elbow)° (L\(left)/R\(right))   active: \(active)",
                "top>= \(formatDegree(Double(configuration.curlTopFlexionDegrees)))°   lockout<= \(formatDegree(Double(configuration.curlLockoutFlexionDegrees)))°   gates: top>=\(String(format: "%.2f", configuration.upThreshold)) lockout<=\(String(format: "%.2f", configuration.downThreshold))   amp: \(String(format: "%.2f", configuration.minAmplitude))",
            ]
        }
    )

    static let all: [ExerciseDefinition] = [squat, bicepCurl]

    static var defaultExercise: ExerciseDefinition { squat }

    static func definition(for id: String) -> ExerciseDefinition? {
        all.first(where: { $0.id == id })
    }

    static func index(for id: String) -> Int? {
        all.firstIndex(where: { $0.id == id })
    }

    private static func formatDegree(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f", value)
    }
}
