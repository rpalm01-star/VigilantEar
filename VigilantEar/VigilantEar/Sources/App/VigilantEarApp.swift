import SwiftUI
import SwiftData

// A test for git to push.
class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppGlobals.currentDeviceID = PersistentAttributesManager.shared.staticDeviceIdentifierFromKeychain
        AppGlobals.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let deviceLocale = Locale.current.identifier
        let appLanguage = Bundle.main.preferredLocalizations.first ?? "Unknown"
        CloudKitLogManager.log(step: "AppDelegate.application", message: "📱 Startup Language - System: \(deviceLocale), App: \(appLanguage)")
        return true
    }
}

@main
struct VigilantEarApp: App {
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @State private var isVerified = false
    @State private var verificationViewModel = StartupVerificationViewModel()
    @StateObject private var uiManager = UIManager()
    
    @Environment(\.scenePhase) private var scenePhase
    
    // THE SINGLE SOURCE OF TRUTH
    private let deps = DependencyContainer.shared
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isVerified {
                    ContentView()
                        .environment(deps.microphoneManager)
                        .environment(deps.acousticCoordinator)
                        .environment(deps.capAlertManager)
                        .environmentObject(uiManager)
                        .onAppear {
                            CloudKitLogManager.logInstallation()
                            deps.microphoneManager.startCapturing()
                            AppGlobals.doLog(message: "🚀 All verification passed — starting full backend", step: "VigilantEarApp")
                        }
                } else {
                    VStack(spacing: 0) {
                        StartupVerificationView(viewModel: verificationViewModel)
                    }
                    .background(Color(.systemGroupedBackground))
                    // Auto-advance when everything passed
                    .onChange(of: verificationViewModel.isFinished && verificationViewModel.allPassed) { oldValue, newValue in
                        if newValue {
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
            .onChange(of: scenePhase) { oldPhase, newPhase in
                switch newPhase {
                case .background:
                    if isVerified && DependencyContainer.shared.isAnyAlertEnabled() {
                        AppGlobals.doLog(message: "🔊 Not forcing microphone to sleep. At least one user alert is enabled", step: "VigilantEarApp")
                    } else if isVerified {
                        AppGlobals.doLog(message: "🔊 🔴 Sleeping microphone. All user alerts are disabled.", step: "VigilantEarApp")
                        deps.microphoneManager.stopCapturing()
                    }
                case .active:
                    if isVerified && !deps.microphoneManager.isListening {
                        AppGlobals.doLog(message: "🔊 ✅ App foregrounded — restarting microphone", step: "VigilantEarApp")
                        deps.microphoneManager.startCapturing()
                    }
                default:
                    break
                }
            }
        }
    }
}
