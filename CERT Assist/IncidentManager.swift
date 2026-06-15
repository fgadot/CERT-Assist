//
//  IncidentManager.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//

import Foundation
import Observation

/// Main data manager for the CERT Field Board app
/// Handles all incidents, members, reports, and tasks
@Observable
class IncidentManager {
    
    // MARK: - Singleton
    
    static let shared = IncidentManager()
    
    // MARK: - Properties
    
    var currentIncident: Incident?
    var currentMember: CERTMember?
    
    var members: [CERTMember] = []
    var reports: [IncidentReport] = []
    var tasks: [Task] = []
    
    // MARK: - Computed Properties
    
    var isCheckedIn: Bool {
        currentMember != nil
    }
    
    var availableMembers: [CERTMember] {
        members.filter { $0.status == .available || $0.status == .assigned }
    }
    
    var activeReports: [IncidentReport] {
        reports.filter { $0.status != .resolved }
    }
    
    var openTasks: [Task] {
        tasks.filter { $0.status == .open }
    }
    
    var assignedTasks: [Task] {
        tasks.filter { $0.status == .assigned }
    }
    
    var completedTasks: [Task] {
        tasks.filter { $0.status == .completed }
    }

    var cancelledTasks: [Task] {
        tasks.filter { $0.status == .cancelled }
    }
    
    // MARK: - Init
    
    private init() {
        loadData()
        
        // For development: add sample data if empty
        #if DEBUG
        if members.isEmpty {
            addSampleData()
        }
        #endif
    }
    
    // MARK: - Incident Management
    
    func startNewIncident(name: String) {
        let incident = Incident(name: name, startDate: Date(), isActive: true)
        currentIncident = incident
        saveData()
    }
    
    func endCurrentIncident() {
        currentIncident?.isActive = false
        currentIncident?.endDate = Date()
        saveData()
    }
    
    // MARK: - Member Management
    
    func checkIn(name: String, role: String, equipment: [Equipment]) {
        let member = CERTMember(
            name: name,
            role: role,
            status: .available,
            equipment: equipment
        )
        currentMember = member
        members.append(member)
        saveData()
    }
    
    func updateMemberStatus(_ status: MemberStatus) {
        guard var member = currentMember else { return }
        member.status = status
        member.lastUpdated = Date()
        currentMember = member
        
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        }
        saveData()
    }
    
    func updateMemberLocation(_ location: LocationData) {
        guard var member = currentMember else { return }
        member.location = location
        member.lastUpdated = Date()
        currentMember = member
        
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        }
        saveData()
    }
    
    func checkOut() {
        guard var member = currentMember else { return }
        member.status = .unavailable
        member.lastUpdated = Date()
        
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        }
        currentMember = nil
        saveData()
    }
    
    // MARK: - Report Management
    
    func addReport(_ report: IncidentReport) {
        reports.append(report)
        saveData()
    }
    
    func updateReport(_ report: IncidentReport) {
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = report
            saveData()
        }
    }
    
    func deleteReport(_ report: IncidentReport) {
        reports.removeAll { $0.id == report.id }
        saveData()
    }
    
    // MARK: - Task Management
    
    func addTask(_ task: Task) {
        tasks.append(task)
        saveData()
    }
    
    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            saveData()
        }
    }
    
    func completeTask(_ task: Task) {
        var updatedTask = task
        updatedTask.status = .completed
        updatedTask.completedAt = Date()
        updateTask(updatedTask)
    }

    func cancelTask(_ task: Task) {
        var updatedTask = task
        updatedTask.status = .cancelled
        updateTask(updatedTask)
    }

    func reopenTask(_ task: Task) {
        var updatedTask = task
        updatedTask.status = updatedTask.assignedTo.isEmpty ? .open : .assigned
        updateTask(updatedTask)
    }

    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
        saveData()
    }
    
    // MARK: - Data Persistence
    
    private func saveData() {
        let encoder = JSONEncoder()
        
        if let membersData = try? encoder.encode(members) {
            UserDefaults.standard.set(membersData, forKey: "members")
        }
        
        if let reportsData = try? encoder.encode(reports) {
            UserDefaults.standard.set(reportsData, forKey: "reports")
        }
        
        if let tasksData = try? encoder.encode(tasks) {
            UserDefaults.standard.set(tasksData, forKey: "tasks")
        }
        
        if let incidentData = try? encoder.encode(currentIncident) {
            UserDefaults.standard.set(incidentData, forKey: "currentIncident")
        }
        
        if let memberData = try? encoder.encode(currentMember) {
            UserDefaults.standard.set(memberData, forKey: "currentMember")
        }
    }
    
    private func loadData() {
        let decoder = JSONDecoder()
        
        if let membersData = UserDefaults.standard.data(forKey: "members"),
           let loadedMembers = try? decoder.decode([CERTMember].self, from: membersData) {
            members = loadedMembers
        }
        
        if let reportsData = UserDefaults.standard.data(forKey: "reports"),
           let loadedReports = try? decoder.decode([IncidentReport].self, from: reportsData) {
            reports = loadedReports
        }
        
        if let tasksData = UserDefaults.standard.data(forKey: "tasks"),
           let loadedTasks = try? decoder.decode([Task].self, from: tasksData) {
            tasks = loadedTasks
        }
        
        if let incidentData = UserDefaults.standard.data(forKey: "currentIncident"),
           let loadedIncident = try? decoder.decode(Incident.self, from: incidentData) {
            currentIncident = loadedIncident
        }
        
        if let memberData = UserDefaults.standard.data(forKey: "currentMember"),
           let loadedMember = try? decoder.decode(CERTMember.self, from: memberData) {
            currentMember = loadedMember
        }
    }
    
    func clearAllData() {
        members = []
        reports = []
        tasks = []
        currentIncident = nil
        currentMember = nil
        
        UserDefaults.standard.removeObject(forKey: "members")
        UserDefaults.standard.removeObject(forKey: "reports")
        UserDefaults.standard.removeObject(forKey: "tasks")
        UserDefaults.standard.removeObject(forKey: "currentIncident")
        UserDefaults.standard.removeObject(forKey: "currentMember")
    }
    
    // MARK: - Sample Data (Development)
    
    private func addSampleData() {
        // Sample incident
        currentIncident = Incident(name: "Sapphire Point Hurricane Response", startDate: Date())
        
        // Sample members
        let frank = CERTMember(
            name: "Frank Gadot",
            role: "Team Leader",
            status: .available,
            equipment: [.radio, .firstAidKit, .vehicle]
        )
        currentMember = frank
        members = [frank]
        
        // Sample report
        let report = IncidentReport(
            type: .treeDown,
            location: LocationData(latitude: 34.0522, longitude: -118.2437, address: "123 Main St"),
            severity: .medium,
            status: .new,
            notes: "Large oak tree blocking road",
            reportedBy: frank.id
        )
        reports = [report]
        
        // Sample task
        let task = Task(
            title: "Check clubhouse for damage",
            description: "Visual inspection of community clubhouse and grounds",
            status: .open,
            priority: .high
        )
        tasks = [task]
        
        saveData()
    }
}
