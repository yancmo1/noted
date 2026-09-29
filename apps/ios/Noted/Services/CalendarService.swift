import EventKit
import Foundation

struct CalendarEventLink: Codable, Hashable, Identifiable {
    let sourceID: String
    let candidateID: String
    let eventIdentifier: String
    let calendarIdentifier: String?
    let calendarTitle: String?
    let title: String
    let startDate: Date
    let endDate: Date
    let createdAt: Date

    var id: String { "\(sourceID):\(candidateID)" }
}

struct EventCalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isDefault: Bool
}

enum CalendarCandidateDateBuilder {
    static func startDate(for candidate: CalendarCandidate, calendar: Calendar = .current, now: Date = Date()) -> Date? {
        guard let date = dateComponents(from: candidate.dateText, calendar: calendar),
              let month = date.month,
              let day = date.day,
              let timeText = candidate.timeText,
              let time = timeComponents(from: timeText, calendar: calendar),
              let hour = time.hour,
              let minute = time.minute else {
            return nil
        }

        var components = DateComponents()
        components.year = candidate.datePrecision == "full_date"
            ? (date.year ?? calendar.component(.year, from: now))
            : calendar.component(.year, from: now)
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = time.second ?? 0
        return calendar.date(from: components)
    }

    private static func dateComponents(from text: String, calendar: Calendar) -> DateComponents? {
        let formats = ["MMMM d, yyyy", "MMMM d", "MMM d, yyyy", "MMM d"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                let components = calendar.dateComponents([.year, .month, .day], from: date)
                if components.month != nil, components.day != nil { return components }
            }
        }
        return nil
    }

    private static func timeComponents(from text: String, calendar: Calendar) -> DateComponents? {
        let formats = ["h:mm a", "h:mm:ss a", "h a", "h.mm a"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return calendar.dateComponents([.hour, .minute, .second], from: date)
            }
        }
        return nil
    }
}

final class CalendarLinkStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default, baseDirectory: URL? = nil) {
        self.fileManager = fileManager
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else {
            base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }
        let metadataDirectory = base.appendingPathComponent("MemoryGarden", isDirectory: true)
        fileURL = metadataDirectory.appendingPathComponent("calendar-event-links.json")
    }

    func load() -> [CalendarEventLink] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return (try? decoder.decode([CalendarEventLink].self, from: data)) ?? []
    }

    func link(for sourceID: String, candidateID: String) -> CalendarEventLink? {
        load().first { $0.sourceID == sourceID && $0.candidateID == candidateID }
    }

    func save(_ link: CalendarEventLink) throws {
        var links = load().filter { $0.id != link.id }
        links.append(link)
        links.sort { $0.createdAt < $1.createdAt }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .deferredToDate
        let data = try encoder.encode(links)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

enum CalendarServiceError: LocalizedError {
    case accessDenied
    case noWritableCalendars
    case calendarSelectionRequired
    case calendarUnavailable
    case eventIdentifierUnavailable
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Noted does not have permission to add events to Calendar. You can allow access in Settings."
        case .noWritableCalendars:
            "No writable Calendar is available on this iPhone."
        case .calendarSelectionRequired:
            "Choose a Calendar before adding the event."
        case .calendarUnavailable:
            "That Calendar is no longer available. Choose another Calendar and try again."
        case .eventIdentifierUnavailable:
            "Calendar saved the event, but did not return an identifier for Noted to remember."
        case .invalidTitle:
            "Give the calendar event a title before adding it."
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func availableCalendars() async throws -> [EventCalendarOption] {
        let accessGranted = try await requestFullAccess()
        guard accessGranted else { throw CalendarServiceError.accessDenied }

        let defaultCalendarID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { calendar in
                EventCalendarOption(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    isDefault: calendar.calendarIdentifier == defaultCalendarID
                )
            }
            .sorted { left, right in
                if left.isDefault != right.isDefault { return left.isDefault }
                return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
    }

    func createEvent(sourceID: String, candidateID: String, title: String, startDate: Date, calendarIdentifier: String, duration: TimeInterval = 30 * 60) async throws -> CalendarEventLink {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw CalendarServiceError.invalidTitle }
        guard !calendarIdentifier.isEmpty else { throw CalendarServiceError.calendarSelectionRequired }

        let accessGranted = try await requestFullAccess()
        guard accessGranted else { throw CalendarServiceError.accessDenied }
        guard let calendar = eventStore.calendar(withIdentifier: calendarIdentifier), calendar.allowsContentModifications else {
            throw CalendarServiceError.calendarUnavailable
        }

        let endDate = startDate.addingTimeInterval(duration)
        let event = EKEvent(eventStore: eventStore)
        event.title = trimmedTitle
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = calendar
        event.notes = "Created by Noted from calendar candidate \(candidateID)."
        try eventStore.save(event, span: .thisEvent)
        guard let eventIdentifier = event.eventIdentifier else { throw CalendarServiceError.eventIdentifierUnavailable }

        return CalendarEventLink(
            sourceID: sourceID,
            candidateID: candidateID,
            eventIdentifier: eventIdentifier,
            calendarIdentifier: calendar.calendarIdentifier,
            calendarTitle: calendar.title,
            title: trimmedTitle,
            startDate: startDate,
            endDate: endDate,
            createdAt: Date()
        )
    }

    private func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}
