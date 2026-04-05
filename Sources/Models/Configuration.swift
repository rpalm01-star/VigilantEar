import Foundation

/// Simple configuration system for VigilantEar
@Observable
final class Configuration {
    @MainActor static let shared = Configuration()
    
    private(set) var items: [String: ConfigItem] = [:]
    
    private init() {
        loadDefaults()
    }
    
    private func loadDefaults() {
        // Default values for the app
        items["micBaseline"] = ConfigItem(value: 0.12)           // meters between mics
        items["speedOfSound"] = ConfigItem(value: 343.0)         // m/s
        items["minDecibelThreshold"] = ConfigItem(value: 75.0)   // dB for alerts
        items["confidenceThreshold"] = ConfigItem(value: 0.65)   // for classification
        items["backgroundModeEnabled"] = ConfigItem(value: true)
    }
    
    func value<T>(for key: String, default defaultValue: T) -> T {
        guard let item = items[key],
              let value = item.value as? T else {
            return defaultValue
        }
        return value
    }
    
    func setValue<T>(_ value: T, for key: String) {
        items[key] = ConfigItem(value: value)
    }
}

// MARK: - ConfigItem (self-contained, no external AnyCodable needed)

struct ConfigItem: Codable, Equatable {
    let value: AnyCodable   // lightweight wrapper defined below
    
    init<T>(value: T) {
        self.value = AnyCodable(value)
    }
}

// MARK: - Lightweight AnyCodable (included so no external dependency)

struct AnyCodable: Codable, Equatable {
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        <#code#>
    }
    
    let value: Any
    
    init<T>(_ value: T) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) { value = bool }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let string = try? container.decode(String.self) { value = string }
        else { value = "" }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:   try container.encode(bool)
        case let int as Int:     try container.encode(int)
        case let double as Double: try container.encode(double)
        case let string as String: try container.encode(string)
        default:                 try container.encode("\(value)")
        }
    }
}
