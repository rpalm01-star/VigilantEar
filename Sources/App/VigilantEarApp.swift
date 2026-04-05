//
//  VigilantEarApp.swift
//  VigilantEar
//
//  Created by Robert Palmer on 4/5/26.
//


import SwiftUI
import GoogleMaps   // (if you want Maps later)

@main
struct VigilantEarApp: App {
    init() {
        GMSServices.provideAPIKey("AIzaSyDbOOoFp_JqjRbAm6OsgFiOc0c9zHLjksI")  // paste your real key
    }

    var body: some Scene {
        WindowGroup {
            ContentView()   // this is now your real one from Sources
        }
    }
}
