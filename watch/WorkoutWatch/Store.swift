import Foundation
import SwiftUI
import UserNotifications
import WatchKit

// 整個手錶 App 的狀態：登入、課表快照、進行中的訓練、休息倒數
@MainActor
final class Store: ObservableObject {
    @Published var auth: AuthSession? { didSet { save(auth, "auth") } }
    @Published var snapshot: Snapshot? { didSet { save(snapshot, "snapshot") } }
    @Published var workout: Workout? { didSet { save(workout, "workout") } }
    @Published var restEnd: Date? { didSet { save(restEnd, "restEnd") } }
    @Published var alarming = false   // 休息結束、還沒按「開始下一組」
    private var alarmTask: Task<Void, Never>?
    @Published var showEnd = false    // 「結束訓練」的選項畫面
    @Published var loading = false
    @Published var message: String?

    // 手錶自己練過的上次紀錄（網頁快照還沒更新前先用這個）
    private var localLast: [String: [SSet]] { didSet { save(localLast, "localLast") } }
    // 沒網路時存不上去的紀錄，下次連線再補傳
    private var pending: [Data] { didSet { save(pending, "pending") } }

    init() {
        auth = Store.load("auth")
        snapshot = Store.load("snapshot")
        workout = Store.load("workout")
        restEnd = Store.load("restEnd")
        localLast = Store.load("localLast") ?? [:]
        pending = Store.load("pending") ?? []
    }

