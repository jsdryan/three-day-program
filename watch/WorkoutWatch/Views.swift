import SwiftUI

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
        #if DEBUG
        // 模擬器測試用：-autostart 天數 -autocomplete 次數
        .task {
            let a = UserDefaults.standard
            if let d = a.string(forKey: "autostart"), let day = Int(d) {
                store.start(day: day, askNotify: false)
                for _ in 0..<a.integer(forKey: "autocomplete") { store.completeSet(); store.skipRest() }
                if a.bool(forKey: "autorest") { store.startRest(65) }
            }
        }
        #endif
        .onChange(of: phase) { _, p in
            // 從背景回來時，倒數已經過了就直接收掉
            if p == .active, let e = store.restEnd, e <= Date() { store.skipRest() }
        }
    }
}

// ---- 登入：輸入 Email → 收 6 位數驗證碼 ----
struct LoginView: View {
    @EnvironmentObject var store: Store
    @State private var email = ""
    @State private var code = ""
    @State private var sent = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("健身課表").font(.headline.italic())
                if !sent {
                    Text("輸入網頁版登入用的 Gmail").font(.caption2).foregroundStyle(.secondary)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    Button("寄驗證碼") {
                        Task { sent = await store.sendCode(email: email.trimmingCharacters(in: .whitespaces).lowercased()) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!email.contains("@") || store.loading)
                } else {
                    Text("驗證碼寄到 \(email)").font(.caption2).foregroundStyle(.secondary)
                    TextField("驗證碼", text: $code)
                    Button("登入") {
                        Task { await store.verify(email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                                                  code: code.filter(\.isNumber)) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(code.filter(\.isNumber).count < 6 || store.loading)
                    Button("重寄") { sent = false; code = "" }.font(.caption2)
                }
                if store.loading { ProgressView() }
                if let m = store.message { Text(m).font(.caption2).foregroundStyle(.red) }
            }
        }
    }
}

// ---- 選今天練哪一天 ----
struct DaysView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            List {
                if let m = store.message {
                    Text(m).font(.caption2).foregroundStyle(.secondary)
                }
                if let s = store.snapshot {
                    Section(s.pname ?? "課表") {
                        ForEach(Array(s.days.enumerated()), id: \.offset) { i, d in
                            Button {
                                store.start(day: i)
                            } label: {
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
            .navigationTitle("今天練哪天")
        }
        .task { await store.refresh() }
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
            }
        }
        .sheet(isPresented: $showList) { ExerciseList(showList: $showList) }
        .overlay {
            if store.restEnd != nil { RestView() }
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

    private var si: Int { item.nextSet ?? max(0, item.sets.count - 1) }
    private var cur: WSet { item.sets[si] }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let mc = item.mc {
                    Text(mc).font(.caption2.weight(.semibold)).foregroundStyle(Color.brandRed).lineLimit(1)
                }
                Text(item.n).font(.headline).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                Text("第 \(si + 1)/\(item.sets.count) 組 · \(item.rm) RM\(item.groupSize > 1 ? " · 超級組" : "")")
                    .font(.caption2).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    valueBox(title: "kg", text: weightText, field: .w)
                        .digitalCrownRotation($crownW, from: 0, through: 500, by: 0.5,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                    valueBox(title: "次", text: cur.r.map(String.init) ?? "–", field: .r)
                        .digitalCrownRotation($crownR, from: 0, through: 100, by: 1,
                                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                }

                Button {
                    store.completeSet()
                } label: {
                    Label("完成", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if !item.last.isEmpty {
                    Text("上次 " + item.last.map { "\($0.w.map(fmtW) ?? "自體")×\($0.r.map(String.init) ?? "–")" }.joined(separator: "、"))
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .onAppear {
            crownW = cur.w ?? 0
            crownR = Double(cur.r ?? 0)
            focus = .w
        }
        .onChange(of: crownW) { _, v in
            let nv: Double? = (item.bw && v == 0) ? nil : v
            if nv != cur.w { store.setWeight(nv) }
        }
        .onChange(of: crownR) { _, v in
            if Int(v) != cur.r { store.setReps(Int(v)) }
        }
        .onChange(of: si) { _, _ in
            crownW = cur.w ?? 0
            crownR = Double(cur.r ?? 0)
        }
    }

    private var weightText: String {
        if let w = cur.w, w > 0 { return fmtW(w) }
        return item.bw ? "自體" : "–"
    }

    @ViewBuilder
    private func valueBox(title: String, text: String, field: Field) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.system(size: 26, weight: .heavy, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
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

// 動作清單：跳到任一動作、加減組、練完存檔
struct ExerciseList: View {
    @EnvironmentObject var store: Store
    @Binding var showList: Bool
    @State private var confirmDiscard = false

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
                            Task { _ = await store.finish(); showList = false }
                        } label: { Label("練完存檔", systemImage: "square.and.arrow.up") }
                        Button(role: .destructive) { confirmDiscard = true } label: { Text("放棄這次訓練") }
                    }
                }
            }
            .navigationTitle("動作")
        }
        .confirmationDialog("放棄後這次不會存檔", isPresented: $confirmDiscard) {
            Button("放棄", role: .destructive) { store.discard(); showList = false }
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
                Task { _ = await store.finish() }
            } label: {
                Text(store.loading ? "存檔中…" : "練完存檔").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
