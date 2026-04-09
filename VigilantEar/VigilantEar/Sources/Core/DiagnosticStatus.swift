import SwiftUI

enum DiagnosticStatus: Equatable {
    case pending
    case running
    case passed
    case failed(reason: String)
}

struct DiagnosticStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    var status: DiagnosticStatus = .pending
}