    // ---- 存取 ----
    private func save<T: Encodable>(_ v: T?, _ key: String) {
        let d = UserDefaults.standard
        if let v, let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) } else { d.removeObject(forKey: key) }
    }
    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // ---- 登入：輸入手機網頁上的配對碼 ----
    func pair(code: String) async {
        loading = true; defer { loading = false }
        do {
            auth = try await Supa.shared.pair(code: code)
            message = nil
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func logout() { auth = nil; snapshot = nil; workout = nil; restEnd = nil }

    private func validAuth() async throws -> AuthSession {
        guard let a = auth else { throw SupaError.http(0, "還沒登入") }
        let fresh = try await Supa.shared.refreshed(a)
        if fresh.access != a.access { auth = fresh }
        return fresh
    }

    // 從雲端抓最新課表，順便補傳之前沒傳成功的紀錄
    func refresh() async {
        guard auth != nil else { return }
        loading = true; defer { loading = false }
        do {
            let a = try await validAuth()
            await flushPending(a)
            if let s = try await Supa.shared.loadSnapshot(a) { snapshot = s; message = nil }
            else if snapshot == nil { message = "雲端還沒有課表。先用手機打開網頁版一次（登入同一個帳號）。" }
        } catch {
            message = snapshot == nil ? "連不上雲端：\(error.localizedDescription)" : nil
        }
    }

    // ---- 訓練 ----
    func start(day: Int, askNotify: Bool = true) {
        guard let s = snapshot, s.days.indices.contains(day) else { return }
        var w = Workout(snapshot: s, day: day, localLast: localLast)
        w.current = w.items.firstIndex { !$0.isDone } ?? 0
        workout = w
        if askNotify {
            requestNotificationPermission()
            Task { await HealthWorkout.shared.start() }
        }
    }

    // App 被系統關掉後重開、訓練還在：把體能訓練接回來，暗屏震動才有效
    func resumeHealthIfNeeded() {
        if workout != nil && !HealthWorkout.shared.isRunning { Task { await HealthWorkout.shared.resumeOrStart() } }
    }

    func jump(to i: Int) { workout?.current = i }

    // 調整目前這組；後面還沒做的組跟著一起變（通常每組同重量）
    func setWeight(_ v: Double?) {
        guard var w = workout, let si = w.items[w.current].nextSet else { return }
        for j in si..<w.items[w.current].sets.count where !w.items[w.current].sets[j].done {
            w.items[w.current].sets[j].w = v
        }
        workout = w
    }

    func setReps(_ v: Int?) {
        guard var w = workout, let si = w.items[w.current].nextSet else { return }
        for j in si..<w.items[w.current].sets.count where !w.items[w.current].sets[j].done {
            w.items[w.current].sets[j].r = v
        }
        workout = w
    }

    func addSet() {
        guard var w = workout else { return }
        let last = w.items[w.current].sets.last
        w.items[w.current].sets.append(WSet(w: last?.w, r: last?.r))
        workout = w
    }

    func removeSet() {
        guard var w = workout, let si = w.items[w.current].sets.lastIndex(where: { !$0.done }),
              w.items[w.current].sets.count > 1 else { return }
        w.items[w.current].sets.remove(at: si)
        workout = w
    }

    // 按「完成」：記這一組，決定下一步（超級組先換另一個動作，不休息）
    func completeSet() {
        guard var w = workout else { return }
        dismissAlarm()
        let c = w.current
        guard let si = w.items[c].nextSet else { return }
        w.items[c].sets[si].done = true
        let it = w.items[c]
        WKInterfaceDevice.current().play(.success)

        if it.groupSize > 1 && it.pos < it.groupSize - 1 && !w.items[c + 1].isDone {
            w.current = c + 1
            workout = w
            return
        }
        let first = c - it.pos
        let groupRange = first..<(first + it.groupSize)
        if let again = groupRange.first(where: { !w.items[$0].isDone }) {
            w.current = again
        } else if let next = (groupRange.upperBound..<w.items.count).first(where: { !w.items[$0].isDone })
                    ?? (0..<w.items.count).first(where: { !w.items[$0].isDone }) {
            w.current = next
        }
        workout = w
        if w.items.contains(where: { !$0.isDone }) { startRest(it.rest) }
    }

    // ---- 休息倒數 ----
    private static let restIDs = (0..<30).map { "rest-\($0)" }

    func startRest(_ sec: Int) {
        dismissAlarm()
        let end = Date().addingTimeInterval(TimeInterval(sec))
        restEnd = end
        scheduleRestNotification(at: end)
    }

    func addRest(_ sec: Int) {
        guard let e = restEnd else { return }
        let end = e.addingTimeInterval(TimeInterval(sec))
        restEnd = end
        scheduleRestNotification(at: end)
    }

    func skipRest() {
        restEnd = nil
        clearRestNotifications()
    }

    // 倒數到 0：顯示「休息結束」並每 2 秒震一次，直到按「開始下一組」（最多 2 分鐘）
    func restFinished() {
        guard restEnd != nil else { return }
        restEnd = nil
        // 體能訓練進行中，App 暗屏也在跑，自己震就好；不然螢幕亮著才自己震，暗著靠通知
        if HealthWorkout.shared.isRunning || WKApplication.shared().applicationState == .active { clearRestNotifications() }
        alarming = true
        alarmTask?.cancel()
        alarmTask = Task { @MainActor in
            let dev = WKInterfaceDevice.current()
            for _ in 0..<60 {
                guard !Task.isCancelled, self.alarming else { return }
                dev.play(.notification)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            self.alarming = false
        }
    }

    func dismissAlarm() {
        alarming = false
        alarmTask?.cancel()
        alarmTask = nil
        clearRestNotifications()
    }

    func clearRestNotifications() {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: Store.restIDs)
        c.removeDeliveredNotifications(withIdentifiers: Store.restIDs)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // 手放下、App 在背景時：時間到起每 4 秒一則通知（共 30 則），打開 App 或按「開始下一組」就全部取消
    private func scheduleRestNotification(at date: Date) {
        let c = UNUserNotificationCenter.current()
        clearRestNotifications()
        // 備援：萬一體能訓練沒開成（例如沒給健康權限），才靠通知震
        let body = workout.map { "下一個：" + $0.items[$0.current].n } ?? "開始下一組"
        for (i, id) in Store.restIDs.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "休息結束"
            content.body = body
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.threadIdentifier = "rest"
            let t = max(1, date.timeIntervalSinceNow + Double(i * 4))
            c.add(UNNotificationRequest(identifier: id, content: content,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: t, repeats: false)))
        }
    }

    // ---- 練完存檔：格式跟網頁版的歷史紀錄一樣 ----
    // saveHealth：使用者在結束畫面選「存入 Apple 健身與健康」才存，不會自動存
    func finish(saveHealth: Bool) async -> Bool {
        guard let w = workout else { return false }
        skipRest(); dismissAlarm()
        var items: [[String: Any]] = []
        var done = 0
        for it in w.items {
            let log = it.sets.filter(\.done)
            guard !log.isEmpty else { continue }
            done += log.count
            var o: [String: Any] = ["n": it.n, "rm": it.rm, "sets": log.count,
                                    "log": log.map { ["w": $0.w as Any? ?? NSNull(), "r": $0.r as Any? ?? NSNull()] },
                                    "w": log[0].w as Any? ?? NSNull()]
            if let orig = it.orig { o["orig"] = orig }
            if it.bw { o["bw"] = true }
            if let mc = it.mc { o["mc"] = mc }
            items.append(o)
            localLast[it.n] = log.map { SSet(w: $0.w, r: $0.r) }
        }
        guard done > 0 else { message = "還沒完成任何一組。"; return false }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rec: [String: Any] = ["id": Int(Date().timeIntervalSince1970 * 1000), "t": fmt.string(from: Date()),
                                  "prog": w.prog, "day": w.day, "did": w.did, "name": w.dayName,
                                  "done": done, "total": w.totalSets, "items": items, "src": "watch",
                                  "dur": Int(Date().timeIntervalSince(w.started))]
        if let p = w.pname { rec["pname"] = p }
        let data = (try? JSONSerialization.data(withJSONObject: rec)) ?? Data()
        workout = nil
        await HealthWorkout.shared.end(save: saveHealth)
        loading = true; defer { loading = false }
        do {
            let a = try await validAuth()
            try await Supa.shared.saveSession(a, record: rec)
            message = "已存檔：\(done) 組\(saveHealth ? "，也存進 Apple 健身" : "")。手機歷史紀錄打開就會看到。"
        } catch {
            pending.append(data)
            message = "先存在手錶上，連上網路後會自動上傳。"
        }
        return true
    }

    func discard() {
        skipRest(); dismissAlarm(); workout = nil
        Task { await HealthWorkout.shared.end(save: false) }
    }

    private func flushPending(_ a: AuthSession) async {
        var left: [Data] = []
        for d in pending {
            guard let rec = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            do { try await Supa.shared.saveSession(a, record: rec) } catch { left.append(d) }
        }
        if left.count != pending.count { pending = left }
    }
}
