import SwiftUI
import UserNotifications

@main
struct WorkoutWatchApp: App {
    @StateObject private var store = Store()
    private let notiDelegate = NotiDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notiDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.brandRed)
        }
    }
}

// App 在前景時不跳系統通知，由畫面自己震動（避免震兩次）
final class NotiDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}

extension Color {
    static let brandRed = Color(red: 0.89, green: 0.09, blue: 0.04)
}
