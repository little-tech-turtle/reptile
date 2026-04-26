import Foundation

public protocol ExerciseProfile: Sendable {
    var id: String { get }

    func makeMetricCalculator(configuration: RepCountingConfiguration) -> any MetricCalculator
    func makePeakDetector(configuration: RepCountingConfiguration) -> any PeakDetector
    func makeRepCounter(configuration: RepCountingConfiguration) -> any RepCounter
    func makeMetricFilters(configuration: RepCountingConfiguration) -> [any MetricFilter]
}
