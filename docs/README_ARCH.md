# VigilantEar: Architectural Decision Records (ADR)

## 1. Service Decoupling (Mic vs. Permissions)
**Status:** Decoupled
**Decision:** `MicrophoneManager` and `PermissionsManager` remain separate entities.

### Rationale
* **Safety First:** iOS will terminate the process if `AVAudioEngine` attempts to tap a microphone before `AVCaptureDevice.requestAccess` is resolved. Separation ensures the "Gatekeeper" (Permissions) finishes before the "Engine" (Mic) ignites.
* **Testability:** Decoupling allows the `MockDataGenerator` to bypass hardware permissions entirely during UI testing.

---

## 2. Acoustic Analysis Pipeline
**Pattern:** Hardware Tap -> Buffer Analysis -> Main Thread Dispatch

### Physics Implementation
1. **Doppler Shift ($\Delta f$):** Calculated via FFT (Fast Fourier Transform) on the primary mono channel to detect relative velocity of motorcycles/sirens.


[Image of Doppler effect frequency shift diagram]


2. **TDOA ($\Delta t$):** Uses cross-correlation between Channel 0 (Top Mic) and Channel 1 (Bottom Mic) to determine the phase delay.


---

## 3. Data Flow & Observation
**Framework:** Swift 6 @Observable

* **Source of Truth:** All acoustic data originates in `MicrophoneManager`.
* **UI Binding:** `ContentView` observes the `estimatedAngle` and `currentDecibels` properties, ensuring a 120Hz refresh rate for the "Liquid Glass" arrow, optimized for the M4 GPU.

---
## 4. Recent Changes

Here is a summary of the systems architecture to make VigilantEar thread-safe and mathematically bulletproof:

The Systems Recap
The AGC Defeater (Rolling Noise Floor): We bypassed iOS's aggressive Automatic Gain Control by ditching hardcoded decibel thresholds. The app now maintains a rolling average of the ambient background noise and only triggers analysis when an acoustic event physically spikes above that shifting baseline.

GCC-PHAT Spatial Tracking: We upgraded the Time Difference of Arrival (TDOA) math. By implementing Generalized Cross-Correlation with Phase Transform (GCC-PHAT) via the Accelerate framework, the app now ignores multipath urban echoes and locks onto the true phase-alignment of the sound wave to determine the exact compass bearing.

FM Doppler Tracking: We rewrote the velocity math to outsmart the frequency-modulated (FM) "wail" of emergency sirens. The pipeline now tracks the mathematical center of the siren's frequency sweep over a 2-second rolling window to accurately calculate if the vehicle is approaching or receding.

Swift 6 Strict Concurrency Architecture: We broke the monolithic microphone manager into a three-stage pipeline. MicrophoneManager handles raw hardware. AcousticProcessingPipeline runs the intense DSP math on a heavily isolated background actor using safe C-pointers. AcousticCoordinator lives on the @MainActor and listens to an AsyncStream pipe to drive the SwiftUI radar at 60fps without dropping frames.
