import SwiftUI
import WatchKit

// 第 0 步：確認 App 裝得上手錶、手腕震動有效
struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 10) {
            Text("健身課表")
                .font(.title3.weight(.heavy))
                .italic()
            Text("手錶版 0.1")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                WKInterfaceDevice.current().play(.notification)
                count += 1
            } label: {
                Label("測試震動", systemImage: "waveform")
                    .frame(maxWidth: .infinity)
            }
            .tint(Color(red: 0.89, green: 0.09, blue: 0.04))
            if count > 0 {
                Text("震了 \(count) 次")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    ContentView()
}
