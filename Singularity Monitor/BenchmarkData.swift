import Foundation
import Yams

enum AppGroup {
    static let identifier = "group.com.breitburg.singularity"
    static let userDefaults: UserDefaults = UserDefaults(suiteName: identifier) ?? .standard
    static var cacheURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent("snapshot.yaml")
    }
}

struct HorizonEstimate: Hashable {
    let estimateMinutes: Double
    let ciLowMinutes: Double?
    let ciHighMinutes: Double?
}

struct ModelResult: Identifiable, Hashable {
    let id: String
    let displayName: String
    let releaseDate: Date
    let averageScore: Double
    let isSOTA: Bool
    let p50: HorizonEstimate
    let p80: HorizonEstimate
}

struct BenchmarkSnapshot {
    let benchmarkName: String
    let fetchedAt: Date
    let models: [ModelResult]

    var earliestReleaseDate: Date { models.first?.releaseDate ?? Date(timeIntervalSince1970: 0) }
    var latestReleaseDate: Date { models.last?.releaseDate ?? Date() }
}

enum BenchmarkLoaderError: LocalizedError {
    case invalidYAML
    case missingResults
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidYAML: return String(localized: "The benchmark file isn't valid YAML.")
        case .missingResults: return String(localized: "The benchmark file has no results section.")
        case .decodingFailed(let detail): return String(localized: "Couldn't read benchmark: \(detail)")
        }
    }
}

struct BenchmarkLoader {
    static let benchmarkURL = URL(string: "https://metr.org/assets/benchmark_results_1_1.yaml")!

    static func load(session: URLSession = .shared) async throws -> BenchmarkSnapshot {
        var request = URLRequest(url: benchmarkURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await session.data(for: request)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BenchmarkLoaderError.invalidYAML
        }
        let snapshot = try parse(yamlText: text)
        if let cacheURL = AppGroup.cacheURL {
            try? data.write(to: cacheURL, options: .atomic)
        }
        return snapshot
    }

    static func cachedSnapshot() -> BenchmarkSnapshot? {
        guard let cacheURL = AppGroup.cacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return try? parse(yamlText: text)
    }

