import GoogleMaps

@main
struct VigilantEarApp: App {
    init() {
        // 1. Find the Keys.plist file
        if let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path),
           let apiKey = dict["GoogleMapsAPIKey"] as? String {
            
            // 2. Provide the key to Google Maps
            GMSServices.provideAPIKey(apiKey)
            print("Google Maps successfully initialized.")
        } else {
            print("Error: Keys.plist not found or API Key missing!")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
