

#include <Wire.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <Adafruit_ADS1X15.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"
#include <SPIFFS.h>
#include <WiFiClientSecure.h>
#include <LittleFS.h>
#include <base64.h>





// ── WIFI & FIREBASE ──────────────────────────────────────────
#define WIFI_SSID      "Galaxy A35 5G A3C4"
#define WIFI_PASSWORD  " "
#define API_KEY        "  "
#define DATABASE_URL   "   "
#define DEVICE_ID      "device_001"
#define CACHE_FILE "/readings_cache.json"
#define MAX_CACHE_READINGS 50
#define WIFI_RECONNECT_INTERVAL 5000  // 5 seconds

// ── HARDWARE PINS ────────────────────────────────────────────
#define RELAY_IN1 26
#define RELAY_IN2 27

// ── ADS1115 CHANNELS ─────────────────────────────────────────
#define CH_VOLTAGE  0
#define CH_CURR_1   1
#define CH_CURR_2   2
#define CH_NEUTRAL  3

// ── CALIBRATION ──────────────────────────────────────────────
float CAL_VOLTAGE = 0.711f;
float CAL_CURR_1  = 1.234f;
float CAL_CURR_2  = 0.127f;
float CAL_CURR_3  = 1.26f;

// ── FAULT THRESHOLDS ─────────────────────────────────────────
#define OVERCURRENT_A   15.0f
#define OVERVOLTAGE_V  260.0f
#define UNDERVOLTAGE_V 180.0f
#define LEAK_TRIP_MA    38.0f

// ── OBJECTS ──────────────────────────────────────────────────
Adafruit_ADS1115 ads;
TFT_eSPI tft = TFT_eSPI();
FirebaseData fbdo;
FirebaseData streamData1, streamData2;
FirebaseAuth fbAuth;
FirebaseConfig fbConfig;

// ── TWILIO SMS CONFIG ───────────────────────────────────
#define TWILIO_ACCOUNT_SID "AC5f3ca472c58d555dfb179d0581b6fef1"  // ← Your Account SID
#define TWILIO_AUTH_TOKEN  "83b7a4041eb25d1055750f346272ba06"    // ← Your Auth Token
#define TWILIO_PHONE       "+16623986991"  // ← Your Twilio number
#define YOUR_PHONE         "+919810732385"  // ← Your verified personal phone

// ── ALERT SETTINGS ───────────────────────────────────────
#define SEND_SMS_ON_FAULT true   // Set to false to disable SMS
#define SMS_DEBOUNCE_MS 10000   // 5 minutes between SMS (prevent spam)



// ── GLOBAL SENSOR READINGS ───────────────────────────────────
// FIX: these MUST be global so setTestFaultValues() can access them
float g_voltage     = 230.0f;
float g_current1    = 0.0f;
float g_current2    = 0.0f;
float g_currentNeut = 0.0f;
float g_leakageMA   = 0.0f;
float g_temperature = 28.5f;

// ── GLOBAL FAULT STATE ───────────────────────────────────────

bool   faultActive = false;
String faultType   = "normal";

// ── RELAY STATE ──────────────────────────────────────────────
bool relay1State = true;
bool relay2State = true;

// ── ENERGY TRACKING ──────────────────────────────────────────
float totalEnergykWh    = 0.0f;
float circuit1EnergykWh = 0.0f;
float circuit2EnergykWh = 0.0f;
unsigned long lastEnergyUpdate = 0;
const float COST_PER_UNIT = 8.5f;

// ── FIREBASE STATE ───────────────────────────────────────────
bool firebaseConnected   = false;
unsigned long lastFirebaseSend = 0;
#define FIREBASE_SEND_MS 1000

// ── TEST MODE STATE ──────────────────────────────────────────
bool   testMode          = false;
String testFaultType     = "normal";
float  testVoltage       = 0.0f;
float  testCurrentHeavy  = 0.0f;
float  testCurrentLight  = 0.0f;
unsigned long testModeStartTime = 0;

//sms debounce
unsigned long lastSMSSent = 0;


// ── GRAPH VARIABLES ──────────────────────────────────────────
int   xPos        = 0;
int   prevY1      = 220;
int   prevY2      = 220;
float maxGraphAmps = 10.0f;
bool wifiConnected = false;
unsigned long lastWiFiCheck = 0;
unsigned long lastCacheWrite = 0;
#define CACHE_WRITE_INTERVAL 5000  // Cache every 5 seconds

// ── CACHE STRUCTURE (DEFINE BEFORE USE!) ───────────────────
struct CachedReading {
  unsigned long timestamp;
  float voltage;
  float current1;
  float current2;
  float power1;
  float power2;
  float totalPower;
  float leakage_mA;
  bool relay1_on;
  bool relay2_on;
};

// Cache variables (NOW the struct is defined, so this works!)
CachedReading cacheReadings[MAX_CACHE_READINGS];
int cacheIndex = 0;



// ── LEAKAGE DEBOUNCE ───────────────────────────────────
unsigned long lastLeakageCheck = 0;
float leakageAccumulator = 0.0f;  // Smooth leakage reading
#define LEAKAGE_SMOOTH_FACTOR 0.1f  // 10% new, 90% old
#define LEAKAGE_DEBOUNCE_MS 2000    // 2 seconds stable before trip





// ════════════════════════════════════════════════════════════
//   TEMPERATURE
// ════════════════════════════════════════════════════════════
float generateFakeTemperature() {
  static float baseTemp = 28.5f;
  static unsigned long lastChange = 0;
  if (millis() - lastChange >= 10000) {
    lastChange = millis();
    float variation = (random(100) / 100.0f) - 0.5f;
    baseTemp += variation;
    baseTemp = constrain(baseTemp, 25.0f, 35.0f);
  }
  return baseTemp + ((random(20) / 100.0f) - 0.1f);
}

