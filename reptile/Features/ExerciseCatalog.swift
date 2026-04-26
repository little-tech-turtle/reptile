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
        defaultTuning: .squatDefault,
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
                readValue: { Float($0.squat.kneeBottomFlexionDegrees) },
                writeValue: { $0.squat.kneeBottomFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "squat-hip-bottom",
                title: "Hip bottom target",
                hint: "Lower = easier depth trigger.",
                min: 30,
                max: 120,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.squat.hipBottomFlexionDegrees) },
                writeValue: { $0.squat.hipBottomFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "squat-bottom-gate",
                title: "Bottom gate",
                hint: "Lower = easier to count at depth.",
                min: 0.60,
                max: 0.95,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.gates.downThreshold) },
                writeValue: { $0.gates.downThreshold = CGFloat($1) }
            ),
            .init(
                id: "squat-lockout-gate",
                title: "Stand lockout gate",
                hint: "Lower = stricter full-stand requirement.",
                min: 0.03,
                max: 0.30,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.squat.standLockoutThreshold) },
                writeValue: { $0.squat.standLockoutThreshold = CGFloat($1) }
            ),
        ],
        thresholdDefinitions: [
            .init(label: "lockout", color: .systemGreen, value: { $0.squat.standLockoutThreshold }),
            .init(label: "entry", color: .systemOrange, value: { $0.squat.descendEntryThreshold }),
            .init(label: "bottom", color: .systemRed, value: { $0.gates.downThreshold }),
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
                "bottom>= knee \(formatDegree(Double(configuration.squat.kneeBottomFlexionDegrees)))° / hip \(formatDegree(Double(configuration.squat.hipBottomFlexionDegrees)))°   lockout<= knee \(formatDegree(Double(configuration.squat.kneeLockoutFlexionDegrees)))° / hip \(formatDegree(Double(configuration.squat.hipLockoutFlexionDegrees)))°   amp: \(String(format: "%.2f", configuration.gates.minAmplitude))",
            ]
        }
    )

    static let bicepCurl = ExerciseDefinition(
        id: "bicepCurl",
        title: "Bicep Curl",
        shortTitle: "Curl",
        repSound: nil,
        defaultTuning: .bicepCurlDefault,
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
                readValue: { Float($0.curl.topFlexionDegrees) },
                writeValue: { $0.curl.topFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "curl-lockout-flexion",
                title: "Lockout flexion max",
                hint: "Higher = easier lockout recognition.",
                min: 0,
                max: 50,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.curl.lockoutFlexionDegrees) },
                writeValue: { $0.curl.lockoutFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "curl-top-gate",
                title: "Top gate",
                hint: "Lower = easier to hit top phase.",
                min: 0.40,
                max: 0.95,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.gates.upThreshold) },
                writeValue: { $0.gates.upThreshold = CGFloat($1) }
            ),
            .init(
                id: "curl-lockout-gate",
                title: "Lockout gate",
                hint: "Higher = easier lockout completion.",
                min: 0.05,
                max: 0.60,
                format: "%.0f%%",
                displayScale: 100,
                readValue: { Float($0.gates.downThreshold) },
                writeValue: { $0.gates.downThreshold = CGFloat($1) }
            ),
        ],
        thresholdDefinitions: [
            .init(label: "lockout", color: .systemGreen, value: { $0.gates.downThreshold }),
            .init(label: "top", color: .systemRed, value: { $0.gates.upThreshold }),
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
                "top>= \(formatDegree(Double(configuration.curl.topFlexionDegrees)))°   lockout<= \(formatDegree(Double(configuration.curl.lockoutFlexionDegrees)))°   gates: top>=\(String(format: "%.2f", configuration.gates.upThreshold)) lockout<=\(String(format: "%.2f", configuration.gates.downThreshold))   amp: \(String(format: "%.2f", configuration.gates.minAmplitude))",
            ]
        }
    )

    static let benchPress = ExerciseDefinition(
        id: "benchPress",
        title: "Bench Press",
        shortTitle: "Bench",
        repSound: nil,
        defaultTuning: .benchPressDefault,
        makeProfile: { BenchPressExerciseProfile() },
        tuningControls: [
            .init(
                id: "bench-bottom-elbow",
                title: "Bottom elbow target",
                hint: "Lower = easier elbow depth trigger.",
                min: 20,
                max: 95,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.bench.bottomElbowFlexionDegrees) },
                writeValue: { $0.bench.bottomElbowFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "bench-lockout-elbow",
                title: "Lockout elbow max",
                hint: "Higher = easier elbow lockout recognition.",
                min: 0,
                max: 40,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.bench.lockoutElbowFlexionDegrees) },
                writeValue: { $0.bench.lockoutElbowFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "bench-bottom-shoulder",
                title: "Bottom shoulder target",
                hint: "Lower = easier shoulder depth trigger.",
                min: 20,
                max: 95,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.bench.bottomShoulderFlexionDegrees) },
                writeValue: { $0.bench.bottomShoulderFlexionDegrees = CGFloat($1) }
            ),
            .init(
                id: "bench-lockout-shoulder",
                title: "Lockout shoulder max",
                hint: "Higher = easier shoulder lockout recognition.",
                min: 0,
                max: 40,
                format: "%.0f°",
                displayScale: 1,
                readValue: { Float($0.bench.lockoutShoulderFlexionDegrees) },
                writeValue: { $0.bench.lockoutShoulderFlexionDegrees = CGFloat($1) }
            ),
        ],
        thresholdDefinitions: [
            .init(label: "lockout", color: .systemGreen, value: { $0.gates.downThreshold }),
            .init(label: "bottom", color: .systemRed, value: { $0.gates.upThreshold }),
        ],
        diagnosticsText: { output, configuration in
            let scalars = output.exerciseDiagnostics?.scalars ?? [:]
            let elbow = formatDegree(scalars["bench.elbowFlexionDegrees"])
            let shoulder = formatDegree(scalars["bench.shoulderFlexionDegrees"])
            let leftElbow = formatDegree(scalars["bench.leftElbowFlexionDegrees"])
            let rightElbow = formatDegree(scalars["bench.rightElbowFlexionDegrees"])
            let leftShoulder = formatDegree(scalars["bench.leftShoulderFlexionDegrees"])
            let rightShoulder = formatDegree(scalars["bench.rightShoulderFlexionDegrees"])
            return [
                "elbow: \(elbow)° (L\(leftElbow)/R\(rightElbow))  shoulder: \(shoulder)° (L\(leftShoulder)/R\(rightShoulder))",
                "bottom>= elbow \(formatDegree(Double(configuration.bench.bottomElbowFlexionDegrees)))° / shoulder \(formatDegree(Double(configuration.bench.bottomShoulderFlexionDegrees)))°   lockout<= elbow \(formatDegree(Double(configuration.bench.lockoutElbowFlexionDegrees)))° / shoulder \(formatDegree(Double(configuration.bench.lockoutShoulderFlexionDegrees)))°   gates: bottom>=\(String(format: "%.2f", configuration.gates.upThreshold)) lockout<=\(String(format: "%.2f", configuration.gates.downThreshold))   amp: \(String(format: "%.2f", configuration.gates.minAmplitude))",
            ]
        }
    )

    static let all: [ExerciseDefinition] = [squat, bicepCurl, benchPress]

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
