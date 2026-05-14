import Foundation

// MARK: - CronStore errors

enum CronStoreError: Error, LocalizedError {
    case malformedResponse(String)

    var errorDescription: String? {
        switch self {
        case .malformedResponse(let detail): return "Malformed cron response: \(detail)"
        }
    }
}

// MARK: - CronStore

/// Loads and maintains the list of cron jobs, with enable/disable/delete/create.
@Observable
@MainActor
final class CronStore {

    // MARK: - Observable state

    private(set) var jobs: [CronJob] = []
    private(set) var isLoading: Bool = false
    private(set) var loadError: Error?
    private(set) var mutationError: Error?

    // MARK: - Private

    private let client: GatewayClient

    // MARK: - Init

    init(client: GatewayClient) {
        self.client = client
    }

    // MARK: - Load

    func load() async throws {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let payload = try await client.send(method: GatewayMethod.cronList, params: EmptyCronParams())
            try applyCronList(payload: payload)
        } catch {
            loadError = error
            throw error
        }
    }

    // MARK: - Enable / Disable

    func setEnabled(_ jobId: String, enabled: Bool) async throws {
        mutationError = nil
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }

        let previous = jobs[idx].enabled
        jobs[idx].enabled = enabled

        let method = enabled ? GatewayMethod.cronEnable : GatewayMethod.cronDisable
        let params = CronIdParams(cronId: jobId)
        do {
            _ = try await client.send(method: method, params: params)
        } catch {
            if let revertIdx = jobs.firstIndex(where: { $0.id == jobId }) {
                jobs[revertIdx].enabled = previous
            }
            mutationError = error
            throw error
        }
    }

    // MARK: - Delete

    func delete(_ jobId: String) async throws {
        mutationError = nil
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        let removed = jobs.remove(at: idx)
        do {
            _ = try await client.send(method: GatewayMethod.cronDelete, params: CronIdParams(cronId: jobId))
        } catch {
            let insertAt = min(idx, jobs.count)
            jobs.insert(removed, at: insertAt)
            mutationError = error
            throw error
        }
    }

    // MARK: - Rename

    func rename(_ jobId: String, newLabel: String) async throws {
        mutationError = nil
        let trimmed = newLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = jobs.firstIndex(where: { $0.id == jobId }) else { return }
        let previous = jobs[idx].name
        jobs[idx].name = trimmed
        struct RenameParams: Encodable { let cronId: String; let label: String }
        do {
            _ = try await client.send(method: GatewayMethod.cronUpdate, params: RenameParams(cronId: jobId, label: trimmed))
        } catch {
            if let revertIdx = jobs.firstIndex(where: { $0.id == jobId }) {
                jobs[revertIdx].name = previous
            }
            mutationError = error
            throw error
        }
    }

    // MARK: - Create

    func create(label: String, schedule: String, task: String) async throws {
        mutationError = nil
        let params = CronCreateParams(label: label, schedule: schedule, task: task)
        do {
            _ = try await client.send(method: GatewayMethod.cronCreate, params: params)
            try await load()
        } catch {
            mutationError = error
            throw error
        }
    }

    // MARK: - Private: parse list response

    private func applyCronList(payload: [String: JSONValue]) throws {
        let arr: [JSONValue]
        if let v = payload["jobs"], case .array(let a) = v {
            arr = a
        } else if let v = payload["cron"], case .array(let a) = v {
            arr = a
        } else if let v = payload["items"], case .array(let a) = v {
            arr = a
        } else {
            jobs = []
            return
        }

        var result: [CronJob] = []
        for item in arr {
            guard case .object(let obj) = item else { continue }
            if let job = parseJob(obj: obj) {
                result.append(job)
            }
        }
        jobs = result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func parseJob(obj: [String: JSONValue]) -> CronJob? {
        guard let idVal = obj["id"], case .string(let id) = idVal, !id.isEmpty else { return nil }

        // name — gateway uses "name", fall back to "label" then id
        let name: String
        if let v = obj["name"], case .string(let s) = v, !s.isEmpty { name = s }
        else if let v = obj["label"], case .string(let s) = v, !s.isEmpty { name = s }
        else { name = id }

        let description: String?
        if let v = obj["description"], case .string(let s) = v, !s.isEmpty { description = s }
        else { description = nil }

        let enabled: Bool
        if let v = obj["enabled"], case .bool(let b) = v { enabled = b }
        else { enabled = false }

        let agentId: String?
        if let v = obj["agentId"], case .string(let s) = v, !s.isEmpty { agentId = s }
        else { agentId = nil }

        // schedule — can be nested object or flat string
        var scheduleExpr = ""
        var tz: String? = nil
        if let sv = obj["schedule"], case .object(let sobj) = sv {
            if let ev = sobj["expr"], case .string(let s) = ev { scheduleExpr = s }
            if let tv = sobj["tz"], case .string(let t) = tv, !t.isEmpty { tz = t }
        } else if let v = obj["schedule"], case .string(let s) = v {
            scheduleExpr = s
        }

        // task — from payload.message, fall back to top-level "task"
        var task = ""
        if let pv = obj["payload"], case .object(let pobj) = pv {
            if let mv = pobj["message"], case .string(let s) = mv { task = s }
        }
        if task.isEmpty, let v = obj["task"], case .string(let s) = v { task = s }

        // delivery
        var deliveryMode: String? = nil
        if let dv = obj["delivery"], case .object(let dobj) = dv {
            if let mv = dobj["mode"], case .string(let s) = mv { deliveryMode = s }
        }

        // state — nested object
        var lastRunAt: Date? = nil
        var nextRunAt: Date? = nil
        var lastRunStatus: String? = nil
        var lastDurationMs: Int? = nil
        var consecutiveErrors = 0

        if let stv = obj["state"], case .object(let sobj) = stv {
            lastRunAt = dateFromJSONValue(sobj["lastRunAtMs"])
            nextRunAt = dateFromJSONValue(sobj["nextRunAtMs"])
            if let v = sobj["lastRunStatus"], case .string(let s) = v { lastRunStatus = s }
            if let v = sobj["lastDurationMs"] {
                switch v {
                case .int(let i): lastDurationMs = i
                case .double(let d): lastDurationMs = Int(d)
                default: break
                }
            }
            if let v = sobj["consecutiveErrors"] {
                switch v {
                case .int(let i): consecutiveErrors = i
                case .double(let d): consecutiveErrors = Int(d)
                default: break
                }
            }
        }
        // Also try top-level for flat responses
        if lastRunAt == nil { lastRunAt = dateFromJSONValue(obj["lastRunAtMs"] ?? obj["lastRunAt"]) }
        if nextRunAt == nil { nextRunAt = dateFromJSONValue(obj["nextRunAtMs"] ?? obj["nextRunAt"]) }

        return CronJob(
            id: id,
            name: name,
            description: description,
            schedule: scheduleExpr,
            tz: tz,
            enabled: enabled,
            agentId: agentId,
            deliveryMode: deliveryMode,
            lastRunAt: lastRunAt,
            nextRunAt: nextRunAt,
            lastRunStatus: lastRunStatus,
            lastDurationMs: lastDurationMs,
            consecutiveErrors: consecutiveErrors,
            task: task
        )
    }

    private func dateFromJSONValue(_ value: JSONValue?) -> Date? {
        guard let value else { return nil }
        switch value {
        case .int(let ms):
            return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        case .double(let ms):
            return Date(timeIntervalSince1970: ms / 1000.0)
        case .string(let s):
            // Try ISO 8601
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: s) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: s)
        default:
            return nil
        }
    }
}

// MARK: - Request param types

private struct EmptyCronParams: Encodable {}

private struct CronIdParams: Encodable {
    let cronId: String
}

private struct CronCreateParams: Encodable {
    let label: String
    let schedule: String
    let task: String
}
