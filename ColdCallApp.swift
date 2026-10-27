import SwiftUI
import SwiftData

@main
struct ColdCallApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .modelContainer(for: [CallRecord.self, Lead.self, DayPlan.self])
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Сегодня", systemImage: "phone.arrow.up.right.fill") }
            LeadsView()
                .tabItem { Label("Лиды", systemImage: "person.2.fill") }
            HistoryView()
                .tabItem { Label("Итоги", systemImage: "chart.bar.xaxis") }
        }
        .tint(.cyan)
    }
}
