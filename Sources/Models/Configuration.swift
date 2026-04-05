import Foundation

// MARK: - VigilantEar Root Model
struct VigilantEarConfig: Codable {
    let projectMetadata: ProjectMetadata
    let configurations: [ConfigItem]
    let deviceStatus: DeviceStatus

    enum CodingKeys: String, CodingKey {
        case projectMetadata = "project_metadata"
        case configurations
        case deviceStatus = "device_status"
    }
}

struct ProjectMetadata: Codable {
    let appId: String
    let owner: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case owner, environment
    }
}

struct ConfigItem: Codable {
    let key: String
    let value: AnyCodable // Using a wrapper to handle mixed types (Float, Bool, String)
    let type: String
    let description: String
}

struct DeviceStatus: Codable {
    let lastSync: String
    let batteryLevel: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case lastSync = "last_sync"
        case batteryLevel = "battery_level"
        case status
    }
}
