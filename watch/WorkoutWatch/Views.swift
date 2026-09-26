import SwiftUI
import WidgetKit

struct RootView: View {
    @EnvironmentObject var store: Store
    @Environment(\.scenePhase) private var phase

    var body: some View {
        Group {
            if store.auth == nil {
                LoginView()
            } else if store.workout != nil {
                WorkoutView()
            } else {
                DaysView()
            }
        }
        .task {
            store.resumeHealthIfNeeded()
            store.publishNext()
        }
        #if DEBUG
        .onAppear { if UserDefaults.standard.bool(forKey: "reset") { store.discard() } }
        #endif
        #if DEBUG
        // 模擬器測試用：-autostart 天數 -autocomplete 次數
        .task {
            let a = UserDefaults.standard
            if let d = a.string(forKey: "autostart"), let day = Int(d) {
                store.start(day: day, askNotify: false)
                for _ in 0..<a.integer(forKey: "autocomplete") { store.completeSet(); store.skipRest() }
                if a.bool(forKey: "showend") { store.showEnd = true }
                if a.bool(forKey: "autorest") { store.startRest(a.integer(forKey: "restsec") > 0 ? a.integer(forKey: "restsec") : 65) }
            }
        }
        #endif
        .onChange(of: phase) { _, p in
            // 從背景回來時，倒數已經過了：切到「休息結束」畫面繼續震，直到按掉
            if p == .active, let e = store.restEnd, e <= Date() { store.restFinished() }
            // 螢幕亮起來、已經在「休息結束」畫面：改由 App 自己震，收掉剩下的通知
            if p == .active && store.alarming { store.clearRestNotifications() }
        }
    }
}

// ---- 登入：輸入手機網頁上「連結 Apple Watch」給的 8 位數配對碼 ----
struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var code = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("健身課表").font(.headline.italic())
                Text("在手機網頁按「連結 Apple Watch」，把 8 位數配對碼輸入這裡")
                    .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField("配對碼", text: $code)
                Button("登入") {
                    Task { await store.pair(code: code.filter(\.isNumber)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.filter(\.isNumber).count != 8 || store.loading)
                if store.loading { ProgressView() }
                if let m = store.message { Text(m).font(.caption2).foregroundStyle(.red) }
            }
        }
    }
}

// ---- 選今天練哪一天 ----
struct DaysView: View {
    @EnvironmentObject var store: Store
    @State private var path: [Int] = {
        #if DEBUG
        if let p = UserDefaults.standard.string(forKey: "preview"), let d = Int(p) { return [d] }
        #endif
        return []
    }()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                StepsRow()
                    .task { await store.loadSteps() }
                if let m = store.message {
                    Text(m).font(.caption2).foregroundStyle(.secondary)
                }
                if let s = store.snapshot {
                    Section(s.pname ?? "課表") {
                        ForEach(Array(s.days.enumerated()), id: \.offset) { i, d in
                            NavigationLink(value: i) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("第 \(i + 1) 天").font(.caption2).foregroundStyle(Color.brandRed)
                                    Text(d.name).font(.headline).lineLimit(2)
                                    Text("\(d.ex.reduce(0) { $0 + $1.items.count }) 個動作")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button { Task { await store.refresh() } } label: {
                        Label(store.loading ? "更新中…" : "重新抓課表", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) { store.logout() } label: { Text("登出") }
                }
            }
            .navigationTitle("開始訓練")
            .navigationDestination(for: Int.self) { DayPreview(day: $0) }
            // 點錶面「下一次訓練」小工具（gymplan://day/1）直接打開那一天的預覽
            .onOpenURL { url in
                if url.host == "day", let i = Int(url.lastPathComponent) { path = [i] }
            }
        }
        .task { await store.refresh() }
    }
}

// 今天步數：狀態放在 Store，清單重畫時不會一直重讀；讀不到就教使用者去健康 App 打開權限
struct StepsRow: View {
    @EnvironmentObject var store: Store
    @State private var showHelp = false

