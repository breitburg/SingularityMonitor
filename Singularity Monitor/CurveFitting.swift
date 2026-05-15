import Foundation

enum FitKind: String, CaseIterable, Hashable {
    case exponential
    case hyperexponential
    case hyperbolic
    case sigmoid

    var shortLabel: String {
        switch self {
        case .exponential: return "Exp"
        case .hyperexponential: return "Hyperexp"
        case .hyperbolic: return "Hyperbolic"
        case .sigmoid: return "Sigmoid"
        }
    }

    var longLabel: String {
        switch self {
        case .exponential: return "Exponential"
        case .hyperexponential: return "Hyperexponential"
        case .hyperbolic: return "Hyperbolic"
        case .sigmoid: return "Sigmoid"
        }
    }
}

enum CurveSelection: Hashable, RawRepresentable {
    case auto
    case fixed(FitKind)

    var rawValue: String {
        switch self {
        case .auto: return "auto"
        case .fixed(let kind): return kind.rawValue
        }
    }

    init?(rawValue: String) {
        if rawValue == "auto" { self = .auto; return }
        if let kind = FitKind(rawValue: rawValue) { self = .fixed(kind); return }
        return nil
    }

    var displayLabel: String {
        switch self {
        case .auto: return "Best Fit"
        case .fixed(let kind): return kind.longLabel
        }
    }
}

enum HorizonMetric: String, CaseIterable, Hashable {
    case p50, p80

    var label: String {
        switch self {
        case .p50: return "p50"
        case .p80: return "p80"
        }
    }

    var displayLabel: String {
        if rawValue.hasPrefix("p"), let percentage = Int(rawValue.dropFirst()) {
            return "\(percentage)%"
        }
        return rawValue
    }

    var longLabel: String {
        switch self {
        case .p50: return "50% success rate"
        case .p80: return "80% success rate"
        }
    }
}

struct CurveFit {
    let kind: FitKind
    let metric: HorizonMetric
    let referenceDate: Date
    let coefficients: [Double]
    let anchorLogOffset: Double
    let rSquared: Double
    let pointCount: Int
    let domain: ClosedRange<Date>

    func daysSinceReference(_ date: Date) -> Double {
        date.timeIntervalSince(referenceDate) / 86_400.0
    }

    private func rawLogMinutes(at date: Date) -> Double {
        let t = daysSinceReference(date)
        switch kind {
        case .exponential:
            return coefficients[0] + coefficients[1] * t
        case .hyperexponential:
            return coefficients[0] + coefficients[1] * t + coefficients[2] * t * t
        case .hyperbolic:
            let tsDays = coefficients[0]
            let logA = coefficients[1]
            let p = coefficients[2]
            let diff = tsDays - t
            if diff <= 0 { return .infinity }
            return logA - p * log(diff)
        case .sigmoid:
            let asymptote = coefficients[0]
            let a = coefficients[1]
            let b = coefficients[2]
            return log(asymptote) - log(1.0 + exp(a + b * t))
        }
    }

    static let singularityThresholdMinutes: Double = 60.0 * 24.0 * 365.25 * 100.0

    var singularityDate: Date? {
        timeToReach(minutes: Self.singularityThresholdMinutes)
    }

    func timeToReach(minutes targetMinutes: Double) -> Date? {
        guard targetMinutes.isFinite, targetMinutes > 0 else { return nil }
        let targetRawLog = log(targetMinutes) - anchorLogOffset
        let tDays: Double?
        switch kind {
        case .exponential:
            let intercept = coefficients[0]
            let slope = coefficients[1]
            guard slope != 0 else { tDays = nil; break }
            tDays = (targetRawLog - intercept) / slope
        case .hyperexponential:
            let intercept = coefficients[0]
            let linear = coefficients[1]
            let quadratic = coefficients[2]
            guard quadratic != 0 else {
                tDays = linear != 0 ? (targetRawLog - intercept) / linear : nil
                break
            }
            let discriminant = linear * linear - 4.0 * quadratic * (intercept - targetRawLog)
            guard discriminant >= 0 else { tDays = nil; break }
            let root1 = (-linear + sqrt(discriminant)) / (2.0 * quadratic)
            let root2 = (-linear - sqrt(discriminant)) / (2.0 * quadratic)
            let candidates = [root1, root2].filter { $0.isFinite && $0 > 0 }
            tDays = candidates.min()
        case .hyperbolic:
            let tsDays = coefficients[0]
            let logA = coefficients[1]
            let p = coefficients[2]
            guard p > 0 else { tDays = nil; break }
            let logDiff = (logA - targetRawLog) / p
            tDays = tsDays - exp(logDiff)
        case .sigmoid:
            let asymptote = coefficients[0]
            let a = coefficients[1]
            let b = coefficients[2]
            let targetMinutesAtAnchor = exp(targetRawLog)
            guard asymptote > targetMinutesAtAnchor, b != 0 else { tDays = nil; break }
            let ratio = asymptote / targetMinutesAtAnchor - 1.0
            guard ratio > 0 else { tDays = nil; break }
            tDays = (log(ratio) - a) / b
        }
        guard let tDays, tDays.isFinite else { return nil }
        return referenceDate.addingTimeInterval(tDays * 86_400.0)
    }

