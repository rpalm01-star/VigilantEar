import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
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
            Group {
                if isVerified {
                    ContentView()
                    // Pass exactly what the Container built into the environment
                        .environment(deps.microphoneManager)
                        .environment(deps.classificationService)
                        .environment(deps.acousticCoordinator)
                    
                    // We deleted the .task block!
                    // The DependencyContainer already wired the pipeline together.
                    
                } else {
                    VStack(spacing: 0) {
                        StartupVerificationView(viewModel: verificationViewModel)
                        
                        if verificationViewModel.isFinished {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isVerified = true
                                }
                            }) {
                                Text("Launch Application")
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
    }
}
