import Foundation
import EventKit
import Contacts
import UIKit

// MARK: - Response params

struct PhoneResponseParams: Encodable {
    let requestId: String
    let data: [String: JSONValue]?
    let error: String?
}

// MARK: - PhoneContextHandler

@Observable @MainActor
final class PhoneContextHandler {

    private let client: GatewayClient
    private var task: Task<Void, Never>?
    private var requestTimestampsByMethod: [String: [Date]] = [:]

    private let sensitiveMethods: Set<String> = [
        "phone.calendar.list",
        "phone.contacts.search",
        "phone.reminders.list"
    ]
    private let rateLimitWindow: TimeInterval = 5 * 60
    private let maxSensitiveRequestsPerWindow = 8

    init(client: GatewayClient) {
        self.client = client
    }

    func start() {
        task = Task { [weak self] in
            guard let self else { return }
            for await event in await self.client.events() {
                guard event.name == GatewayEventName.phoneRequest else { continue }
                await self.handle(event: event)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Dispatch

    private func handle(event: GatewayEvent) async {
        guard let requestId = event.payload["requestId"]?.stringValue,
              let method = event.payload["method"]?.stringValue else { return }

        let params = event.payload["params"]?.objectValue ?? [:]

        guard allowSensitivePhoneRequest(method: method) else {
            await reply(
                requestId: requestId,
                data: nil,
                error: "Phone context is only available while Claw is open and rate-limited."
            )
            return
        }

        switch method {
        case "phone.calendar.list":
            await handleCalendarList(requestId: requestId, params: params)
        case "phone.contacts.search":
            await handleContactsSearch(requestId: requestId, params: params)
        case "phone.reminders.list":
            await handleRemindersList(requestId: requestId, params: params)
        default:
            await reply(requestId: requestId, data: nil, error: "Unknown method: \(method)")
        }
    }

    // MARK: - Calendar

    private func handleCalendarList(requestId: String, params: [String: JSONValue]) async {
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        if calStatus == .denied || calStatus == .restricted {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToEvents()
        } catch {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }
        guard granted else {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }

        let rawDays = params["daysAhead"]?.intValue ?? 7
        let daysAhead = min(max(1, rawDays), 30)
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now

        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        let formatter = ISO8601DateFormatter()
        let items: [[String: String]] = events.prefix(50).map { ev in
            var d: [String: String] = [
                "title": ev.title ?? "",
                "start": formatter.string(from: ev.startDate),
                "end": formatter.string(from: ev.endDate),
                "calendar": ev.calendar?.title ?? ""
            ]
            if let loc = ev.location { d["location"] = loc }
            return d
        }

        await reply(requestId: requestId, data: ["events": makeStringArray(items)], error: nil)
    }

    // MARK: - Contacts

    private func handleContactsSearch(requestId: String, params: [String: JSONValue]) async {
        let query = params["query"]?.stringValue ?? ""

        guard !query.isEmpty else {
            await reply(requestId: requestId, data: ["contacts": .array([])], error: nil)
            return
        }

        let contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        if contactsStatus == .denied || contactsStatus == .restricted {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }

        let store = CNContactStore()
        do {
            try await store.requestAccess(for: .contacts)
        } catch {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]

        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
        if !query.isEmpty {
            fetchRequest.predicate = CNContact.predicateForContacts(matchingName: query)
        }

        var results: [[String: String]] = []
        do {
            try store.enumerateContacts(with: fetchRequest) { contact, stop in
                let name = [contact.givenName, contact.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                let email = (contact.emailAddresses.first?.value as String?) ?? ""
                results.append(["name": name, "phone": phone, "email": email])
                if results.count >= 10 { stop.pointee = true }
            }
        } catch {
            await reply(requestId: requestId, data: nil, error: error.localizedDescription)
            return
        }

        await reply(requestId: requestId, data: ["contacts": makeStringArray(results)], error: nil)
    }

    // MARK: - Reminders

    private func handleRemindersList(requestId: String, params: [String: JSONValue]) async {
        let remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        if remindersStatus == .denied || remindersStatus == .restricted {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }
        let store = EKEventStore()
        let granted: Bool
        do {
            granted = try await store.requestFullAccessToReminders()
        } catch {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }
        guard granted else {
            await reply(requestId: requestId, data: nil, error: "Permission denied")
            return
        }

        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)

        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { fetched in
                continuation.resume(returning: fetched ?? [])
            }
        }

        let formatter = ISO8601DateFormatter()
        let items: [[String: String]] = reminders.map { r in
            var d: [String: String] = [
                "title": r.title ?? "",
                "priority": "\(r.priority)",
                "list": r.calendar?.title ?? ""
            ]
            if let due = r.dueDateComponents?.date {
                d["dueDate"] = formatter.string(from: due)
            }
            return d
        }

        let limited = items.prefix(50)
        await reply(requestId: requestId, data: ["reminders": .array(Array(limited).map { dict in .object(dict.mapValues { .string($0) }) })], error: nil)
    }

    // MARK: - Helpers

    private func allowSensitivePhoneRequest(method: String) -> Bool {
        guard sensitiveMethods.contains(method) else { return true }
        guard UIApplication.shared.applicationState == .active else { return false }

        let now = Date()
        let cutoff = now.addingTimeInterval(-rateLimitWindow)
        var timestamps = requestTimestampsByMethod[method, default: []]
            .filter { $0 >= cutoff }

        guard timestamps.count < maxSensitiveRequestsPerWindow else {
            requestTimestampsByMethod[method] = timestamps
            return false
        }

        timestamps.append(now)
        requestTimestampsByMethod[method] = timestamps
        return true
    }

    private func reply(requestId: String, data: [String: JSONValue]?, error: String?) async {
        let p = PhoneResponseParams(requestId: requestId, data: data, error: error)
        try? await client.send(method: GatewayMethod.phoneResponse, params: p)
    }

    private func makeStringArray(_ items: [[String: String]]) -> JSONValue {
        .array(items.map { dict in .object(dict.mapValues { .string($0) }) })
    }
}
