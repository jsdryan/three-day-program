import WidgetKit
import SwiftUI
import HealthKit

// 錶面小工具：今天走了幾步（直接讀手錶健康資料，約 15 分鐘更新一次）
struct StepsEntry: TimelineEntry {
    let date: Date
    let steps: Int?
}

struct StepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StepsEntry { StepsEntry(date: .now, steps: 5234) }

    func getSnapshot(in context: Context, completion: @escaping (StepsEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        fetchSteps { completion(StepsEntry(date: .now, steps: $0)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StepsEntry>) -> Void) {
        fetchSteps { steps in
            let entry = StepsEntry(date: .now, steps: steps)
            // 過午夜要歸零：下次更新取「15 分鐘後」和「明天 0 點」較早的那個
            let midnight = Calendar.current.startOfDay(for: .now).addingTimeInterval(86400)
            let next = min(Date().addingTimeInterval(15 * 60), midnight)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // 手錶鎖定時健康資料讀不到，就用上次讀到的（同一天才用）
    private func fetchSteps(_ done: @escaping (Int?) -> Void) {
        let d = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: .now)
        let cached: Int? = (d.object(forKey: "day") as? Date) == today ? d.integer(forKey: "steps") : nil
        guard HKHealthStore.isHealthDataAvailable() else { done(cached); return }
        let store = HKHealthStore()
        let pred = HKQuery.predicateForSamples(withStart: today, end: .now)
        let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: pred,
                                  options: .cumulativeSum) { _, result, _ in
            if let v = result?.sumQuantity()?.doubleValue(for: .count()) {
                let n = Int(v)
                d.set(n, forKey: "steps")
                d.set(today, forKey: "day")
                done(n)
            } else {
                done(cached)
            }
        }
        store.execute(q)
    }
}

struct StepsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StepsEntry

    private var full: String { entry.steps.map { $0.formatted(.number) } ?? "–" }
    // 圓形格子放不下 5 位數，改成 5.2k
    private var short: String {
        guard let s = entry.steps else { return "–" }
        return s >= 10000 ? String(format: "%.0fk", Double(s) / 1000)
             : s >= 1000 ? String(format: "%.1fk", Double(s) / 1000) : String(s)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            // 跟錶面其他圓形格子一樣有深灰圓底
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "figure.walk").font(.system(size: 14, weight: .semibold))
                    Text(short).font(.system(size: 17, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                }
                .padding(4)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                Label("今天步數", systemImage: "figure.walk").font(.caption2).foregroundStyle(.secondary)
                Text(full).font(.system(size: 28, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "figure.walk").font(.title3)
                .widgetLabel { Text("\(full) 步") }
        default:
            Label("\(full) 步", systemImage: "figure.walk")
        }
    }
}

@main
struct GymWidgets: WidgetBundle {
    var body: some Widget {
        StepsWidget()
        NextWorkoutWidget()
    }
}

struct StepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StepsWidget", provider: StepsProvider()) { entry in
            StepsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("今天步數")
        .description("顯示今天走了幾步")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
