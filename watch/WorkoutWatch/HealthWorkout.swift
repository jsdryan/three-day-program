import Foundation
import HealthKit

// 把一次重訓記成 Apple「體能訓練」。進行中 watchOS 會讓 App 在螢幕變暗時繼續執行，休息結束才震得了手腕
final class HealthWorkout: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = HealthWorkout()
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    var isRunning: Bool { session?.state == .running }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        do { try await store.requestAuthorization(toShare: share, read: read); return true } catch { return false }
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
                        from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
