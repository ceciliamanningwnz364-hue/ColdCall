import SwiftUI
import SwiftData
import Charts

private struct DayStat: Identifiable {
    let day: Date
    var total = 0
    var talks = 0
    var leads = 0
    var goal = 0
    var id: Date { day }
}

struct HistoryView: View {
    @Query private var calls: [CallRecord]
    @Query(sort: \DayPlan.day, order: .reverse) private var plans: [DayPlan]
    @AppStorage("callsGoal") private var defaultCalls = 120

    init() {
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: .now)) ?? .distantPast
        _calls = Query(
            filter: #Predicate<CallRecord> { $0.date >= since },
            sort: \CallRecord.date, order: .reverse
        )
    }

    /// 30 дней, от сегодняшнего к более старым
    private var days: [DayStat] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: calls) { cal.startOfDay(for: $0.date) }
        var goals: [Date: Int] = [:]
        for plan in plans { goals[plan.day] = plan.callsGoal }
        let today = cal.startOfDay(for: .now)

        return (0..<30).compactMap { offset -> DayStat? in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let items = grouped[d] ?? []
            let stats = DayStats(items)
            return DayStat(day: d, total: stats.total, talks: stats.talks,
                           leads: stats.count(.lead), goal: goals[d] ?? defaultCalls)
        }
    }

    var body: some View {
        let all = days
        let week = Array(all.prefix(7).reversed())
        let weekTotal = week.reduce(0) { $0 + $1.total }
        let weekTalks = week.reduce(0) { $0 + $1.talks }
        let weekLeads = week.reduce(0) { $0 + $1.leads }
        let conversion = weekTalks > 0 ? Int((Double(weekLeads) / Double(weekTalks) * 100).rounded()) : 0
        let todayGoal = all.first?.goal ?? defaultCalls

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        StatTile(title: "Звонков", value: "\(weekTotal)", color: .cyan)
                        StatTile(title: "Разговоров", value: "\(weekTalks)", color: .mint)
                        StatTile(title: "Лидов", value: "\(weekLeads)", color: .yellow)
                        StatTile(title: "Конверсия", value: "\(conversion)%", color: .pink)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Последние 7 дней").font(.headline)
                        Chart {
                            ForEach(week) { d in
                                BarMark(
                                    x: .value("День", d.day, unit: .day),
                                    y: .value("Звонки", d.total)
                                )
                                .foregroundStyle(
                                    LinearGradient(colors: [.cyan, .indigo], startPoint: .top, endPoint: .bottom)
                                )
                                .cornerRadius(7)
                            }
                            RuleMark(y: .value("Цель", todayGoal))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("цель \(todayGoal)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                        .frame(height: 190)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                        .chartYAxis {
                            AxisMarks { _ in
                                AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                                AxisValueLabel()
                            }
                        }
                    }
                    .padding(16)
                    .glassCard(radius: 30)

                    let active = all.filter { $0.total > 0 }
                    if active.isEmpty {
                        ContentUnavailableView(
                            "Истории пока нет",
                            systemImage: "chart.bar.xaxis",
                            description: Text("Здесь появятся итоги каждого дня")
                        )
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                Text("По дням").font(.title3.bold())
                                Spacer()
                            }
                            ForEach(active) { DayRow(stat: $0) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Итоги")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct DayRow: View {
    let stat: DayStat

    private var reached: Bool { stat.goal > 0 && stat.total >= stat.goal }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stat.day, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline.weight(.semibold))
                Text("Разговоров \(stat.talks) · Лидов \(stat.leads)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(stat.total) / \(stat.goal)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(reached ? Color.mint : Color.white)
                ProgressView(value: Double(min(stat.total, max(stat.goal, 1))),
                             total: Double(max(stat.goal, 1)))
                    .tint(reached ? Color.mint : Color.cyan)
                    .frame(width: 90)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .softCard(radius: 22)
    }
}
