# VigilantEar 👂🛰️

**VigilantEar** is an iOS-based acoustic research and accessibility tool designed to monitor urban noise pollution and provide real-time directional awareness for the deaf and hard-of-hearing (D/HH) community.

By leveraging machine learning and advanced acoustic physics, the app identifies high-decibel mobile noise sources—such as un-muffled motorcycles and emergency sirens—and tracks their movement using the Doppler effect and Time Difference of Arrival (TDOA) logic.

-----

## 🌟 Key Features

  - **Real-Time Sound Classification:** Uses Apple's `SoundAnalysis` and `Core ML` to distinguish between motorcycles, sirens, and general city traffic.
  - **Directional Tracking:** Guesses the heading of a moving sound source over a 5-second window using multi-microphone phase analysis.
  - **Noise Pollution Mapping:** Automatically logs coordinates, time, and sound vectors to a Google Maps interface for urban research.
  - **Accessibility Alerts:** Provides haptic feedback and visual cues to alert users of approaching high-volume vehicles.
  - **Background Operation:** Runs as a background service with "Critical Alert" entitlements for safety-first notifications.

## 🛠️ Tech Stack (2026)

  - **Language:** Swift 6.0+
  - **Frameworks:** SwiftUI, SoundAnalysis, Core ML
  - **Mapping:** Google Maps SDK for iOS
  - **Database:** SwiftData (for local event logging)
  - **Minimum Requirements:** iOS 18.0+, iPhone with 3-mic array (iPhone 13 or newer recommended)

## 🧬 The Physics Behind the App

VigilantEar utilizes two primary acoustic principles:

1.  **The Doppler Effect:** Measuring the frequency shift ($\Delta f$) to determine if a source is approaching or receding.
2.  **TDOA (Time Difference of Arrival):** Calculating the micro-second delay between the top and bottom microphones to estimate the **Angle of Arrival ($\theta$)**.

$$\Delta t = \frac{d \cdot \cos(\theta)}{v_s}$$

-----

## 🚀 Getting Started

### Prerequisites

  - **Xcode 26+**
  - A Mac (Apple Silicon M1-M5) or a Cloud Mac instance.
  - An Apple Developer account (for Background Mode and Critical Alert testing).

### Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/rpalm01-star/VigilantEar.git
    ```
2.  Open `Package.swift` in Xcode.
3.  Ensure the **"Audio, AirPlay, and Picture in Picture"** background mode is enabled in the *Signing & Capabilities* tab.
4.  Build & run on a physical iPhone (iOS 18+)

-----

## 📊 Research Goals & Data Privacy

This project is intended for **Acoustic Pollution Research**.

  - **Privacy:** Audio is processed locally on-device. No raw audio recordings are uploaded or stored. Only metadata (timestamp, coordinate, classification, and vector) is logged.
  - **Data Availability:** Logged events can be exported via CSV for use in GIS (Geographic Information Systems) mapping.

## ⚖️ License & Disclaimer

**License:** Distributed under the **Apache License 2.0**. See `LICENSE` for more information.

**Disclaimer:** VigilantEar is a research and accessibility aid. It is **not** a life-saving device and should not be relied upon exclusively for safety in traffic or emergency situations. Accuracy may vary based on environmental factors like wind, echoes (multipath), and hardware calibration.
