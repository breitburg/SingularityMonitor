import SwiftUI
import WidgetKit

struct SingularityWidget: Widget {
    let kind: String = "SingularityHorizonWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SingularityWidgetProvider()) { entry in
            SingularityWidgetView(entry: entry)
        }
        .configurationDisplayName("Singularity Monitor")
        .description("Current AI horizon length from METR benchmarks.")
        .supportedFamilies([.systemSmall])
    }
}
