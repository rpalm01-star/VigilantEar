# 👂 VigilantEar: Audio Analysis Architecture

This document defines the real-time signal processing pipeline for the **VigilantEar** research application, optimized for the **Apple M4 Neural Engine**.

---

## 🏗️ The Three-Layer Processing Pipeline

### 1. Ingestion Layer (Hardware Interface)
* **Driver:** `AVAudioEngine`
* **Sampling:** 44.1kHz / 32-bit Float PCM.
* **Source:** Triple-microphone array (iPhone 13+ / M4 MacBook Air).
* **Mechanism:** An asynchronous `installTap` on Bus 0 captures raw 100ms buffers.

### 2. Analysis Layer (Digital Signal Processing)
The core physics of the app are calculated here before being dispatched to the UI.

#### A. Doppler Effect ($\Delta f$)
Used to determine if a noise source (Motorcycle/Siren) is approaching or receding.
* **Logic:** Fast Fourier Transform (FFT) identifies the "Peak Frequency."
* **Equation:**
    $$f = f_0 \left( \frac{v + v_r}{v + v_s} \right)$$
    *Where $v$ is the speed of sound, $v_r$ is the receiver velocity, and $v_s$ is the source velocity.*



[Image of Doppler effect frequency shift diagram]


#### B. Time Difference of Arrival (TDOA)
Used to calculate the **Angle of Arrival ($\theta$)** for directional guidance.
* **Logic:** Cross-correlation of the phase delay ($\Delta t$) between the Top and Bottom microphones.
* **Equation:**
    $$\theta = \arccos\left( \frac{v \cdot \Delta t}{d} \right)$$
    *Where $d$ is the distance between microphones and $v$ is the speed of sound.*



### 3. Classification Layer (Core ML)
* **Model:** `SoundAnalysis` framework utilizing a custom Core ML model.
* **Concurrency:** Processes buffers on a background `Task` to utilize the **M4 Neural Engine**, keeping the main thread free for 120Hz UI rendering.

---

## 📊 Technical Constraints

| Component | Target Latency | Accuracy Goal |
| :--- | :--- | :--- |
| **FFT Pitch Detection** | < 10ms | ± 5Hz |
| **TDOA Vectoring** | < 15ms | ± 10 Degrees |
| **ML Classification** | < 50ms | > 85% Confidence |

---

## 🛠️ Implementation
1.  **Initialize** `AVAudioEngine` in `MicrophoneManager.swift`.
2.  **Apply** the `Accelerate` framework for high-performance FFT math.
3.  **Bridge** the output to the `estimatedAngle` observable property for the "Liquid Glass" UI.
