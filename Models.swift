import SwiftUI
import SwiftData

// MARK: - Результат звонка

enum CallOutcome: String, CaseIterable, Identifiable {
    case noAnswer, talk, rejected, callback, lead

    var id: String { rawValue }

    /// Кнопки быстрого ввода на экране «Сегодня»
    static let quick: [CallOutcome] = [.noAnswer, .talk, .rejected, .lead]

    var title: String {
        switch self {
        case .noAnswer: return "Недозвон"
        case .talk:     return "Разговор"
        case .rejected: return "Отказ"
        case .callback: return "Перезвонить"
        case .lead:     return "Лид"
        }
    }

    var icon: String {
        switch self {
        case .noAnswer: return "phone.down.fill"
        case .talk:     return "bubble.left.and.bubble.right.fill"
        case .rejected: return "hand.thumbsdown.fill"
        case .callback: return "arrow.triangle.2.circlepath"
        case .lead:     return "star.fill"
        }
    }

    var color: Color {
        switch self {
        case .noAnswer: return .gray
        case .talk:     return .cyan
        case .rejected: return .pink
        case .callback: return .orange
        case .lead:     return .mint
        }
    }

    /// Считается ли звонок разговором (кто-то снял трубку и пообщался)
    var isTalk: Bool { self != .noAnswer }
}

// MARK: - Статус лида

enum LeadStatus: String, CaseIterable, Identifiable {
    case new, inProgress, meeting, won, lost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new:        return "Новый"
        case .inProgress: return "В работе"
        case .meeting:    return "Встреча"
        case .won:        return "Сделка"
        case .lost:       return "Потерян"
        }
    }

    var icon: String {
        switch self {
        case .new:        return "sparkles"
        case .inProgress: return "hourglass"
        case .meeting:    return "calendar"
        case .won:        return "checkmark.seal.fill"
        case .lost:       return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .new:        return .cyan
        case .inProgress: return .orange
        case .meeting:    return .purple
        case .won:        return .mint
        case .lost:       return .gray
        }
    }
}

// MARK: - Модели SwiftData

@Model
final class DayPlan {
    @Attribute(.unique) var day: Date
    var callsGoal: Int
    var talksGoal: Int

    init(day: Date, callsGoal: Int, talksGoal: Int) {
        self.day = day
        self.callsGoal = callsGoal
        self.talksGoal = talksGoal
    }
}

@Model
final class CallRecord {
    var date: Date
    var outcomeRaw: String
    var note: String
    var contactName: String
    var phone: String
    var lead: Lead?

    init(outcome: CallOutcome, date: Date = .now) {
        self.date = date
        self.outcomeRaw = outcome.rawValue
        self.note = ""
        self.contactName = ""
        self.phone = ""
    }

    var outcome: CallOutcome {
        get { CallOutcome(rawValue: outcomeRaw) ?? .noAnswer }
        set { outcomeRaw = newValue.rawValue }
    }

    /// Имя контакта или телефон — для подписи в журнале
    var contactLabel: String {
        if !contactName.isEmpty { return contactName }
        return phone
    }
}

@Model
final class Lead {
    var name: String
    var phone: String
    var company: String
    var note: String
    var statusRaw: String
    var createdAt: Date
    var nextContact: Date?

    @Relationship(deleteRule: .nullify, inverse: \CallRecord.lead)
    var calls: [CallRecord] = []

    init(name: String = "", phone: String = "", company: String = "", note: String = "",
         status: LeadStatus = .new, nextContact: Date? = nil) {
        self.name = name
        self.phone = phone
        self.company = company
        self.note = note
        self.statusRaw = status.rawValue
        self.createdAt = .now
        self.nextContact = nextContact
    }

    var status: LeadStatus {
        get { LeadStatus(rawValue: statusRaw) ?? .new }
        set { statusRaw = newValue.rawValue }
    }

    var displayName: String {
        if !name.isEmpty { return name }
        if !phone.isEmpty { return phone }
        return "Без имени"
    }

    var initials: String {
        displayName.first(where: { $0.isLetter }).map { String($0).uppercased() } ?? "•"
    }

    var callURL: URL? {
        let d = phone.phoneDigits
        return d.isEmpty ? nil : URL(string: "tel:\(d)")
    }

    var whatsappURL: URL? {
        let d = phone.phoneDigits.replacingOccurrences(of: "+", with: "")
        return d.isEmpty ? nil : URL(string: "https://wa.me/\(d)")
    }
}

// MARK: - Утилиты

extension String {
    var phoneDigits: String { filter { $0.isNumber || $0 == "+" } }
}

/// Сводка по дню — считается один раз за проход, а не в каждой строке
struct DayStats {
    let total: Int
    let talks: Int
    private let counts: [CallOutcome: Int]

    init(_ calls: [CallRecord]) {
        var c: [CallOutcome: Int] = [:]
        for call in calls { c[call.outcome, default: 0] += 1 }
        counts = c
        total = calls.count
        talks = calls.count - (c[.noAnswer] ?? 0)
    }

    func count(_ outcome: CallOutcome) -> Int { counts[outcome] ?? 0 }

    /// Доля разговоров от всех набранных
    var pickupRate: Int { total > 0 ? Int((Double(talks) / Double(total) * 100).rounded()) : 0 }

    /// Доля лидов от разговоров
    var conversion: Int { talks > 0 ? Int((Double(count(.lead)) / Double(talks) * 100).rounded()) : 0 }
}

/// Склонение: 1 звонок, 2 звонка, 5 звонков
func ruPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let m10 = n % 10, m100 = n % 100
    if m100 >= 11 && m100 <= 14 { return many }
    if m10 == 1 { return one }
    if m10 >= 2 && m10 <= 4 { return few }
    return many
}
