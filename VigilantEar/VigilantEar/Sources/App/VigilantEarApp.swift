import SwiftUI
import GoogleMaps
import SwiftData

@main
struct VigilantEarApp: App {
    @State private var isVerified = false
    @State private var verificationViewModel = StartupVerificationViewModel()
    
    @Environment(\.scenePhase) private var scenePhase
    
    // Grab everything directly from your unified container
    private let deps = DependencyContainer.shared
    
    init() {
        // Only Google Maps needs to be configured here now
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String, !apiKey.isEmpty {
            GMSServices.provideAPIKey(apiKey)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isVerified {
                    ContentView()
                    // Use the managers from your DependencyContainer
                        .environment(deps.microphoneManager)
                        .environment(deps.classificationService)
                } else {
                    VStack(spacing: 0) {
                        StartupVerificationView(viewModel: verificationViewModel)
                        
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
                            .padding(.bottom, 20)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .defersSystemGestures(on: .all)
            .persistentSystemOverlays(.hidden)
        }
        // Attach the database from your DependencyContainer
        .modelContainer(deps.sharedModelContainer)
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                // 1. Request a formal background execution lease from the OS
                var bgTask: UIBackgroundTaskIdentifier = .invalid
                bgTask = UIApplication.shared.beginBackgroundTask(withName: "FlushAcousticQueue") {
                    // Expiration handler if we take too long (iOS gives us ~30 seconds)
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
                
                let queueManager = EventQueueManager(container: deps.sharedModelContainer)
                Task {
                    // 2. Safely run the file write
                    await queueManager.flushQueue()
                    
                    // 3. Explicitly tell the OS we are done and it can safely suspend the app
                    UIApplication.shared.endBackgroundTask(bgTask)
                    bgTask = .invalid
                }
            }
        }
    }
}
