import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var loadState: LoadState = .idle
    @State private var previousOpenDate: Date?

    @AppStorage("selectedMetric", store: AppGroup.userDefaults)
    private var metric: HorizonMetric = .p50

    @AppStorage("curveSelection", store: AppGroup.userDefaults)
    private var curveSelection: CurveSelection = .auto

    @AppStorage("lastOpenAt", store: AppGroup.userDefaults)
    private var lastOpenAtSeconds: Double = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Singularity Monitor")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .preferredColorScheme(.dark)
        .task {
            if previousOpenDate == nil {
                previousOpenDate = lastOpenAtSeconds > 0
                    ? Date(timeIntervalSince1970: lastOpenAtSeconds)
                    : nil
                lastOpenAtSeconds = Date().timeIntervalSince1970
            }
            await load()
        }
        .onChange(of: metric) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: curveSelection) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            ProgressView("Fetching METR benchmarks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            ErrorView(message: message) { Task { await load() } }
        case .loaded(let snapshot):
            LoadedView(
                snapshot: snapshot,
                metric: $metric,
                curveSelection: $curveSelection,
                previousOpenDate: previousOpenDate,
                onRefresh: { await load(isRefresh: true) }
            )
        }
    }

    private func load(isRefresh: Bool = false) async {
        if !isRefresh {
            if let cached = BenchmarkLoader.cachedSnapshot() {
                loadState = .loaded(cached)
            } else {
                loadState = .loading
            }
        }
        do {
            let snapshot = try await BenchmarkLoader.load()
            loadState = .loaded(snapshot)
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            if case .loaded = loadState { return }
            if !isRefresh {
                loadState = .error(error.localizedDescription)
            }
        }
    }

    enum LoadState {
        case idle
        case loading
        case loaded(BenchmarkSnapshot)
        case error(String)
    }
}

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Couldn't load benchmarks")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum Explanation: String, Identifiable {
    case heroNow, heroSingularity, heroDoubling
    case statistics, rateOfChange, fit, models

    var id: String { rawValue }
}

private struct LoadedView: View {
    static let collapsedModelCount = 3

    let snapshot: BenchmarkSnapshot
    @Binding var metric: HorizonMetric
    @Binding var curveSelection: CurveSelection
    let previousOpenDate: Date?
    let onRefresh: () async -> Void

    @State private var isShowingAllModels: Bool = false
    @State private var heroPageIndex: Int = 0
    @State private var explanation: Explanation?
    @State private var fit: CurveFit?
    @State private var resolvedFitKind: FitKind?

    private static let heroExpandedHeight: CGFloat = 168

    private static let rateWindows: [(label: String, seconds: TimeInterval)] = [
        ("Per hour", 3_600),
        ("Per day", 86_400),
        ("Per week", 86_400 * 7),
        ("Per month", 86_400 * 30.4375),
        ("Per year", 86_400 * 365.25)
    ]

    private struct FitInputs: Hashable {
        let metric: HorizonMetric
        let selection: CurveSelection
        let fetchedAt: Date
    }

    private var projectedNextReleaseDate: Date? {
        guard let earliest = snapshot.models.first?.releaseDate,
              let latest = snapshot.models.last?.releaseDate,
              snapshot.models.count >= 2 else { return nil }
        let averageGap = latest.timeIntervalSince(earliest) / Double(snapshot.models.count - 1)
        return latest.addingTimeInterval(averageGap)
    }

