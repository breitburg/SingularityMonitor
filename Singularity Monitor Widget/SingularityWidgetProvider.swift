import Foundation
import WidgetKit

struct SingularityWidgetEntry: TimelineEntry {
    let date: Date
    let minutes: Double?
    let resolvedFitKind: FitKind?
}

struct SingularityWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SingularityWidgetEntry {
        SingularityWidgetEntry(date: Date(), minutes: nil, resolvedFitKind: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SingularityWidgetEntry) -> Void) {
        Task {
            let entries = await buildEntries(now: Date())
            completion(entries.first ?? placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SingularityWidgetEntry>) -> Void) {
        Task {
            let now = Date()
            let entries = await buildEntries(now: now)
            let policy: TimelineReloadPolicy
            if entries.contains(where: { $0.minutes != nil }) {
                policy = .after(now.addingTimeInterval(24 * 3_600))
            } else {
                policy = .after(now.addingTimeInterval(3_600))
            }
            completion(Timeline(entries: entries, policy: policy))
        }
    }

    private func buildEntries(now: Date) async -> [SingularityWidgetEntry] {
        let metric = HorizonMetric(rawValue: AppGroup.userDefaults.string(forKey: "selectedMetric") ?? "") ?? .p50
        let selection = CurveSelection(rawValue: AppGroup.userDefaults.string(forKey: "curveSelection") ?? "") ?? .auto

        let snapshot: BenchmarkSnapshot? = await {
            if let fresh = try? await BenchmarkLoader.load() { return fresh }
            return BenchmarkLoader.cachedSnapshot()
        }()

        guard let snapshot else {
            return [SingularityWidgetEntry(date: now, minutes: nil, resolvedFitKind: nil)]
        }

        let resolved: (FitKind, CurveFit)?
        switch selection {
        case .auto:
            resolved = FitKind.allCases
                .compactMap { kind -> (FitKind, CurveFit)? in
                    guard let candidate = CurveFitter.fit(kind: kind, metric: metric, snapshot: snapshot) else { return nil }
                    return (kind, candidate)
                }
                .max(by: { $0.1.rSquared < $1.1.rSquared })
        case .fixed(let kind):
            if let candidate = CurveFitter.fit(kind: kind, metric: metric, snapshot: snapshot) {
                resolved = (kind, candidate)
            } else {
                resolved = nil
            }
        }

        guard let (resolvedKind, fit) = resolved else {
            return [SingularityWidgetEntry(date: now, minutes: nil, resolvedFitKind: nil)]
        }

        return (0..<24).map { hourOffset in
            let entryDate = now.addingTimeInterval(Double(hourOffset) * 3_600)
            return SingularityWidgetEntry(
                date: entryDate,
                minutes: fit.predictMinutes(at: entryDate),
                resolvedFitKind: resolvedKind
            )
        }
    }
}