// ════════════════════════════════════════════════════════════
//  RELAY CONTROL
// ════════════════════════════════════════════════════════════
void setRelay1(bool on) {
  digitalWrite(RELAY_IN2, on ? LOW : HIGH);
  relay1State = on;
  Serial.printf(">>> R1: %s\n", on ? "ON" : "OFF");
  if (firebaseConnected && Firebase.ready())
    Firebase.RTDB.setBool(&fbdo, ("/" + String(DEVICE_ID) + "/readings/relay1_on").c_str(), on);
}

void setRelay2(bool on) {
  digitalWrite(RELAY_IN1, on ? LOW : HIGH);
  relay2State = on;
  Serial.printf(">>> R2: %s\n", on ? "ON" : "OFF");
  if (firebaseConnected && Firebase.ready())
    Firebase.RTDB.setBool(&fbdo, ("/" + String(DEVICE_ID) + "/readings/relay2_on").c_str(), on);
}

// ── Trip and reset helpers ────────────────────────────────────
void tripRelay() {
  // ✅ Physically turn OFF both relays (HIGH = OFF for most relay modules)
  digitalWrite(RELAY_IN1, HIGH);  // Trip relay 1
  digitalWrite(RELAY_IN2, HIGH);  // Trip relay 2
  
  // Update state variables
  relay1State = false;
  relay2State = false;
  
  Serial.println("[FAULT] Relay tripped for safety");
  
  // Optional: Also update Firebase if online (but trip happens regardless)
  if (firebaseConnected && Firebase.ready()) {
    Firebase.RTDB.setBool(&fbdo, ("/" + String(DEVICE_ID) + "/readings/relay1_on").c_str(), false);
    Firebase.RTDB.setBool(&fbdo, ("/" + String(DEVICE_ID) + "/readings/relay2_on").c_str(), false);
  }
}
bool shouldTripRelay(String fault) {
   return (fault == "overcurrent"           ||  // Wire fire risk
          fault == "earth_leakage_critical"||  // Electrocution risk  
          fault == "short_circuit"         ||  // Arc flash risk
          fault == "overvoltage"           ||  // Appliance destruction
          fault == "undervoltage");  
}

// ════════════════════════════════════════════════════════════
//  FIREBASE STREAMS
// ════════════════════════════════════════════════════════════
void initRelayStreams() {
  String p1 = "/" + String(DEVICE_ID) + "/relay/circuit_1";
  String p2 = "/" + String(DEVICE_ID) + "/relay/circuit_2";
  if (Firebase.RTDB.beginStream(&streamData1, p1.c_str()))
    Serial.println("[STREAM] C1: " + p1);
  if (Firebase.RTDB.beginStream(&streamData2, p2.c_str()))
    Serial.println("[STREAM] C2: " + p2);
}

// ════════════════════════════════════════════════════════════
//  RELAY CONTROL (WORKS OFFLINE)
// ════════════════════════════════════════════════════════════
void checkRelayStreams() {
  // Relay control via Firebase (only when online)
  if (!firebaseConnected || !Firebase.ready()) {
    // When offline, relay stays in last known state
    // Local control can be added here (buttons, etc.)
    return;
  }
  
  if (Firebase.RTDB.readStream(&streamData1) && streamData1.streamAvailable()) {
    if (streamData1.dataTypeEnum() == fb_esp_rtdb_data_type_boolean) {
      bool state = streamData1.boolData();
      digitalWrite(RELAY_IN2, state ? LOW : HIGH);
      relay1State = state;
      Serial.printf("[STREAM] R1: %s\n", state ? "ON" : "OFF");
    }
  }
  
  if (Firebase.RTDB.readStream(&streamData2) && streamData2.streamAvailable()) {
    if (streamData2.dataTypeEnum() == fb_esp_rtdb_data_type_boolean) {
      bool state = streamData2.boolData();
      digitalWrite(RELAY_IN1, state ? LOW : HIGH);
      relay2State = state;
      Serial.printf("[STREAM] R2: %s\n", state ? "ON" : "OFF");
    }
  }
  
  if (!streamData1.httpConnected() || !streamData2.httpConnected()) {
    initRelayStreams();
  }
}

// ════════════════════════════════════════════════════════════
//  FAULT DETECTION
// ════════════════════════════════════════════════════════════
String detectFaults(float voltage, float current, float leakMA) {
  if (leakMA   >= LEAK_TRIP_MA)                    return "earth_leakage_critical";
  if (current  >= OVERCURRENT_A)                   return "overcurrent";
  if (voltage  >= OVERVOLTAGE_V)                   return "overvoltage";
  if (voltage  <= UNDERVOLTAGE_V && voltage > 10)  return "undervoltage";
  return "normal";
}

