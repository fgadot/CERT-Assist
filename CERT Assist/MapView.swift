//
//  MapView.swift
//  CERT Assist
//
//  Created by frank gadot on 2026.06.09.
//

import SwiftUI
import MapKit
import CoreLocation

struct MapView: View {
    
    @State private var manager = IncidentManager.shared
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedReport: IncidentReport?
    
    var reportAnnotations: [ReportAnnotation] {
        manager.reports.map { report in
            ReportAnnotation(report: report)
        }
    }
    
    var memberAnnotations: [MemberAnnotation] {
        manager.members.compactMap { member in
            guard let location = member.location else { return nil }
            return MemberAnnotation(member: member, location: location)
        }
    }
    
    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selectedReport) {
                // Report markers
                ForEach(reportAnnotations) { annotation in
                    Annotation(annotation.report.type.rawValue, coordinate: annotation.coordinate) {
                        ReportMarker(report: annotation.report)
                    }
                    .tag(annotation.report)
                }
                
                // Member markers
                ForEach(memberAnnotations) { annotation in
                    Annotation(annotation.member.name, coordinate: annotation.coordinate) {
                        MemberMarker(member: annotation.member)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Map")
            .sheet(item: $selectedReport) { report in
                ReportDetailSheet(report: report)
            }
        }
    }
}

struct ReportAnnotation: Identifiable {
    let id: UUID
    let report: IncidentReport
    let coordinate: CLLocationCoordinate2D
    
    init(report: IncidentReport) {
        self.id = report.id
        self.report = report
        self.coordinate = report.location.coordinate
    }
}

struct MemberAnnotation: Identifiable {
    let id: UUID
    let member: CERTMember
    let coordinate: CLLocationCoordinate2D
    let location: LocationData
    
    init(member: CERTMember, location: LocationData) {
        self.id = member.id
        self.member = member
        self.location = location
        self.coordinate = location.coordinate
    }
}

struct ReportMarker: View {
    let report: IncidentReport
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(report.severity.color))
                .frame(width: 36, height: 36)
            
            Image(systemName: report.type.icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
        }
        .shadow(radius: 4)
    }
}

struct MemberMarker: View {
    let member: CERTMember
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(member.status.color))
                .frame(width: 32, height: 32)
            
            Image(systemName: "person.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
        .shadow(radius: 2)
    }
}

#Preview {
    MapView()
}
