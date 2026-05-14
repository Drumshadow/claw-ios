import Foundation

struct CronJob: Identifiable, Hashable {
    let id: String
    var name: String
    var description: String?
    var schedule: String
    var tz: String?
    var enabled: Bool
    var agentId: String?
    var deliveryMode: String?
    var lastRunAt: Date?
    var nextRunAt: Date?
    var lastRunStatus: String?   // "ok", or an error string
    var lastDurationMs: Int?
    var consecutiveErrors: Int
    var task: String             // from payload.message

    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func == (lhs: CronJob, rhs: CronJob) -> Bool { lhs.id == rhs.id }

    var lastRunOk: Bool { lastRunStatus == "ok" }
    var hasErrors: Bool { consecutiveErrors > 0 }

    var formattedDuration: String? {
        guard let ms = lastDurationMs else { return nil }
        if ms < 1000 { return "\(ms)ms" }
        let s = Double(ms) / 1000.0
        if s < 60 { return String(format: "%.1fs", s) }
        let m = Int(s / 60)
        let rem = Int(s) % 60
        return "\(m)m \(rem)s"
    }

    var scheduleWithTz: String {
        guard let tz = tz, !tz.isEmpty else { return schedule }
        return "\(schedule) (\(tz))"
    }
}
