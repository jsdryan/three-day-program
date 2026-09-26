import WidgetKit
import SwiftUI

// 錶面小工具：下一次該練哪一天（手錶 App 算好寫進共用的 App Group，點一下打開那一天的預覽）
struct NextEntry: TimelineEntry {
    let date: Date
    let day: Int?
    let name: String
    let count: Int
    let last: Date?
    let preview: String
}

struct NextProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextEntry {
        NextEntry(date: .now, day: 1, name: "拉：背、二頭、肩後", count: 7, last: .now.addingTimeInterval(-3 * 86400),
                  preview: "大剪刀下拉・窄握划船・滑輪下拉")
    }
    func getSnapshot(in context: Context, completion: @escaping (NextEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextEntry>) -> Void) {
        // 手錶 App 每次更新課表、練完都會叫小工具重畫；另外每小時更新一次「幾天前」
        completion(Timeline(entries: [read()], policy: .after(.now.addingTimeInterval(3600))))
    }
    private func read() -> NextEntry {
        let o = UserDefaults(suiteName: "group.com.jsdryan.gymplan")?.dictionary(forKey: "next")
        let last = (o?["last"] as? Double).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return NextEntry(date: .now, day: o?["day"] as? Int, name: o?["name"] as? String ?? "",
                         count: o?["count"] as? Int ?? 0, last: last, preview: o?["preview"] as? String ?? "")
    }
}

struct NextView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextEntry

    private var lastText: String {
        guard let l = entry.last else { return "還沒練過" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: l),
                                                   to: Calendar.current.startOfDay(for: entry.date)).day ?? 0
        return days == 0 ? "今天練過" : days == 1 ? "昨天" : "\(days) 天前"
    }

    var body: some View {
        if let day = entry.day {
            switch family {
            case .accessoryInline:
                Label("下一次：\(entry.name)", systemImage: "dumbbell.fill")
            default:
                // 最重要的「練哪天」最大；上面一行放標題和幾天前，下面一行放前幾個動作
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill").widgetAccentable()
                        Text("下一次 · 第 \(day + 1) 天")
                        Spacer(minLength: 4)
                        Text(lastText).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.2))
                    Text(entry.name)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.55)
                    Text(entry.preview.isEmpty ? "\(entry.count) 個動作" : entry.preview)
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Label("打開健身課表", systemImage: "dumbbell.fill").font(.caption)
        }
    }
}

struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextWorkout", provider: NextProvider()) { entry in
            NextView(entry: entry)
                .widgetURL(URL(string: "gymplan://day/\(entry.day ?? 0)"))
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("下一次訓練")
        .description("顯示下一次該練哪一天，點一下直接開始")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}
