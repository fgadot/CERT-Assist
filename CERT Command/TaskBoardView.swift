//
//  TaskBoardView.swift
//  CERT Command
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI

struct TaskBoardView: View {

    @State private var manager = IncidentManager.shared
    @State private var showingNewTask = false
    @State private var selectedTask: Task?

    var body: some View {
        NavigationStack {
            List {
                if !manager.openTasks.isEmpty {
                    Section("Open (\(manager.openTasks.count))") {
                        ForEach(manager.openTasks) { task in
                            Button { selectedTask = task } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !manager.assignedTasks.isEmpty {
                    Section("Assigned (\(manager.assignedTasks.count))") {
                        ForEach(manager.assignedTasks) { task in
                            Button { selectedTask = task } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !manager.completedTasks.isEmpty {
                    Section("Completed (\(manager.completedTasks.count))") {
                        ForEach(manager.completedTasks) { task in
                            Button { selectedTask = task } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if !manager.cancelledTasks.isEmpty {
                    Section("Cancelled (\(manager.cancelledTasks.count))") {
                        ForEach(manager.cancelledTasks) { task in
                            Button { selectedTask = task } label: { TaskRow(task: task) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                if manager.tasks.isEmpty {
                    ContentUnavailableView(
                        "No Tasks Yet",
                        systemImage: "checklist",
                        description: Text("Create tasks to coordinate team activities")
                    )
                }
            }
            .navigationTitle("Task Board")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewTask = true
                    } label: {
                        Label("New Task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewTask) {
                NewTaskSheet()
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailSheet(task: task)
            }
        }
    }
}

// MARK: - TaskRow

struct TaskRow: View {

    let task: Task
    @State private var manager = IncidentManager.shared

    var assignedNames: String {
        let names = task.assignedTo.compactMap { id in
            manager.members.first(where: { $0.id == id })?.name
        }
        return names.isEmpty ? "Unassigned" : names.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.status.icon)
                .font(.title3)
                .foregroundStyle(task.status.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)

                Text(assignedNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(task.priority.rawValue, systemImage: task.priority.icon)
                        .font(.caption)
                        .foregroundStyle(task.priority.color)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(task.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - NewTaskSheet

struct NewTaskSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared

    @State private var title = ""
    @State private var description = ""
    @State private var priority: Severity = .medium
    @State private var selectedMembers: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Priority", selection: $priority) {
                        ForEach(Severity.allCases, id: \.self) { sev in
                            Label(sev.rawValue, systemImage: sev.icon)
                                .tag(sev)
                        }
                    }
                }

                Section("Assign To") {
                    if manager.availableMembers.isEmpty {
                        Text("No members available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.availableMembers) { member in
                            Toggle(isOn: Binding(
                                get: { selectedMembers.contains(member.id) },
                                set: { isSelected in
                                    if isSelected { selectedMembers.insert(member.id) }
                                    else { selectedMembers.remove(member.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name).font(.subheadline)
                                    Text(member.role).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createTask()
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    func createTask() {
        let task = Task(
            title: title,
            description: description,
            assignedTo: Array(selectedMembers),
            status: selectedMembers.isEmpty ? .open : .assigned,
            priority: priority
        )
        manager.addTask(task)
    }
}

// MARK: - TaskDetailSheet

struct TaskDetailSheet: View {

    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared
    @State private var task: Task
    @State private var isEditing = false

    // Mirrors for edit mode
    @State private var editTitle: String
    @State private var editDescription: String
    @State private var editPriority: Severity
    @State private var editSelectedMembers: Set<UUID>

    init(task: Task) {
        _task = State(initialValue: task)
        _editTitle = State(initialValue: task.title)
        _editDescription = State(initialValue: task.description)
        _editPriority = State(initialValue: task.priority)
        _editSelectedMembers = State(initialValue: Set(task.assignedTo))
    }

    var isActive: Bool {
        task.status != .completed && task.status != .cancelled
    }

    var assignedNames: [String] {
        task.assignedTo.compactMap { id in
            manager.members.first(where: { $0.id == id })?.name
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isEditing {
                    editContent
                } else {
                    viewContent
                }
            }
            .navigationTitle(isEditing ? "Edit Task" : "Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") { discardEdits() }
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Save") { saveEdits() }
                            .disabled(editTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else if isActive {
                        Button("Edit") { isEditing = true }
                    }
                }
            }
        }
    }

    // MARK: - View content

    @ViewBuilder
    var viewContent: some View {
        Section {
            HStack {
                Image(systemName: task.status.icon)
                    .font(.title)
                    .foregroundStyle(task.status.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title).font(.headline)
                    Text(task.status.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        if isActive {
            Section("Status") {
                Picker("Status", selection: $task.status) {
                    ForEach(TaskStatus.activeStatuses, id: \.self) { status in
                        Label(status.rawValue, systemImage: status.icon).tag(status)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: task.status) {
                    if task.status == .completed && task.completedAt == nil {
                        task.completedAt = Date()
                    }
                    manager.updateTask(task)
                }

                Picker("Priority", selection: $task.priority) {
                    ForEach(Severity.allCases, id: \.self) { sev in
                        Label(sev.rawValue, systemImage: sev.icon).tag(sev)
                    }
                }
                .onChange(of: task.priority) {
                    manager.updateTask(task)
                }
            }
        }

        if !task.description.isEmpty {
            Section("Description") {
                Text(task.description)
            }
        }

        Section("Assigned To") {
            if assignedNames.isEmpty {
                Text("Unassigned").foregroundStyle(.secondary)
            } else {
                ForEach(assignedNames, id: \.self) { name in
                    Text(name)
                }
            }
        }

        if !task.notes.isEmpty {
            Section("Notes") {
                Text(task.notes)
            }
        }

        Section("Timeline") {
            LabeledContent("Created") {
                Text(task.createdAt, style: .relative) + Text(" ago")
            }
            if let completedAt = task.completedAt {
                LabeledContent("Completed") {
                    Text(completedAt, style: .relative) + Text(" ago")
                }
            }
        }

        if isActive {
            Section {
                Button {
                    manager.completeTask(task)
                    dismiss()
                } label: {
                    Label("Mark Complete", systemImage: "checkmark.circle.fill")
                }

                Button(role: .destructive) {
                    manager.cancelTask(task)
                    dismiss()
                } label: {
                    Label("Cancel Task", systemImage: "xmark.circle")
                }
            }
        }

        if task.status == .cancelled {
            Section {
                Button {
                    manager.reopenTask(task)
                    dismiss()
                } label: {
                    Label("Re-open Task", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }

        Section {
            Button("Delete Task", role: .destructive) {
                manager.deleteTask(task)
                dismiss()
            }
        }
    }

    // MARK: - Edit content

    @ViewBuilder
    var editContent: some View {
        Section("Task Details") {
            TextField("Title", text: $editTitle)

            TextField("Description", text: $editDescription, axis: .vertical)
                .lineLimit(3...6)

            Picker("Priority", selection: $editPriority) {
                ForEach(Severity.allCases, id: \.self) { sev in
                    Label(sev.rawValue, systemImage: sev.icon).tag(sev)
                }
            }
        }

        Section("Assign To") {
            if manager.members.isEmpty {
                Text("No members").foregroundStyle(.secondary)
            } else {
                ForEach(manager.members) { member in
                    Toggle(isOn: Binding(
                        get: { editSelectedMembers.contains(member.id) },
                        set: { selected in
                            if selected { editSelectedMembers.insert(member.id) }
                            else { editSelectedMembers.remove(member.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(.subheadline)
                            Text(member.role).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    func saveEdits() {
        task.title = editTitle.trimmingCharacters(in: .whitespaces)
        task.description = editDescription
        task.priority = editPriority
        task.assignedTo = Array(editSelectedMembers)
        task.status = task.assignedTo.isEmpty ? .open : .assigned
        manager.updateTask(task)
        isEditing = false
    }

    func discardEdits() {
        editTitle = task.title
        editDescription = task.description
        editPriority = task.priority
        editSelectedMembers = Set(task.assignedTo)
        isEditing = false
    }
}

#Preview {
    TaskBoardView()
}
