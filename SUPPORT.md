# VigilantEar Support 👂🛰️

Thank you for using **VigilantEar**. Our mission is to provide enhanced situational awareness through advanced acoustic event detection and real-time emergency alerts.

## Contact Us

If you are experiencing technical issues, have questions about alert accuracy, or would like to provide feedback, please reach us via email at:

**Email:** [vigilantear@wingdingssocial.com](mailto:vigilantear@wingdingssocial.com)

## Frequently Asked Questions

### How does VigilantEar work in the background?
VigilantEar listens only when you turn on monitoring. It runs efficiently in the background and sends vibrations or visual alerts when it detects important sounds.

### Does VigilantEar drain my battery?
No. VigilantEar uses very little battery. We optimized the app carefully so you can run it all day without worry.

Here is exactly how we keep battery use low:  
- We use efficient on-device machine learning models that need almost no power.  
- We stop listening automatically when the app isn't in the foreground if you turn off all alerts in the settings panel.
- We avoid almost all cloud data calls and keep processing on your phone.  
- We added smart throttling to reduce processing requirements.
- Our algorithms are precision math that run off the display thread and run only when needed.

### Why isn't the app detecting sirens?

Ensure that you have granted **Microphone** permissions in your phone Settings. VigilantEar requires active microphone access to process acoustic signatures. Also, ensure your device is not in "Silent Mode" if you want haptic feedback.

### How accurate are the weather alerts?

VigilantEar polls official government CAP (Common Alerting Protocol) feeds. Alerts are as accurate as the data provided by the National Weather Service and other international agencies. Location simulation or network delays may occasionally affect update frequency.

### Does the app work in the background?

Yes, VigilantEar is designed to monitor for critical acoustic events while in the background, provided the necessary permissions are enabled.

### What do the alert toggles control?

The five alert toggles in the **settings menu** control whether VigilantEar sends a notification alert to you when it detects matching sounds.  

These toggles only affect notifications sent while the app is in the background or not actively open. They do **not** affect on-screen alert display when the app is open and in the foreground.

The toggles are:  
- **Siren Alerts** — Emergency vehicle sirens (police, fire, ambulance, etc.)  
- **Alarms** — Smoke detector and fire alarms  
- **Knocks** — Door knocks and doorbells
- **Weather Alerts** — Severe weather warnings from official government sources  
- **People Alerts** — People closeby (in quiet environments)  

### How do I disable the microphone when the app is not in the foreground?

The app stops using the microphone completely in background mode when *all* alert toggles are turned off via the app's settings panel. It does not listen for or send background notifications when all toggles are disabled. When at least one alert is enabled the microphone is enabled for background sound collection.

### Why doesn't the app consistently detect *all* sounds?

Acute sounds like alarms and firetruck sirens are relatively easy for the sound ML processing engine to detect. Broadband sounds (like car engines or tires) are harder but we do an adequate (if imperfect) job of that considering the limited capabilities of the phone itself. Time Distance of Arrival (TDOA) algorithms are only so precise given the short distance between microphones.

---

*VigilantEar is an accessibility tool built with care. Please use it responsibly.* 

Made with ❤️ for the D/HH community and acoustic research.

© 2026 Wingdings, Inc.
All rights reserved
