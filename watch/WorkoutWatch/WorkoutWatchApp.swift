import SwiftUI
import UserNotifications
import WatchKit

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

// 螢幕亮著、App 在前景時不跳系統通知，由畫面自己震（避免震兩次）；手放下螢幕暗著時照常跳通知震手腕
final class NotiDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async {
            completionHandler(WKApplication.shared().applicationState == .active ? [] : [.banner, .sound])
        }
    }
}

extension Color {
    static let brandRed = Color(red: 0.89, green: 0.09, blue: 0.04)
}
