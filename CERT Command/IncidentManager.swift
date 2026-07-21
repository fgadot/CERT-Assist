//
//  IncidentManager.swift
//  CERT Command
//
//  Created by frank gadot on 2026.06.09.
//

import Foundation
import CoreLocation
import Observation
import UserNotifications

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
        members.filter { $0.status == .available || $0.status == .onTask }
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
    
    // MARK: - Device Token

    // Stable UUID that identifies this device across app launches
    var deviceToken: String {
        if let token = UserDefaults.standard.string(forKey: "certDeviceToken") { return token }
        let token = UUID().uuidString
        UserDefaults.standard.set(token, forKey: "certDeviceToken")
        return token
    }

    // MARK: - Init

    private init() {
        loadData()
        serverURL = UserDefaults.standard.string(forKey: "certServerURL") ?? ""
        // Migrate PIN from UserDefaults to Keychain on first launch after upgrade
        if let legacyPIN = UserDefaults.standard.string(forKey: "certMemberPIN"), !legacyPIN.isEmpty {
            KeychainHelper.set(legacyPIN, forKey: "certMemberPIN")
            UserDefaults.standard.removeObject(forKey: "certMemberPIN")
        }
        memberPIN = KeychainHelper.get("certMemberPIN") ?? ""
    }
    
    // MARK: - Incident Management
    
    func startNewIncident(name: String) {
        let incident = Incident(name: name, startDate: Date(), isActive: true)
        currentIncident = incident
    }
    
    func endCurrentIncident() {
        currentIncident?.isActive = false
        currentIncident?.endDate = Date()
    }
    
    // MARK: - Version Enforcement

    var requiresUpdate = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func isVersion(_ version: String, atLeast minimum: String) -> Bool {
        let v = version.split(separator: ".").compactMap { Int($0) }
        let m = minimum.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(v.count, m.count) {
            let vi = i < v.count ? v[i] : 0
            let mi = i < m.count ? m[i] : 0
            if vi < mi { return false }
            if vi > mi { return true }
        }
        return true
    }

    // Returns false if the server explicitly requires a newer version.
    // Network errors are treated as pass (don't block on connectivity issues).
    @MainActor
    func checkVersion(serverURL: String) async -> Bool {
        let base = serverURL.trimmingCharacters(in: ["/"])
        guard let url = URL(string: base + "/api/version") else { return true }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        struct VersionResponse: Decodable { var minimumVersion: String }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return true  // can't reach server — don't block
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let versionInfo = try? decoder.decode(VersionResponse.self, from: data) else { return true }

        if !isVersion(appVersion, atLeast: versionInfo.minimumVersion) {
            requiresUpdate = true
            return false
        }
        return true
    }

    // MARK: - Check-in State

    var checkInError: String?
    var isCheckingIn = false
    var remoteCheckoutMessage: String? = nil
    private var pollTimer: Timer?

    // Saved after a successful check-in so subsequent API calls can reach the server
    private(set) var serverURL: String = ""
    private(set) var memberPIN: String = ""

    // MARK: - Member Management

    @MainActor
    func checkIn(name: String, role: String, equipment: [Equipment], serverURL: String, memberPIN: String) async {
        isCheckingIn = true
        checkInError = nil

        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: ["/"])
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://" + base
        }
        guard let url = URL(string: base + "/api/checkin") else {
            checkInError = "Invalid server address"
            isCheckingIn = false
            return
        }

        let versionOK = await checkVersion(serverURL: base)
        guard versionOK else {
            checkInError = nil  // UpdateRequiredView handles the messaging
            isCheckingIn = false
            return
        }

        struct Payload: Encodable {
            var name: String
            var role: String
            var status: String
            var equipment: [String]
            var lastUpdated: Date
            var deviceToken: String
        }

        struct CheckInResponse: Decodable {
            var success: Bool
            var message: String
            var memberId: UUID?
            var checkedOutByLeader: Bool?
        }

        let payload = Payload(
            name: name,
            role: role,
            status: "Available",
            equipment: equipment.map(\.rawValue),
            lastUpdated: Date(),
            deviceToken: deviceToken
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 10

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        guard let body = try? encoder.encode(payload) else {
            checkInError = "Failed to encode request"
            isCheckingIn = false
            return
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                checkInError = "Invalid server response"
                isCheckingIn = false
                return
            }
            if http.statusCode == 401 {
                checkInError = "Incorrect PIN — try again"
                isCheckingIn = false
                return
            }
            guard http.statusCode == 200 else {
                checkInError = "Server error (\(http.statusCode))"
                isCheckingIn = false
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(CheckInResponse.self, from: data)
            if result.checkedOutByLeader == true {
                checkInError = result.message
                isCheckingIn = false
                return
            }
            let member = CERTMember(
                id: result.memberId ?? UUID(),
                name: name,
                role: role,
                status: .available,
                equipment: equipment
            )
            currentMember = member
            members = [member]
            self.serverURL = base
            self.memberPIN = memberPIN
            saveCurrentMember()
            applyLocationMode(locationTrackingMode)
            startServerPolling()
        } catch {
            checkInError = "Could not reach server — check URL and connection"
        }

        isCheckingIn = false
    }

    @MainActor
    private func pushStatusUpdate(memberID: UUID, status: MemberStatus) async {
        guard !serverURL.isEmpty, !memberPIN.isEmpty else { return }
        let base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: ["/"])
        guard let url = URL(string: "\(base)/api/members/\(memberID)/status") else { return }

        struct StatusPayload: Encodable { var status: String }
        let payload = StatusPayload(status: status.rawValue)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 8

        let encoder = JSONEncoder()
        guard let body = try? encoder.encode(payload) else { return }
        request.httpBody = body

        _ = try? await URLSession.shared.data(for: request)
    }
    
    func updateMemberStatus(_ status: MemberStatus) {
        guard var member = currentMember else { return }
        member.status = status
        member.lastUpdated = Date()
        currentMember = member

        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        }

        saveCurrentMember()
        let memberID = member.id
        Swift.Task { await self.pushStatusUpdate(memberID: memberID, status: status) }
    }
    
    func updateMemberLocation(_ location: LocationData) {
        guard var member = currentMember else { return }
        member.location = location
        member.lastUpdated = Date()
        currentMember = member
        
        if let index = members.firstIndex(where: { $0.id == member.id }) {
            members[index] = member
        }
    }
    
    private func performLocalCheckout() {
        locationTimer?.invalidate()
        locationTimer = nil
        stopServerPolling()
        locationManager.stopUpdating()
        cancelLocationReminder()
        currentMember = nil
        members = []
        reports = []
        tasks = []
        saveCurrentMember()
        UserDefaults.standard.removeObject(forKey: "reports")
        UserDefaults.standard.removeObject(forKey: "tasks")
        UserDefaults.standard.removeObject(forKey: "members")
    }

    func checkOut() {
        guard let member = currentMember else { return }
        let id = member.id
        performLocalCheckout()
        Swift.Task { await self.pushCheckOut(memberID: id) }
    }

    // MARK: - Server Polling (detects force-checkout by team leader)

    private func startServerPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Swift.Task { @MainActor [weak self] in await self?.pollServerStatus() }
        }
        Swift.Task { @MainActor [weak self] in await self?.pollServerStatus() }
    }

    private func stopServerPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @MainActor
    private func pollServerStatus() async {
        guard !serverURL.isEmpty, !memberPIN.isEmpty, isCheckedIn else { return }
        let base = serverURL.trimmingCharacters(in: ["/"])
        let tokenParam = deviceToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceToken
        guard let url = URL(string: "\(base)/api/me?deviceToken=\(tokenParam)") else { return }

        var request = URLRequest(url: url)
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 8

        struct RemoteTask: Decodable {
            var id: UUID?
            var title: String
            var description: String
            var assignedTo: [UUID]
            var status: TaskStatus
            var priority: String
            var notes: String
            var createdAt: Date?
            var completedAt: Date?
        }
        struct MeResponse: Decodable {
            var checkedOutByLeader: Bool
            var subTeamName: String?
            var subTeamColor: String?
            var assignedTasks: [RemoteTask]?
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let result = try? decoder.decode(MeResponse.self, from: data) else { return }

        if result.checkedOutByLeader {
            remoteCheckoutMessage = "Your Team Leader has checked you out."
            performLocalCheckout()
        } else {
            if var member = currentMember,
               member.subTeamName != result.subTeamName || member.subTeamColor != result.subTeamColor {
                member.subTeamName = result.subTeamName
                member.subTeamColor = result.subTeamColor
                currentMember = member
                if let idx = members.firstIndex(where: { $0.id == member.id }) {
                    members[idx] = member
                }
                saveCurrentMember()
            }
            if let remoteTasks = result.assignedTasks {
                tasks = remoteTasks.compactMap { remote in
                    guard let taskId = remote.id else { return nil }
                    return Task(
                        id: taskId,
                        title: remote.title,
                        description: remote.description,
                        assignedTo: remote.assignedTo,
                        status: remote.status,
                        priority: Severity(rawValue: remote.priority) ?? .medium,
                        createdAt: remote.createdAt ?? Date(),
                        completedAt: remote.completedAt,
                        notes: remote.notes
                    )
                }
                saveData()
            }
        }
    }

    @MainActor
    private func pushCheckOut(memberID: UUID) async {
        guard !serverURL.isEmpty, !memberPIN.isEmpty else { return }
        guard let url = URL(string: serverURL.trimmingCharacters(in: ["/"])  + "/api/checkout") else { return }

        struct Body: Encodable { var memberId: UUID }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 8

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let body = try? encoder.encode(Body(memberId: memberID)) else { return }
        request.httpBody = body

        _ = try? await URLSession.shared.data(for: request)
    }
    
    // MARK: - Location Tracking

    enum LocationTrackingMode: String {
        case automatic = "automatic"
        case manual    = "manual"
    }

    private let locationManager = LocationManager.shared
    private var locationTimer: Timer?

    var locationTrackingMode: LocationTrackingMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "certLocationMode") ?? "manual"
            return LocationTrackingMode(rawValue: raw) ?? .manual
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "certLocationMode")
            applyLocationMode(newValue)
        }
    }

    func applyLocationMode(_ mode: LocationTrackingMode) {
        locationTimer?.invalidate()
        locationTimer = nil
        cancelLocationReminder()
        guard isCheckedIn else { return }

        locationManager.requestPermissionAndStart()

        switch mode {
        case .automatic:
            locationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Swift.Task { @MainActor [weak self] in await self?.pushCurrentLocation() }
            }
            // Push immediately on activation
            Swift.Task { @MainActor [weak self] in await self?.pushCurrentLocation() }
        case .manual:
            scheduleLocationReminder()
        }
    }

    @MainActor
    func pushCurrentLocation() async {
        guard let clLocation = locationManager.currentLocation,
              let member = currentMember else { return }
        let locationData = LocationData(coordinate: clLocation.coordinate)
        await pushLocationToServer(locationData, memberID: member.id)
        // Update local state so the map reflects it immediately
        var updated = member
        updated.location = locationData
        updated.lastUpdated = Date()
        currentMember = updated
        if let idx = members.firstIndex(where: { $0.id == member.id }) {
            members[idx] = updated
        }
    }

    @MainActor
    private func pushLocationToServer(_ location: LocationData, memberID: UUID) async {
        guard !serverURL.isEmpty, !memberPIN.isEmpty else { return }
        let base = serverURL.trimmingCharacters(in: ["/"])
        guard let url = URL(string: "\(base)/api/members/\(memberID)/location") else { return }

        struct LocationPayload: Encodable {
            var latitude: Double
            var longitude: Double
            var address: String?
            var timestamp: Date
        }
        let payload = LocationPayload(latitude: location.latitude, longitude: location.longitude,
                                      address: location.address, timestamp: location.timestamp)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 8

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(payload) else { return }
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    private func scheduleLocationReminder() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "CERT Location Reminder"
            content.body = "Your team leader needs your location. Tap to update."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30 * 60, repeats: true)
            let req = UNNotificationRequest(identifier: "certLocationReminder", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }
    }

    private func cancelLocationReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["certLocationReminder"])
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
    }
    
    // MARK: - Task Management
    
    func addTask(_ task: Task) {
        tasks.append(task)
    }
    
    func updateTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
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
    }
    
    // MARK: - Data Persistence

    // Saves only the fields needed to resume a check-in session across launches
    private func saveCurrentMember() {
        let encoder = JSONEncoder()
        if let member = currentMember, let data = try? encoder.encode(member) {
            UserDefaults.standard.set(data, forKey: "currentMember")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentMember")
        }
    }

    // Re-registers with the server on launch so the member entry survives server restarts
    @MainActor
    func autoResume() async {
        guard let member = currentMember, !serverURL.isEmpty, !memberPIN.isEmpty else { return }

        let versionOK = await checkVersion(serverURL: serverURL)
        guard versionOK else { return }  // requiresUpdate already set; UI will block

        guard let checkInURL = URL(string: serverURL.trimmingCharacters(in: ["/"])  + "/api/checkin") else { return }

        struct ResumePayload: Encodable {
            var name: String
            var role: String
            var status: String
            var equipment: [String]
            var lastUpdated: Date
            var deviceToken: String
        }
        struct ResumeResponse: Decodable {
            var success: Bool
            var memberId: UUID?
            var checkedOutByLeader: Bool?
        }

        let payload = ResumePayload(
            name: member.name,
            role: member.role,
            status: member.status.rawValue,
            equipment: member.equipment.map(\.rawValue),
            lastUpdated: Date(),
            deviceToken: deviceToken
        )

        var request = URLRequest(url: checkInURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 10

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        guard let body = try? encoder.encode(payload) else { return }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                // PIN rejected — clear session so user is prompted to check in again
                currentMember = nil
                members = []
                saveCurrentMember()
                return
            }
            guard http.statusCode == 200 else { return }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            if let result = try? decoder.decode(ResumeResponse.self, from: data) {
                if result.checkedOutByLeader == true {
                    remoteCheckoutMessage = "Your Team Leader checked you out while you were away."
                    performLocalCheckout()
                    return
                }
                if let newId = result.memberId, newId != member.id {
                    // Server assigned a new ID (e.g. after a restart) — update locally
                    let updated = CERTMember(id: newId, name: member.name, role: member.role,
                                            status: member.status, location: member.location,
                                            equipment: member.equipment)
                    currentMember = updated
                    members = [updated]
                    saveCurrentMember()
                }
            }
            applyLocationMode(locationTrackingMode)
            startServerPolling()
            await fetchMyReports()
        } catch {
            // Network failure — keep local state; user can still see their status
        }
    }

    private func fetchMyReports() async {
        guard let member = currentMember,
              !serverURL.isEmpty, !memberPIN.isEmpty else { return }
        let memberId = member.id
        let base = serverURL.trimmingCharacters(in: ["/"])
        guard let url = URL(string: "\(base)/api/members/\(memberId)/reports") else { return }
        var request = URLRequest(url: url)
        request.setValue(memberPIN, forHTTPHeaderField: "X-CERT-Token")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        if let fetched = try? decoder.decode([IncidentReport].self, from: data) {
            reports = fetched
            saveData()
        }
    }

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
        
    }
}
