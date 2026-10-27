import SwiftUI
import SwiftData

// MARK: - Список лидов

struct LeadsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Lead.createdAt, order: .reverse) private var leads: [Lead]

    @State private var search = ""
    @State private var filter: LeadStatus?
    @State private var editing: Lead?
    @State private var creating = false
    @State private var pendingDelete: Lead?

    private var filtered: [Lead] {
        leads.filter { lead in
            let matchesStatus = filter == nil || lead.status == filter
            let matchesSearch = search.isEmpty
                || lead.name.localizedCaseInsensitiveContains(search)
                || lead.company.localizedCaseInsensitiveContains(search)
                || lead.note.localizedCaseInsensitiveContains(search)
                || lead.phone.contains(search)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if leads.isEmpty {
                        ContentUnavailableView(
                            "Пока нет лидов",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("Нажми «Лид» на экране «Сегодня» или добавь вручную кнопкой +")
                        )
                        .padding(.top, 60)
                    } else {
                        filterBar

                        if filtered.isEmpty {
                            Text("Ничего не найдено")
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(filtered) { lead in
                                    LeadCard(lead: lead)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editing = lead }
                                        .contextMenu {
                                            ForEach(LeadStatus.allCases) { s in
                                                Button { lead.status = s } label: {
                                                    Label(s.title, systemImage: s.icon)
                                                }
                                            }
                                            Divider()
                                            Button(role: .destructive) { remove(lead) } label: {
                                                Label("Удалить", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            .navigationTitle("Лиды")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $search, prompt: "Имя, телефон, заметка")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Добавить лида")
                }
            }
        }
        .sheet(item: $editing, onDismiss: flushDelete) { lead in
            LeadEditorSheet(lead: lead) {
                pendingDelete = lead
                editing = nil
            }
        }
        .sheet(isPresented: $creating) { LeadEditorSheet() }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Все · \(leads.count)", color: .white, selected: filter == nil) { filter = nil }
                ForEach(LeadStatus.allCases) { s in
                    let n = leads.filter { $0.status == s }.count
                    chip(title: "\(s.title) · \(n)", color: s.color, selected: filter == s) {
                        filter = (filter == s) ? nil : s
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : color)
                .background(selected ? color.opacity(0.55) : color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(PressStyle())
        .animation(.snappy, value: selected)
    }

    private func remove(_ lead: Lead) {
        withAnimation {
            context.delete(lead)
            try? context.save()
        }
    }

    private func flushDelete() {
        if let lead = pendingDelete {
            remove(lead)
            pendingDelete = nil
        }
    }
}

// MARK: - Карточка лида

private struct LeadCard: View {
    let lead: Lead

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(lead.initials)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(lead.status.color.opacity(0.25), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(lead.displayName).font(.headline)
                    if !lead.company.isEmpty {
                        Text(lead.company).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !lead.phone.isEmpty, !lead.name.isEmpty {
                        Text(lead.phone).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                StatusPill(status: lead.status)
            }

            if !lead.note.isEmpty {
                Text(lead.note)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if let next = lead.nextContact {
                    Label(next.formatted(.dateTime.day().month().hour().minute()), systemImage: "bell.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(next < Date.now ? Color.orange : Color.secondary)
                }
                Spacer()
                if let url = lead.callURL {
                    Link(destination: url) { actionIcon("phone.fill", .green) }
                }
                if let url = lead.whatsappURL {
                    Link(destination: url) { actionIcon("message.fill", .mint) }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .softCard(radius: 26)
    }

    private func actionIcon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(width: 38, height: 38)
            .background(color.opacity(0.20), in: Circle())
    }
}

// MARK: - Создание / редактирование лида

struct LeadEditorSheet: View {
    var lead: Lead?
    var call: CallRecord?
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var phone: String
    @State private var company: String
    @State private var note: String
    @State private var status: LeadStatus
    @State private var hasNext: Bool
    @State private var next: Date

    init(lead: Lead? = nil, call: CallRecord? = nil, onDelete: (() -> Void)? = nil) {
        self.lead = lead
        self.call = call
        self.onDelete = onDelete
        _name = State(initialValue: lead?.name ?? call?.contactName ?? "")
        _phone = State(initialValue: lead?.phone ?? call?.phone ?? "")
        _company = State(initialValue: lead?.company ?? "")
        _note = State(initialValue: lead?.note ?? call?.note ?? "")
        _status = State(initialValue: lead?.status ?? .new)
        _hasNext = State(initialValue: lead?.nextContact != nil)
        _next = State(initialValue: lead?.nextContact
                      ?? Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Контакт") {
                    TextField("Имя", text: $name)
                    TextField("Компания", text: $company)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                }

                Section("Статус") {
                    Picker("Статус", selection: $status) {
                        ForEach(LeadStatus.allCases) { s in
                            Label(s.title, systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Следующий контакт") {
                    Toggle("Назначить дату", isOn: $hasNext.animation())
                    if hasNext {
                        DatePicker("Когда", selection: $next, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Заметка") {
                    TextField("Что нужно клиенту, о чём договорились…", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                }

                if lead != nil, let onDelete {
                    Section {
                        Button("Удалить лида", role: .destructive) { onDelete() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AuroraBackground() }
            .navigationTitle(lead == nil ? "Новый лид" : "Лид")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                                  && phone.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        let target: Lead
        if let lead {
            target = lead
        } else {
            target = Lead()
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.phone = phone.trimmingCharacters(in: .whitespaces)
        target.company = company.trimmingCharacters(in: .whitespaces)
        target.note = note
        target.status = status
        target.nextContact = hasNext ? next : nil

        if let call {
            call.lead = target
            call.outcome = .lead
            if call.contactName.isEmpty { call.contactName = target.name }
            if call.phone.isEmpty { call.phone = target.phone }
        }
        try? context.save()
        dismiss()
    }
}
