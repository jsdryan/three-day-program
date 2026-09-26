import Foundation

// ---- 網頁版存在 prefs.data.watch 的課表快照 ----
struct Snapshot: Codable {
    var prog: String
    var pname: String?
    var updated: Double?
    var days: [SDay]
}

struct SDay: Codable, Identifiable, Hashable {
    var did: String
    var name: String
    var lastT: String?      // 這一天上次練的時間（網頁版算好）
    var ex: [SGroup]
    var id: String { did }
}

struct SGroup: Codable, Hashable {
    var sup: Bool
    var rest: Int
    var note: String?
    var items: [SItem]
}

struct SItem: Codable, Hashable {
    var id: String
    var n: String
    var orig: String?
    var rm: String
    var bw: Bool?
    var mc: String?
    var last: [SSet]?
    var lastT: String?
}

struct SSet: Codable, Hashable {
    var w: Double?
    var r: Int?
}

// ---- 手錶上正在進行的訓練 ----
struct WSet: Codable, Hashable {
    var w: Double?
    var r: Int?
    var done: Bool = false
}

struct WItem: Codable, Identifiable, Hashable {
    var id: String
    var n: String
    var orig: String?
    var rm: String
    var bw: Bool
    var mc: String?
    var last: [SSet]
    var sets: [WSet]
    var group: Int       // 第幾個動作群組（超級組的兩個動作同一群）
    var pos: Int         // 在群組裡的位置
    var groupSize: Int
    var rest: Int

    var doneCount: Int { sets.filter(\.done).count }
    var isDone: Bool { !sets.isEmpty && sets.allSatisfy(\.done) }
    var nextSet: Int? { sets.firstIndex { !$0.done } }
}

struct Workout: Codable {
    var prog: String
    var pname: String?
    var day: Int
    var did: String
    var dayName: String
    var items: [WItem]
    var started: Date
    var current: Int = 0

    init(snapshot: Snapshot, day: Int, localLast: [String: [SSet]]) {
        let d = snapshot.days[day]
        prog = snapshot.prog
        pname = snapshot.pname
        self.day = day
        did = d.did
        dayName = d.name
        started = Date()
        var out: [WItem] = []
        for (gi, g) in d.ex.enumerated() {
            for (pi, it) in g.items.enumerated() {
                // 上次紀錄：手錶自己存過比較新的就用手錶的
                let last = localLast[it.n] ?? it.last ?? []
                let count = max(last.count, 3)
                let fallbackR = Workout.firstNumber(it.rm)
                let sets = (0..<count).map { i -> WSet in
                    let src = last.isEmpty ? nil : last[min(i, last.count - 1)]
                    return WSet(w: src?.w, r: src?.r ?? fallbackR)
                }
                out.append(WItem(id: it.id, n: it.n, orig: it.orig, rm: it.rm, bw: it.bw ?? false, mc: it.mc,
                                 last: last, sets: sets, group: gi, pos: pi, groupSize: g.items.count, rest: g.rest))
            }
        }
        items = out
    }

    static func firstNumber(_ s: String) -> Int? {
        Int(String(s.prefix { $0.isNumber }))
    }

    var doneSets: Int { items.reduce(0) { $0 + $1.doneCount } }
    var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }
}