// ════════════════════════════════════════════════════════════
//  DISPLAY FUNCTIONS
// ════════════════════════════════════════════════════════════
void drawAttractiveDisplay(float voltage, float current1, float current2, float temp) {
  static unsigned long lastDraw = 0;
  if (millis() - lastDraw < 50) return;
  lastDraw = millis();

  float power1     = voltage * current1;
  float power2     = voltage * current2;
  float totalPower = power1 + power2;

  tft.fillRect(0, 36, 320, 200, TFT_BLACK);

  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(10, 40);
  tft.print("ADHUNIK YANTRA");

  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.setTextSize(3);
  tft.setCursor(10, 70);
  tft.print(voltage, 1);
  tft.setTextSize(2);
  tft.print(" V");

  tft.setTextColor(TFT_ORANGE, TFT_BLACK);
  tft.setCursor(180, 70);
  tft.print(temp, 1);
  tft.print("C");

  // Circuit 1
  tft.drawRect(5, 105, 150, 80, TFT_GREEN);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(15, 115); tft.print("Circuit 1");
  tft.setCursor(15, 140); tft.print("I: "); tft.print(current1, 2); tft.print(" A");
  tft.setCursor(15, 165); tft.print("P: "); tft.print(power1,   1); tft.print(" W");

  // Circuit 2
  tft.drawRect(165, 105, 150, 80, TFT_CYAN);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  tft.setCursor(175, 115); tft.print("Circuit 2");
  tft.setCursor(175, 140); tft.print("I: "); tft.print(current2, 2); tft.print(" A");
  tft.setCursor(175, 165); tft.print("P: "); tft.print(power2,   1); tft.print(" W");

  tft.setTextColor(TFT_MAGENTA, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(80, 210);
  tft.print("Total: "); tft.print(totalPower, 1); tft.print(" W");

  // Live graph
  tft.drawLine(0, 235, 320, 235, TFT_DARKGREY);
  int yPos1 = 235 - (int)((current1 / maxGraphAmps) * 40);
  int yPos2 = 235 - (int)((current2 / maxGraphAmps) * 40);
  if (xPos > 0) {
    tft.drawPixel(xPos - 1, prevY1, TFT_GREEN);
    tft.drawPixel(xPos - 1, prevY2, TFT_CYAN);
  }
  prevY1 = yPos1;
  prevY2 = yPos2;
  xPos = (xPos + 1) % 320;
  if (xPos == 0) tft.fillRect(0, 236, 320, 4, TFT_BLACK);
}

void displayFault(String fault, float voltage, float current) {
  tft.fillScreen(TFT_RED);
  tft.fillRect(10, 10, 300, 220, TFT_BLACK);

  tft.setTextColor(TFT_RED, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(50, 30);
  tft.print("!! FAULT DETECTED !!");

  tft.setTextSize(3);
  tft.setCursor(20, 70);
  if      (fault == "overvoltage")           tft.print("OVERVOLTAGE");
  else if (fault == "undervoltage")          tft.print("UNDERVOLTAGE");
  else if (fault == "overcurrent")           tft.print("OVERCURRENT");
  else if (fault == "earth_leakage_critical")tft.print("EARTH LEAKAGE");
  else if (fault == "short_circuit")         tft.print("SHORT CIRCUIT");
  else                                       tft.print("FAULT");

  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.setCursor(20, 130);
  tft.print("V: "); tft.print(voltage, 1); tft.print(" V");
  tft.setCursor(20, 160);
  tft.print("I: "); tft.print(current, 2); tft.print(" A");

  tft.setTextColor(TFT_RED, TFT_BLACK);
  tft.setCursor(50, 200);
  tft.print("RELAY TRIPPED!");
}

// ════════════════════════════════════════════════════════════
//  TEST MODE DISPLAY
// ════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════
//  TEST MODE DISPLAY (ATTRACTIVE VERSION)
// ════════════════════════════════════════════════════════════
void displayTestFault(String faultT) {
  // Define color schemes for different faults
  uint16_t bgColor, textColor, borderColor, subTextColor;
  
  if (faultT == "overvoltage") {
    // 🔴 RED theme for Overvoltage
    bgColor       = 0xB800;     // Dark Red
    textColor     = TFT_WHITE;
    borderColor   = TFT_RED;
    subTextColor  = 0xFFE0;     // Light Yellow
  }
  else if (faultT == "undervoltage") {
    // 🟠 ORANGE theme for Undervoltage
    bgColor       = 0xFD20;     // Dark Orange
    textColor     = TFT_WHITE;
    borderColor   = TFT_ORANGE;
    subTextColor  = 0xFDA0;     // Light Orange
  }
  else if (faultT == "overcurrent") {
    // 🔥 RED/ORANGE theme for Overcurrent
    bgColor       = 0x8000;     // Maroon
    textColor     = TFT_WHITE;
    borderColor   = 0xFD00;     // Bright Orange
    subTextColor  = 0xFF80;     // Peach
  }
  else if (faultT == "leakage") {
    // 🟣 PURPLE theme for Earth Leakage
    bgColor       = 0x801F;     // Dark Purple
    textColor     = TFT_WHITE;
    borderColor   = 0x07FF;     // Magenta
    subTextColor  = 0x83FF;     // Light Purple
  }
  else if (faultT == "short_circuit") {
    // 🔴 CRIMSON theme for Short Circuit
    bgColor       = 0xA000;     // Dark Crimson
    textColor     = TFT_WHITE;
    borderColor   = TFT_RED;
    subTextColor  = 0xFFE0;     // Light Yellow
  }
  else {
    // Default - GRAY theme
    bgColor       = 0x4208;     // Dark Gray
    textColor     = TFT_WHITE;
    borderColor   = TFT_WHITE;
    subTextColor  = 0x8410;     // Light Gray
  }
  
  // Fill background
  tft.fillScreen(bgColor);
  
  // Draw border frame
  tft.drawRect(5, 5, 310, 230, borderColor);
  tft.drawRect(10, 10, 300, 220, borderColor);
  
  // Draw decorative corner elements
  tft.fillRect(15, 15, 30, 5, borderColor);
  tft.fillRect(15, 15, 5, 30, borderColor);
  tft.fillRect(270, 15, 30, 5, borderColor);
  tft.fillRect(305, 15, 5, 30, borderColor);
  tft.fillRect(15, 205, 30, 5, borderColor);
  tft.fillRect(15, 225, 5, 15, borderColor);
  tft.fillRect(270, 205, 30, 5, borderColor);
  tft.fillRect(305, 225, 5, 15, borderColor);
  
  // Header - TEST MODE FAULT
  tft.setTextColor(borderColor, bgColor);
  tft.setTextSize(2);
  tft.setTextDatum(MC_DATUM);  // Middle center alignment
  tft.drawString("⚠️ TEST MODE FAULT ⚠️", 160, 35);
  
  // Main fault name (LARGE and BOLD)
  tft.setTextColor(textColor, bgColor);
  tft.setTextSize(3);
  
  if (faultT == "overvoltage") {
    tft.drawString("OVERVOLTAGE", 160, 90);
  }
  else if (faultT == "undervoltage") {
    tft.drawString("UNDERVOLTAGE", 160, 90);
  }
  else if (faultT == "overcurrent") {
    tft.drawString("OVERCURRENT", 160, 90);
  }
  else if (faultT == "leakage") {
    tft.drawString("EARTH LEAKAGE", 160, 90);
  }
  else if (faultT == "short_circuit") {
    tft.drawString("SHORT CIRCUIT", 160, 90);
  }
  
  // Demo notice
  tft.setTextColor(subTextColor, bgColor);
  tft.setTextSize(1);
  tft.drawString("═══════════════════════════", 160, 130);
  tft.drawString("DEMO - NOT A REAL FAULT", 160, 145);
  tft.drawString("═══════════════════════════", 160, 160);
  
  // Fault description
  tft.setTextSize(1);
  tft.setTextColor(subTextColor, bgColor);
  
  if (faultT == "overvoltage") {
    tft.drawString("Voltage exceeds 260V", 160, 175);
    tft.drawString("Equipment damage risk", 160, 190);
  }
  else if (faultT == "undervoltage") {
    tft.drawString("Voltage below 180V", 160, 175);
    tft.drawString("Motor/compressor risk", 160, 190);
  }
  else if (faultT == "overcurrent") {
    tft.drawString("Current exceeds 15A", 160, 175);
    tft.drawString("Overload protection", 160, 190);
  }
  else if (faultT == "leakage") {
    tft.drawString("Leakage current >= 25mA", 160, 175);
    tft.drawString("Electric shock risk", 160, 190);
  }
  else if (faultT == "short_circuit") {
    tft.drawString("Massive current spike", 160, 175);
    tft.drawString("Fire hazard - immediate trip", 160, 190);
  }
  
  // Relay status (BOTTOM - LARGE)
  tft.setTextColor(borderColor, bgColor);
  tft.setTextSize(2);
  tft.setTextDatum(MC_DATUM);
  tft.drawString("🔌 RELAY TRIPPED!", 160, 220);
  
  // Reset text datum to default
  tft.setTextDatum(TL_DATUM);
}
// ════════════════════════════════════════════════════════════
//  BUZZER - DISTINCT SOUNDS FOR EACH FAULT TYPE (ACTIVE-HIGH)
// ════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════
//  BUZZER - DISTINCT SOUNDS FOR EACH FAULT TYPE (FIXED)
// ════════════════════════════════════════════════════════════
#define BUZZER_PIN 32

// Buzzer pattern variables
unsigned long lastBeepTime = 0;
bool buzzerOn = false;
int beepCount = 0;

unsigned long startupTime = 0;
#define STARTUP_STABILIZE_MS 10000  //

// Define distinct patterns for each fault
void updateBuzzer() {
  if (!faultActive) {
    noTone(BUZZER_PIN);
    buzzerOn = false;
    beepCount = 0;
    lastBeepTime = 0;
    return;
  }

  // Select pattern
  int onTime, offTime, maxBeeps, pauseTime, freq;
  if      (faultType == "overvoltage")             { onTime=150; offTime=150; maxBeeps=3; pauseTime=1000; freq=2000; }
  else if (faultType == "undervoltage")            { onTime=400; offTime=300; maxBeeps=2; pauseTime=1500; freq=1000; }
  else if (faultType == "overcurrent")             { onTime=200; offTime=200; maxBeeps=4; pauseTime=800;  freq=1500; }
  else if (faultType.indexOf("leakage") >= 0)      { onTime=100; offTime=100; maxBeeps=5; pauseTime=500;  freq=2500; }
  else if (faultType == "short_circuit")           { onTime=80;  offTime=80;  maxBeeps=10;pauseTime=200;  freq=3000; }
  else                                             { onTime=200; offTime=200; maxBeeps=3; pauseTime=1000; freq=1500; }

  unsigned long now = millis();

  // Not started yet
  if (lastBeepTime == 0) {
    lastBeepTime = now;
    beepCount = 0;
    buzzerOn = false;
  }

  unsigned long elapsed = now - lastBeepTime;

  if (!buzzerOn) {
    // Waiting for next beep
    unsigned long waitTime = (beepCount == 0) ? 0 : offTime;
    // After full set of beeps, use pause time
    if (beepCount >= maxBeeps) waitTime = pauseTime;

    if (elapsed >= (unsigned long)waitTime) {
      if (beepCount >= maxBeeps) {
        // Reset for next sequence
        beepCount = 0;
      }
      // Turn buzzer ON
      tone(BUZZER_PIN, freq);
      buzzerOn = true;
      lastBeepTime = now;
    }
  } else {
    // Buzzer is ON — wait for onTime to expire
    if (elapsed >= (unsigned long)onTime) {
      noTone(BUZZER_PIN);
      buzzerOn = false;
      beepCount++;
      lastBeepTime = now;
    }
  }
}
//  ENERGY UPDATE
// ════════════════════════════════════════════════════════════
void updateEnergy(float current1, float current2, float voltage) {
  if (millis() - lastEnergyUpdate < 1000) return;
  lastEnergyUpdate = millis();

  circuit1EnergykWh += (voltage * current1) / 1000.0f / 3600.0f;
  circuit2EnergykWh += (voltage * current2) / 1000.0f / 3600.0f;
  totalEnergykWh     = circuit1EnergykWh + circuit2EnergykWh;
}

// ════════════════════════════════════════════════════════════
//  RMS MEASUREMENT
// ════════════════════════════════════════════════════════════
float getChannelRMS(uint8_t channel, adsGain_t gain) {
  ads.setGain(gain);

  long offsetSum = 0;
  for (int i = 0; i < 50; i++)
    offsetSum += ads.readADC_SingleEnded(channel);
  float offset = offsetSum / 50.0f;

  double sumSq = 0;
  int n = 0;
  unsigned long t0 = micros();
  while (micros() - t0 < 20000) {
    float s = ads.readADC_SingleEnded(channel) - offset;
    sumSq += (double)(s * s);
    n++;
  }
  return (n > 0) ? sqrtf(sumSq / n) : 0.0f;
}

// ════════════════════════════════════════════════════════════
//  FIREBASE UPLOAD
// ════════════════════════════════════════════════════════════
void sendToFirebase(float voltage, float c1, float c2, float temp, float neutral, float leakage) {
  if (!firebaseConnected || !Firebase.ready()) return;

  String base = "/" + String(DEVICE_ID) + "/readings/";
  Firebase.RTDB.setFloat(&fbdo, (base+"voltage").c_str(),         voltage);
  Firebase.RTDB.setFloat(&fbdo, (base+"current1").c_str(),        c1);
  Firebase.RTDB.setFloat(&fbdo, (base+"current2").c_str(),        c2);
  Firebase.RTDB.setFloat(&fbdo, (base+"currentNeutral").c_str(),  neutral);
  Firebase.RTDB.setFloat(&fbdo, (base+"leakage_mA").c_str(),      leakage);
  Firebase.RTDB.setFloat(&fbdo, (base+"power1").c_str(),          voltage*c1);
  Firebase.RTDB.setFloat(&fbdo, (base+"power2").c_str(),          voltage*c2);
  Firebase.RTDB.setFloat(&fbdo, (base+"totalPower").c_str(),      voltage*(c1+c2));
  Firebase.RTDB.setFloat(&fbdo, (base+"temperature").c_str(),     temp);
  Firebase.RTDB.setFloat(&fbdo, (base+"totalEnergy_kWh").c_str(), totalEnergykWh);
  Firebase.RTDB.setFloat(&fbdo, (base+"circuit1Energy_kWh").c_str(), circuit1EnergykWh);
  Firebase.RTDB.setFloat(&fbdo, (base+"circuit2Energy_kWh").c_str(), circuit2EnergykWh);
  Firebase.RTDB.setFloat(&fbdo, (base+"totalCost").c_str(),       totalEnergykWh * COST_PER_UNIT);
  Firebase.RTDB.setBool (&fbdo, (base+"relay1_on").c_str(),       relay1State);
  Firebase.RTDB.setBool (&fbdo, (base+"relay2_on").c_str(),       relay2State);
  Firebase.RTDB.setBool (&fbdo, (base+"faultActive").c_str(),     faultActive);
  Firebase.RTDB.setString(&fbdo,(base+"faultMessage").c_str(),    faultType);
  Firebase.RTDB.setInt  (&fbdo, (base+"timestamp").c_str(),       millis());

  Serial.printf("[FB] V=%.1f I1=%.2f I2=%.2f P=%.1f T=%.1f Fault=%s\n",
                voltage, c1, c2, voltage*(c1+c2), temp, faultType.c_str());
}

// ════════════════════════════════════════════════════════════
//  TEST MODE — set simulated fault values
//  FIX: now uses global g_voltage, g_current1, g_current2
// ════════════════════════════════════════════════════════════
void setTestFaultValues(String faultT) {
  if (faultT == "overvoltage") {
    testVoltage      = 265.0f;
    testCurrentHeavy = g_current1;   // keep actual current
    testCurrentLight = g_current2;
  }
  else if (faultT == "undervoltage") {
    testVoltage      = 175.0f;
    testCurrentHeavy = g_current1;
    testCurrentLight = g_current2;
  }
  else if (faultT == "overcurrent") {
    testVoltage      = g_voltage;
    testCurrentHeavy = 16.5f;        // above 15A threshold
    testCurrentLight = g_current2;
  }
  else if (faultT == "leakage") {
    testVoltage      = g_voltage;
    testCurrentHeavy = 2.5f;
    testCurrentLight = 2.45f;        // 50mA leakage difference
  }
  else if (faultT == "short_circuit") {
    testVoltage      = g_voltage;
    testCurrentHeavy = 45.0f;
    testCurrentLight = 0.0f;
  }
  else {
    testVoltage      = g_voltage;
    testCurrentHeavy = g_current1;
    testCurrentLight = g_current2;
  }
}

void checkTestModeCommands() {
  if (!firebaseConnected || !Firebase.ready()) return;

  static String lastCmd = "";
  if (Firebase.RTDB.getString(&fbdo, "/" + String(DEVICE_ID) + "/commands/test_fault")) {
    String cmd = fbdo.stringData();
    if (cmd != "" && cmd != lastCmd) {
      lastCmd = cmd;
      Serial.printf("[TEST] Command: %s\n", cmd.c_str());
   if (cmd == "normal") {
        testMode     = false;
        testFaultType = "normal";
        
        // ✅ CLEAR FAULT STATE WHEN TEST MODE ENDS
        faultActive = false;
        faultType = "normal";
        g_leakageMA = 0.0f;  // Reset leakage
        noTone(BUZZER_PIN);  // Silence buzzer
        
        Serial.println("[TEST] Deactivated - fault state cleared");
      } else {
        testMode          = true;
        testFaultType     = cmd;
        testModeStartTime = millis();
        setTestFaultValues(cmd);
        Serial.printf("[TEST] Activated: %s\n", cmd.c_str());
      }
      Firebase.RTDB.setString(&fbdo,
        ("/" + String(DEVICE_ID) + "/commands/test_fault").c_str(), "");
    }
  }
}

void applyTestModeValues(float &voltage, float &cHeavy, float &cLight) {
  if (testMode) {
    voltage = testVoltage;
    cHeavy  = testCurrentHeavy;
    cLight  = testCurrentLight;
  }
}
// ════════════════════════════════════════════════════════════
//  WIFI CONNECTION MONITOR
// ════════════════════════════════════════════════════════════
void checkWiFiConnection() {
  if (millis() - lastWiFiCheck >= WIFI_RECONNECT_INTERVAL) {
    lastWiFiCheck = millis();
    
    if (WiFi.status() != WL_CONNECTED) {
      // WiFi disconnected
      if (wifiConnected) {
        Serial.println("[WiFi] Disconnected - entering offline mode");
        wifiConnected = false;
        
        // Show offline on TFT
        tft.setTextColor(TFT_RED, TFT_BLACK);
        tft.setCursor(10, 10);
        tft.print("WiFi: OFFLINE");
      }
      
      // Try to reconnect
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    } else {
      // WiFi connected
      if (!wifiConnected) {
        Serial.println("[WiFi] Reconnected - syncing cached data");
        wifiConnected = true;
        
        // Show online on TFT
        tft.setTextColor(TFT_GREEN, TFT_BLACK);
        tft.setCursor(10, 10);
        tft.print("WiFi: ONLINE");
        
        // Sync cached readings to Firebase
        syncCachedReadings();
      }
    }
  }
}

// ════════════════════════════════════════════════════════════
//  LOCAL DATA CACHING (SPIFFS)
// ════════════════════════════════════════════════════════════
bool initCache() {
  if (!LittleFS.begin(true)) {
    Serial.println("[Cache] Failed to initialize LittleFS");
    return false;
  }
  Serial.println("[Cache] LittleFS initialized");
  
  // Load existing cache
  loadCacheFromFile();
  return true;
}

void saveToCache(float voltage, float current1, float current2, 
                 float power1, float power2, float totalPower,
                 float leakage_mA, bool relay1_on, bool relay2_on) {
  // Add new reading to cache
  cacheReadings[cacheIndex].timestamp = millis();
  cacheReadings[cacheIndex].voltage = voltage;
  cacheReadings[cacheIndex].current1 = current1;
  cacheReadings[cacheIndex].current2 = current2;
  cacheReadings[cacheIndex].power1 = power1;
  cacheReadings[cacheIndex].power2 = power2;
  cacheReadings[cacheIndex].totalPower = totalPower;
  cacheReadings[cacheIndex].leakage_mA = leakage_mA;
  cacheReadings[cacheIndex].relay1_on = relay1_on;
  cacheReadings[cacheIndex].relay2_on = relay2_on;
  
  cacheIndex = (cacheIndex + 1) % MAX_CACHE_READINGS;
  
  // Save to file every 5 seconds
  if (millis() - lastCacheWrite >= CACHE_WRITE_INTERVAL) {
    lastCacheWrite = millis();
    saveCacheToFile();
  }
}

void saveCacheToFile() {
  File file = LittleFS.open(CACHE_FILE, "w");
  if (!file) {
    Serial.println("[Cache] Failed to open file for writing");
    return;
  }
  
  // Write cache as JSON
  file.print("{\"readings\":[");
  for (int i = 0; i < MAX_CACHE_READINGS; i++) {
    int idx = (cacheIndex + i) % MAX_CACHE_READINGS;
    if (i > 0) file.print(",");
    file.print("{");
    file.print("\"t\":"); file.print(cacheReadings[idx].timestamp);
    file.print(",\"v\":"); file.print(cacheReadings[idx].voltage);
    file.print(",\"i1\":"); file.print(cacheReadings[idx].current1);
    file.print(",\"i2\":"); file.print(cacheReadings[idx].current2);
    file.print(",\"p1\":"); file.print(cacheReadings[idx].power1);
    file.print(",\"p2\":"); file.print(cacheReadings[idx].power2);
    file.print(",\"tp\":"); file.print(cacheReadings[idx].totalPower);
    file.print(",\"l\":"); file.print(cacheReadings[idx].leakage_mA);
    file.print(",\"r1\":"); file.print(cacheReadings[idx].relay1_on ? "1" : "0");
    file.print(",\"r2\":"); file.print(cacheReadings[idx].relay2_on ? "1" : "0");
    file.print("}");
  }
  file.print("]}");
  file.close();
  
  Serial.printf("[Cache] Saved %d readings to file\n", MAX_CACHE_READINGS);
}

void loadCacheFromFile() {
  if (!LittleFS.exists(CACHE_FILE)) {
    Serial.println("[Cache] No cache file found");
    return;
  }
  
  File file = LittleFS.open(CACHE_FILE, "r");
  if (!file) {
    Serial.println("[Cache] Failed to open file for reading");
    return;
  }
  
  // Simple JSON parsing (or use ArduinoJson if available)
  String json = file.readString();
  file.close();
  
  Serial.println("[Cache] Loaded cache from file");
  // Note: Full JSON parsing requires ArduinoJson library
  // For now, cache is saved but loaded on next boot
}

void syncCachedReadings() {
  if (!firebaseConnected || !Firebase.ready()) return;
  
  Serial.println("[Cache] Syncing cached readings to Firebase...");
  
  // Send latest cached reading
  CachedReading &latest = cacheReadings[(cacheIndex - 1 + MAX_CACHE_READINGS) % MAX_CACHE_READINGS];
  
  String base = "/" + String(DEVICE_ID) + "/readings/";
  Firebase.RTDB.setFloat(&fbdo, (base + "voltage").c_str(), latest.voltage);
  Firebase.RTDB.setFloat(&fbdo, (base + "current1").c_str(), latest.current1);
  Firebase.RTDB.setFloat(&fbdo, (base + "current2").c_str(), latest.current2);
  Firebase.RTDB.setFloat(&fbdo, (base + "totalPower").c_str(), latest.totalPower);
  Firebase.RTDB.setFloat(&fbdo, (base + "leakage_mA").c_str(), latest.leakage_mA);
  Firebase.RTDB.setBool(&fbdo, (base + "relay1_on").c_str(), latest.relay1_on);
  Firebase.RTDB.setBool(&fbdo, (base + "relay2_on").c_str(), latest.relay2_on);
  Firebase.RTDB.setInt(&fbdo, (base + "timestamp").c_str(), latest.timestamp);
  
  Serial.println("[Cache] Sync complete");
}


// ════════════════════════════════════════════════════════════
//  SEND TWILIO SMS ALERT
// ════════════════════════════════════════════════════════════
bool sendTwilioSMS(String faultType, float voltage, float current) {
  if (!wifiConnected) {
    Serial.println("[Twilio] Offline - cannot send SMS");
    return false;
  }
  
  WiFiClientSecure client;
  client.setInsecure();  // Skip SSL certificate verification
  
  if (client.connect("api.twilio.com", 443)) {
    // Build SMS message
    String message = "🚨 Adhunik Yantra Alert!\n";
    message += "Device: " + String(DEVICE_ID) + "\n";
    message += "Fault: " + faultType + "\n";
    message += "Voltage: " + String(voltage, 1) + "V\n";
    message += "Current: " + String(current, 2) + "A\n";
    message += "Time: " + String(millis()/1000) + "s";
    
    // Build Authorization header (Base64 encoded)
    String credentials = String(TWILIO_ACCOUNT_SID) + ":" + String(TWILIO_AUTH_TOKEN);
    String auth = "Basic " + base64::encode(credentials);
    
    // Build POST body
    String body = "From=" + String(TWILIO_PHONE) + 
                  "&To=" + String(YOUR_PHONE) + 
                  "&Body=" + message;
    
    // Send HTTP POST request
    client.print("POST /2010-04-01/Accounts/" + String(TWILIO_ACCOUNT_SID) + "/Messages.json HTTP/1.1\r\n");
    client.print("Host: api.twilio.com\r\n");
    client.print("Authorization: " + auth + "\r\n");
    client.print("Content-Type: application/x-www-form-urlencoded\r\n");
    client.print("Content-Length: " + String(body.length()) + "\r\n");
    client.print("Connection: close\r\n\r\n");
    client.print(body);
    
    // Wait for response
    delay(1000);
    
    // Read response
    bool success = false;
    while (client.available()) {
      String line = client.readStringUntil('\n');
      if (line.indexOf("\"status\":\"queued\"") >= 0 || line.indexOf("201") >= 0) {
        success = true;
      }
    }
    
    client.stop();
    
    if (success) {
      Serial.println("[Twilio] SMS sent successfully!");
      return true;
    } else {
      Serial.println("[Twilio] SMS failed to send");
      return false;
    }
  }
  
  Serial.println("[Twilio] Connection failed");
  return false;
}

void setup() {
  Serial.begin(115200);


  
  // ✅ Initialize cache FIRST
  initCache();

  startupTime = millis();  // Record startup time
 

  
  // Initialize relays
  pinMode(RELAY_IN1, OUTPUT);
  pinMode(RELAY_IN2, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  noTone(BUZZER_PIN);
  
  // Start with relays ON
  digitalWrite(RELAY_IN1, LOW);
  digitalWrite(RELAY_IN2, LOW);
  relay1State = relay2State = true;
  
  // Initialize TFT
  tft.init();
  tft.setRotation(3);
  tft.fillScreen(TFT_BLACK);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.setCursor(50, 100);
  tft.print("Starting...");
  
  // Initialize ADS1115
  Wire.begin(21, 22);
  ads.setDataRate(RATE_ADS1115_860SPS);
  if (!ads.begin(0x48)) {
    tft.fillScreen(TFT_RED);
    tft.print("ADS1115 FAIL");
    while(1);
  }
  Serial.println("[OK] ADS1115");
  
  // Connect WiFi
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("[WiFi] Connecting");
  int tries = 0;
  while (WiFi.status() != WL_CONNECTED && tries++ < 15) {
    delay(300); Serial.print(".");
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    tft.setCursor(10, 10);
    tft.print("WiFi: ONLINE");
    Serial.println("\n[WiFi] OK");
  } else {
    wifiConnected = false;
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.setCursor(10, 10);
    tft.print("WiFi: OFFLINE");
    Serial.println("\n[WiFi] Failed - offline mode");
  }
  
  // Initialize Firebase
  fbConfig.api_key = API_KEY;
  fbConfig.database_url = DATABASE_URL;
  fbConfig.token_status_callback = tokenStatusCallback;
  
  if (Firebase.signUp(&fbConfig, &fbAuth, "", "")) {
    firebaseConnected = true;
    Firebase.begin(&fbConfig, &fbAuth);
    Firebase.reconnectWiFi(true);
    Serial.println("[Firebase] OK");
    initRelayStreams();
  }
  
  randomSeed(analogRead(0));
  tft.fillScreen(TFT_BLACK);
  Serial.println("[BOOT] Ready");
  
}


void loop() {
  // ✅ 0. Check WiFi connection (every 5 seconds)
  checkWiFiConnection();
  
  // 1. Check test mode commands
  checkTestModeCommands();
  
  // 2. Read sensors (WORKS OFFLINE)
  float rawV = getChannelRMS(CH_VOLTAGE, GAIN_ONE);
  g_voltage = rawV * 0.000125f * CAL_VOLTAGE * 1000.0f;
  if (g_voltage < 30.0f) g_voltage = 0.0f;
  
  float rawI1 = getChannelRMS(CH_CURR_1, GAIN_EIGHT);
  g_current1  = rawI1 * 0.0001105f * CAL_CURR_1;
  if (g_current1 < 0.03f) g_current1 = 0.0f;
  
  float rawI2 = getChannelRMS(CH_CURR_2, GAIN_EIGHT);
  g_current2  = rawI2 * 0.0001105f * CAL_CURR_2;
  if (g_current2 < 0.02f) g_current2 = 0.0f;
  
  float rawNeut = getChannelRMS(CH_NEUTRAL, GAIN_EIGHT);
  g_currentNeut = rawNeut * 0.0001105f * CAL_CURR_3;
  if (g_currentNeut < 0.02f) g_currentNeut = 0.0f;
  
  // Calculate leakage
  // Calculate leakage with smoothing and hysteresis
float rawLeakage = fabsf(g_current1 - g_currentNeut) * 1000.0f;

// Smooth the reading (EWMA-style)
leakageAccumulator = LEAKAGE_SMOOTH_FACTOR * rawLeakage + 
                     (1.0f - LEAKAGE_SMOOTH_FACTOR) * leakageAccumulator;

// Apply hysteresis: only trip if sustained above threshold
if (millis() - lastLeakageCheck >= LEAKAGE_DEBOUNCE_MS) {
  lastLeakageCheck = millis();
  
  if (leakageAccumulator >= LEAK_TRIP_MA) {
    g_leakageMA = leakageAccumulator;
  } else if (leakageAccumulator >= (LEAK_TRIP_MA - 10.0f)) {
    g_leakageMA = leakageAccumulator;  // Warning zone
  } else {
    g_leakageMA = 0.0f;
    leakageAccumulator = 0.0f;
  }
}

// Final noise floor
if (g_leakageMA < 1.5f) g_leakageMA = 0.0f;
  
  g_temperature = generateFakeTemperature();
  
  // 3. Working copies
  float voltage = g_voltage;
  float currentHeavy = g_current1;
  float currentLight = g_current2;
  
  // 4. Apply test mode + relay OFF zeroing
  applyTestModeValues(voltage, currentHeavy, currentLight);
  if (!relay1State) { currentHeavy = 0.0f; g_current1 = 0.0f; }
  if (!relay2State) { currentLight = 0.0f; g_current2 = 0.0f; }
  
  // 5. Fault detection (WORKS OFFLINE)
  String detectedFault;
 if (millis() - startupTime < 20000) {
  detectedFault = "normal";  // Ignore readings during startup
  g_leakageMA = 0.0f;
} else if (testMode) {
  detectedFault = testFaultType;
  g_leakageMA = (testFaultType == "leakage") ? 50.0f : 0.0f;
} else {
 
  detectedFault = detectFaults(voltage, currentHeavy, g_leakageMA);
}
  
// 6. Update fault state
if (detectedFault != "normal") {
  faultActive = true;
  faultType = detectedFault;

  Serial.println("[DEBUG] Fault detected, checking SMS...");
  
  // ✅ SEND SMS ALERT (with debounce to prevent spam)
  
  
  #if SEND_SMS_ON_FAULT
  Serial.println("[DEBUG] SEND_SMS_ON_FAULT is TRUE");
  Serial.printf("[DEBUG] wifiConnected: %d\n", wifiConnected);
  Serial.printf("[DEBUG] Time since last SMS: %lu ms\n", millis() - lastSMSSent);
 if (wifiConnected && (millis() - lastSMSSent >= SMS_DEBOUNCE_MS)) {
    Serial.println("[DEBUG] Calling sendTwilioSMS()...");
    
    bool smsResult = sendTwilioSMS(faultType, voltage, currentHeavy);
    Serial.printf("[DEBUG] SMS result: %d\n", smsResult);
    
    if (smsResult) {
      lastSMSSent = millis();
      Serial.printf("[Twilio] SMS sent for fault: %s\n", faultType.c_str());
    }
  } else {
    Serial.println("[DEBUG] SMS NOT sent - check wifiConnected or debounce");
  }
  #else
  Serial.println("[DEBUG] SEND_SMS_ON_FAULT is FALSE");
  #endif
  
  if (testMode)
    displayTestFault(testFaultType);
  else
    displayFault(faultType, voltage, currentHeavy);
  
  if (shouldTripRelay(faultType))
    tripRelay();
    
} else {
  faultActive = false;
  faultType = "normal";
  
  if (!testMode)
    drawAttractiveDisplay(voltage, currentHeavy, currentLight, g_temperature);
}
  // 7. Buzzer (WORKS OFFLINE)
  updateBuzzer();
  
  // 8. Energy (WORKS OFFLINE)
  updateEnergy(currentHeavy, currentLight, voltage);
  
  // 9. Cache readings (WORKS OFFLINE)
  saveToCache(voltage, currentHeavy, currentLight,
              voltage * currentHeavy, voltage * currentLight,
              voltage * (currentHeavy + currentLight),
              g_leakageMA, relay1State, relay2State);
  
  // 10. Firebase relay streams (ONLY WHEN ONLINE)
  checkRelayStreams();
  
  // 11. Firebase upload (ONLY WHEN ONLINE)
  if (firebaseConnected && wifiConnected && 
      millis() - lastFirebaseSend >= FIREBASE_SEND_MS) {
    lastFirebaseSend = millis();
    sendToFirebase(voltage, currentHeavy, currentLight,
                   g_temperature, g_currentNeut, g_leakageMA);
  }
  
  // 12. Serial debug
  static unsigned long lastDebug = 0;
  if (millis() - lastDebug >= 1000) {
    lastDebug = millis();
    Serial.printf("WiFi:%s | Fault:%s | V:%.1f | I1:%.2f | I2:%.2f\n",
                  wifiConnected ? "ON" : "OFF",
                  faultType.c_str(), voltage, currentHeavy, currentLight);
  }
}
