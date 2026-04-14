# ⚡ Adhunik Yantra — Smart Distribution Board Monitoring and automated fault detection system

<p align="center">
  <img src="https://img.shields.io/badge/Platform-ESP32-blue?style=for-the-badge&logo=espressif" />
  <img src="https://img.shields.io/badge/App-Flutter-02569B?style=for-the-badge&logo=flutter" />
  <img src="https://img.shields.io/badge/Cloud-Firebase-FFCA28?style=for-the-badge&logo=firebase" />
  <img src="https://img.shields.io/badge/AI-Groq%20LLaMA-FF6B35?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Hackathon-HACKSAGON%202025%20Finalist-gold?style=for-the-badge" />
</p>

> 🏆 **HACKSAGON 2025-26 Finalist** — ABV-IIITM Gwalior  
> Built by **Ayush Joshi Thayyil**, **Aryan Patel**, **Anshuman Upadhyay** and **Rishav Kumar**
> 
> **APK DOWNLOAD LINK ->https://drive.google.com/file/d/1P2wZZLrQBbzXlT1FVmcOAoikv8oMyUHn/view?usp=sharing**

---

## 📖 Table of Contents

- [Overview](#-overview)
- [The Problem](#-the-problem)
- [Key Features](#-key-features)
- [System Architecture](#-system-architecture)
- [Hardware Components](#-hardware-components)
- [Firmware (ESP32)](#-firmware-esp32)
- [Flutter Mobile App](#-flutter-mobile-app)
- [Firebase Integration](#-firebase-integration)
- [Circuit Analyzer](#-circuit-analyzer)
- [Energy Coach (EWMA)](#-energy-coach-ewma)
- [Motor Health & Predictive Maintenance](#-motor-health--predictive-maintenance)
- [Fault Detection Engine](#-fault-detection-engine)
- [Offline Mode & Data Caching](#-offline-mode--data-caching)
- [SMS Alerts via Twilio](#-sms-alerts-via-twilio)
- [Getting Started](#-getting-started)
- [Project Structure](#-project-structure)
- [Tech Stack](#-tech-stack)
- [Team](#-team)

---

## 🌟 Overview

**Adhunik Yantra** is an end-to-end smart electrical distribution board monitoring system designed to bring intelligence to the most neglected part of every home — the fuse box.

Most homes have no visibility into what's happening inside their distribution board. Adhunik Yantra changes that by combining real-time sensor monitoring, AI-powered circuit analysis, intelligent fault detection, energy coaching, and predictive motor health monitoring — all in a single system built from hardware up.

The system consists of three layers:
1. **Hardware Node** — ESP32 + ADS1115 sensing voltage, current, and leakage in real time
2. **Cloud Backend** — Firebase Realtime Database for live sync, relay control, and fault state
3. **Flutter Mobile App** — Full-featured dashboard with charts, controls, AI analysis, and alerts

---

## 🔍 The Problem

- Homeowners have **zero visibility** into what's happening in their distribution board
- Circuit schedule diagrams (the sticker inside your fuse box) are full of codes and symbols that nobody explains
- Electrical faults like earth leakage or overcurrent are discovered only **after** something trips or burns
- Energy wastage is invisible — devices left on overnight, abnormal consumption patterns go completely unnoticed
- Motor failures (pumps, ACs, compressors) are unpredictable, leading to expensive emergency repairs
- No low-cost solution exists that covers monitoring, protection, cloud sync, and AI analysis together

---

## 🚀 Key Features

| Feature | Description |
|---|---|
| ⚡ Real-time Monitoring | Live voltage, current, power, and energy across 2 circuits |
| 🚨 Fault Detection & Auto-Trip | Overcurrent, overvoltage, undervoltage, earth leakage, short circuit |
| 📱 Flutter App | Live dashboard, charts, relay control, energy tracking |
| 🔌 Offline Mode | LittleFS cache on ESP32, auto-sync on reconnect |
| 🧠 Circuit Analyzer | OCR + Groq LLaMA AI explains your home's wiring in plain language |
| 📊 Energy Coach (EWMA) | Detects abnormal energy patterns, prevents wastage |
| ⚙️ Motor Health Monitoring | Tracks current signatures to predict device failure |
| 📲 SMS Alerts | Twilio SMS sent on every fault detection |
| 🔔 Push Notifications | Twilio for real-time mobile alerts |
| 🧪 Test Mode | Remote fault simulation via Firebase for demo/testing |

---

## 🏗 System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        HARDWARE LAYER                        │
│                                                             │
│  ZMPT101B ──┐                                               │
│  ZMCT103C ──┼──► ADS1115 (I2C) ──► ESP32 ──► TFT Display   │
│  CT Clamp ──┘          │                │                   │
│                        │           Relay Module             │
│                   GPIO 21/22      (Circuit Trip)            │
│                        │                │                   │
│                   Buzzer (GPIO32)   LittleFS Cache          │
└────────────────────────┼────────────────┼───────────────────┘
                         │                │
                    WiFi / HTTPS     Offline Cache
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    FIREBASE RTDB (Cloud)                     │
│                                                             │
│  /device_001/readings/    ← sensor data pushed every 1s    │
│  /device_001/relay/       ← relay commands pulled (stream)  │
│  /device_001/commands/    ← test_fault commands             │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    FLUTTER MOBILE APP                        │
│                                                             │
│  Dashboard ──► Live Charts ──► Relay Control               │
│  Energy Tracker ──► Cost Calculator                        │
│  Circuit Analyzer ──► ML Kit OCR ──► Groq LLaMA AI        │
│  Motor Health ──► EWMA Engine ──► Push Notifications       │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 Hardware Components

| Component | Model | Purpose |
|---|---|---|
| Microcontroller | ESP32 (38-pin) | Main processor, WiFi, GPIO |
| ADC | ADS1115 (16-bit, 4-ch) | Precision analog-to-digital conversion |
| Voltage Sensor | ZMPT101B | AC mains voltage measurement |
| Current Sensor 1 | ZMCT103C | Heavy circuit current (Circuit 1) |
| Current Sensor 2 | CT Clamp | Light circuit current (Circuit 2) |
| Neutral Monitor | CT Clamp | Neutral current for leakage calculation |
| Display | TFT ILI9341 (320×240) | Local live display |
| Relay Module | 2-channel 5V relay | Circuit isolation on fault |
| Buzzer | Active buzzer (GPIO 32) | Audible fault alerts |
| Power Supply | HLK-5M05 | Mains to 5V for ESP32 |
| Buck Converter | MP1584EN | 5V to 3.3V regulation |

### Wiring Summary

```
ESP32 GPIO 21 (SDA) ──► ADS1115 SDA
ESP32 GPIO 22 (SCL) ──► ADS1115 SCL
ADS1115 CH0           ──► ZMPT101B (Voltage)
ADS1115 CH1           ──► ZMCT103C (Current 1)
ADS1115 CH2           ──► CT Clamp (Current 2)
ADS1115 CH3           ──► CT Clamp (Neutral)
ESP32 GPIO 26         ──► Relay IN1 (Circuit 2)
ESP32 GPIO 27         ──► Relay IN2 (Circuit 1)
ESP32 GPIO 32         ──► Buzzer
```

---

## 💾 Firmware (ESP32)

### Sensor Reading — RMS Measurement

The firmware reads AC signals using RMS (Root Mean Square) calculation over a 20ms window (one full 50Hz cycle). This gives accurate true RMS values even for non-sinusoidal loads.


```

The auto DC offset removal ensures accurate readings regardless of sensor bias drift — no manual calibration needed after initial setup.

### Calibration Constants

```cpp
float CAL_VOLTAGE = 0.711f;   // Voltage channel scaling
float CAL_CURR_1  = 1.204f;   // ZMCT103C scaling
float CAL_CURR_2  = 0.127f;   // CT Clamp scaling
float CAL_CURR_3  = 1.26f;    // Neutral CT scaling
```

These were derived experimentally against a calibrated reference meter. Earth leakage is computed as:

```cpp
g_leakageMA = fabsf(g_current1 - g_currentNeut) * 1000.0f;
```

### Startup Stabilization

The first 10 seconds after boot are ignored for fault detection to prevent false triggers during sensor warm-up:

```cpp
#define STARTUP_STABILIZE_MS 10000

if (millis() - startupTime < STARTUP_STABILIZE_MS) {
  detectedFault = "normal";
  g_leakageMA = 0.0f;
}
```

### Buzzer Fault Patterns

Each fault type has a distinct buzzer pattern so the sound alone identifies the fault:

| Fault | Pattern | Frequency |
|---|---|---|
| Overvoltage | 3 short beeps, 1s pause | 2000 Hz |
| Undervoltage | 2 slow beeps, 1.5s pause | 1000 Hz |
| Overcurrent | 4 medium beeps, 0.8s pause | 1500 Hz |
| Earth Leakage | 5 rapid beeps, 0.5s pause | 2500 Hz |
| Short Circuit | 10 very fast beeps, 0.2s pause | 3000 Hz |

---

## 📱 Flutter Mobile App

The mobile app is built with Flutter and connects to Firebase RTDB for live data streaming.

### Screens

- **Dashboard** — Live gauges for voltage, current, power, and energy cost
- **Live Charts** — Real-time fl_chart graphs for current waveform per circuit
- **Relay Control** — Toggle Circuit 1 and Circuit 2 with one tap
- **Energy Tracker** — kWh consumption, cost in ₹ (configurable rate)
- **Circuit Analyzer** — OCR + AI explanation of circuit schedule diagrams
- **Motor Health** — EWMA-based deviation alerts and trend graphs
- **Fault History** — Log of past fault events with timestamps

### Key Dependencies

```yaml
dependencies:
  firebase_core: ^2.32.0
  firebase_database: ^10.5.7
  firebase_messaging: ^14.7.10
  fl_chart: ^0.66.2
  google_mlkit_text_recognition: ^0.15.1
  image_picker: any
  file_picker: ^8.3.7
  shared_preferences: any
  flutter_riverpod: ^2.6.1
  go_router: ^13.2.5
```

### Firebase Live Streaming

The app uses `onValue` streams from Firebase RTDB for zero-latency UI updates:

```dart
FirebaseDatabase.instance
  .ref('device_001/readings')
  .onValue
  .listen((event) {
    final data = event.snapshot.value as Map;
    // Update UI state
  });
```

---

## ☁️ Firebase Integration

### Realtime Database Structure

```
adhunikyantra-rtdb/
└── device_001/
    ├── readings/
    │   ├── voltage          (float)
    │   ├── current1         (float)
    │   ├── current2         (float)
    │   ├── currentNeutral   (float)
    │   ├── leakage_mA       (float)
    │   ├── power1           (float)
    │   ├── power2           (float)
    │   ├── totalPower       (float)
    │   ├── temperature      (float)
    │   ├── totalEnergy_kWh  (float)
    │   ├── circuit1Energy_kWh (float)
    │   ├── circuit2Energy_kWh (float)
    │   ├── totalCost        (float)
    │   ├── relay1_on        (bool)
    │   ├── relay2_on        (bool)
    │   ├── faultActive      (bool)
    │   ├── faultMessage     (string)
    │   └── timestamp        (int, millis)
    ├── relay/
    │   ├── circuit_1        (bool) ← app writes, ESP32 streams
    │   └── circuit_2        (bool)
    └── commands/
        └── test_fault       (string) ← for test mode
```

### Relay Control via Firebase Streams

The ESP32 opens persistent SSE streams to both relay paths and responds within ~200ms of a change:

```cpp
Firebase.RTDB.beginStream(&streamData1, "/device_001/relay/circuit_1");
Firebase.RTDB.beginStream(&streamData2, "/device_001/relay/circuit_2");
```

---

## 🧠 Circuit Analyzer

The Circuit Analyzer is the flagship AI feature — it makes home electrical diagrams understandable to anyone.

### How It Works

```
User Input (Photo / PDF / Manual Text)
         │
         ▼
  Google ML Kit OCR
  (On-device, no internet needed)
         │
         ▼
  Extracted raw circuit schedule text
         │
         ▼
  Groq LLaMA API (cloud)
  Prompt: "Explain this circuit schedule
           in simple terms for a homeowner"
         │
         ▼
  Plain-language breakdown
  (Which breaker controls what,
   load ratings, safety notes)
```

### Input Modes

1. **Camera** — Take a photo of the circuit schedule sticker/diagram
2. **Gallery** — Pick an existing photo from phone storage
3. **PDF** — Load a PDF electrical plan (extracted via pdf_render)
4. **Manual** — Type the circuit details directly

### Why Groq LLaMA?

During development we tested Anthropic Claude API and Gemini API before settling on Groq. Groq's free tier offered sufficient throughput for demo use without rate-limiting issues, and LLaMA's instruction-following was accurate for structured electrical text.

---

## 📊 Energy Coach (EWMA)

### What is EWMA?

**EWMA** — Exponentially Weighted Moving Average — is a statistical technique that computes a running average while giving **exponentially more weight to recent observations** than older ones. Unlike a simple moving average, EWMA adapts quickly to genuine trend changes while smoothing out random noise.

The formula is:

```
EWMAₜ = α × Xₜ + (1 - α) × EWMAₜ₋₁
```

Where:
- `Xₜ` = current power reading
- `α` = smoothing factor (0 < α < 1), typically 0.1–0.3
- A **lower α** = more smoothing, slower to react
- A **higher α** = reacts faster, less smoothing

### How Adhunik Yantra Uses EWMA

The Energy Coach continuously computes an EWMA baseline of your home's power consumption. When the current reading deviates significantly from the EWMA baseline (beyond a configurable threshold), it flags it as abnormal behaviour.

**Examples of what it catches:**
- A heater or iron left ON overnight — power doesn't drop to idle as expected
- A sudden unexplained load appearing after midnight
- Gradual load creep over days (multiple devices accumulating standby draw)
- One circuit consuming significantly more than its historical average

This allows the system to **alert users before their electricity bill arrives**, not after.

---

## ⚙️ Motor Health & Predictive Maintenance

### The Problem with Motors

Electric motors (pumps, AC compressors, geysers, washing machines) degrade gradually before they fail catastrophically. Signs of degradation show up in their **current draw signature** long before any physical symptom is visible:

- A failing motor draws **more current than normal** as winding resistance increases
- Bearing wear causes **erratic current spikes** that don't appear in healthy motors
- Impending short-circuit failures show a **gradual drift** in current baseline

### How Adhunik Yantra Detects This

By continuously monitoring the current waveform and comparing it against the EWMA-learned baseline, the system detects:

| Symptom | What it means |
|---|---|
| Rising EWMA baseline for a circuit | Motor drawing more power over time → winding degradation |
| Sudden current spikes above 3σ threshold | Bearing fault or mechanical obstruction |
| Current drop with no load change | Motor losing efficiency → imminent failure |
| Asymmetric current between start and run | Capacitor fault in single-phase motors |

When a deviation crosses the threshold, the app sends a **predictive maintenance alert** — "Your pump motor is showing unusual current patterns. Check or service it before it fails."

This shifts maintenance from **reactive** (replace after failure) to **predictive** (fix before failure), saving both money and inconvenience.

---

## 🚨 Fault Detection Engine

### Thresholds

```cpp
#define OVERCURRENT_A   15.0f   // Trips relay immediately
#define OVERVOLTAGE_V  260.0f   // Trips relay immediately  
#define UNDERVOLTAGE_V 180.0f   // Warning only
#define LEAK_TRIP_MA    38.0f   // Earth leakage → relay trips (electrocution risk)
```

### Detection Priority

Faults are checked in priority order (most dangerous first):

```cpp
String detectFaults(float voltage, float current, float leakMA) {
  if (leakMA   >= LEAK_TRIP_MA)                    return "earth_leakage_critical";
  if (current  >= OVERCURRENT_A)                   return "overcurrent";
  if (voltage  >= OVERVOLTAGE_V)                   return "overvoltage";
  if (voltage  <= UNDERVOLTAGE_V && voltage > 10)  return "undervoltage";
  return "normal";
}
```

Earth leakage is checked first because even 30–50mA through a human body can cause cardiac arrest. The relay trips within one loop cycle (~50ms) of detection.

### Relay Trip Logic

Not all faults trip the relay — undervoltage is a warning (devices may be damaged but there's no fire/shock risk), while others require immediate isolation:

```cpp
bool shouldTripRelay(String fault) {
  return (fault == "overcurrent"           ||
          fault == "earth_leakage_critical" ||
          fault == "short_circuit");
}
```

---

## 📦 Offline Mode & Data Caching

A key design goal was that the device must continue working **without internet**. Adhunik Yantra achieves full offline operation:

| Function | Offline Behaviour |
|---|---|
| Sensor reading | ✅ Continues normally |
| Fault detection | ✅ Continues normally |
| Relay trip on fault | ✅ Continues normally |
| Buzzer alerts | ✅ Continues normally |
| TFT display | ✅ Continues normally |
| Energy tracking | ✅ Continues normally |
| Data logging | ✅ Cached to LittleFS |
| Firebase upload | ❌ Paused |
| Relay remote control | ❌ Paused (last state held) |

### LittleFS Cache

Up to 50 readings are stored in a circular buffer in LittleFS (flash filesystem on ESP32). The cache is flushed to disk every 5 seconds as a JSON file.

When WiFi reconnects, the latest cached reading is immediately synced to Firebase:

```cpp
void syncCachedReadings() {
  CachedReading &latest = cacheReadings[(cacheIndex - 1 + MAX_CACHE_READINGS) % MAX_CACHE_READINGS];
  // Push to Firebase RTDB
}
```

---

## 📲 SMS Alerts via Twilio

When a fault is detected and WiFi is available, the ESP32 directly makes an HTTPS POST request to the Twilio API and sends an SMS to the registered phone number.

```
🚨 Adhunik Yantra Alert!
Device: device_001
Fault: earth_leakage_critical
Voltage: 231.4V
Current: 0.82A
Time: 3847s
```

A **10-second debounce** prevents SMS spam if the fault condition fluctuates. The debounce resets only after the fault clears and reappears.

---

## 📁 Project Structure

```
adhunik-yantra/
│
├── firmware/
│   └── adhunik_yantra.ino          # Main ESP32 firmware
│
└── adhunikyantra/                  # Flutter app
    ├── lib/
    │   ├── main.dart
    │   ├── providers/
    │   │   ├── live_data_provider.dart     # Firebase stream provider
    │   │   └── fault_provider.dart         # Fault state management
    │   ├── screens/
    │   │   ├── dashboard_screen.dart       # Main live dashboard
    │   │   ├── circuit_analyzer_screen.dart # OCR + AI screen
    │   │   └── motor_health_screen.dart    # Predictive maintenance
    │   └── services/
    │       └── groq_service.dart           # LLaMA API calls
    ├── android/
    │   └── app/
    │       ├── build.gradle.kts
    │       └── proguard-rules.pro
    └── pubspec.yaml
```

---

## 🧰 Tech Stack

| Layer | Technology |
|---|---|
| **Microcontroller** | ESP32 (Xtensa LX6 dual-core, 240MHz) |
| **ADC** | ADS1115 16-bit via I2C |
| **Firmware Language** | C++ (Arduino framework) |
| **Local Storage** | LittleFS (ESP32 flash filesystem) |
| **Mobile App** | Flutter (Dart) |
| **State Management** | Riverpod |
| **Routing** | go_router |
| **Charts** | fl_chart |
| **Cloud Database** | Firebase Realtime Database |
| **Push Notifications** | Firebase Cloud Messaging + Twilio |
| **On-device OCR** | Google ML Kit Text Recognition |
| **AI Inference** | Groq API (LLaMA 3) |
| **SMS Alerts** | Twilio REST API |
| **Statistical Engine** | EWMA (custom implementation) |

---

## 👥 Team

| Name 
|---|
| **Ayush Joshi Thayyil** 
| **Aryan Patel** 
| **Rishav Kumar** 
| **Anshuman Upadhyay**



---

## 📄 License

This project is open-source and available under the [MIT License](LICENSE).

---

<p align="center">
  Made with ⚡ at ABV-IIITM Gwalior &nbsp;|&nbsp; HACKSAGON 2025-26 Finalist
</p>
