import SwiftUI
import GoogleMaps

@main
struct VigilantEarApp: App {
    @State private var audioManager: MicrophoneManager
    @State private var isVerified = false
    @State private var verificationViewModel = StartupVerificationViewModel()
    
    private let classificationService = DependencyContainer.shared.classificationService
    
    init() {
        let manager = MicrophoneManager(
            coordinator: DependencyContainer.shared.acousticCoordinator,
            classificationService: DependencyContainer.shared.classificationService
        )
        _audioManager = State(initialValue: manager)
        
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String, !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if isVerified {
                ContentView()
                    .environment(audioManager)
                    .environment(classificationService)
            } else {
                // Wrap in a VStack to stack the view and button vertically
                VStack(spacing: 0) {
                    StartupVerificationView(viewModel: verificationViewModel)
                    
                    // Only show the button area if diagnostics are finished
                    if verificationViewModel.isFinished {
                        Button(action: {
                            withAnimation(.spring()) {
                                isVerified = true
                            }
                        }) {
                            Text("Begin Monitoring")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20) // Proper padding from the bottom edge
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .background(Color(.systemGroupedBackground)) // Optional: matches list style
            }
        }
    }
}
