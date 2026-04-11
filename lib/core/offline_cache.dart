import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline cache for storing last known readings and historical data
/// All keys use 'ay_' prefix to avoid conflicts with other apps
class OfflineCache {
  static const String _keyPrefix = 'ay_';
  
  // Last readings keys
  static const String _keyVoltage = '${_keyPrefix}last_voltage';
  static const String _keyCurrent1 = '${_keyPrefix}last_current1';
  static const String _keyCurrent2 = '${_keyPrefix}last_current2';
  static const String _keyPower1 = '${_keyPrefix}last_power1';
  static const String _keyPower2 = '${_keyPrefix}last_power2';
  static const String _keyTotalPower = '${_keyPrefix}last_totalPower';
  static const String _keyLeakage = '${_keyPrefix}last_leakage_mA';
  static const String _keyRelay1 = '${_keyPrefix}last_relay1_on';
  static const String _keyRelay2 = '${_keyPrefix}last_relay2_on';
  static const String _keyFault = '${_keyPrefix}last_fault';
  static const String _keyEnergy = '${_keyPrefix}last_energy_kwh';
  static const String _keyUpdated = '${_keyPrefix}last_updated';
  static const String _keyAmbientTemp = '${_keyPrefix}last_ambient_temp';
  
  // Historical data keys
  static const String _keyPowerHistory = '${_keyPrefix}power_history';
  static const String _keyFaultHistory = '${_keyPrefix}fault_history';
  static const String _keyCircuits = '${_keyPrefix}last_circuits';
  
  static const int _maxHistoryPoints = 50;
  static const int _maxFaultHistory = 10;
  
  static SharedPreferences? _prefs;
  static final _initCompleter = Completer<void>();
  
  /// Initialize the cache - call this before using other methods
  static Future<void> initialize() async {
    if (_prefs != null) return;
    if (!_initCompleter.isCompleted) {
      _prefs = await SharedPreferences.getInstance();
      _initCompleter.complete();
    }
    await _initCompleter.future;
  }
  
  static SharedPreferences get _preferences {
    if (_prefs == null) {
      throw StateError('OfflineCache not initialized. Call initialize() first.');
    }
    return _prefs!;
  }
  
  /// Save last known readings to cache
  /// Uses compute for non-blocking write if data is large
  static Future<void> saveReadings(Map<String, dynamic> readings) async {
    await initialize();
    
    final data = {
      _keyVoltage: readings['voltage']?.toString() ?? '0.0',
      _keyCurrent1: readings['current1']?.toString() ?? '0.0',
      _keyCurrent2: readings['current2']?.toString() ?? '0.0',
      _keyPower1: readings['power1']?.toString() ?? '0.0',
      _keyPower2: readings['power2']?.toString() ?? '0.0',
      _keyTotalPower: readings['totalPower']?.toString() ?? 
          (readings['power']?.toString() ?? '0.0'),
      _keyLeakage: readings['leakage_ma']?.toString() ?? '0.0',
      _keyRelay1: readings['relay1']?.toString() ?? 'false',
      _keyRelay2: readings['relay2']?.toString() ?? 'false',
      _keyFault: readings['fault']?.toString() ?? 'false',
      _keyEnergy: readings['energy_kwh']?.toString() ?? '0.0',
      _keyAmbientTemp: readings['ambient_temp_c']?.toString() ?? '24.5',
      _keyUpdated: DateTime.now().millisecondsSinceEpoch.toString(),
    };
    
    // For small data, write directly. For larger data, use compute
    if (data.length > 10) {
      await compute(_saveReadingsIsolate, {'prefs': _preferences, 'data': data});
    } else {
      await _saveReadingsData(data);
    }
  }
  
  /// Get last known readings from cache
  static Map<String, dynamic> getLastReadings() {
    if (_prefs == null) {
      return {};
    }
    
    return {
      'voltage': double.tryParse(_preferences.getString(_keyVoltage) ?? '0.0') ?? 0.0,
      'current1': double.tryParse(_preferences.getString(_keyCurrent1) ?? '0.0') ?? 0.0,
      'current2': double.tryParse(_preferences.getString(_keyCurrent2) ?? '0.0') ?? 0.0,
      'power1': double.tryParse(_preferences.getString(_keyPower1) ?? '0.0') ?? 0.0,
      'power2': double.tryParse(_preferences.getString(_keyPower2) ?? '0.0') ?? 0.0,
      'totalPower': double.tryParse(_preferences.getString(_keyTotalPower) ?? '0.0') ?? 0.0,
      'leakage_ma': double.tryParse(_preferences.getString(_keyLeakage) ?? '0.0') ?? 0.0,
      'relay1': _preferences.getString(_keyRelay1) == 'true',
      'relay2': _preferences.getString(_keyRelay2) == 'true',
      'fault': _preferences.getString(_keyFault) == 'true',
      'energy_kwh': double.tryParse(_preferences.getString(_keyEnergy) ?? '0.0') ?? 0.0,
      'ambient_temp_c': double.tryParse(_preferences.getString(_keyAmbientTemp) ?? '24.5') ?? 24.5,
      'last_updated': int.tryParse(_preferences.getString(_keyUpdated) ?? '0') ?? 0,
    };
  }
  
