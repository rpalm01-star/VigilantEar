import Foundation
import CoreLocation
import Observation
import Combine

// MARK: - CAP Alert Model
struct CAPAlert: Identifiable {
    let id = UUID()
    let event: String
    let headline: String
    let polygon: [CLLocationCoordinate2D]
}

// MARK: - Main Manager
@Observable
@MainActor
class CAPAlertManager: ObservableObject {
        
    var nearbyAlerts: [CAPAlert] = []
    
    private var allActiveAlerts: [CAPAlert] = []
    private var lastLocation: CLLocationCoordinate2D?
    private var isFetching = false
    
    // MARK: - Europe MeteoGate Feed (unchanged, already working)
    func getEuropeFeeds() {
        let apiKey = AppGlobals.meteoGateKey
        
        Task { @MainActor in
            let utc = TimeZone(secondsFromGMT: 0)!
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = utc
            
            let now = Date()
            let startOfDay = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
            
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = utc
            formatter.formatOptions = [.withInternetDateTime]
            
            let datetimeParam = "\(formatter.string(from: startOfDay))/\(formatter.string(from: tomorrow))"
            
            var components = URLComponents(string: "https://api.meteogate.eu/warnings/collections/warnings/locations/ALL")!
            components.queryItems = [
                URLQueryItem(name: "f", value: "GeoJSON"),
                URLQueryItem(name: "datetime", value: datetimeParam),
                URLQueryItem(name: "apikey", value: apiKey)
            ]
            
            guard let url = components.url else { return }
            
            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
            request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let http = response as? HTTPURLResponse else { return }
                
                if http.statusCode == 429 {
                    AppGlobals.doLog(message: "⚠️ Rate limited (429) by MeteoGate – skipping Europe feed this cycle", step: "CAP_MGR")
                    return
                }
                
                if http.statusCode != 200 {
                    AppGlobals.doLog(message: "⚠️ Europe feed returned status \(http.statusCode)", step: "CAP_MGR")
                    return
                }
                
                AppGlobals.doLog(message: "✅ Status: \(http.statusCode)", step: "CAP_MGR")
                
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let features = json["features"] as? [[String: Any]] else {
                    AppGlobals.doLog(message: "❌ Could not parse GeoJSON", step: "CAP_MGR")
                    return
                }
                
                AppGlobals.doLog(message: "🌍 EUROPEAN WEATHER WARNINGS: \(features.count) total features found", step: "CAP_MGR")
                
                var seen = Set<String>()
                var uniqueWarnings: [[String: Any]] = []
                for feature in features {
                    guard let id = feature["id"] as? String else { continue }
                    if seen.contains(id) { continue }
                    seen.insert(id)
                    uniqueWarnings.append(feature)
                }
                
                AppGlobals.doLog(message: "📊 Unique warnings: \(uniqueWarnings.count)", step: "CAP_MGR")
                
                var newEuropeAlerts: [CAPAlert] = []
                
                for feature in uniqueWarnings {
                    let props = feature["properties"] as? [String: Any] ?? [:]
                    let geometry = feature["geometry"] as? [String: Any] ?? [:]
                    let coordsArray = geometry["coordinates"] as? [[[Double]]] ?? []
                    
                    var detailURL: URL? = nil
                    if let links = props["links"] as? [[String: Any]] ?? feature["links"] as? [[String: Any]] {
                        for link in links {
                            if let rel = link["rel"] as? String, rel == "json",
                               let href = link["href"] as? String,
                               let url = URL(string: href) {
                                detailURL = url
                                break
                            }
                        }
                    }
                    
                    var title = "No title"
                    var event = "Unknown event"
                    var description = "No description"
                    
                    if let detailURL = detailURL {
                        var detailRequest = URLRequest(url: detailURL)
                        detailRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                        let (detailData, _) = try await URLSession.shared.data(for: detailRequest)
                        
                        if let detailJSON = try? JSONSerialization.jsonObject(with: detailData) as? [String: Any],
                           let infoArray = detailJSON["info"] as? [[String: Any]],
                           let info = infoArray.first {
                            title = info["headline"] as? String ?? info["event"] as? String ?? title
                            event = info["event"] as? String ?? info["awareness_type"] as? String ?? event
                            description = info["description"] as? String ?? description
                        }
                    }
                    
                    var polygon: [CLLocationCoordinate2D] = []
                    if let firstRing = coordsArray.first {
                        for point in firstRing {
                            if point.count >= 2 {
                                polygon.append(CLLocationCoordinate2D(latitude: point[1], longitude: point[0]))
                            }
                        }
                    }
                    
                    if !polygon.isEmpty {
                        newEuropeAlerts.append(CAPAlert(event: event, headline: title, polygon: polygon))
                    }
                }
                
                self.allActiveAlerts.append(contentsOf: newEuropeAlerts)
                self.recalculateIntersections()
                
                AppGlobals.doLog(message: "✅ Added \(newEuropeAlerts.count) unique European alerts", step: "CAP_MGR")
                AppGlobals.doLog(message: "🌍 Total active alerts now: \(self.allActiveAlerts.count)", step: "CAP_MGR")
                
            } catch {
                AppGlobals.doLog(message: "❌ Request failed: \(error)", step: "CAP_MGR", isError: true)
            }
        }
    }
    
    // MARK: - Global CAP Feeds (US NWS + others)
    private let feedURLs: [URL] = [
        URL(string: "https://api.weather.gov/alerts/active.atom")!
    ]
    
    func startPolling() {
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
        
        // Clear the slate for the new 15-minute polling cycle
        self.allActiveAlerts.removeAll(keepingCapacity: true)
        
        getEuropeFeeds()
        
        var combinedAlerts: [CAPAlert] = []
        for url in feedURLs {
            do {
                var request = URLRequest(url: url)
                request.setValue("application/atom+xml, application/xml", forHTTPHeaderField: "Accept")
                request.setValue("VigilantEar/1.0 (iOS; Robert Palmer)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 10
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let parser = CAPFeedParser()
                    let parsedAlerts = parser.parse(data: data)
                    combinedAlerts.append(contentsOf: parsedAlerts)
                }
            } catch {
                AppGlobals.doLog(message: "⚠️ Feed failed: \(url)", step: "CAP_MGR", isError: true)
            }
        }
        
        self.allActiveAlerts.append(contentsOf: combinedAlerts)
        recalculateIntersections()
        
        AppGlobals.doLog(message: "🌍 CAP Feeds Parsed. \(allActiveAlerts.count) active alerts globally.", step: "CAP_MGR")
        
        isFetching = false
    }
    
    // MARK: - Improved Mock Injection (large, reliable rectangle)
    func injectMockFeed(xmlData: Data, timeoutInSeconds: Int = 30) {
        let parser = CAPFeedParser()
        let parsedAlerts = parser.parse(data: xmlData)
        
        AppGlobals.doLog(message: "🧪 injectMockFeed: Parsed \(parsedAlerts.count) mock alerts", step: "CAP_MGR")
        
        for alert in parsedAlerts {
            AppGlobals.doLog(message: "🧪 Mock alert added → \(alert.headline) | Polygon points: \(alert.polygon.count)", step: "CAP_MGR")
        }
        
        self.allActiveAlerts.append(contentsOf: parsedAlerts)
        self.recalculateIntersections()
        
        AppGlobals.doLog(message: "🧪 Injected mock alerts. Nearby alerts is now: \(nearbyAlerts.count)", step: "CAP_MGR")
        
        // Auto-remove after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeoutInSeconds)) { [weak self] in
            guard let self = self else { return }
            self.allActiveAlerts.removeAll { $0.headline.contains("(SIM)") }
            self.recalculateIntersections()
            AppGlobals.doLog(message: "🧪 Mock alert timed out and removed. Nearby alerts is now: \(self.nearbyAlerts.count)", step: "CAP_MGR")
        }
    }
    
    // MARK: - Existing helpers (unchanged)
    private func recalculateIntersections() {
        guard let location = lastLocation else {
            AppGlobals.doLog(message: "⚠️ recalculateIntersections: No lastLocation set", step: "CAP_MGR")
            return
        }
        
        self.nearbyAlerts = allActiveAlerts.filter { alert in
            !alert.polygon.isEmpty && contains(polygon: alert.polygon, test: location)
        }
        
        AppGlobals.doLog(message: "📍 recalculateIntersections: \(nearbyAlerts.count) nearby alerts", step: "CAP_MGR")
    }
    
    private func contains(polygon: [CLLocationCoordinate2D], test: CLLocationCoordinate2D) -> Bool {
        var isInside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            if (polygon[i].longitude < test.longitude && polygon[j].longitude >= test.longitude) ||
                (polygon[j].longitude < test.longitude && polygon[i].longitude >= test.longitude) {
                if (polygon[i].latitude + (test.longitude - polygon[i].longitude) / (polygon[j].longitude - polygon[i].longitude) * (polygon[j].latitude - polygon[i].latitude) < test.latitude) {
                    isInside.toggle()
                }
            }
            j = i
        }
        return isInside
    }
}

// MARK: - Synchronous XML Parser (unchanged)
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
                    let finalEvent = cleanEvent.isEmpty ? String(localized: AppGlobals.emergencyAlertText) : cleanEvent
                    
                    alerts.append(CAPAlert(event: finalEvent, headline: currentHeadline, polygon: coordinates))
                }
            }
            
            currentEvent = ""
            currentHeadline = ""
            currentPolygonStr = ""
        }
    }
}
