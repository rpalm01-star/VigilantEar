# VigilantEar 👂🛰️

**VigilantEar** is an iOS-based acoustic research and accessibility tool designed to provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community. 

By leveraging machine learning and advanced acoustic physics, the app identifies high-decibel mobile noise sources—such as un-muffled motorcycles and emergency vehicles—and tracks their movement using Center-Frequency Doppler shifts and Phase-Transform spatial mapping.

## 🌟 Key Features
* **Tactical Radar View:** A real-time spatial display calibrated to a **30-foot research horizon**, providing visual distance markers at 7.5ft, 15ft, 22.5ft, and 30ft.
* **Heartbeat Data Pruning:** A dedicated 10Hz "Heartbeat" timer ensures the radar remains snappy by independently pruning stale acoustic events every 100ms.
* **High-Temporal Detection:** An optimized **0.9 overlap factor** allows the engine to track rapid, repeated events (like snaps or bell rings) without dropping detections.
* **Emergency Breach Haptics:** Automatic triggering of **CoreHaptics** alerts when a classified emergency vehicle (Siren/Ambulance/Fire) enters the 7.5ft inner safety ring.
* **Unique Event Tracking:** Every acoustic hit is assigned a unique UUID, allowing for overlapping "pulses" on the radar even if the sound type is identical.

## 🧬 The Physics Behind the App
VigilantEar operates on a custom Digital Signal Processing (DSP) foundation:
1. **GCC-PHAT Spatial Tracking:** Utilizes Generalized Cross-Correlation with Phase Transform to ignore urban multipath echoes and lock onto the true phase-alignment of sound waves.
2. **FM Doppler Velocity:** Tracks the mathematical center of a siren's frequency sweep over a 2-second rolling window to accurately calculate approach vs. recession velocity.
3. **Hardware-Specific Calibration:** Automatically adjusts TDOA math based on the physical microphone baseline of the specific iPhone model (e.g., **0.163m** for iPhone 16 Pro Max).

## 🛠️ Tech Stack (2026)
* **Language:** Swift 6 (Strict Concurrency & Actor-isolated pipelines)
* **Frameworks:** SwiftUI, Accelerate (vDSP), SoundAnalysis, CoreHaptics, SwiftData
* **Hardware Required:** iPhone 13 or newer configured for stereo capture (optimized for **iPhone 16 Pro Max**)

## 🚀 Getting Started
1. Clone the repository: `git clone https://github.com/rpalm01-star/VigilantEar.git`
2. Open the project in **Xcode 16+**.
3. Build & run on a physical device to enable the stereo microphone tap and ANE acceleration.

## 📊 Research Goals & Data Privacy
* **Privacy:** Audio buffers are processed entirely locally on-device. No raw audio recordings are uploaded or stored.
* **Data Availability:** Logged events can be exported via CSV for use in GIS (Geographic Information Systems) platforms.

## ⚖️ License & Disclaimer
**License:** Distributed under the **Apache License 2.0**.
**Disclaimer:** VigilantEar is an experimental research and accessibility aid. It is **not** a certified life-saving device. Accuracy may vary based on environmental factors and hardware calibration.