    static func parse(yamlText: String) throws -> BenchmarkSnapshot {
        let root: Any?
        do {
            root = try Yams.load(yaml: yamlText)
        } catch {
            throw BenchmarkLoaderError.decodingFailed(error.localizedDescription)
        }

        guard let rootMap = root as? [String: Any] else {
            throw BenchmarkLoaderError.invalidYAML
        }
        let benchmarkName = rootMap["benchmark_name"] as? String ?? "METR Horizon"
        guard let resultsMap = rootMap["results"] as? [String: Any] else {
            throw BenchmarkLoaderError.missingResults
        }

        var models: [ModelResult] = []
        models.reserveCapacity(resultsMap.count)
        for (key, value) in resultsMap {
            guard let entry = value as? [String: Any] else { continue }
            guard let parsed = makeModelResult(key: key, entry: entry) else { continue }
            models.append(parsed)
        }
        models.sort { $0.releaseDate < $1.releaseDate }

        return BenchmarkSnapshot(
            benchmarkName: benchmarkName,
            fetchedAt: Date(),
            models: models
        )
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return formatter
    }()

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func makeModelResult(key: String, entry: [String: Any]) -> ModelResult? {
        let metrics = entry["metrics"] as? [String: Any] ?? [:]

        guard let averageScore = doubleValue(in: metrics, path: ["average_score", "estimate"]) else {
            return nil
        }
        guard let p50Estimate = doubleValue(in: metrics, path: ["p50_horizon_length", "estimate"]) else {
            return nil
        }
        guard let p80Estimate = doubleValue(in: metrics, path: ["p80_horizon_length", "estimate"]) else {
            return nil
        }

        let p50 = HorizonEstimate(
            estimateMinutes: p50Estimate,
            ciLowMinutes: doubleValue(in: metrics, path: ["p50_horizon_length", "ci_low"]),
            ciHighMinutes: doubleValue(in: metrics, path: ["p50_horizon_length", "ci_high"])
        )
        let p80 = HorizonEstimate(
            estimateMinutes: p80Estimate,
            ciLowMinutes: doubleValue(in: metrics, path: ["p80_horizon_length", "ci_low"]),
            ciHighMinutes: doubleValue(in: metrics, path: ["p80_horizon_length", "ci_high"])
        )

        let isSOTA = (metrics["is_sota"] as? Bool) ?? false

        let releaseDate: Date
        if let dateValue = entry["release_date"] as? Date {
            releaseDate = dateValue
        } else if let dateString = entry["release_date"] as? String,
                  let parsedDate = parseDate(dateString) {
            releaseDate = parsedDate
        } else {
            return nil
        }

        return ModelResult(
            id: key,
            displayName: displayName(forKey: key),
            releaseDate: releaseDate,
            averageScore: averageScore,
            isSOTA: isSOTA,
            p50: p50,
            p80: p80
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        if let date = dateFormatter.date(from: string) { return date }
        return fallbackDateFormatter.date(from: string)
    }

    private static func doubleValue(in map: [String: Any], path: [String]) -> Double? {
        var node: Any = map
        for key in path {
            guard let dict = node as? [String: Any], let next = dict[key] else { return nil }
            node = next
        }
        if let number = node as? Double { return number }
        if let number = node as? Int { return Double(number) }
        if let number = node as? NSNumber { return number.doubleValue }
        if let string = node as? String { return Double(string) }
        return nil
    }

    private static func displayName(forKey key: String) -> String {
        if let override = displayNameOverrides[key] { return override }
        var working = key
        let dropSuffixes = ["_inspect", "_2025_08_07"]
        for suffix in dropSuffixes {
            if working.hasSuffix(suffix) {
                working = String(working.dropLast(suffix.count))
            }
        }

        let pieces = working.split(separator: "_").map(String.init)
        var rendered: [String] = []
        for piece in pieces {
            if piece.allSatisfy(\.isNumber) {
                rendered.append(piece)
                continue
            }
            if let lower = piece.first?.lowercased(), let upper = piece.first?.uppercased(), lower == upper {
                rendered.append(piece)
                continue
            }
            rendered.append(piece.prefix(1).uppercased() + piece.dropFirst())
        }
        var name = rendered.joined(separator: " ")
        name = name.replacingOccurrences(of: " 4 1 ", with: " 4.1 ")
        name = name.replacingOccurrences(of: " 3 5 ", with: " 3.5 ")
        name = name.replacingOccurrences(of: " 3 7 ", with: " 3.7 ")
        name = name.replacingOccurrences(of: " 4 5 ", with: " 4.5 ")
        name = name.replacingOccurrences(of: " 4 6 ", with: " 4.6 ")
        name = name.replacingOccurrences(of: " 3 1 ", with: " 3.1 ")
        name = name.replacingOccurrences(of: " 5 1 ", with: " 5.1 ")
        name = name.replacingOccurrences(of: " 5 2", with: " 5.2")
        name = name.replacingOccurrences(of: " 5 3", with: " 5.3")
        name = name.replacingOccurrences(of: " 5 4", with: " 5.4")
        name = name.replacingOccurrences(of: " 3 5", with: " 3.5")
        name = name.replacingOccurrences(of: " 4 1", with: " 4.1")
        return name
    }

    private static let displayNameOverrides: [String: String] = [
        "davinci_002": "davinci-002",
        "gpt2": "GPT-2",
        "gpt_3_5_turbo_instruct": "GPT-3.5 Turbo",
        "gpt_4": "GPT-4",
        "gpt_4_1106_inspect": "GPT-4 (1106)",
        "gpt_4_turbo_inspect": "GPT-4 Turbo",
        "gpt_4o_inspect": "GPT-4o",
        "gpt_5_2025_08_07_inspect": "GPT-5",
        "gpt_5_1_codex_max_inspect": "GPT-5.1 Codex Max",
        "gpt_5_2": "GPT-5.2",
        "gpt_5_3_codex": "GPT-5.3 Codex",
        "gpt_5_4": "GPT-5.4",
        "o1_preview": "o1-preview",
        "o1_inspect": "o1",
        "o3_inspect": "o3",
        "claude_3_opus_inspect": "Claude 3 Opus",
        "claude_3_5_sonnet_20240620_inspect": "Claude 3.5 Sonnet (Jun 2024)",
        "claude_3_5_sonnet_20241022_inspect": "Claude 3.5 Sonnet (Oct 2024)",
        "claude_3_7_sonnet_inspect": "Claude 3.7 Sonnet",
        "claude_4_opus_inspect": "Claude 4 Opus",
        "claude_4_1_opus_inspect": "Claude 4.1 Opus",
        "claude_opus_4_5_inspect": "Claude Opus 4.5",
        "claude_opus_4_6_inspect": "Claude Opus 4.6",
        "claude_mythos_preview_early_inspect": "Claude Mythos (early preview)",
        "gemini_3_pro": "Gemini 3 Pro",
        "gemini_3_1_pro": "Gemini 3.1 Pro"
    ]
}