  /// Get formatted last updated string
  static String getLastUpdatedString() {
    final lastUpdated = int.tryParse(_preferences.getString(_keyUpdated) ?? '0') ?? 0;
    if (lastUpdated == 0) return 'No cached data';
    
    final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
    final now = DateTime.now();
    final diff = now.difference(lastUpdateTime);
    
    if (diff.inDays > 0) {
      return 'Last updated: ${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else if (diff.inHours > 0) {
      return 'Last updated: ${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inMinutes > 0) {
      return 'Last updated: ${diff.inMinutes} min${diff.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Last updated: Just now';
    }
  }
  
  /// Save power reading to history (last 50 points)
  static Future<void> savePowerReading(double power) async {
    await initialize();
    
    final history = getPowerHistory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    history.add({
      'power': power,
      'timestamp': timestamp,
    });
    
    // Keep only last 50 points
    while (history.length > _maxHistoryPoints) {
      history.removeAt(0);
    }
    
    await _preferences.setString(_keyPowerHistory, jsonEncode(history));
  }
  
  /// Get power history as list of {power, timestamp} maps
  static List<Map<String, dynamic>> getPowerHistory() {
    if (_prefs == null) return [];
    
    final json = _preferences.getString(_keyPowerHistory);
    if (json == null || json.isEmpty) return [];
    
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Get power history as chart spots for fl_chart
  static List<Map<String, dynamic>> getPowerHistoryForChart() {
    final history = getPowerHistory();
    if (history.isEmpty) return [];
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    return history.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final timestamp = data['timestamp'] as int? ?? now;
      final minutesAgo = (now - timestamp) ~/ (1000 * 60);
      
      return {
        'x': index.toDouble(),
        'y': (data['power'] as num?)?.toDouble() ?? 0.0,
        'minutes_ago': minutesAgo,
      };
    }).toList();
  }
  
  /// Save fault to history (last 10 faults)
  static Future<void> saveFault(Map<String, dynamic> fault) async {
    await initialize();
    
    final history = getFaultHistory();
    
    // Check if fault already exists
    final faultId = fault['id']?.toString();
    if (faultId != null) {
      history.removeWhere((f) => f['id']?.toString() == faultId);
    }
    
    history.insert(0, fault);
    
    // Keep only last 10 faults
    while (history.length > _maxFaultHistory) {
      history.removeLast();
    }
    
    await _preferences.setString(_keyFaultHistory, jsonEncode(history));
  }
  
  /// Get fault history
  static List<Map<String, dynamic>> getFaultHistory() {
    if (_prefs == null) return [];
    
    final json = _preferences.getString(_keyFaultHistory);
    if (json == null || json.isEmpty) return [];
    
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Save circuits list to cache
  static Future<void> saveCircuits(List<Map<String, dynamic>> circuits) async {
    await initialize();
    await _preferences.setString(_keyCircuits, jsonEncode(circuits));
  }
  
  /// Get cached circuits list
  static List<Map<String, dynamic>> getCircuits() {
    if (_prefs == null) return [];
    
    final json = _preferences.getString(_keyCircuits);
    if (json == null || json.isEmpty) return [];
    
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      return [];
    }
  }
  
  /// Clear all cached data
  static Future<void> clearCache() async {
    await initialize();
    
    final keys = [
      _keyVoltage,
      _keyCurrent1,
      _keyCurrent2,
      _keyPower1,
      _keyPower2,
      _keyTotalPower,
      _keyLeakage,
      _keyRelay1,
      _keyRelay2,
      _keyFault,
      _keyEnergy,
      _keyUpdated,
      _keyAmbientTemp,
      _keyPowerHistory,
      _keyFaultHistory,
      _keyCircuits,
    ];
    
    for (final key in keys) {
      await _preferences.remove(key);
    }
  }
  
  /// Get approximate cache size in bytes
  static int getCacheSize() {
    if (_prefs == null) return 0;
    
    final keys = [
      _keyVoltage,
      _keyCurrent1,
      _keyCurrent2,
      _keyPower1,
      _keyPower2,
      _keyTotalPower,
      _keyLeakage,
      _keyRelay1,
      _keyRelay2,
      _keyFault,
      _keyEnergy,
      _keyUpdated,
      _keyAmbientTemp,
      _keyPowerHistory,
      _keyFaultHistory,
      _keyCircuits,
    ];
    
    int size = 0;
    for (final key in keys) {
      final value = _preferences.getString(key);
      if (value != null) {
        size += value.length * 2; // UTF-16 encoding
      }
    }
    return size;
  }
  
  /// Check if we have any cached data
  static bool hasCachedData() {
    if (_prefs == null) return false;
    return _preferences.containsKey(_keyUpdated);
  }
  
  /// Get timestamp of last cache update
  static DateTime? getLastUpdateTime() {
    final lastUpdated = int.tryParse(_preferences.getString(_keyUpdated) ?? '0') ?? 0;
    if (lastUpdated == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(lastUpdated);
  }
  
  // Internal helper to save readings data
  static Future<void> _saveReadingsData(Map<String, String> data) async {
    final prefs = _preferences;
    final futures = <Future<bool>>[];
    
    data.forEach((key, value) {
      futures.add(prefs.setString(key, value));
    });
    
    await Future.wait(futures);
  }
  
  // Isolate entry point for saving readings
  static void _saveReadingsIsolate(Map<String, dynamic> args) {
    final prefs = args['prefs'] as SharedPreferences;
    final data = args['data'] as Map<String, String>;
    
    data.forEach((key, value) {
      prefs.setString(key, value);
    });
  }
}
