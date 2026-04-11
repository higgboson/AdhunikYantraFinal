import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/firebase_paths.dart';
import '../core/offline_cache.dart';
import '../models/live_data_model.dart';

final liveDataProvider = StreamProvider<LiveData>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.live(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase stream error: $error');
  })
      .asyncMap((event) async {
    if (event.snapshot.value != null && event.snapshot.value is Map) {
      try {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        // Convert to Map<String, dynamic>
        final stringData = Map<String, dynamic>.from(data);
        
        final liveData = LiveData.fromMap(stringData);
        
        // Save to cache for offline access
        await OfflineCache.saveReadings(stringData);
        await OfflineCache.savePowerReading(liveData.totalPower);
        
        return liveData;
      } catch (e) {
        print("Error parsing live data: $e");
        return _getCachedLiveData();
      }
    }
    return _getCachedLiveData();
  });
});

final liveDataStreamProvider = StreamProvider.family<LiveData, String>((ref, deviceId) {
  final path = FirebasePaths.live(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase stream error: $error');
  })
      .asyncMap((event) async {
    if (event.snapshot.value != null && event.snapshot.value is Map) {
      try {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        // Convert to Map<String, dynamic>
        final stringData = Map<String, dynamic>.from(data);
        
        final liveData = LiveData.fromMap(stringData);
        
        // Save to cache
        await OfflineCache.saveReadings(stringData);
        await OfflineCache.savePowerReading(liveData.totalPower);
        
        return liveData;
      } catch (e) {
        return _getCachedLiveData();
      }
    }
    return _getCachedLiveData();
  });
});

/// Get LiveData from cache when offline
LiveData _getCachedLiveData() {
  final cached = OfflineCache.getLastReadings();
  return LiveData(
    voltage: cached['voltage'] ?? 0.0,
    totalPower: cached['totalPower'] ?? 0.0,
    leakage: cached['leakage_ma'] ?? 0.0,
    ambientTemp: cached['ambient_temp_c'] ?? 24.5,
    timestamp: cached['last_updated'] ?? 0,
    lastUpdate: cached['last_updated'] != null 
        ? DateTime.fromMillisecondsSinceEpoch(cached['last_updated'])
        : null,
  );
}

/// Provider for cached power history for offline graph display
final offlinePowerHistoryProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return OfflineCache.getPowerHistoryForChart();
});