import Foundation
import CoreLocation
import Observation

struct CAPAlert: Identifiable {
    let id = UUID()
    let event: String
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
    
    // The Global CAP Feeds Array
    private let feedURLs: [URL] = [
        URL(string: "https://api.weather.gov/alerts/active.atom")!,                        // US: National Weather Service
        URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-spain")!,   // EU: Spain (Meteoalarm)
        URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-germany")!, // EU: Germany (Meteoalarm)
        URL(string: "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-ireland")!  // EU: Ireland (Meteoalarm)
        
        // (You can add more European countries just by copying the URL
        // and changing the country name at the very end!)
    ]
    
    func startPolling() {
        // Poll every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
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
        
        var combinedAlerts: [CAPAlert] = []
        
        // Loop through all international feeds
        for url in feedURLs {
            do {
                var request = URLRequest(url: url)
                request.setValue("\(AppGlobals.appTitle)/\(AppGlobals.appVersion) (\(AppGlobals.appEmail))", forHTTPHeaderField: "User-Agent")
                request.setValue("application/cap+xml", forHTTPHeaderField: "Accept")
                
                // Don't let a dead international server hang the other feeds
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    // Run the parser directly on the current actor
                    let parser = CAPFeedParser()
                    let parsedAlerts = parser.parse(data: data)
                    combinedAlerts.append(contentsOf: parsedAlerts)
                } else {
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    AppGlobals.doLog(message: "⚠️ Bad status \(status) from \(url.host ?? "Unknown")", step: "CAP_MGR", isError: true)
                }
                
            } catch {
                AppGlobals.doLog(message: "⚠️ Fetch Failed for \(url.host ?? "Unknown"): \(error.localizedDescription)", step: "CAP_MGR", isError: true)
            }
        }
        
        // Overwrite the master array only after all feeds have been processed
        self.allActiveAlerts = combinedAlerts
        recalculateIntersections()
        
        AppGlobals.doLog(message: "🌍 CAP Feeds Parsed. \(allActiveAlerts.count) active alerts globally.", step: "CAP_MGR")
        
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

// MARK: - Synchronous XML Parser
class CAPFeedParser: NSObject, XMLParserDelegate {
    private var alerts: [CAPAlert] = []
    
    private var currentElement = ""
    private var currentEvent = ""
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
        
        if currentElement == "title" || currentElement == "headline" {
            currentHeadline += string
        } else if currentElement == "cap:event" || currentElement == "event" {
            currentEvent += string
        } else if currentElement == "cap:polygon" || currentElement == "polygon" {
            currentPolygonStr += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == currentElement {
            currentElement = ""
        }
        
        if elementName == "entry" || elementName == "info" {
            if !currentPolygonStr.isEmpty {
                let pairs = currentPolygonStr.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                var coordinates: [CLLocationCoordinate2D] = []
                
                for pair in pairs {
                    let latLon = pair.split(separator: ",")
                    if latLon.count == 2, let lat = Double(latLon[0]), let lon = Double(latLon[1]) {
                        coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                }
                
                if !coordinates.isEmpty {
                    let cleanEvent = currentEvent.trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalEvent = cleanEvent.isEmpty ? "EMERGENCY ALERT" : cleanEvent
                    
                    alerts.append(CAPAlert(event: finalEvent, headline: currentHeadline, polygon: coordinates))
                }
            }
            
            // Reset for the next alert block
            currentEvent = ""
            currentHeadline = ""
            currentPolygonStr = ""
        }
    }
}
