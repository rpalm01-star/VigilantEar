# VigilantEar 👂🛰️

**VigilantEar** is an iOS-based acoustic research and accessibility tool designed to provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community.

By leveraging on-device machine learning and advanced acoustic physics, the app acts as an "Air Traffic Control" radar for the street. It identifies emergency vehicles (sirens) and broadband mobile noise sources (tire roar/engines), tracking their movement through physical space using multi-target frequency isolation, Phase-Transform spatial mapping, and geographic sensor fusion.

## 🌟 Key Features
* **Multi-Target Tracker (MTT)**: Capable of isolating and tracking multiple independent acoustic targets simultaneously in a crowded environment, generating unique session IDs and trajectories for each vehicle.
* **Geographic Projection & Road Snapping**: Upgrades relative acoustic TDOA angles into absolute GPS world coordinates using Haversine math. Integrates with MapKit to snap fuzzy acoustic estimates directly onto the nearest physical road geometry for clean, realistic street tracking.
* **Tactical MapKit HUD**: A real-time, auto-following MapKit display plotting targets dynamically up to a 1,000-foot research horizon. Features visual perimeter anchors at 30ft (Green), 500ft (Yellow), and 1,000ft (Red).
* **Deep Acoustic Scanning**: The CoreML pipeline actively scans the top 5 confidence results to pull out the background broadband rumble of approaching vehicles hidden underneath environmental foreground noise.
* **Cloud Telemetry**: Live, real-time spatial and diagnostic telemetry streaming to Google Cloud Firestore for post-test GIS trajectory analysis, acoustic model tuning, and hardware debugging.

## 🧬 The Physics & Math Engine
VigilantEar operates on a custom Digital Signal Processing (DSP) and geographic fusion foundation built natively in Swift:

* **GCC-PHAT Spatial Tracking**: Utilizes Generalized Cross-Correlation with Phase Transform to process massive stereo buffers (4096 frames). It calculates the Time Difference of Arrival (TDOA) between the top and bottom iPhone microphones to lock onto both tonal spikes and broadband white-noise with sub-millisecond precision.
* **Sensor Fusion Velocity**: Combines lagging geographic GPS math with instantaneous acoustic Doppler shifts via a Complementary Filter. This allows the predictive simulator to smoothly coast vehicle dots along their road vectors even if the acoustic signal is temporarily occluded by a building.
* **Hardware-Specific Calibration**: Automatically locks the `AVAudioSession` into raw spatial stereo and adjusts the geographic math based on the physical microphone baseline of the exact iPhone model running the code (e.g., 0.163m for iPhone 16 Pro Max).

## 🛠️ Tech Stack (2026)
* **Language:** Swift 6 (Strict Concurrency & Actor-isolated pipelines)
* **Frameworks:** SwiftUI, MapKit, Accelerate (vDSP), SoundAnalysis, AVFoundation, Firebase Firestore
* **Hardware Required:** iPhone 13 or newer. The app relies heavily on Apple Neural Engine (ANE) acceleration and built-in stereo microphone arrays. (Original development and baseline calibration targeted the iPhone 16 Pro Max).

## 🚀 Getting Started
1. Clone the repository: `git clone https://github.com/rpalm01-star/VigilantEar.git`
2. Open the project in Xcode 16+.
3. Supply your own `GoogleService-Info.plist` to enable Firebase telemetry logging.
4. Build & run on a **physical device**. (The simulator cannot process the required hardware-level `AVAudioEngine` stereo mic taps or CoreML spatial logic).

## 📊 Research Goals & Data Privacy
* **Privacy by Design**: Audio buffers are processed entirely locally on-device in real-time. No raw audio recordings are ever uploaded, recorded, or stored on disc.
* **Data Availability**: Only mathematical trajectories (bearing, distance, ML labels, confidence scores) are securely transmitted to your designated Firestore database for research and analysis purposes.

## ⚖️ License & Disclaimer
* **License**: Distributed under the Apache License 2.0.
* **Disclaimer**: VigilantEar is an experimental research and accessibility aid. It is *not* a certified life-saving device. Tracking accuracy may vary based on environmental factors, wind shear, multipath reflections (echoes), and hardware calibration. Use situational awareness at all times.
