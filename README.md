# VigilantEar 👂🛰️

* **VigilantEar** is an iOS-based acoustic research and accessibility tool designed to provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community.

By leveraging on-device machine learning and advanced acoustic physics, the app acts as an "Air Traffic Control" radar for the street. It identifies emergency vehicles (sirens) and broadband mobile noise sources (tire roar/engines), tracking their movement through physical space using multi-target frequency isolation and Phase-Transform spatial mapping.

## 🌟 Key Features
* **Multi-Target Tracker (MTT)**: Capable of isolating and tracking multiple independent acoustic targets simultaneously in a crowded environment, generating unique sessions and trajectories for each vehicle.

* **Tactical MapKit HUD**: A real-time, auto-following MapKit display plotting targets dynamically up to a 1,000-foot research horizon. Features visual perimeter anchors at 30ft (Green), 500ft (Yellow), and 1,000ft (Red).

* **Deep Acoustic Scannin*g*: The CoreML pipeline doesn't just listen to the loudest foreground sound. It actively scans the top 5 confidence results to pull out the background broadband rumble of approaching vehicles hidden underneath environmental noise.

* **Dynamic Volume Gating**: Automatically lowers amplitude thresholds for broadband sounds (like tire wash) while maintaining strict gates for tonal sounds (like music or voices).

* **Cloud Telemetry**: Live, real-time spatial and diagnostic telemetry streaming to Google Cloud Firestore for post-test GIS trajectory analysis and debugging.

## 🧬 The Physics Behind the App
VigilantEar operates on a custom Digital Signal Processing (DSP) foundation built natively in Swift:

* **GCC-PHAT Spatial Tracking**: Utilizes Generalized Cross-Correlation with Phase Transform to process massive stereo buffers (4096 frames). It calculates Time Difference of Arrival (TDOA) to lock onto both tonal spikes and broadband white-noise with sub-millisecond precision.

* **Independent FM Dopple*r*: Every spawned target possesses its own independent 40-frame Doppler tracker, calculating specific approach vs. recession velocities simultaneously.

* **Hardware-Specific Calibration**: Automatically adjusts the spatial math based on the physical microphone baseline of the exact iPhone model running the code (e.g., 0.163m for iPhone 16 Pro Max).

## 🛠️ Tech Stack (2026)
Language: Swift 6 (Strict Concurrency & Actor-isolated pipelines)

Frameworks: SwiftUI, MapKit, Accelerate (vDSP), SoundAnalysis, Firebase Firestore

Hardware Required: iPhone 13 or newer configured for stereo capture (original development for iPhone 16 Pro Max)

## 🚀 Getting Started
Clone the repository: git clone https://github.com/rpalm01-star/VigilantEar.git

Open the project in Xcode 16+.

Supply your own GoogleService-Info.plist for Firebase logging.

Build & run on a physical device to enable the stereo microphone tap and ANE (Apple Neural Engine) acceleration.

## 📊 Research Goals & Data Privacy
* **Privacy**: Audio buffers are processed entirely locally on-device in real-time. No raw audio recordings are ever uploaded, recorded, or stored.

* **Data Availability**: Only mathematical trajectories (bearing, distance, ML labels) are securely transmitted to your designated Firestore database for research use.

## ⚖️ License & Disclaimer
* **License**: Distributed under the Apache License 2.0.
* **Disclaimer**: VigilantEar is an experimental research and accessibility aid. It is not a certified life-saving device. Accuracy may vary based on environmental factors, wind shear, multipath reflections, and hardware calibration.