    var body: some View {
        Form {
            Section {
                heroRow
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        switch heroPageIndex {
                        case 1: explanation = .heroSingularity
                        case 2: explanation = .heroDoubling
                        default: explanation = .heroNow
                        }
                    }
            }
            #if !os(macOS)
            .listSectionSpacing(0)
            #endif

            if let fit {
                Section {
                    LabeledContent("Doubling time") {
                        Text(doublingDisplay(for: fit, at: Date()))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    if let singularity = fit.singularityDate {
                        LabeledContent("Singularity") {
                            Text(singularity, format: .dateTime.month(.abbreviated).year())
                        }
                    }
                } header: {
                    sectionHeader("Statistics", target: .statistics)
                }

                Section {
                    if let previousOpenDate {
                        progressRow(
                            title: "Last App Open",
                            subtitle: previousOpenDate.formatted(.relative(presentation: .named)),
                            anchor: previousOpenDate,
                            fit: fit
                        )
                    }
                    if let startOfWeek = Self.startOfCurrentWeek() {
                        progressRow(
                            title: "Since This \(Self.weekdayName(for: startOfWeek))",
                            subtitle: nil,
                            anchor: startOfWeek,
                            fit: fit
                        )
                    }
                } header: {
                    Text("Recent Progress").textCase(nil)
                }

                Section {
                    ForEach(Self.rateWindows, id: \.label) { window in
                        LabeledContent(window.label) {
                            Text(rateDisplay(over: window.seconds, fit: fit))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }
                } header: {
                    sectionHeader("Rate of Change", target: .rateOfChange)
                }
            }

            Section {
                Picker(selection: $curveSelection) {
                    Text("Best Fit").tag(CurveSelection.auto)
                    Divider()
                    ForEach(FitKind.allCases, id: \.self) { kind in
                        Text(kind.longLabel).tag(CurveSelection.fixed(kind))
                    }
                } label: {
                    Text("Curve")
                }
                .pickerStyle(.menu)

                Picker(selection: $metric) {
                    ForEach(HorizonMetric.allCases, id: \.self) { value in
                        Text(value.displayLabel).tag(value)
                    }
                } label: {
                    Text("Metric")
                }
                .pickerStyle(.menu)

                if let fit {
                    LabeledContent("R²") {
                        Text(String(format: "%.3f", fit.rSquared))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            } header: {
                sectionHeader("Fit", target: .fit)
            }

            Section {
                if let fit, let projectedDate = projectedNextReleaseDate {
                    modelRow(
                        name: String(localized: "Next Up"),
                        date: projectedDate,
                        minutes: fit.predictMinutes(at: projectedDate),
                        isProjected: true
                    )
                }
                let models = Array(snapshot.models.reversed())
                let visibleModels = isShowingAllModels ? models : Array(models.prefix(Self.collapsedModelCount))
                ForEach(visibleModels) { model in
                    modelRow(
                        name: model.displayName,
                        date: model.releaseDate,
                        minutes: metric == .p50 ? model.p50.estimateMinutes : model.p80.estimateMinutes,
                        isProjected: false
                    )
                }
                if models.count > Self.collapsedModelCount {
                    Button {
                        withAnimation {
                            isShowingAllModels.toggle()
                        }
                    } label: {
                        HStack {
                            Text(isShowingAllModels
                                ? "Hide previous models"
                                : "Show \(models.count - Self.collapsedModelCount) previous models")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(isShowingAllModels ? 180 : 0))
                        }
                    }
                }
            } header: {
                sectionHeader("Models", target: .models)
            }

            Section {
                LabeledContent("Benchmark", value: "METR Horizon v1.1")
                if let fit {
                    LabeledContent("Data points", value: "\(fit.pointCount)")
                }
                LabeledContent("Updated") {
                    Text(snapshot.fetchedAt, style: .relative)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Source").textCase(nil)
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 0, for: .scrollContent)
        .refreshable { await onRefresh() }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.red.opacity(0.28), Color.red.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Color.groupedBackground)
        .task(id: FitInputs(metric: metric, selection: curveSelection, fetchedAt: snapshot.fetchedAt)) {
            switch curveSelection {
            case .auto:
                let candidates = FitKind.allCases.compactMap { kind -> (FitKind, CurveFit)? in
                    guard let candidate = CurveFitter.fit(kind: kind, metric: metric, snapshot: snapshot) else { return nil }
                    return (kind, candidate)
                }
                if let best = candidates.max(by: { $0.1.rSquared < $1.1.rSquared }) {
                    resolvedFitKind = best.0
                    fit = best.1
                } else {
                    resolvedFitKind = nil
                    fit = nil
                }
            case .fixed(let kind):
                resolvedFitKind = kind
                fit = CurveFitter.fit(kind: kind, metric: metric, snapshot: snapshot)
            }
        }
        .sheet(item: $explanation) { kind in
            NavigationStack {
                switch kind {
                case .heroNow: HeroNowExplanation()
                case .heroSingularity: HeroSingularityExplanation()
                case .heroDoubling: HeroDoublingExplanation()
                case .statistics: StatisticsExplanation(fitKind: resolvedFitKind ?? .exponential)
                case .rateOfChange: RateOfChangeExplanation()
                case .fit: FitExplanation()
                case .models: ModelsExplanation()
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringResource, target: Explanation) -> some View {
        HStack(spacing: 6) {
            Text(title).textCase(nil)
            Button {
                explanation = target
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("About \(Text(title))"))
        }
    }

    @ViewBuilder
    private var heroRow: some View {
        if let fit {
            let singularityDate = fit.singularityDate
            TimelineView(.animation) { context in
                let now = context.date
                VStack(spacing: 12) {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 0) {
                            heroPage(
                                index: 0,
                                title: "Current horizon",
                                minutes: fit.predictMinutes(at: now)
                            )
                            heroPage(
                                index: 1,
                                title: "Until singularity",
                                minutes: singularityDate.map { $0.timeIntervalSince(now) / 60.0 } ?? .nan
                            )
                            heroPage(
                                index: 2,
                                title: "Doubling time",
                                minutes: fit.doublingTimeDays(at: now) * 1_440.0
                            )
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: heroScrollPositionBinding)
                    .scrollIndicators(.hidden)
                    .frame(height: 140)

                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index == heroPageIndex ? Color.primary : Color.secondary.opacity(0.35))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: heroPageIndex)
                }
                .frame(height: Self.heroExpandedHeight)
            }
        } else {
            Text("Not enough data to fit a curve.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var heroScrollPositionBinding: Binding<Int?> {
        Binding(
            get: { heroPageIndex },
            set: { newValue in
                if let newValue, newValue != heroPageIndex {
                    heroPageIndex = newValue
                }
            }
        )
    }

    private func heroPage(index: Int, title: LocalizedStringResource, minutes: Double) -> some View {
        HeroReadout(title: title, minutes: minutes)
            .containerRelativeFrame(.horizontal)
            .scrollTransition { content, phase in
                content
                    .blur(radius: sqrt(abs(phase.value)) * 10)
                    .opacity(1 - sqrt(abs(phase.value)))
            }
            .id(index)
    }

    @ViewBuilder
    private func modelRow(name: String, date: Date, minutes: Double, isProjected: Bool) -> some View {
        LabeledContent {
            Text(Self.compactMinutes(minutes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isProjected {
                        Image(systemName: "circle.dashed")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    Text(name)
                        .foregroundStyle(isProjected ? Color.secondary : Color.primary)
                }
                Text(date, format: .dateTime.month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func progressRow(title: LocalizedStringResource, subtitle: String?, anchor: Date, fit: CurveFit) -> some View {
        LabeledContent {
            Text(progressDisplay(from: anchor, fit: fit))
                .monospacedDigit()
                .contentTransition(.numericText())
        } label: {
            if let subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
            }
        }
    }

    private func progressDisplay(from anchor: Date, fit: CurveFit) -> String {
        let previousValue = fit.predictMinutes(at: anchor)
        let currentValue = fit.predictMinutes(at: Date())
        guard previousValue > 0, previousValue.isFinite, currentValue.isFinite else { return "—" }
        let percentChange = (currentValue / previousValue - 1.0) * 100.0
        let absoluteChangeMinutes = currentValue - previousValue
        return "\(Self.formatSignedPercent(percentChange)) (\(Self.formatSignedDuration(minutes: absoluteChangeMinutes)))"
    }

    private static func startOfCurrentWeek() -> Date? {
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start
    }

    private static func weekdayName(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide))
    }

    private func rateDisplay(over duration: TimeInterval, fit: CurveFit) -> String {
        let now = Date()
        let later = now.addingTimeInterval(duration)
        let nowValue = fit.predictMinutes(at: now)
        let laterValue = fit.predictMinutes(at: later)
        guard nowValue > 0, nowValue.isFinite, laterValue.isFinite else { return "—" }
        let percentChange = (laterValue / nowValue - 1.0) * 100.0
        let absoluteChangeMinutes = laterValue - nowValue
        return "\(Self.formatSignedPercent(percentChange)) (\(Self.formatSignedDuration(minutes: absoluteChangeMinutes)))"
    }

    private static func formatSignedPercent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        let absoluteValue = abs(value)
        let formatted: String
        if absoluteValue < 0.01 {
            formatted = String(format: "%.4f", absoluteValue)
        } else if absoluteValue < 1 {
            formatted = String(format: "%.2f", absoluteValue)
        } else if absoluteValue < 100 {
            formatted = String(format: "%.1f", absoluteValue)
        } else {
            formatted = String(format: "%.0f", absoluteValue)
        }
        return "\(sign)\(formatted)%"
    }

    private static func formatSignedDuration(minutes: Double) -> String {
        let sign = minutes >= 0 ? "+" : "−"
        let absoluteMinutes = abs(minutes)
        if absoluteMinutes < 1.0 / 60.0 {
            return "\(sign)\(String(format: "%.0f", absoluteMinutes * 60_000)) ms"
        }
        if absoluteMinutes < 1.0 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes * 60.0)) sec"
        }
        if absoluteMinutes < 60.0 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes)) min"
        }
        if absoluteMinutes < 60.0 * 24.0 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes / 60.0)) h"
        }
        if absoluteMinutes < 60.0 * 24.0 * 7.0 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes / 1_440.0)) d"
        }
        if absoluteMinutes < 60.0 * 24.0 * 30.4375 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes / (1_440.0 * 7.0))) wk"
        }
        if absoluteMinutes < 60.0 * 24.0 * 365.25 {
            return "\(sign)\(String(format: "%.1f", absoluteMinutes / (1_440.0 * 30.4375))) mo"
        }
        return "\(sign)\(String(format: "%.1f", absoluteMinutes / (1_440.0 * 365.25))) yr"
    }

    private static func compactMinutes(_ minutes: Double) -> String {
        guard minutes.isFinite, minutes > 0 else { return "—" }
        if minutes < 1.0 / 60.0 { return String(format: "%.0fms", minutes * 60_000) }
        if minutes < 1.0 { return String(format: "%.0fs", minutes * 60.0) }
        if minutes < 60.0 { return String(format: "%.0fm", minutes) }
        if minutes < 60.0 * 24.0 { return String(format: "%.1fh", minutes / 60.0) }
        if minutes < 60.0 * 24.0 * 30.4375 { return String(format: "%.1fd", minutes / 1_440.0) }
        if minutes < 60.0 * 24.0 * 365.25 { return String(format: "%.1fmo", minutes / (1_440.0 * 30.4375)) }
        return String(format: "%.1fy", minutes / (1_440.0 * 365.25))
    }

    private func doublingDisplay(for fit: CurveFit, at date: Date) -> String {
        let doubling = fit.doublingTimeDays(at: date)
        if !doubling.isFinite { return "—" }
        if doubling < 0 { return "−\(String(format: "%.1f", -doubling)) days" }
        return "\(String(format: "%.1f", doubling)) days"
    }
}