    func predictMinutes(at date: Date) -> Double {
        exp(rawLogMinutes(at: date) + anchorLogOffset)
    }

    func doublingTimeDays(at date: Date) -> Double {
        let t = daysSinceReference(date)
        switch kind {
        case .exponential:
            return log(2.0) / coefficients[1]
        case .hyperexponential:
            let slope = coefficients[1] + 2.0 * coefficients[2] * t
            return log(2.0) / slope
        case .hyperbolic:
            let tsDays = coefficients[0]
            let p = coefficients[2]
            let diff = tsDays - t
            if diff <= 0 { return 0 }
            return log(2.0) * diff / p
        case .sigmoid:
            let a = coefficients[1]
            let b = coefficients[2]
            let rawRatio = 1.0 / (1.0 + exp(a + b * t))
            let slope = -b * (1.0 - rawRatio)
            return log(2.0) / slope
        }
    }
}

enum CurveFitter {
    static func fit(kind: FitKind, metric: HorizonMetric, snapshot: BenchmarkSnapshot) -> CurveFit? {
        let valueFor: (ModelResult) -> Double = { result in
            metric == .p50 ? result.p50.estimateMinutes : result.p80.estimateMinutes
        }

        let samples: [(date: Date, value: Double)] = snapshot.models
            .filter { valueFor($0) > 0 }
            .map { ($0.releaseDate, valueFor($0)) }

        let minimumSamples: Int
        switch kind {
        case .exponential: minimumSamples = 3
        case .hyperexponential, .hyperbolic: minimumSamples = 4
        case .sigmoid: minimumSamples = 5
        }
        guard samples.count >= minimumSamples else { return nil }
        guard let referenceDate = samples.map(\.date).min() else { return nil }
        guard let latestSample = samples.max(by: { $0.date < $1.date }) else { return nil }

        let times = samples.map { $0.date.timeIntervalSince(referenceDate) / 86_400.0 }
        let logValues = samples.map { log($0.value) }

        let coefficients: [Double]
        let rSquared: Double

        switch kind {
        case .exponential:
            guard let result = ordinaryLeastSquaresLinear(x: times, y: logValues) else { return nil }
            coefficients = [result.intercept, result.slope]
            rSquared = result.rSquared
        case .hyperexponential:
            guard let result = ordinaryLeastSquaresQuadratic(x: times, y: logValues) else { return nil }
            coefficients = result.coefficients
            rSquared = result.rSquared
        case .hyperbolic:
            guard let result = fitHyperbolic(times: times, logValues: logValues) else { return nil }
            coefficients = result.coefficients
            rSquared = result.rSquared
        case .sigmoid:
            guard let result = fitSigmoid(times: times, logValues: logValues, values: samples.map(\.value)) else { return nil }
            coefficients = result.coefficients
            rSquared = result.rSquared
        }

        let anchorTime = latestSample.date.timeIntervalSince(referenceDate) / 86_400.0
        let rawLogAtAnchor = rawLogPrediction(kind: kind, coefficients: coefficients, t: anchorTime)
        let anchorLogOffset = log(latestSample.value) - rawLogAtAnchor

        let earliest = samples.map(\.date).min() ?? referenceDate
        let latest = samples.map(\.date).max() ?? referenceDate
        return CurveFit(
            kind: kind,
            metric: metric,
            referenceDate: referenceDate,
            coefficients: coefficients,
            anchorLogOffset: anchorLogOffset,
            rSquared: rSquared,
            pointCount: samples.count,
            domain: earliest...latest
        )
    }

