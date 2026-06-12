//
//  TaskBoardView.swift
//  CERT Assist
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
                            Button {
                                selectedTask = task
                            } label: {
                                TaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if !manager.assignedTasks.isEmpty {
                    Section("Assigned (\(manager.assignedTasks.count))") {
                        ForEach(manager.assignedTasks) { task in
                            Button {
                                selectedTask = task
                            } label: {
                                TaskRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if !manager.completedTasks.isEmpty {
                    Section("Completed (\(manager.completedTasks.count))") {
                        ForEach(manager.completedTasks) { task in
                            Button {
                                selectedTask = task
                            } label: {
                                TaskRow(task: task)
                            }
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
            // Status Icon
            Image(systemName: task.status.icon)
                .font(.title3)
                .foregroundStyle(Color(task.status.color))
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
                        .foregroundStyle(Color(task.priority.color))
                    
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
                                    if isSelected {
                                        selectedMembers.insert(member.id)
                                    } else {
                                        selectedMembers.remove(member.id)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.subheadline)
                                    Text(member.role)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                    Button("Cancel") {
                        dismiss()
                    }
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

struct TaskDetailSheet: View {
    
    @Environment(\.dismiss) private var dismiss
    @State private var manager = IncidentManager.shared
    @State private var task: Task
    @State private var editMode = false
    
    init(task: Task) {
        self.task = task
    }
    
    var assignedNames: [String] {
        task.assignedTo.compactMap { id in
            manager.members.first(where: { $0.id == id })?.name
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: task.status.icon)
                            .font(.title)
                            .foregroundStyle(Color(task.status.color))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.headline)
                            Text(task.status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Status") {
                    Picker("Status", selection: $task.status) {
                        ForEach(TaskStatus.allCases, id: \.self) { status in
                            Label(status.rawValue, systemImage: status.icon)
                                .tag(status)
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
                            Label(sev.rawValue, systemImage: sev.icon)
                                .tag(sev)
                        }
                    }
                    .onChange(of: task.priority) {
                        manager.updateTask(task)
                    }
                }
                
                if !task.description.isEmpty {
                    Section("Description") {
                        Text(task.description)
                    }
                }
                
                Section("Assigned To") {
                    if assignedNames.isEmpty {
                        Text("Unassigned")
                            .foregroundStyle(.secondary)
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
                
                if task.status != .completed {
                    Section {
                        Button {
                            manager.completeTask(task)
                            dismiss()
                        } label: {
                            Label("Mark Complete", systemImage: "checkmark.circle.fill")
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
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    TaskBoardView()
}