private struct HeroReadout: View {
    let title: LocalizedStringResource
    let minutes: Double

    var body: some View {
        let (value, unit) = formattedHeroMinutes(minutes)
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.subheadline)
                Image(systemName: "questionmark.circle")
                    .font(.subheadline)
            }
            .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value)
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.default, value: value)
                Text(unit)
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                    .foregroundStyle(Color.white)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
    }
}

private func formattedHeroMinutes(_ minutes: Double) -> (String, String) {
    guard minutes.isFinite, minutes > 0 else { return ("—", "") }
    if minutes < 1.0 {
        return (String(format: "%.5f", minutes * 60.0), "s")
    }
    if minutes < 60.0 {
        return (String(format: "%.7f", minutes), "m")
    }
    if minutes < 60.0 * 24.0 {
        return (String(format: "%.7f", minutes / 60.0), "h")
    }
    if minutes < 60.0 * 24.0 * 7.0 {
        return (String(format: "%.7f", minutes / 1_440.0), "d")
    }
    if minutes < 60.0 * 24.0 * 30.4375 {
        return (String(format: "%.7f", minutes / (1_440.0 * 7.0)), "w")
    }
    if minutes < 60.0 * 24.0 * 365.25 {
        return (String(format: "%.7f", minutes / (1_440.0 * 30.4375)), "M")
    }
    return (String(format: "%.7f", minutes / (1_440.0 * 365.25)), "y")
}

extension Color {
    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var secondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#Preview {
    ContentView()
}
