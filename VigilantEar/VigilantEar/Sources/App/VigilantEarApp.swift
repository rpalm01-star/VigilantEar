import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        AppGlobals.currentDeviceID = UIDevice.current.identifierForVendor?.uuidString ?? "unset"
        Task {
            await CloudLogger.shared.purgeOldLogs()
        }
        return true
    }
}

@main
struct VigilantEarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @State private var isVerified = false
    @State private var verificationViewModel = StartupVerificationViewModel()
    
    @Environment(\.scenePhase) private var scenePhase
    
    // THE SINGLE SOURCE OF TRUTH
    private let deps = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            // Wrap the whole routing logic in a single Group
            Group {
                if isVerified {
                    ContentView()
                    // Pass exactly what the Container built into the environment
                        .environment(deps.microphoneManager)
                        .environment(deps.classificationService)
                        .environment(deps.acousticCoordinator)
                        .environment(deps.capAlertManager)
                    
                } else {
                    VStack(spacing: 0) {
                        StartupVerificationView(viewModel: verificationViewModel)
                    }
                    .background(Color(.systemGroupedBackground))
                    // --- THE AUTO-LAUNCH WATCHER ---
                    .onChange(of: verificationViewModel.isFinished) { _, isFinished in
                        if isFinished && verificationViewModel.allPassed {
                            // A tiny half-second delay gives the user a micro-burst of
                            // visual confirmation (seeing all green checks) before animating away.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    isVerified = true
                                }
                            }
                        }
                    }
                }
            }
            .defersSystemGestures(on: .all)
            .persistentSystemOverlays(.hidden)
        }
    }
}
