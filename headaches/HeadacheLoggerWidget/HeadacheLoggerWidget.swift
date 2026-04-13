import SwiftUI
import WidgetKit

private struct LogHeadacheProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry() }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry()], policy: .never))
    }

    struct Entry: TimelineEntry {
        let date: Date = .now
    }
}

private struct LogHeadacheWidgetContent: View {
    var body: some View {
        Button(intent: LogHeadacheIntent()) {
            VStack(spacing: 8) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.hierarchical)
                Text("Log headache")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
        .buttonStyle(.plain)
    }
}

struct LogHeadacheWidget: Widget {
    let kind = "com.jackwallner.headachelogger.logwidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LogHeadacheProvider()) { _ in
            LogHeadacheWidgetContent()
                .containerBackground(for: .widget) {
                    Color(red: 0.35, green: 0.12, blue: 0.16)
                }
        }
        .configurationDisplayName("Log headache")
        .description("One tap to log a headache.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HeadacheLoggerWidgetBundle: WidgetBundle {
    var body: some Widget {
        LogHeadacheWidget()
    }
}
