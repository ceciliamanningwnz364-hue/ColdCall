import SwiftUI
import SwiftData

// MARK: - Контейнер: пересоздаёт экран при смене дня

struct TodayView: View {
    @State private var day = Calendar.current.startOfDay(for: .now)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TodayContent(day: day)
            .id(day)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                let today = Calendar.current.startOfDay(for: .now)
                if today != day { day = today }
            }
    }
}

// MARK: - Основной экран

private struct TodayContent: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @Query private var calls: [CallRecord]
    @Query private var plans: [DayPlan]

    @AppStorage("callsGoal") private var defaultCalls = 120
    @AppStorage("talksGoal") private var defaultTalks = 20
    @AppStorage("autoNote") private var autoNote = true

    @State private var editingCall: CallRecord?
    @State private var leadCall: CallRecord?
    @State private var pendingDelete: CallRecord?
    @State private var showGoal = false

    init(day: Date) {
        self.day = day
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        _calls = Query(
            filter: #Predicate<CallRecord> { $0.date >= day && $0.date < end },
            sort: \CallRecord.date, order: .reverse
        )
        _plans = Query(filter: #Predicate<DayPlan> { $0.day == day })
    }

    private var callsGoal: Int { plans.first?.callsGoal ?? defaultCalls }
    private var talksGoal: Int { plans.first?.talksGoal ?? defaultTalks }

    var body: some View {
        let s = DayStats(calls)
        let goalHit = callsGoal > 0 && s.total >= callsGoal && s.talks >= talksGoal

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HeroCard(day: day, total: s.total, talks: s.talks,
                             callsGoal: callsGoal, talksGoal: talksGoal)

                    GlassGroup(spacing: 12) {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(CallOutcome.quick) { outcome in
                                ActionButton(outcome: outcome, count: s.count(outcome)) { log(outcome) }
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        StatTile(title: "Лидов", value: "\(s.count(.lead))", color: .mint)
                        StatTile(title: "Дозвон", value: "\(s.pickupRate)%", color: .cyan)
                        StatTile(title: "Лид из разговора", value: "\(s.conversion)%", color: .yellow)
                    }

                    logSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Сегодня")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGoal = true } label: { Image(systemName: "target") }
                        .accessibilityLabel("Цель на день")
                }
            }
        }
        .task {
            if plans.isEmpty {
                context.insert(DayPlan(day: day, callsGoal: defaultCalls, talksGoal: defaultTalks))
                try? context.save()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: calls.count)
        .sensoryFeedback(.success, trigger: goalHit)
        .sheet(item: $editingCall, onDismiss: flushDelete) { call in
            CallDetailSheet(call: call) {
                pendingDelete = call
                editingCall = nil
            }
        }
        .sheet(item: $leadCall) { call in
            LeadEditorSheet(call: call)
        }
        .sheet(isPresented: $showGoal) {
            if let plan = plans.first { GoalSheet(plan: plan) }
        }
    }

    // MARK: Журнал

    @ViewBuilder
    private var logSection: some View {
        HStack {
            Text("Журнал").font(.title3.bold())
            Text("\(calls.count)").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            if !calls.isEmpty {
                Button(action: undoLast) {
                    Label("Отменить", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .glassCard(radius: 18, interactive: true)
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.top, 6)

        if calls.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "phone.arrow.up.right").font(.title).foregroundStyle(.secondary)
                Text("Пока пусто").font(.headline)
                Text("Нажимай кнопки выше после каждого звонка")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .softCard(radius: 24)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(Array(calls.enumerated()), id: \.element.persistentModelID) { item in
                    Button { editingCall = item.element } label: {
                        CallRow(call: item.element, number: calls.count - item.offset)
                    }
                    .buttonStyle(PressStyle())
                    .contextMenu {
                        Button(role: .destructive) { remove(item.element) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Действия

    private func log(_ outcome: CallOutcome) {
        let call = CallRecord(outcome: outcome)
        context.insert(call)
        try? context.save()
        switch outcome {
        case .lead:
            leadCall = call
        case .talk, .rejected, .callback:
            if autoNote { editingCall = call }
        case .noAnswer:
            break
        }
    }

    private func undoLast() {
        guard let last = calls.first else { return }
        withAnimation { remove(last) }
    }

    private func remove(_ call: CallRecord) {
        context.delete(call)
        try? context.save()
    }

    /// Удаляем запись только после закрытия шторки — иначе SwiftData может упасть на «отсоединённой» модели
    private func flushDelete() {
        if let call = pendingDelete {
            remove(call)
            pendingDelete = nil
        }
    }
}

// MARK: - Карточка с кольцами

private struct HeroCard: View {
    let day: Date
    let total: Int
    let talks: Int
    let callsGoal: Int
    let talksGoal: Int

    private var headline: String {
        if callsGoal > 0, total >= callsGoal, talks >= talksGoal { return "Цель выполнена 🔥" }
        if total >= callsGoal {
            let left = max(talksGoal - talks, 0)
            return "Звонки закрыты, осталось \(left) \(ruPlural(left, "разговор", "разговора", "разговоров"))"
        }
        let left = callsGoal - total
        return "До цели: \(left) \(ruPlural(left, "звонок", "звонка", "звонков"))"
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 18) {
                RingStat(title: "Звонки", value: total, goal: callsGoal, colors: [.cyan, .blue, .indigo])
                RingStat(title: "Разговоры", value: talks, goal: talksGoal, colors: [.mint, .green, .yellow])
            }
        }
        .padding(18)
        .glassCard(radius: 34)
        .animation(.snappy, value: total)
    }
}

private struct RingStat: View {
    let title: String
    let value: Int
    let goal: Int
    let colors: [Color]

    private var progress: Double { goal > 0 ? Double(value) / Double(goal) : 0 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                ProgressRing(progress: progress, colors: colors)
                VStack(spacing: 0) {
                    Text("\(value)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("из \(goal)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }
            .aspectRatio(1, contentMode: .fit)

            Text("\(title) · \(Int(progress * 100))%")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: value)
    }
}

// MARK: - Кнопка быстрого ввода

private struct ActionButton: View {
    let outcome: CallOutcome
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: outcome.icon).font(.title2)
                    Spacer()
                    Text("\(count)")
                        .font(.title2.weight(.bold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                HStack {
                    Text(outcome.title).font(.headline)
                    Spacer()
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 96)
            .glassCard(radius: 28, tint: outcome.color.opacity(0.55), interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .animation(.snappy, value: count)
    }
}

// MARK: - Строка журнала

struct CallRow: View {
    let call: CallRecord
    let number: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: call.outcome.icon)
                .font(.subheadline)
                .foregroundStyle(call.outcome.color)
                .frame(width: 36, height: 36)
                .background(call.outcome.color.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("#\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(call.outcome.title).font(.subheadline.weight(.semibold))
                }
                if !call.contactLabel.isEmpty {
                    Text(call.contactLabel).font(.footnote).foregroundStyle(.primary.opacity(0.8))
                }
                if !call.note.isEmpty {
                    Text(call.note).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(call.date, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(12)
        .softCard(radius: 22)
    }
}

// MARK: - Детали звонка + заметка

struct CallDetailSheet: View {
    @Bindable var call: CallRecord
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @FocusState private var noteFocused: Bool
    @State private var showLeadEditor = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Результат") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(CallOutcome.allCases) { o in
                                Button { call.outcome = o } label: {
                                    Label(o.title, systemImage: o.icon)
                                        .font(.subheadline.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .foregroundStyle(call.outcome == o ? Color.white : o.color)
                                        .background(
                                            call.outcome == o ? o.color.opacity(0.75) : o.color.opacity(0.15),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    LabeledContent("Время") {
                        Text(call.date, format: .dateTime.hour().minute())
                    }
                }

                Section("Контакт") {
                    TextField("Имя", text: $call.contactName)
                    TextField("Телефон", text: $call.phone).keyboardType(.phonePad)
                }

                Section("Заметка") {
                    TextField("О чём говорили, возражения, договорённости…", text: $call.note, axis: .vertical)
                        .lineLimit(5...12)
                        .focused($noteFocused)
                }

                Section {
                    if let lead = call.lead {
                        Label("Лид: \(lead.displayName)", systemImage: "star.fill").foregroundStyle(.mint)
                    } else {
                        Button { showLeadEditor = true } label: {
                            Label("Сделать лидом", systemImage: "star")
                        }
                    }
                    Button("Удалить звонок", role: .destructive) { onDelete() }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Звонок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .task {
                if call.note.isEmpty {
                    try? await Task.sleep(for: .milliseconds(550))
                    noteFocused = true
                }
            }
            .onDisappear { try? context.save() }
            .sheet(isPresented: $showLeadEditor) { LeadEditorSheet(call: call) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Цель на день

private struct GoalSheet: View {
    @Bindable var plan: DayPlan

    @AppStorage("callsGoal") private var defaultCalls = 120
    @AppStorage("talksGoal") private var defaultTalks = 20
    @AppStorage("autoNote") private var autoNote = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Звонков за день") {
                    HStack {
                        TextField("120", value: $plan.callsGoal, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title.bold().monospacedDigit())
                        Stepper("", value: $plan.callsGoal, in: 1...1000, step: 5).labelsHidden()
                    }
                    presets([50, 80, 100, 120, 150, 200], value: $plan.callsGoal)
                }

                Section("Разговоров за день") {
                    HStack {
                        TextField("20", value: $plan.talksGoal, format: .number)
                            .keyboardType(.numberPad)
                            .font(.title.bold().monospacedDigit())
                        Stepper("", value: $plan.talksGoal, in: 1...500, step: 1).labelsHidden()
                    }
                    presets([10, 15, 20, 30, 40], value: $plan.talksGoal)
                }

                Section {
                    Toggle("Открывать заметку после разговора", isOn: $autoNote)
                } footer: {
                    Text("Новые дни стартуют с этой цели. Прошлые дни сохраняют свою.")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Цель на день")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
            .onDisappear {
                plan.callsGoal = max(1, plan.callsGoal)
                plan.talksGoal = max(1, plan.talksGoal)
                defaultCalls = plan.callsGoal
                defaultTalks = plan.talksGoal
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func presets(_ values: [Int], value: Binding<Int>) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button("\(v)") { value.wrappedValue = v }
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            value.wrappedValue == v ? Color.cyan.opacity(0.65) : Color.white.opacity(0.10),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
