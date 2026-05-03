# VigilantEar 👂🛰️

**Effective Date:** May 1, 2026

**VigilantEar** is an iOS-based acoustic research and accessibility tool designed to provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community.

By leveraging on-device machine learning and advanced acoustic physics, the app acts as an "Air Traffic Control" radar for the street. It identifies emergency vehicles (sirens) and broadband mobile noise sources (tire roar/engines), tracking their movement through physical space using multi-target frequency isolation, Phase-Transform spatial mapping, and geographic sensor fusion.

## 🌟 Key Features
* **Multi-Target Tracker (MTT)**: Capable of isolating and tracking multiple independent acoustic targets simultaneously in a crowded environment, generating unique session IDs and trajectories for each vehicle.
* **Geographic Projection & Road Snapping**: Upgrades relative acoustic TDOA angles into absolute GPS world coordinates using Haversine math. Integrates with MapKit to snap fuzzy acoustic estimates directly onto the nearest physical road geometry for clean, realistic street tracking.
* **Tactical MapKit HUD**: A real-time, auto-following MapKit display plotting targets dynamically up to a 1,000-foot research horizon. Features visual perimeter anchors at 30ft (Green), 500ft (Yellow), and 1,000ft (Red).
* **Deep Acoustic Scanning**: The CoreML pipeline actively scans the top 5 confidence results to pull out the background broadband rumble of approaching vehicles hidden underneath environmental foreground noise.
* **Cloud Telemetry**: Live, real-time spatial and diagnostic telemetry streaming to Google Cloud Firestore for post-test GIS trajectory analysis, acoustic model tuning, and hardware debugging.
* **Weather Alerts**: Live, real-time alerts are updated on the screen every 15 minutes. It shows an outlined, shaded area on the map and an on-screen text notice.

## 🧬 The Physics & Math Engine
VigilantEar operates on a custom Digital Signal Processing (DSP) and geographic fusion foundation built natively in Swift:

* **GCC-PHAT Spatial Tracking**: Utilizes Generalized Cross-Correlation with Phase Transform to process massive stereo buffers (4096 frames). It calculates the Time Difference of Arrival (TDOA) between the top and bottom iPhone microphones to lock onto both tonal spikes and broadband white-noise with sub-millisecond precision.
* **Sensor Fusion Velocity**: Combines lagging geographic GPS math with instantaneous acoustic Doppler shifts via a Complementary Filter. This allows the predictive simulator to smoothly coast vehicle dots along their road vectors even if the acoustic signal is temporarily occluded by a building.
* **Hardware-Specific Calibration**: Automatically locks the `AVAudioSession` into raw spatial stereo and adjusts the geographic math based on the physical microphone baseline of the exact iPhone model running the code (e.g., 0.163m for iPhone 16 Pro Max).

## 🛠️ Tech Stack (2026)
* **Language:** Swift 6 (Strict Concurrency & Actor-isolated pipelines)
* **Frameworks:** SwiftUI, MapKit, Accelerate (vDSP), SoundAnalysis, AVFoundation, Firebase Firestore
* **Hardware Required:** iPhone 13 or newer. The app relies heavily on Apple Neural Engine (ANE) acceleration and built-in stereo microphone arrays. (Original development and baseline calibration targeted the iPhone 16 Pro Max).

## 📊 Research Goals & Data Privacy
* **Privacy by Design**: Audio buffers are processed entirely locally on-device in real-time. No raw audio recordings are ever uploaded, recorded, or stored on disc. No personally idetifiable information is *ever* transmitted off-device.
* **Data Availability**: In the future, mathematical trajectories (bearing, distance, ML labels/sound classifications, and confidence scores) will be securely transmitted to a cloud database for research and analysis purposes.
* **Exception Handling**: In rare instances, a sound classification type label (such as "thunderstorm") are transmitted to a cloud database to assist with application updates for unknown or recently added ML classifications.

## ⚖️ Disclaimer
* **Disclaimer**: VigilantEar is an experimental research and accessibility aid. It is *not* a certified life-saving device. Tracking accuracy may vary based on environmental factors, wind shear, multipath reflections (echoes), and hardware calibration. Use situational awareness at all times.