    private static func rawLogPrediction(kind: FitKind, coefficients: [Double], t: Double) -> Double {
        switch kind {
        case .exponential:
            return coefficients[0] + coefficients[1] * t
        case .hyperexponential:
            return coefficients[0] + coefficients[1] * t + coefficients[2] * t * t
        case .hyperbolic:
            let diff = coefficients[0] - t
            if diff <= 0 { return .infinity }
            return coefficients[1] - coefficients[2] * log(diff)
        case .sigmoid:
            return log(coefficients[0]) - log(1.0 + exp(coefficients[1] + coefficients[2] * t))
        }
    }

    private struct LinearResult {
        let intercept: Double
        let slope: Double
        let rSquared: Double
    }

    private static func ordinaryLeastSquaresLinear(x: [Double], y: [Double]) -> LinearResult? {
        let n = Double(x.count)
        guard n >= 2 else { return nil }
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        var syy = 0.0
        for index in 0..<x.count {
            let dx = x[index] - meanX
            let dy = y[index] - meanY
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let intercept = meanY - slope * meanX
        var residualSumOfSquares = 0.0
        for index in 0..<y.count {
            let residual = y[index] - (intercept + slope * x[index])
            residualSumOfSquares += residual * residual
        }
        let rSquared = syy > 0 ? max(0, min(1, 1 - residualSumOfSquares / syy)) : 0
        return LinearResult(intercept: intercept, slope: slope, rSquared: rSquared)
    }

    private struct QuadraticResult {
        let coefficients: [Double]
        let rSquared: Double
    }

    private static func ordinaryLeastSquaresQuadratic(x: [Double], y: [Double]) -> QuadraticResult? {
        let n = Double(x.count)
        guard n >= 3 else { return nil }

        var sumX = 0.0, sumX2 = 0.0, sumX3 = 0.0, sumX4 = 0.0
        var sumY = 0.0, sumXY = 0.0, sumX2Y = 0.0
        for index in 0..<x.count {
            let xi = x[index]
            let xi2 = xi * xi
            sumX += xi
            sumX2 += xi2
            sumX3 += xi2 * xi
            sumX4 += xi2 * xi2
            sumY += y[index]
            sumXY += xi * y[index]
            sumX2Y += xi2 * y[index]
        }

        var matrix: [[Double]] = [
            [n,     sumX,  sumX2, sumY],
            [sumX,  sumX2, sumX3, sumXY],
            [sumX2, sumX3, sumX4, sumX2Y]
        ]

        for pivot in 0..<3 {
            var maxRow = pivot
            for row in (pivot + 1)..<3 where abs(matrix[row][pivot]) > abs(matrix[maxRow][pivot]) {
                maxRow = row
            }
            if maxRow != pivot { matrix.swapAt(pivot, maxRow) }
            let pivotValue = matrix[pivot][pivot]
            guard abs(pivotValue) > 1e-12 else { return nil }
            for column in pivot..<4 { matrix[pivot][column] /= pivotValue }
            for row in 0..<3 where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot..<4 {
                    matrix[row][column] -= factor * matrix[pivot][column]
                }
            }
        }

        let coefficients = [matrix[0][3], matrix[1][3], matrix[2][3]]
        let meanY = sumY / n
        var totalSumOfSquares = 0.0, residualSumOfSquares = 0.0
        for index in 0..<x.count {
            let xi = x[index]
            let predicted = coefficients[0] + coefficients[1] * xi + coefficients[2] * xi * xi
            let residual = y[index] - predicted
            residualSumOfSquares += residual * residual
            let deviation = y[index] - meanY
            totalSumOfSquares += deviation * deviation
        }
        let rSquared = totalSumOfSquares > 0 ? max(0, min(1, 1 - residualSumOfSquares / totalSumOfSquares)) : 0
        return QuadraticResult(coefficients: coefficients, rSquared: rSquared)
    }

    private struct HyperbolicResult {
        let coefficients: [Double]
        let rSquared: Double
    }

