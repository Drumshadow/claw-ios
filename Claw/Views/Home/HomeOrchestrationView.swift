import SwiftUI

// MARK: - HomeOrchestrationView
//
// The personal AI orchestration hub. Shows:
//   - Connected integrations summary
//   - Active home tasks (with agent-assist capability)
//   - Grocery list
//   - Quick-ask input to delegate to an agent
//
// Data source: HomeOrchestrationStore

struct HomeOrchestrationView: View {
    @Environment(HomeOrchestrationStore.self) private var store
    @Environment(SessionStore.self) private var sessionStore
    @State private var quickTaskText: String = ""
    @State private var showAllTasks: Bool = false
    @State private var showGroceryList: Bool = false
    @State private var showIntegrations: Bool = false
    @State private var showAddTask: Bool = false
    @State private var newTaskTitle: String = ""
    @State private var newTaskAssignAgent: Bool = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Integration status bar
                integrationsBar

                // Quick-delegate field
                quickDelegateCard

                // Active tasks
                tasksCard

                // Grocery list preview
                groceryCard

                // Recently completed
                if !store.doneTasks.isEmpty {
                    completedTasksCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color.clawBg)
        .navigationTitle("Home AI")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    IntegrationRegistryView()
                        .environment(store)
                } label: {
                    Image(systemName: "plug")
                }
                .tint(Color.clawAccent)
            }
        }
        .task { await store.loadAll() }
        .refreshable { await store.loadAll() }
        .sheet(isPresented: $showAddTask) {
            addTaskSheet
        }
    }

    // MARK: - Integration Status Bar

    private var integrationsBar: some View {
        HStack(spacing: 0) {
            ForEach(store.integrations.filter { $0.isEnabled }.prefix(4)) { integration in
                integrationDot(integration)
                if integration.id != store.integrations.filter { $0.isEnabled }.prefix(4).last?.id {
                    Divider().frame(height: 28).background(Color.clawBorder)
                }
            }
            if store.integrations.filter({ $0.isEnabled }).count == 0 {
                HStack {
                    Image(systemName: "plug.slash")
                        .foregroundStyle(Color.clawMuted)
                    Text("No integrations connected")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .background(Color.clawBgAccent)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.clawBorder, lineWidth: 1)
        )
    }

    private func integrationDot(_ integration: HomeIntegration) -> some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color(hex: integration.kind.colorHex).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: integration.kind.systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: integration.kind.colorHex))
            }
            Circle()
                .fill(integration.connectionStatus.isActive ? Color.clawOk : Color.clawMuted.opacity(0.4))
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Quick Delegate Card

    private var quickDelegateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ask your agent", systemImage: "cpu")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.clawMuted)

            HStack(spacing: 8) {
                TextField("What should I help with today?", text: $quickTaskText, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.clawText)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.clawBgElevated)
                    .cornerRadius(10)

                Button {
                    guard !quickTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    let text = quickTaskText
                    quickTaskText = ""
                    Task {
                        await store.createTask(
                            title: text,
                            description: nil,
                            priority: .normal,
                            dueDate: nil,
                            assignToAgent: true
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(quickTaskText.isEmpty ? Color.clawMuted.opacity(0.4) : Color.clawAccent)
                }
                .disabled(quickTaskText.isEmpty)
            }
        }
        .padding(14)
        .background(Color.clawCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.clawBorder, lineWidth: 1))
    }

    // MARK: - Tasks Card

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                if store.unreadTaskCount > 0 {
                    Text("\(store.unreadTaskCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.clawAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.clawAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    showAddTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.clawAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(Color.clawBorder)

            let displayTasks = showAllTasks ? store.pendingTasks : Array(store.pendingTasks.prefix(3))

            if displayTasks.isEmpty {
                HStack {
                    Spacer()
                    Text("All caught up! ✓")
                        .font(.caption)
                        .foregroundStyle(Color.clawMuted)
                    Spacer()
                }
                .padding(.vertical, 16)
            } else {
                ForEach(displayTasks) { task in
                    HomeTaskRow(task: task) { status in
                        Task { await store.updateTaskStatus(task.id, status: status) }
                    }
                    if task.id != displayTasks.last?.id {
                        Divider().background(Color.clawBorder).padding(.leading, 44)
                    }
                }

                if store.pendingTasks.count > 3 {
                    Button {
                        withAnimation { showAllTasks.toggle() }
                    } label: {
                        HStack {
                            Text(showAllTasks ? "Show less" : "Show \(store.pendingTasks.count - 3) more")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.clawAccent)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.clawCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.clawBorder, lineWidth: 1))
    }

    // MARK: - Grocery Card

    private var groceryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Groceries", systemImage: "cart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawTextStrong)
                if let list = store.primaryGroceryList, list.unboughtCount > 0 {
                    Text("\(list.unboughtCount) items")
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)
                }
                Spacer()
                NavigationLink {
                    GroceryListView()
                        .environment(store)
                } label: {
                    Text("See all")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.clawAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().background(Color.clawBorder)

            if let list = store.primaryGroceryList {
                let preview = list.items.filter { !$0.isBought }.prefix(4)
                if preview.isEmpty {
                    HStack {
                        Spacer()
                        Text("Nothing on the list 🛒")
                            .font(.caption).foregroundStyle(Color.clawMuted)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(Array(preview)) { item in
                        HStack(spacing: 10) {
                            Button {
                                Task { await store.toggleGroceryItem(listId: list.id, itemId: item.id) }
                            } label: {
                                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(item.isBought ? Color.clawOk : Color.clawMuted)
                            }
                            .buttonStyle(.plain)

                            Image(systemName: item.category.systemImage)
                                .font(.caption2)
                                .foregroundStyle(Color.clawMuted)
                                .frame(width: 14)

                            Text(item.name)
                                .font(.system(size: 13))
                                .foregroundStyle(item.isBought ? Color.clawMuted : Color.clawText)
                                .strikethrough(item.isBought, color: Color.clawMuted)

                            if let qty = item.quantity {
                                Text(qty)
                                    .font(.caption2)
                                    .foregroundStyle(Color.clawMuted)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .background(Color.clawCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.clawBorder, lineWidth: 1))
    }

    // MARK: - Completed Tasks Card

    private var completedTasksCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Completed", systemImage: "checkmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.clawMuted)
                Spacer()
                Text("\(store.doneTasks.count)")
                    .font(.caption2)
                    .foregroundStyle(Color.clawMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Color.clawBorder)

            ForEach(store.doneTasks.prefix(3)) { task in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.clawOk.opacity(0.6))
                    Text(task.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.clawMuted)
                        .strikethrough(true, color: Color.clawMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .background(Color.clawCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.clawBorder, lineWidth: 1))
    }

    // MARK: - Add Task Sheet

    private var addTaskSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $newTaskTitle)
                        .foregroundStyle(Color.clawText)
                    Toggle(isOn: $newTaskAssignAgent) {
                        Label("Assign to AI agent", systemImage: "cpu")
                    }
                    .tint(Color.clawAccent)
                }
                .listRowBackground(Color.clawCard)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clawBg)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        newTaskTitle = ""
                        showAddTask = false
                    }.tint(Color.clawMuted)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let t = newTaskTitle
                        let assign = newTaskAssignAgent
                        newTaskTitle = ""
                        showAddTask = false
                        Task {
                            await store.createTask(title: t, description: nil, priority: .normal, dueDate: nil, assignToAgent: assign)
                        }
                    }
                    .tint(Color.clawAccent)
                    .fontWeight(.semibold)
                    .disabled(newTaskTitle.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - HomeTaskRow

struct HomeTaskRow: View {
    let task: HomeTask
    let onStatusChange: (HomeTaskStatus) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onStatusChange(task.status == .done ? .pending : .done)
            } label: {
                Image(systemName: task.status.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(task.status == .done ? Color.clawOk : Color.clawMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(task.status == .done ? Color.clawMuted : Color.clawText)
                    .strikethrough(task.status == .done, color: Color.clawMuted)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if task.assignedToAgent {
                        Label("AI", systemImage: "cpu")
                            .font(.caption2)
                            .foregroundStyle(Color.clawTeal.opacity(0.8))
                    }
                    if let due = task.dueDate {
                        Label {
                            Text(due, format: Date.FormatStyle.dateTime.month().day())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(.caption2)
                        .foregroundStyle(due < Date() ? Color.clawDanger : Color.clawMuted)
                    }
                }
            }

            Spacer()

            // Priority indicator
            Circle()
                .fill(Color(hex: task.priority.colorHex))
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - GroceryListView

struct GroceryListView: View {
    @Environment(HomeOrchestrationStore.self) private var store
    @State private var newItemName: String = ""
    @State private var showAddItem: Bool = false

    var body: some View {
        Group {
            if let list = store.primaryGroceryList {
                List {
                    ForEach(GroceryCategory.allCases) { cat in
                        let items = list.items.filter { $0.category == cat }
                        if !items.isEmpty {
                            Section(cat.displayName) {
                                ForEach(items) { item in
                                    GroceryItemRow(item: item) {
                                        Task { await store.toggleGroceryItem(listId: list.id, itemId: item.id) }
                                    }
                                    .listRowBackground(Color.clawCard)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.clawBg)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cart").font(.system(size: 44)).foregroundStyle(Color.clawMuted.opacity(0.4))
                    Text("No grocery list").font(.headline).foregroundStyle(Color.clawMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clawBg)
            }
        }
        .navigationTitle("Groceries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddItem = true } label: {
                    Image(systemName: "plus")
                }
                .tint(Color.clawAccent)
            }
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                Form {
                    TextField("Item name", text: $newItemName)
                        .listRowBackground(Color.clawCard)
                }
                .scrollContentBackground(.hidden)
                .background(Color.clawBg)
                .navigationTitle("Add Item")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.clawBgAccent, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { newItemName = ""; showAddItem = false }.tint(Color.clawMuted)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add") {
                            let name = newItemName
                            newItemName = ""
                            showAddItem = false
                            if let listId = store.primaryGroceryList?.id {
                                Task {
                                    await store.addGroceryItem(listId: listId, name: name, quantity: nil, category: .other)
                                }
                            }
                        }
                        .tint(Color.clawAccent).fontWeight(.semibold).disabled(newItemName.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct GroceryItemRow: View {
    let item: GroceryItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isBought ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isBought ? Color.clawOk : Color.clawMuted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 14))
                    .foregroundStyle(item.isBought ? Color.clawMuted : Color.clawText)
                    .strikethrough(item.isBought)
                if let qty = item.quantity {
                    Text(qty)
                        .font(.caption2)
                        .foregroundStyle(Color.clawMuted)
                }
            }

            Spacer()

            if item.addedByAgent {
                Image(systemName: "cpu")
                    .font(.caption2)
                    .foregroundStyle(Color.clawTeal.opacity(0.6))
            }
        }
    }
}
