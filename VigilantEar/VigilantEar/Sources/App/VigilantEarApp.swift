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

    // Grab everything directly from your unified container
    private let deps = DependencyContainer.shared

    @State private var coordinator = AcousticCoordinator()
    
    // 2. Create the background pipeline
    let pipeline = AcousticProcessingPipeline()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isVerified {
                    ContentView()
                    // Use the managers from your DependencyContainer
                        .environment(deps.microphoneManager)
                        .environment(deps.classificationService)
                    // NEW: Inject the coordinator into the SwiftUI environment
                        .environment(coordinator)
                    // NEW: Wire the pipeline to the UI and Microphone once verified
                        .task {
                            // Tell the UI to start listening to the background math
                            coordinator.startListeningToPipeline(pipeline)
                            
                            // Hand the pipeline to the microphone manager so it can feed it
                            deps.microphoneManager.pipeline = pipeline
                        }
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
    }
}
