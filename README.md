# VigilantEar 👂🛰️

**VigilantEar** is an iOS-based acoustic research and accessibility tool designed to monitor urban noise pollution and provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community. 

By leveraging machine learning and advanced acoustic physics, the app identifies high-decibel mobile noise sources—such as un-muffled motorcycles and emergency vehicles—and tracks their movement using Center-Frequency Doppler shifts and Phase-Transform spatial mapping.

## 🌟 Key Features
 * **Real-Time Sound Classification:** Uses Apple's SoundAnalysis to distinguish between motorcycles, sirens, and general city traffic with 0-1ms inference times on the Neural Engine.
 * **Echo-Resilient Directional Tracking:** Calculates the Angle of Arrival (AoA) using Generalized Cross-Correlation with Phase Transform (GCC-PHAT) to filter out urban multipath echoes across a calibrated stereo microphone array.
 * **Dynamic Range Adaptation:** Features a custom Rolling Noise Floor pipeline that actively defeats iOS Automatic Gain Control (AGC) to accurately trigger on volume deltas rather than static thresholds.
 * **Accessibility Alerts:** Provides distinct haptic feedback and visual cues via a real-time spatial Radar View to alert users of approaching high-volume vehicles.
 * **Background Operation:** Runs as an energy-efficient background service utilizing an `AsyncStream` actor pipeline and "Critical Alert" entitlements for safety-first notifications.
 * **Noise Pollution Mapping:** Automatically logs coordinates, time, and sound vectors to a local database for urban research and GIS mapping.

## 🛠️ Tech Stack (2026)
 * **Language:** Swift 6 (Strict Concurrency, Actor-isolated DSP pipelines)
 * **Frameworks:** SwiftUI, Accelerate (vDSP), SoundAnalysis, CoreLocation, CoreHaptics
 * **Mapping:** Google Maps SDK for iOS
 * **Database:** SwiftData 
 * **Minimum Requirements:** iOS 18.0+, iPhone with a 3-mic array configured for stereo capture (iPhone 13 or newer recommended)

## 🧬 The Physics Behind the App
VigilantEar operates on a custom Digital Signal Processing (DSP) foundation:
 1. **Frequency Modulated (FM) Doppler Tracking:** Rather than measuring frame-by-frame pitch, the pipeline tracks the mathematical center of a siren's frequency sweep over a 2-second rolling window to calculate true approach velocity (\(\Delta f\)).
 2. **TDOA (Time Difference of Arrival):** Utilizes `vDSP` to calculate the micro-second delay between the top and bottom microphones, extracting the exact spatial bearing (\(\theta\)) of the acoustic event.

## 🚀 Getting Started
### Prerequisites
 * **Xcode 16+**
 * A Mac (Apple Silicon M1-M5) or a Cloud Mac instance.
 * An Apple Developer account (for Background Mode and Critical Alert testing).

### Installation
 1. Clone the repository: `git clone https://github.com/rpalm01-star/VigilantEar.git`
 2. Open `Package.swift` in Xcode 16+ (or later).
 3. Enable **"Audio, AirPlay, and Picture in Picture"** background mode + Critical Alerts entitlement in your signing profile.
 4. Build & run on a physical iPhone 13+ running iOS 18+.

## 📊 Research Goals & Data Privacy
This project is intended for **Acoustic Pollution Research**.
 * **Privacy:** Audio buffers are processed entirely locally on-device. No raw audio recordings are uploaded or stored. Only metadata (timestamp, coordinate, classification, and vector) is logged to the local container.
 * **Data Availability:** Logged events can be exported via CSV for use in GIS (Geographic Information Systems) platforms.

## ⚖️ License & Disclaimer
**License:** Distributed under the **Apache License 2.0**. See `LICENSE` for more information.

**Disclaimer:** VigilantEar is an experimental research and accessibility aid. It is **not** a certified life-saving device and should not be relied upon exclusively for safety in traffic or emergency situations. Accuracy may vary based on extreme environmental factors (wind, heavy acoustic reflections) and iOS hardware calibration states.
