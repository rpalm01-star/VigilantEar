import Foundation
import SwiftUI

struct BreadCrumb: Identifiable, Equatable {
    let id = UUID()
    let position: CGPoint
    let angle: Double
    let opacity: Double // Fades over time
    let timestamp: Date
}
