//
//  CAPAlert.swift
//  VigilantEar
//
//  Created by Robert Palmer on 5/3/26.
//


import Foundation
import CoreLocation
import Observation

struct CAPAlert: Identifiable {
    let id = UUID()
    let headline: String
    let polygon: [CLLocationCoordinate2D]
}

@Observable
@MainActor
class CAPAlertManager: NSObject {
    
    var nearbyAlerts: [CAPAlert] = []
    
    private var allActiveAlerts: [CAPAlert] = []
    private var lastLocation: CLLocationCoordinate2D?
    private var isFetching = false
    
    // Example: US NWS CAP Feed (Can add Canada/UK URLs to an array and loop them)
    private let feedURL = URL(string: "https://api.weather.gov/alerts/active.atom")!
    
    // XML Parsing State
    private var currentElement = ""
    private var currentHeadline = ""
    private var currentPolygonStr = ""
    private var tempAlerts: [CAPAlert] = []
    
    func startPolling() {
        // Poll every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.fetchFeeds() }
        }
        Task { await fetchFeeds() }
    }
    
    func updateLocation(_ coordinate: CLLocationCoordinate2D) {
        self.lastLocation = coordinate
        recalculateIntersections()
    }
    
    private func fetchFeeds() async {
        guard !isFetching else { return }
        isFetching = true
        
        do {
            var request = URLRequest(url: feedURL)
            request.setValue("VigilantEar/1.0 (Rpalm01@gmail.com)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/cap+xml", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                AppGlobals.doLog(message: "⚠️ NWS returned status code: \(httpResponse.statusCode)", step: "CAP_MGR", isError: true)
            }
            
            // Hop off the Main thread to parse the huge XML synchronously
            let parsedAlerts = await Task.detached {
                let parser = CAPFeedParser()
                return parser.parse(data: data)
            }.value
            
            self.allActiveAlerts = parsedAlerts
            recalculateIntersections()
            
            AppGlobals.doLog(message: "🌍 CAP Feed Parsed. \(allActiveAlerts.count) active alerts globally.", step: "CAP_MGR")
            
        } catch {
            AppGlobals.doLog(message: "⚠️ CAP Fetch Failed: \(error.localizedDescription)", step: "CAP_MGR", isError: true)
        }
        
        isFetching = false
    }
    
    private func recalculateIntersections() {
        guard let location = lastLocation else { return }
        
        // Filter alerts down to only those whose polygon encloses the user
        self.nearbyAlerts = allActiveAlerts.filter { alert in
            !alert.polygon.isEmpty && contains(polygon: alert.polygon, test: location)
        }
    }
    
    // MARK: - Ray-Casting Point-in-Polygon Algorithm
    private func contains(polygon: [CLLocationCoordinate2D], test: CLLocationCoordinate2D) -> Bool {
        var isInside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if (polygon[i].longitude < test.longitude && polygon[j].longitude >= test.longitude ||
                polygon[j].longitude < test.longitude && polygon[i].longitude >= test.longitude) {
                if (polygon[i].latitude + (test.longitude - polygon[i].longitude) / (polygon[j].longitude - polygon[i].longitude) * (polygon[j].latitude - polygon[i].latitude) < test.latitude) {
                    isInside.toggle()
                }
            }
            j = i
        }
        return isInside
    }
    
}

class CAPFeedParser: NSObject, XMLParserDelegate {
    private var alerts: [CAPAlert] = []
    
    private var currentElement = ""
    private var currentHeadline = ""
    private var currentPolygonStr = ""
    
    func parse(data: Data) -> [CAPAlert] {
        alerts.removeAll()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return alerts
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Supports both US ATOM feeds (title) and Global CAP feeds (headline)
        if currentElement == "title" || currentElement == "headline" {
            currentHeadline += string
        } else if currentElement == "cap:polygon" || currentElement == "polygon" {
            currentPolygonStr += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        // Stop recording characters for this element
        if elementName == currentElement {
            currentElement = ""
        }
        
        // "entry" is for US ATOM, "info" is for Global CAP
        if elementName == "entry" || elementName == "info" {
            if !currentPolygonStr.isEmpty {
                let pairs = currentPolygonStr.split(separator: " ")
                var coordinates: [CLLocationCoordinate2D] = []
                
                for pair in pairs {
                    let latLon = pair.split(separator: ",")
                    if latLon.count == 2, let lat = Double(latLon[0]), let lon = Double(latLon[1]) {
                        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                }
                
                if !coordinates.isEmpty {
                    alerts.append(CAPAlert(headline: currentHeadline, polygon: coordinates))
                }
            }
            
            // Reset for the next alert block
            currentHeadline = ""
            currentPolygonStr = ""
        }
    }
}
