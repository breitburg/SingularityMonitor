import SwiftUI
import WidgetKit

struct SingularityWidgetView: View {
    let entry: SingularityWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Horizon")
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer(minLength: 0)

            Text(entry.minutes.map(compactHorizon(minutes:)) ?? "—")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) {
            ZStack {
                Color.black
                LinearGradient(
                    colors: [Color.red.opacity(0.45), Color.red.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private func compactHorizon(minutes: Double) -> String {
    guard minutes.isFinite, minutes > 0 else { return "—" }
    let totalSeconds = minutes * 60.0
    let secondsPerMinute = 60.0
    let secondsPerHour = 3_600.0
    let secondsPerDay = 86_400.0
    let secondsPerYear = 86_400.0 * 365.25
    let secondsPerMonth = secondsPerYear / 12.0

    if totalSeconds < secondsPerMinute {
        return "\(Int(totalSeconds.rounded()))s"
    }
    if totalSeconds < secondsPerHour {
        let mins = Int(totalSeconds / secondsPerMinute)
        let secs = Int((totalSeconds.truncatingRemainder(dividingBy: secondsPerMinute)).rounded())
        return secs > 0 ? "\(mins)m \(secs)s" : "\(mins)m"
    }
    if totalSeconds < secondsPerDay {
        let hours = Int(totalSeconds / secondsPerHour)
        let mins = Int((totalSeconds.truncatingRemainder(dividingBy: secondsPerHour)) / secondsPerMinute)
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }
    if totalSeconds < secondsPerMonth {
        let days = Int(totalSeconds / secondsPerDay)
        let hours = Int((totalSeconds.truncatingRemainder(dividingBy: secondsPerDay)) / secondsPerHour)
        return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
    }
    if totalSeconds < secondsPerYear {
        let months = Int(totalSeconds / secondsPerMonth)
        let days = Int((totalSeconds.truncatingRemainder(dividingBy: secondsPerMonth)) / secondsPerDay)
        return days > 0 ? "\(months)mo \(days)d" : "\(months)mo"
    }
    let years = Int(totalSeconds / secondsPerYear)
    let months = Int((totalSeconds.truncatingRemainder(dividingBy: secondsPerYear)) / secondsPerMonth)
    return months > 0 ? "\(years)y \(months)mo" : "\(years)y"
}
