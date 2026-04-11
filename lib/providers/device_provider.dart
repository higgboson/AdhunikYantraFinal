import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import '../core/constants.dart';
import '../core/firebase_paths.dart';
import '../models/device_info_model.dart';
import '../models/ewma_model.dart';
import '../models/neutral_data_model.dart';

/// Provider for raw ADS1115 readings from Firebase
/// A1 (current1) = Living Room Live
/// A2 (current2) = Kitchen Live  
/// A3 (current3) = Living Room Neutral
final adsReadingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.live(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .map((event) {
    if (event.snapshot.value != null) {
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    }
    return {};
  });
});

/// Provider specifically for neutral/leakage monitoring
/// Calculates leakage as abs(A1 - A3) * 1000 (in mA)
final leakageDataProvider = StreamProvider<LeakageData>((ref) {
  final readingsAsync = ref.watch(adsReadingsProvider);
  
  return readingsAsync.when(
    data: (readings) {
      final a1 = (readings['current1'] as num?)?.toDouble() ?? 0.0; // Living Room Live
      final a3 = (readings['current3'] as num?)?.toDouble() ?? 0.0; // Living Room Neutral
      
      // Calculate leakage in mA
      final leakageMa = ((a1 - a3).abs() * 1000);
      
      return Stream.value(LeakageData(
        liveCurrentA: a1,
        neutralCurrentA: a3,
        leakageMa: leakageMa,
        timestamp: DateTime.now(),
      ));
    },
   loading: () => Stream.value(LeakageData(
  liveCurrentA: 0,
  neutralCurrentA: 0,
  leakageMa: 0,
  timestamp: DateTime.now(),  // ✅ Add this
)),
error: (_, __) => Stream.value(LeakageData(
  liveCurrentA: 0,
  neutralCurrentA: 0,
  leakageMa: 0,
  timestamp: DateTime.now(),  // ✅ Add this
)),
  );
});

class LeakageData {
  final double liveCurrentA;
  final double neutralCurrentA;
  final double leakageMa;
  final DateTime timestamp;

  LeakageData({
    this.liveCurrentA = 0,
    this.neutralCurrentA = 0,
    this.leakageMa = 0,
    required this.timestamp,
  });

  // Color based on leakage threshold
  Color get statusColor {
    if (leakageMa < 20) return const Color(0xFF4CAF50); // Green
    if (leakageMa <= 30) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }

  bool get isWarning => leakageMa >= 20;
  bool get isDanger => leakageMa > 30;
}

// Device Info Provider
final deviceInfoProvider = StreamProvider<DeviceInfo>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.deviceInfo(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .map((event) {
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return DeviceInfo.fromMap(data);
    }
    return DeviceInfo();
  });
});

// EWMA Config Provider
final ewmaConfigsProvider = StreamProvider<Map<String, EwmaConfig>>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.ewma(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .map((event) {
    final configs = <String, EwmaConfig>{};
    
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      
      data.forEach((key, value) {
        if (value != null && value is Map) {
          final configMap = Map<dynamic, dynamic>.from(value);
          configs[key.toString()] = EwmaConfig.fromMap(key.toString(), configMap);
        }
      });
    }
    
    // Fill defaults for missing circuits
    for (final circuitId in AppConstants.circuitIds) {
      configs.putIfAbsent(circuitId, () => EwmaConfig(circuitId: circuitId));
    }
    
    return configs;
  });
});

final ewmaConfigProvider = StreamProvider.family<EwmaConfig, String>((ref, circuitId) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.ewmaCircuit(deviceId, circuitId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .map((event) {
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return EwmaConfig.fromMap(circuitId, data);
    }
    return EwmaConfig(circuitId: circuitId);
  });
});

// Neutral Monitor Provider - reads from neutral_monitor node OR calculates from readings
final neutralDataProvider = StreamProvider<NeutralData>((ref) {
  const deviceId = AppConstants.deviceId;
  final neutralPath = FirebasePaths.neutralMonitor(deviceId);
  final readingsPath = FirebasePaths.live(deviceId);
  
  // Combine both streams
  final neutralStream = FirebaseDatabase.instance.ref(neutralPath).onValue;
  final readingsStream = FirebaseDatabase.instance.ref(readingsPath).onValue;
  
  return Rx.combineLatest2<DatabaseEvent, DatabaseEvent, NeutralData>(
    neutralStream,
    readingsStream,
    (neutralEvent, readingsEvent) {
      // First try to get from neutral_monitor node
      if (neutralEvent.snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(neutralEvent.snapshot.value as Map);
        return NeutralData.fromMap(data);
      }
      
      // Fallback: calculate from readings node (current1 = live, current3 = neutral)
      if (readingsEvent.snapshot.value != null) {
        final readings = Map<String, dynamic>.from(readingsEvent.snapshot.value as Map);
        final liveCurrent = (readings['current1'] as num?)?.toDouble() ?? 0.0;
        final neutralCurrent = (readings['current3'] as num?)?.toDouble() ?? 0.0;
        final differenceMa = ((liveCurrent - neutralCurrent).abs() * 1000);
        
        return NeutralData(
          liveCurrentA: liveCurrent,
          neutralCurrentA: neutralCurrent,
          differenceMa: differenceMa,
          faultActive: differenceMa > 30, // Auto-detect fault if > 30mA
          lastUpdate: DateTime.now(),
        );
      }
      
      return NeutralData();
    },
  );
});

class EwmaNotifier extends StateNotifier<AsyncValue<void>> {
  EwmaNotifier() : super(const AsyncValue.data(null));
  
  Future<void> updateConfig(String deviceId, EwmaConfig config) async {
    state = const AsyncValue.loading();
    try {
      final path = FirebasePaths.ewmaCircuit(deviceId, config.circuitId);
      await FirebaseDatabase.instance.ref(path).update(config.toMap());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
  
  Future<void> startCalibration(String deviceId, String circuitId, int hours, double sensitivity, int minOnMinutes) async {
    state = const AsyncValue.loading();
    try {
      final config = EwmaConfig(
        circuitId: circuitId,
        calibrating: true,
        calibrationHours: hours,
        alpha: sensitivity / 100, // Convert 1-10 to 0.01-0.1
        minOnMinutes: minOnMinutes,
      );
      
      final path = FirebasePaths.ewmaCircuit(deviceId, circuitId);
      await FirebaseDatabase.instance.ref(path).update(config.toMap());
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
  
  Future<void> stopCalibration(String deviceId, String circuitId) async {
    state = const AsyncValue.loading();
    try {
      final path = FirebasePaths.ewmaCalibrating(deviceId, circuitId);
      await FirebaseDatabase.instance.ref(path).set(false);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final ewmaActionsProvider = StateNotifierProvider<EwmaNotifier, AsyncValue<void>>((ref) {
  return EwmaNotifier();
});
