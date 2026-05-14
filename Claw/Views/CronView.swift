import SwiftUI

// MARK: - CronView

/// Lists scheduled cron jobs with enable/disable toggles, swipe-to-delete,
/// and a create sheet.
struct CronView: View {
    @Environment(CronStore.self) private var store

    @State private var showCreateSheet: Bool = false
    @State private var actionError: String?
    @State private var pendingDeleteId: String?
    @State private var selectedJob: CronJob? = nil

    var body: some View {
        ScrollView {
            Group {
                if store.isLoading && store.jobs.isEmpty {
                    loadingView
                } else if store.jobs.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.jobs) { job in
                            CronRow(
                                job: job,
                                onToggle: { newValue in
                                    Task { await performToggle(job.id, enabled: newValue) }
                                },
                                onDelete: {
                                    pendingDeleteId = job.id
                                },
                                onTap: { selectedJob = job }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clawBg)
        .refreshable {
            try? await store.load()
        }
        .navigationTitle("Cron Jobs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.clawAccent)
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateCronSheet { label, schedule, task in
                showCreateSheet = false
                Task { await performCreate(label: label, schedule: schedule, task: task) }
            } onCancel: {
                showCreateSheet = false
            }
        }
        .sheet(item: $selectedJob) { job in
            CronDetailSheet(job: job, store: store)
        }
        .alert(
            "Delete cron job?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            presenting: pendingDeleteId
        ) { jobId in
            Button("Delete", role: .destructive) {
                Task { await performDelete(jobId) }
                pendingDeleteId = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteId = nil
            }
        } message: { _ in
            Text("This will remove the cron job from the gateway. This action cannot be undone.")
        }
        .alert(
            "Action failed",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK") { actionError = nil }
        } message: { detail in
            Text(detail)
        }
        .task {
            if store.jobs.isEmpty {
                try? await store.load()
            }
        }
    }

    // MARK: - Loading / empty states

    private var loadingView: some View {
        VStack {
            ProgressView("Loading cron jobs…")
                .tint(Color.clawAccent)
                .foregroundStyle(Color.clawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.clawMuted.opacity(0.4))

            Text("No cron jobs")
                .font(.headline)
                .foregroundStyle(Color.clawMuted)

            Text("Tap + to create a cron job that runs on a schedule.")
                .font(.subheadline)
                .foregroundStyle(Color.clawMuted.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func performToggle(_ jobId: String, enabled: Bool) async {
        do {
            try await store.setEnabled(jobId, enabled: enabled)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performDelete(_ jobId: String) async {
        do {
            try await store.delete(jobId)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func performCreate(label: String, schedule: String, task: String) async {
        do {
            try await store.create(label: label, schedule: schedule, task: task)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - CronRow

private struct CronRow: View {
    let job: CronJob
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var showDeleteAction: Bool = false

    private let deleteWidth: CGFloat = 80

    var body: some View {
        ZStack(alignment: .trailing) {
            // Background delete action
            HStack {
                Spacer()
                Button {
                    onDelete()
                    withAnimation { offsetX = 0; showDeleteAction = false }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                        Text("Delete")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.clawDanger)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Foreground content
            content
                .offset(x: offsetX)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if gesture.translation.width < 0 {
                                offsetX = max(gesture.translation.width, -deleteWidth)
                            } else if showDeleteAction {
                                offsetX = min(-deleteWidth + gesture.translation.width, 0)
                            }
                        }
                        .onEnded { _ in
                            withAnimation {
                                if offsetX < -deleteWidth / 2 {
                                    offsetX = -deleteWidth
                                    showDeleteAction = true
                                } else {
                                    offsetX = 0
                                    showDeleteAction = false
                                }
                            }
                        }
                )
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.enabled ? "clock.fill" : "clock")
                .font(.system(size: 20))
                .foregroundStyle(job.enabled ? Color.clawAccent : Color.clawMuted.opacity(0.6))
                .frame(width: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Name
                Text(job.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                    .lineLimit(1)

                // Schedule + tz
                Text(job.scheduleWithTz.isEmpty ? "—" : job.scheduleWithTz)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.clawMuted)
                    .lineLimit(1)

                // Status row: last run status dot + duration + next run
                HStack(spacing: 10) {
                    if let status = job.lastRunStatus {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(job.hasErrors ? Color.clawDanger : Color.clawOk)
                                .frame(width: 6, height: 6)
                            Text(job.hasErrors ? "\(job.consecutiveErrors) error\(job.consecutiveErrors == 1 ? "" : "s")" : "OK")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(job.hasErrors ? Color.clawDanger : Color.clawOk)
                        }
                    }
                    if let dur = job.formattedDuration {
                        Text(dur)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.clawMuted.opacity(0.8))
                    }
                    if let next = job.nextRunAt {
                        Label(relativeDate(next), systemImage: "arrow.right.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.clawMuted.opacity(0.8))
                    }
                }
                .padding(.top, 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { job.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .tint(Color.clawAccent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.clawCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}

// MARK: - CreateCronSheet

private struct CreateCronSheet: View {
    let onSubmit: (_ label: String, _ schedule: String, _ task: String) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var schedule: String = ""
    @State private var task: String = ""

    private var canSubmit: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                        .foregroundStyle(Color.clawTextStrong)
                        .listRowBackground(Color.clawCard)
                } header: {
                    Text("Label")
                        .foregroundStyle(Color.clawMuted)
                } footer: {
                    Text("A short name for this scheduled task.")
                        .foregroundStyle(Color.clawMuted.opacity(0.8))
                }

                Section {
                    TextField("e.g. 0 9 * * 1-5", text: $schedule)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.clawTextStrong)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .listRowBackground(Color.clawCard)
                } header: {
                    Text("Schedule")
                        .foregroundStyle(Color.clawMuted)
                } footer: {
                    Text("Cron expression: minute hour day month weekday. Example: `0 9 * * 1-5` runs at 09:00 on weekdays.")
                        .foregroundStyle(Color.clawMuted.opacity(0.8))
                }

                Section {
                    TextField("What the agent should do…", text: $task, axis: .vertical)
                        .lineLimit(4...10)
                        .foregroundStyle(Color.clawTextStrong)
                        .listRowBackground(Color.clawCard)
                } header: {
                    Text("Task")
                        .foregroundStyle(Color.clawMuted)
                } footer: {
                    Text("The prompt or command the agent will execute on each scheduled run.")
                        .foregroundStyle(Color.clawMuted.opacity(0.8))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .tint(Color.clawAccent)
            .navigationTitle("New Cron Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onCancel() }
                        .tint(Color.clawAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        onSubmit(
                            label.trimmingCharacters(in: .whitespacesAndNewlines),
                            schedule.trimmingCharacters(in: .whitespacesAndNewlines),
                            task.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                    .fontWeight(.semibold)
                    .tint(Color.clawAccent)
                    .disabled(!canSubmit)
                }
            }
        }
    }
}

// MARK: - CronDetailSheet

private struct CronDetailSheet: View {
    let job: CronJob
    let store: CronStore
    @Environment(\.dismiss) private var dismiss
    @State private var labelText: String = ""
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $labelText)
                        .foregroundStyle(Color.clawTextStrong)
                        .listRowBackground(Color.clawCard)
                } header: {
                    Text("Name").foregroundStyle(Color.clawMuted)
                }

                if let desc = job.description, !desc.isEmpty {
                    Section {
                        Text(desc)
                            .font(.body)
                            .foregroundStyle(Color.clawText)
                            .listRowBackground(Color.clawCard)
                    } header: {
                        Text("Description").foregroundStyle(Color.clawMuted)
                    }
                }

                Section {
                    LabeledContent("Expression") {
                        Text(job.schedule.isEmpty ? "—" : job.schedule)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(Color.clawText)
                    }
                    .listRowBackground(Color.clawCard)
                    if let tz = job.tz, !tz.isEmpty {
                        LabeledContent("Timezone", value: tz)
                            .listRowBackground(Color.clawCard)
                    }
                } header: {
                    Text("Schedule").foregroundStyle(Color.clawMuted)
                }

                if !job.task.isEmpty {
                    Section {
                        Text(job.task)
                            .font(.body)
                            .foregroundStyle(Color.clawText)
                            .listRowBackground(Color.clawCard)
                    } header: {
                        Text("Task").foregroundStyle(Color.clawMuted)
                    }
                }

                Section {
                    if let status = job.lastRunStatus {
                        LabeledContent("Status") {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(job.hasErrors ? Color.clawDanger : Color.clawOk)
                                    .frame(width: 8, height: 8)
                                Text(job.hasErrors ? "\(job.consecutiveErrors) error(s)" : "OK")
                                    .foregroundStyle(job.hasErrors ? Color.clawDanger : Color.clawOk)
                            }
                        }
                        .listRowBackground(Color.clawCard)
                    }
                    if let dur = job.formattedDuration {
                        LabeledContent("Last Duration", value: dur)
                            .listRowBackground(Color.clawCard)
                    }
                    if let last = job.lastRunAt {
                        LabeledContent("Last Run", value: last.formatted(date: .abbreviated, time: .shortened))
                            .listRowBackground(Color.clawCard)
                    }
                    if let next = job.nextRunAt {
                        LabeledContent("Next Run", value: next.formatted(date: .abbreviated, time: .shortened))
                            .listRowBackground(Color.clawCard)
                    }
                } header: {
                    Text("Last Run").foregroundStyle(Color.clawMuted)
                }

                if let agentId = job.agentId, !agentId.isEmpty {
                    Section {
                        LabeledContent("Agent", value: agentId)
                            .listRowBackground(Color.clawCard)
                        if let delivery = job.deliveryMode, !delivery.isEmpty {
                            LabeledContent("Delivery", value: delivery)
                                .listRowBackground(Color.clawCard)
                        }
                    } header: {
                        Text("Configuration").foregroundStyle(Color.clawMuted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .tint(Color.clawAccent)
            .navigationTitle("Job Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .tint(Color.clawAccent)
                        .disabled(isSaving || labelText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Save failed", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } }), presenting: saveError) { _ in
                Button("OK") { saveError = nil }
            } message: { Text($0) }
        }
        .onAppear { labelText = job.name }
    }

    private func save() async {
        let trimmed = labelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != job.name, !trimmed.isEmpty else { dismiss(); return }
        isSaving = true
        do {
            try await store.rename(job.id, newLabel: trimmed)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