    private static func fitHyperbolic(times: [Double], logValues: [Double]) -> HyperbolicResult? {
        guard let maxTime = times.max() else { return nil }

        let lowerOffsetDays = 90.0
        let upperOffsetDays = 365.25 * 25.0
        let gridCount = 240

        let meanLogValue = logValues.reduce(0, +) / Double(logValues.count)
        var totalSumOfSquares = 0.0
        for value in logValues {
            let deviation = value - meanLogValue
            totalSumOfSquares += deviation * deviation
        }
        guard totalSumOfSquares > 0 else { return nil }

        var bestCoefficients: [Double]?
        var bestResidualSumOfSquares = Double.infinity

        let logLower = log(lowerOffsetDays)
        let logUpper = log(upperOffsetDays)

        for step in 0...gridCount {
            let fraction = Double(step) / Double(gridCount)
            let offset = exp(logLower + fraction * (logUpper - logLower))
            let tsDays = maxTime + offset

            var transformed: [Double] = []
            transformed.reserveCapacity(times.count)
            var valid = true
            for time in times {
                let diff = tsDays - time
                guard diff > 0 else { valid = false; break }
                transformed.append(log(diff))
            }
            guard valid else { continue }

            guard let line = ordinaryLeastSquaresLinear(x: transformed, y: logValues) else { continue }
            if line.slope >= 0 { continue }

            var residualSumOfSquares = 0.0
            for index in 0..<times.count {
                let predicted = line.intercept + line.slope * transformed[index]
                let residual = logValues[index] - predicted
                residualSumOfSquares += residual * residual
            }

            if residualSumOfSquares < bestResidualSumOfSquares {
                bestResidualSumOfSquares = residualSumOfSquares
                bestCoefficients = [tsDays, line.intercept, -line.slope]
            }
        }

        guard let coefficients = bestCoefficients else { return nil }
        let rSquared = max(0, min(1, 1 - bestResidualSumOfSquares / totalSumOfSquares))
        return HyperbolicResult(coefficients: coefficients, rSquared: rSquared)
    }

    private struct SigmoidResult {
        let coefficients: [Double]
        let rSquared: Double
    }

    private static func fitSigmoid(times: [Double], logValues: [Double], values: [Double]) -> SigmoidResult? {
        let maxValue = values.max() ?? 0
        guard maxValue > 0 else { return nil }

        let logLowerBound = log(maxValue * 1.05)
        let logUpperBound = log(maxValue * 5.0)
        let gridCount = 160

        var bestCoefficients: [Double]?
        var bestResidualSumOfSquares = Double.infinity
        var bestTotalSumOfSquares = Double.infinity

        let meanLogValue = logValues.reduce(0, +) / Double(logValues.count)
        var totalSumOfSquares = 0.0
        for value in logValues {
            let deviation = value - meanLogValue
            totalSumOfSquares += deviation * deviation
        }
        guard totalSumOfSquares > 0 else { return nil }

        for step in 0...gridCount {
            let fraction = Double(step) / Double(gridCount)
            let asymptote = exp(logLowerBound + fraction * (logUpperBound - logLowerBound))

            var transformed: [Double] = []
            transformed.reserveCapacity(values.count)
            var valid = true
            for value in values {
                let ratio = asymptote / value - 1.0
                guard ratio > 0 else { valid = false; break }
                transformed.append(log(ratio))
            }
            guard valid else { continue }
            guard let line = ordinaryLeastSquaresLinear(x: times, y: transformed) else { continue }
            if line.slope >= 0 { continue }

            var residualSumOfSquares = 0.0
            for index in 0..<times.count {
                let predicted = log(asymptote) - log(1.0 + exp(line.intercept + line.slope * times[index]))
                let residual = logValues[index] - predicted
                residualSumOfSquares += residual * residual
            }

            if residualSumOfSquares < bestResidualSumOfSquares {
                bestResidualSumOfSquares = residualSumOfSquares
                bestTotalSumOfSquares = totalSumOfSquares
                bestCoefficients = [asymptote, line.intercept, line.slope]
            }
        }

        guard let coefficients = bestCoefficients else { return nil }
        let rSquared = max(0, min(1, 1 - bestResidualSumOfSquares / bestTotalSumOfSquares))
        return SigmoidResult(coefficients: coefficients, rSquared: rSquared)
    }
}
