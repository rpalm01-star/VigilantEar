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
