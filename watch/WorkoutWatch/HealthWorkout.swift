import Foundation
import HealthKit

// 把一次重訓記成 Apple「體能訓練」。進行中 watchOS 會讓 App 在螢幕變暗時繼續執行，休息結束才震得了手腕
final class HealthWorkout: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = HealthWorkout()
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isRunning: Bool { session != nil }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType(), HKQuantityType(.stepCount)]
        do { try await store.requestAuthorization(toShare: share, read: read); return true } catch { return false }
    }

    // 步數一有新資料就叫錶面小工具重畫，不只靠 Apple 每 15 分鐘排一次
    private var stepObserver: HKObserverQuery?
    var onStepsChange: (() -> Void)?
    func watchSteps(onChange: @escaping () -> Void) {
        guard stepObserver == nil else { return }
        let type = HKQuantityType(.stepCount)
        let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, done, _ in
            onChange()
            self?.onStepsChange?()
            done()
        }
        stepObserver = q
        store.execute(q)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    // 今天的步數；沒權限或沒資料時回傳 nil
    func todaySteps() async -> Int? {
        let start = Calendar.current.startOfDay(for: .now)
        let pred = HKQuery.predicateForSamples(withStart: start, end: .now)
        return await withCheckedContinuation { c in
            let q = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, r, _ in
                c.resume(returning: r?.sumQuantity().map { Int($0.doubleValue(for: .count())) })
            }
            store.execute(q)
        }
    }

    func start() async {
        if isRunning { return }
        guard await requestAuthorization() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
        } catch {
            session = nil
            builder = nil
        }
    }

    // App 被系統關掉後重開：先把還在進行的那筆體能訓練接回來，沒有才開新的（避免被切成兩筆）
    func resumeOrStart(allowNew: Bool = true) async {
        if session != nil { return }
        if let s = try? await recover() {
            let b = s.associatedWorkoutBuilder()
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            return
        }
        if allowNew { await start() }
    }

    private func recover() async throws -> HKWorkoutSession? {
        try await withCheckedThrowingContinuation { c in
            store.recoverActiveWorkoutSession { s, e in
                if let e { c.resume(throwing: e) } else { c.resume(returning: s) }
            }
        }
    }

    // save：練完存檔就存進「體能訓練」；放棄就丟掉
    func end(save: Bool) async {
        guard let s = session, let b = builder else { return }
        s.end()
        do {
            try await b.endCollection(at: Date())
            if save { _ = try await b.finishWorkout() } else { b.discardWorkout() }
        } catch {}
        session = nil
        builder = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended && workoutSession === session { session = nil; builder = nil }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
