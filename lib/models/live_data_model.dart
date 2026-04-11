class LiveData {
  final double voltage;
  final double totalPower;
  final double leakage;
  final double ambientTemp;
  final int timestamp;
  final DateTime? lastUpdate;

  LiveData({
    this.voltage = 0.0,
    this.totalPower = 0.0,
    this.leakage = 0.0,
    this.ambientTemp = 24.5, // Default fallback so the UI doesn't say 0°C
    this.timestamp = 0,
    this.lastUpdate,
  });

  factory LiveData.fromMap(Map<dynamic, dynamic> map) {
    return LiveData(
      // Match ESP32 Firebase keys - voltage works, power needs to check multiple possible keys
      voltage: (map['voltage'] as num?)?.toDouble() ?? 0.0,
      // ESP32 sends 'powerHeavy' for heavy circuit power, calculate total from available power values
      totalPower: _parseTotalPower(map),
      // Leakage current - ESP32 sends current1 (living room), current2 (kitchen), current3 (neutral)
      leakage: _parseLeakage(map),
      ambientTemp: (map['ambient_temp_c'] as num?)?.toDouble() ?? 24.5,
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      lastUpdate: DateTime.now(),
    );
  }

  /// Parse total power from various possible ESP32 key names
  static double _parseTotalPower(Map<dynamic, dynamic> map) {
    // Try different possible keys ESP32 might use
    final powerHeavy = (map['powerHeavy'] as num?)?.toDouble() ?? 0.0;
    final powerLight = (map['power_light'] as num?)?.toDouble() ?? 0.0;
    final power = (map['power'] as num?)?.toDouble() ?? 0.0;
    final totalPower = (map['totalPower'] as num?)?.toDouble() ?? 0.0;
    
    // If we have powerHeavy + power_light, use those
    if (powerHeavy > 0 || powerLight > 0) {
      return powerHeavy + powerLight;
    }
    // Otherwise fallback to power or totalPower
    return power > 0 ? power : totalPower;
  }

  /// Parse leakage from current1 (live) and current3 (neutral) difference
  static double _parseLeakage(Map<dynamic, dynamic> map) {
    final current1 = (map['current1'] as num?)?.toDouble() ?? 0.0;
    final current3 = (map['current3'] as num?)?.toDouble() ?? 0.0;
    
    // Calculate leakage in mA
    if (current1 > 0 && current3 > 0) {
      return ((current1 - current3).abs() * 1000);
    }
    // Fallback to direct leakage value if available
    return (map['leakage_ma'] as num?)?.toDouble() ?? 0.0;
  }

  Map<String, dynamic> toMap() {
    return {
      // Kept perfectly symmetrical with fromMap
      'voltage': voltage,
      'power': totalPower,
      'current1': leakage,
      'ambient_temp_c': ambientTemp,
      'timestamp': timestamp,
    };
  }

  // --- SAFETY THRESHOLDS ---
  // Indian standard voltage is normally 230V +/- 6% (approx 216V - 244V)
  // Adjusted slightly wider here for typical fluctuations
  bool get isVoltageNormal => voltage >= 200.0 && voltage <= 250.0;
  
  // Leakage/Current safety threshold (Adjust based on your actual load limits)
  bool get isLeakageSafe => leakage < 30.0;
  
  // Temperature threshold in Celsius
  bool get isTempSafe => ambientTemp < 65.0;

  LiveData copyWith({
    double? voltage,
    double? totalPower,
    double? leakage,
    double? ambientTemp,
    int? timestamp,
    DateTime? lastUpdate,
  }) {
    return LiveData(
      voltage: voltage ?? this.voltage,
      totalPower: totalPower ?? this.totalPower,
      leakage: leakage ?? this.leakage,
      ambientTemp: ambientTemp ?? this.ambientTemp,
      timestamp: timestamp ?? this.timestamp,
      lastUpdate: lastUpdate ?? this.lastUpdate,
    );
  }
}