    var body: some View {
        Group {
            if let steps = store.steps {
                Label("今天 \(steps.formatted(.number)) 步", systemImage: "figure.walk")
                    .font(.footnote.weight(.semibold))
            } else if !store.stepsLoaded {
                Label("讀取步數中…", systemImage: "figure.walk").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button { showHelp.toggle() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("讀不到步數", systemImage: "figure.walk").font(.footnote.weight(.semibold))
                        if showHelp {
                            // Apple 每種資料只問一次權限，問過就不會再跳視窗，只能手動開
                            Text("在 iPhone 打開「健康」→ 右上角頭像 → App → 健身課表 → 打開「步數」")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("點這裡看怎麼打開").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// ---- 開始前：看這一天有哪些動作，按「開始」才真的開始計時、記體能訓練 ----
struct DayPreview: View {
    @EnvironmentObject var store: Store
    let day: Int

    var body: some View {
        if let s = store.snapshot, s.days.indices.contains(day) {
            let d = s.days[day]
            List {
                Section {
                    Button {
                        store.start(day: day)
                    } label: {
                        Label("開始", systemImage: "play.fill")
                            .font(.title3.weight(.heavy)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(Color.brandRed))
                }
                Section("\(d.ex.reduce(0) { $0 + $1.items.count }) 個動作") {
                    ForEach(Array(d.ex.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 2) {
                            if g.sup { Text("超級組").font(.caption2).foregroundStyle(.orange) }
                            ForEach(Array(g.items.enumerated()), id: \.offset) { _, it in
                                Text(it.n).font(.footnote.weight(.semibold)).lineLimit(2)
                                Text("\(it.rm) RM\(it.mc.map { " · " + $0 } ?? "")")
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle(d.name)
        }
    }
}

// ---- 結束：問要不要存進 Apple 健身與健康 ----
struct EndView: View {
    @EnvironmentObject var store: Store
    @State private var confirmDiscard = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("結束訓練").font(.headline)
                if let w = store.workout {
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                        Text(w.started, style: .timer).monospacedDigit()
                        Text("· \(w.doneSets) 組")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                endButton("存檔＋存入 Apple 健身與健康", prominent: true) { await save(true) }
                endButton("只存檔，不存入健康", prominent: false) { await save(false) }
                Button("繼續訓練") { store.showEnd = false }
                    .font(.footnote)
                Button(role: .destructive) { confirmDiscard = true } label: { Text("放棄這次訓練").font(.footnote) }
                if store.loading { ProgressView() }
            }
        }
        .confirmationDialog("放棄後這次不會存檔，也不會存入健康", isPresented: $confirmDiscard) {
            Button("放棄", role: .destructive) { store.showEnd = false; store.discard() }
        }
    }

    private func save(_ health: Bool) async {
        if await store.finish(saveHealth: health) { store.showEnd = false }
    }

    private func endButton(_ title: String, prominent: Bool, action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).font(.footnote.weight(.bold)).multilineTextAlignment(.center)
                .foregroundStyle(prominent ? .white : Color.brandRed)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(prominent ? Color.brandRed : Color.white))
        }
        .buttonStyle(.plain)
        .disabled(store.loading)
    }
}

// ---- 訓練中 ----
struct WorkoutView: View {
    @EnvironmentObject var store: Store
    @State private var showList = false

    var body: some View {
        NavigationStack {
            Group {
                if let w = store.workout {
                    if w.items.allSatisfy(\.isDone) {
                        FinishView()
                    } else {
                        SetView(item: w.items[w.current], index: w.current)
                            .id(w.current)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showList = true } label: { Image(systemName: "list.bullet").foregroundStyle(.white) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.showEnd = true } label: { Text("結束").font(.footnote.weight(.heavy)).foregroundStyle(.white) }
                }
            }
        }
        .sheet(isPresented: $showList) { ExerciseList(showList: $showList) }
        .sheet(isPresented: $store.showEnd) { EndView() }
        .overlay {
            if store.alarming { AlarmView() }
            else if store.restEnd != nil { RestView() }
        }
    }
}

// 一組的畫面：錶冠調重量／次數，按完成
struct SetView: View {
    @EnvironmentObject var store: Store
    let item: WItem
    let index: Int

    enum Field { case w, r }
    @FocusState private var focus: Field?
    @State private var crownW = 0.0
    @State private var crownR = 0.0
    @State private var lastTurn = Date.distantPast
    @State private var skipNext = false
    // 畫面剛打開時錶冠會自己送出幾下轉動（實測把 62.5 改成 65），0.8 秒內一律忽略
    @State private var ready = false

    private var si: Int { item.nextSet ?? max(0, item.sets.count - 1) }
    private var cur: WSet { item.sets[si] }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ElapsedLine()
                if let mc = item.mc {
                    Text(mc).font(.caption2.weight(.semibold)).foregroundStyle(Color.brandRed).lineLimit(1)
                }
                Text(item.n).font(.headline).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                Text("第 \(si + 1)/\(item.sets.count) 組 · \(item.rm) RM\(item.groupSize > 1 ? " · 超級組" : "")")
                    .font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    // detent：只在整格（0.5 kg／1 次）時更新，轉的途中不會出現 62.3 這種中間值
                    valueBox(title: "kg", text: weightInt, frac: weightFrac, value: cur.w ?? 0, field: .w)
                        .digitalCrownRotation(detent: $crownW, from: 0, through: 100, by: 0.5,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    valueBox(title: "次", text: cur.r.map(String.init) ?? "–", frac: nil, value: Double(cur.r ?? 0), field: .r)
                        .digitalCrownRotation(detent: $crownR, from: 0, through: 30, by: 1,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                }

                Button {
                    store.completeSet()
                } label: {
                    Label("完成", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                // 雙指互點＝完成這一組；休息中／休息結束畫面時停用，避免誤按或跟「開始下一組」搶
                .handGestureShortcut(.primaryAction, isEnabled: store.restEnd == nil && !store.alarming)

                if !item.last.isEmpty {
                    Text("上次 " + item.last.map { "\($0.w.map(fmtW) ?? "自體")×\($0.r.map(String.init) ?? "–")" }.joined(separator: "、"))
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            // 重量 0–100 kg、次數 0–30
            crownW = min(100, cur.w ?? 0)
            crownR = Double(min(30, cur.r ?? 0))
            focus = .w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { resync() }
        }
        .onChange(of: crownW) { old, new in
            if skipNext { skipNext = false; return }
            guard ready else { return }
            // 快轉（兩格間隔不到 0.1 秒）直接跳到下一個 2.5 kg；慢轉維持 0.5 kg 微調
            let now = Date()
            let fast = now.timeIntervalSince(lastTurn) < 0.1
            lastTurn = now
            var v = new
            if fast && new != old {
                let up = new > old
                v = min(100, max(0, (up ? (old / 2.5).rounded(.down) + 1 : (old / 2.5).rounded(.up) - 1) * 2.5))
                if v != new { skipNext = true; crownW = v }
            }
            let nv: Double? = (item.bw && v == 0) ? nil : v
            if nv != cur.w { store.setWeight(nv) }
        }
        .onChange(of: crownR) { _, v in
            guard ready else { return }
            if Int(v) != cur.r { store.setReps(Int(v)) }
        }
        .onChange(of: si) { _, _ in
            ready = false
            skipNext = true
            crownW = min(100, cur.w ?? 0)
            crownR = Double(min(30, cur.r ?? 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { resync() }
        }
    }

    // 0.8 秒後把錶冠的值對回「現在這筆訓練」裡真正的數字（從 store 即時讀，不用畫面剛開時記下的舊值）
    private func resync() {
        guard let w = store.workout, w.items.indices.contains(w.current) else { ready = true; return }
        let it = w.items[w.current]
        let s = it.sets[it.nextSet ?? max(0, it.sets.count - 1)]
        let w0 = min(100, s.w ?? 0), r0 = Double(min(30, s.r ?? 0))
        if crownW != w0 { skipNext = true; crownW = w0 }
        if crownR != r0 { crownR = r0 }
        DispatchQueue.main.async { ready = true }
    }

    // 重量拆成整數和小數：小數那格永遠留位置，53 和 53.5 的「53」停在同一個地方
    private var weightInt: String {
        if let w = cur.w, w > 0 { return String(Int(w.rounded(.down))) }
        return item.bw ? "自體" : "–"
    }
    private var weightFrac: String? {
        guard let w = cur.w, w > 0 else { return nil }
        let f = w - w.rounded(.down)
        return f == 0 ? "" : "." + String(Int((f * 10).rounded()))
    }

    @ViewBuilder
    // frac：nil＝沒有小數格；""＝有小數格但這次是整數（留白佔位）
    private func valueBox(title: String, text: String, frac: String?, value: Double, field: Field) -> some View {
        // 單位固定在右邊、數字靠右：57 變 57.5 時只有數字往左長，「kg」不會跟著跑
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // 數字變化時每一位像計分板一樣滾動，不是硬跳
            Text(text).font(.system(size: 26, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                .monospacedDigit()
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.22), value: value)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let frac {
                Text(frac.isEmpty ? ".5" : frac)
                    .font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit()
                    .opacity(frac.isEmpty ? 0 : 1)
                    .animation(.snappy(duration: 0.18), value: frac)
                    .padding(.leading, -2)
            }
            Text(title).font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(focus == field ? Color.brandRed : .clear, lineWidth: 2))
        .focusable(true)
        .focused($focus, equals: field)
        .onTapGesture { focus = field }
    }
}

func fmtW(_ w: Double) -> String {
    w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(format: "%.1f", w)
}

// 休息倒數：全螢幕大字，時間到手腕連震
struct RestView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = max(0, Int(ceil((store.restEnd ?? ctx.date).timeIntervalSince(ctx.date))))
            VStack(spacing: 6) {
                Text("組間休息").font(.caption2).foregroundStyle(.white.opacity(0.8))
                ElapsedLine(onRed: true)
                Text(String(format: "%d:%02d", left / 60, left % 60))
                    .font(.system(size: 48, weight: .heavy, design: .rounded)).monospacedDigit()
                if let w = store.workout {
                    Text("下一個：\(w.items[w.current].n)").font(.caption2).lineLimit(1)
                }
                HStack(spacing: 8) {
                    restButton("+30 秒") { store.addRest(30) }
                    restButton("跳過") { store.skipRest() }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brandRed)
            .onChange(of: left) { _, l in if l == 0 { store.restFinished() } }
        }
        .ignoresSafeArea()
    }

    private func restButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.footnote.weight(.heavy)).foregroundStyle(Color.brandRed)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
    }
}

// 訓練累積時間（從按「開始訓練」起算）＋完成組數
struct ElapsedLine: View {
    @EnvironmentObject var store: Store
    var onRed = false

    var body: some View {
        if let w = store.workout {
            HStack(spacing: 4) {
                Image(systemName: "stopwatch")
                Text(w.started, style: .timer).monospacedDigit()
                Text("· \(w.doneSets)/\(w.totalSets) 組")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(onRed ? Color.white.opacity(0.85) : Color.secondary)
        }
    }
}

// 休息結束：一直震到按「開始下一組」
struct AlarmView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 8) {
            Text("休息結束").font(.system(size: 34, weight: .heavy)).italic()
            if let w = store.workout {
                Text("下一個：\(w.items[w.current].n)").font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            Text("點兩下手指也能關掉").font(.caption2).foregroundStyle(.white.opacity(0.8))
            Button {
                store.dismissAlarm()
            } label: {
                Text("開始下一組").font(.headline.weight(.heavy)).foregroundStyle(Color.brandRed)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            // 雙指互點（食指拇指點兩下）也能按這顆，不用碰螢幕
            .handGestureShortcut(.primaryAction)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandRed)
        .ignoresSafeArea()
    }
}

// 動作清單：跳到任一動作、加減組、結束訓練
struct ExerciseList: View {
    @EnvironmentObject var store: Store
    @Binding var showList: Bool
    var body: some View {
        NavigationStack {
            List {
                if let w = store.workout {
                    Section("\(w.dayName) · \(w.doneSets)/\(w.totalSets) 組") {
                        ForEach(Array(w.items.enumerated()), id: \.offset) { i, it in
                            Button {
                                store.jump(to: i); showList = false
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(it.n).font(.footnote.weight(i == w.current ? .heavy : .regular)).lineLimit(2)
                                        if it.groupSize > 1 { Text("超級組").font(.caption2).foregroundStyle(.orange) }
                                    }
                                    Spacer()
                                    Text("\(it.doneCount)/\(it.sets.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(it.isDone ? .green : .secondary)
                                }
                            }
                        }
                    }
                    Section("目前動作") {
                        Button { store.addSet() } label: { Label("加一組", systemImage: "plus") }
                        Button { store.removeSet() } label: { Label("少一組", systemImage: "minus") }
                    }
                    Section {
                        Button {
                            showList = false
                            // 等清單收起來再開結束畫面（兩個彈出畫面不能同時開）
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.showEnd = true }
                        } label: { Label("結束訓練", systemImage: "stop.fill") }
                    }
                }
            }
            .navigationTitle("動作")
        }

    }
}

// 全部做完
struct FinishView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(.yellow)
            Text("全部完成").font(.headline)
            if let w = store.workout { Text("\(w.doneSets) 組").font(.caption).foregroundStyle(.secondary) }
            Button {
                store.showEnd = true
            } label: {
                Text("結束訓練").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
