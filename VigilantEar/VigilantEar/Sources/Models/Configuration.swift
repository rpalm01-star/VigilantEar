import Foundation

@MainActor
@Observable
final class Configuration {
    static let shared = Configuration()
    
    private(set) var items: [String: ConfigItem] = [:]
    
    private init() {
        loadDefaults()
    }
    
    private func loadDefaults() {
        items["micBaseline"] = ConfigItem(value: 0.12)
        items["speedOfSound"] = ConfigItem(value: 343.0)
        items["minDecibelThreshold"] = ConfigItem(value: 75.0)
        items["confidenceThreshold"] = ConfigItem(value: 0.65)
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

// MARK: - ConfigItem
struct ConfigItem: Codable, Equatable {
    let value: AnyCodable
    
    init<T>(value: T) {
        self.value = AnyCodable(value)
    }
}

// MARK: - AnyCodable
struct AnyCodable: Codable, Equatable {
    let value: Any
    
    init<T>(_ value: T) {
        self.value = value
    }
    
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality for our use case
        String(describing: lhs.value) == String(describing: rhs.value)
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
