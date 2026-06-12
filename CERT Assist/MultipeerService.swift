//
//  MultipeerService.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//
//  STUB: This is a placeholder for the offline peer-to-peer sync feature.
//  This is THE critical feature that differentiates CERT Field Board from other apps.
//
//  Implementation Guide:
//  1. Import MultipeerConnectivity framework
//  2. Create MCSession, MCPeerID, MCNearbyServiceAdvertiser, MCNearbyServiceBrowser
//  3. Encode CERTMember, IncidentReport, and Task objects as JSON
//  4. Send over MCSession
//  5. Receive and merge data (handle conflicts by timestamp)
//  6. Show sync status in UI
//
//  Resources:
//  - https://developer.apple.com/documentation/multipeerconnectivity
//  - Example: https://developer.apple.com/documentation/multipeerconnectivity/mcsession
//

import Foundation
import MultipeerConnectivity
import Observation
import UIKit

/// Handles peer-to-peer data exchange between nearby devices
/// This enables offline coordination when cellular/Wi-Fi is unavailable
@Observable
class MultipeerService: NSObject {
    
    // MARK: - Configuration
    
    private let serviceType = "cert-field"
    private let maxPeers = 8 // Reasonable limit for CERT team size
    
    // MARK: - MultipeerConnectivity Properties
    
    private var peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser
    private var browser: MCNearbyServiceBrowser
    
    // MARK: - Observable State
    
    var isAdvertising = false
    var isBrowsing = false
    var connectedPeers: [MCPeerID] = []
    var lastSyncDate: Date?
    
    // MARK: - Initialization
    
    override init() {
        // Create peer ID from device name or member name
        let deviceName = UIDevice.current.name
        let newPeerID = MCPeerID(displayName: deviceName)
        self.peerID = newPeerID
        
        // Create session
        self.session = MCSession(
            peer: newPeerID,
            securityIdentity: nil,
            encryptionPreference: .required // Always encrypt for privacy
        )
        
        // Create advertiser (makes this device discoverable)
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: newPeerID,
            discoveryInfo: nil,
            serviceType: serviceType
        )
        
        // Create browser (discovers other devices)
        self.browser = MCNearbyServiceBrowser(
            peer: newPeerID,
            serviceType: serviceType
        )
        
        super.init()
        
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }
    
    // MARK: - Public API
    
    /// Start advertising this device to nearby peers
    func startAdvertising() {
        advertiser.startAdvertisingPeer()
        isAdvertising = true
        print("📡 Started advertising as \(peerID.displayName)")
    }
    
    /// Stop advertising
    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
        print("📡 Stopped advertising")
    }
    
    /// Start browsing for nearby peers
    func startBrowsing() {
        browser.startBrowsingForPeers()
        isBrowsing = true
        print("🔍 Started browsing for peers")
    }
    
    /// Stop browsing
    func stopBrowsing() {
        browser.stopBrowsingForPeers()
        isBrowsing = false
        print("🔍 Stopped browsing")
    }
    
    /// Send all local data to connected peers
    func syncData() {
        guard !connectedPeers.isEmpty else {
            print("⚠️ No peers to sync with")
            return
        }
        
        // TODO: Implement data sync
        // 1. Get data from IncidentManager
        // 2. Create SyncMessage with all members, reports, tasks
        // 3. Encode as JSON
        // 4. Send to all connected peers
        
        let manager = IncidentManager.shared
        
        let syncData = SyncMessage(
            members: manager.members,
            reports: manager.reports,
            tasks: manager.tasks,
            timestamp: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(syncData)
            try session.send(data, toPeers: connectedPeers, with: .reliable)
            lastSyncDate = Date()
            print("✅ Sent sync data to \(connectedPeers.count) peer(s)")
        } catch {
            print("❌ Failed to send sync data: \(error)")
        }
    }
    
    /// Disconnect from all peers
    func disconnect() {
        session.disconnect()
        connectedPeers = []
        print("🔌 Disconnected from all peers")
    }
}

// MARK: - MCSessionDelegate

extension MultipeerService: MCSessionDelegate {
    
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ Connected to \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                // Auto-sync when peer connects
                self.syncData()
                
            case .connecting:
                print("🔄 Connecting to \(peerID.displayName)")
                
            case .notConnected:
                print("❌ Disconnected from \(peerID.displayName)")
                self.connectedPeers.removeAll { $0 == peerID }
                
            @unknown default:
                break
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            do {
                let syncData = try JSONDecoder().decode(SyncMessage.self, from: data)
                self.mergeReceivedData(syncData, from: peerID)
                print("✅ Received sync data from \(peerID.displayName)")
            } catch {
                print("❌ Failed to decode sync data: \(error)")
            }
        }
    }
    
    // Merge received data with local data
    private func mergeReceivedData(_ syncData: SyncMessage, from peerID: MCPeerID) {
        let manager = IncidentManager.shared
        
        // Merge members (add new, update existing if timestamp is newer)
        for receivedMember in syncData.members {
            if let existingIndex = manager.members.firstIndex(where: { $0.id == receivedMember.id }) {
                let existing = manager.members[existingIndex]
                if receivedMember.lastUpdated > existing.lastUpdated {
                    manager.members[existingIndex] = receivedMember
                }
            } else {
                manager.members.append(receivedMember)
            }
        }
        
        // Merge reports
        for receivedReport in syncData.reports {
            if let existingIndex = manager.reports.firstIndex(where: { $0.id == receivedReport.id }) {
                let existing = manager.reports[existingIndex]
                if receivedReport.lastUpdated > existing.lastUpdated {
                    manager.reports[existingIndex] = receivedReport
                }
            } else {
                manager.reports.append(receivedReport)
            }
        }
        
        // Merge tasks
        for receivedTask in syncData.tasks {
            if let existingIndex = manager.tasks.firstIndex(where: { $0.id == receivedTask.id }) {
                let existing = manager.tasks[existingIndex]
                if receivedTask.createdAt > existing.createdAt {
                    manager.tasks[existingIndex] = receivedTask
                }
            } else {
                manager.tasks.append(receivedTask)
            }
        }
        
        lastSyncDate = Date()
        print("🔄 Merged data from \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Could be used for photo transfers in the future
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Could be used for photo transfers in the future
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerService: MCNearbyServiceAdvertiserDelegate {
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations (we trust CERT team members)
        // In production, you might want to add confirmation UI
        print("📨 Received invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerService: MCNearbyServiceBrowserDelegate {
    
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        print("🔍 Found peer: \(peerID.displayName)")
        
        // Auto-invite discovered peers
        // In production, you might want to add confirmation UI
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("📡 Lost peer: \(peerID.displayName)")
    }
}

// MARK: - Sync Message

/// Container for all data to be synced between peers
struct SyncMessage: Codable {
    let members: [CERTMember]
    let reports: [IncidentReport]
    let tasks: [Task]
    let timestamp: Date
}

// MARK: - Usage Example
/*
 
 // In your app:
 
 let multipeer = MultipeerService()
 
 // Start advertising and browsing
 multipeer.startAdvertising()
 multipeer.startBrowsing()
 
 // Sync data when needed
 multipeer.syncData()
 
 // Show sync status in UI
 if let lastSync = multipeer.lastSyncDate {
     Text("Last sync: \(lastSync, style: .relative) ago")
 }
 
 Text("\(multipeer.connectedPeers.count) peer(s) connected")
 
 // Stop when done
 multipeer.stopAdvertising()
 multipeer.stopBrowsing()
 multipeer.disconnect()
 
 */
