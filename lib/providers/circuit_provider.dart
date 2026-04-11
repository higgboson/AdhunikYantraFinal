import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rxdart/rxdart.dart';
import '../core/constants.dart';
import '../core/firebase_paths.dart';
import '../core/offline_cache.dart';
import '../models/circuit_model.dart';

final circuitsProvider = StreamProvider<List<Circuit>>((ref) {
  const deviceId = AppConstants.deviceId;
  final circuitsPath = FirebasePaths.circuits(deviceId);
  final readingsPath = FirebasePaths.live(deviceId);
  
  // Combine streams from both circuits and readings nodes
  final circuitsStream = FirebaseDatabase.instance.ref(circuitsPath).onValue;
  final readingsStream = FirebaseDatabase.instance.ref(readingsPath).onValue;
  
  return Rx.combineLatest2<DatabaseEvent, DatabaseEvent, Future<List<Circuit>>>(
    circuitsStream,
    readingsStream,
    (circuitsEvent, readingsEvent) async {
      final prefs = await SharedPreferences.getInstance();
      final circuitNames = prefs.getStringList(AppConstants.prefCircuitNames);
      
      // Get readings data if available
      Map<String, dynamic> readingsData = {};
      if (readingsEvent.snapshot.value != null && readingsEvent.snapshot.value is Map) {
        readingsData = Map<String, dynamic>.from(readingsEvent.snapshot.value as Map);
      }
      
      final circuits = <Circuit>[];
      
      if (circuitsEvent.snapshot.value != null) {
        final circuitsData = Map<dynamic, dynamic>.from(circuitsEvent.snapshot.value as Map);
        
        for (var i = 0; i < AppConstants.circuitCount; i++) {
          final circuitId = AppConstants.circuitIds[i];
          final circuitNodeData = circuitsData[circuitId];
          
          // Start with circuit node data (names, relay, faults, ewma)
          Map<String, dynamic> mergedData = {};
          if (circuitNodeData != null) {
            mergedData = Map<String, dynamic>.from(circuitNodeData as Map);
          }
          
          // ALWAYS merge with readings data (power, current, temp) - readings take priority
          if (readingsData.isNotEmpty) {
            // Debug: print what we're receiving
            print('Circuit $circuitId - Readings data keys: ${readingsData.keys.toList()}');
            
            // Extract common values
            final voltage = (readingsData['voltage'] as num?)?.toDouble() ?? 230.0;
            final temp = (readingsData['temperature'] as num?)?.toDouble() ?? 
                        (readingsData['temp_c'] as num?)?.toDouble() ?? 0.0;
            
            // Add circuit-specific power/current/temp from readings
            if (circuitId == 'circuit_1' || circuitId.contains('1')) {
              // Circuit 1: use power1, current1
              final current1 = (readingsData['current1'] as num?)?.toDouble() ?? 0.0;
              final power1 = (readingsData['power1'] as num?)?.toDouble() ?? 
                            (voltage * current1);
              
              mergedData['current'] = current1;
              mergedData['power'] = power1;
              mergedData['temp_c'] = temp;
              
              print('Circuit $circuitId - current1: $current1, power1: $power1, temp: $temp');
            } else if (circuitId == 'circuit_2' || circuitId.contains('2')) {
              // Circuit 2: use power2, current2 (from A3/Neutral)
              final current2 = (readingsData['current2'] as num?)?.toDouble() ?? 0.0;
              final power2 = (readingsData['power2'] as num?)?.toDouble() ?? 
                            (voltage * current2);
              
              mergedData['current'] = current2;
              mergedData['power'] = power2;
              mergedData['temp_c'] = temp;
              
              print('Circuit $circuitId - current2: $current2, power2: $power2, temp: $temp');
            }
          }
          
          var circuit = Circuit.fromMap(circuitId, mergedData);
          print('Circuit $circuitId - Final power: ${circuit.power}, temp: ${circuit.temp}, current: ${circuit.current}');
          
          // Use cached name if available
          if (circuitNames != null && circuitNames.length > i) {
            circuit = circuit.copyWith(name: circuitNames[i]);
          }
          
          circuits.add(circuit);
        }
      } else {
        // No circuits node data - create from readings data only
        final voltage = (readingsData['voltage'] as num?)?.toDouble() ?? 230.0;
        final temp = (readingsData['temperature'] as num?)?.toDouble() ?? 0.0;
        final current1 = (readingsData['current1'] as num?)?.toDouble() ?? 0.0;
        final current2 = (readingsData['current2'] as num?)?.toDouble() ?? 0.0;
        
        // Circuit 1
        circuits.add(Circuit(
          id: 'circuit_1',
          name: 'Circuit 1',
          current: current1,
          power: (readingsData['power1'] as num?)?.toDouble() ?? (voltage * current1),
          temp: temp,
        ));
        
        // Circuit 2
        circuits.add(Circuit(
          id: 'circuit_2',
          name: 'Circuit 2',
          current: current2,
          power: (readingsData['power2'] as num?)?.toDouble() ?? (voltage * current2),
          temp: temp,
        ));
      }
      
      // Save circuits to cache for offline use
      await OfflineCache.saveCircuits(circuits.map((c) => c.toMap()..['id'] = c.id).toList());
      
      return circuits;
    },
  ).asyncMap((future) => future).handleError((error) async {
    print('Firebase circuits stream error: $error');
    // Return cached circuits when offline
    final cached = OfflineCache.getCircuits();
    if (cached.isNotEmpty) {
      return cached.map((data) => Circuit.fromMap(data['id'] as String, data)).toList();
    }
    return <Circuit>[];
  });
});

/// Provider for cached circuits (for offline use)
final offlineCircuitsProvider = Provider<List<Circuit>>((ref) {
  final cached = OfflineCache.getCircuits();
  if (cached.isEmpty) return [];
  return cached.map((data) => Circuit.fromMap(data['id'] as String, data)).toList();
});

final singleCircuitProvider = StreamProvider.family<Circuit, String>((ref, circuitId) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.circuit(deviceId, circuitId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase circuit stream error: $error');
  })
      .map((event) {
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return Circuit.fromMap(circuitId, data);
    }
    return Circuit(id: circuitId);
  });
});

class CircuitNotifier extends StateNotifier<AsyncValue<void>> {
  CircuitNotifier() : super(const AsyncValue.data(null));
  
  Future<void> toggleRelay(String deviceId, String circuitId, bool newState) async {
    state = const AsyncValue.loading();
    try {
      final path = FirebasePaths.circuitRelay(deviceId, circuitId);
      await FirebaseDatabase.instance.ref(path).set(newState);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
  
  Future<void> updateCircuitName(String deviceId, String circuitId, String newName) async {
    state = const AsyncValue.loading();
    try {
      // Update in Firebase
      final path = FirebasePaths.circuitName(deviceId, circuitId);
      await FirebaseDatabase.instance.ref(path).set(newName);
      
      // Update in cache
      final prefs = await SharedPreferences.getInstance();
      final index = AppConstants.circuitIds.indexOf(circuitId);
      final names = prefs.getStringList(AppConstants.prefCircuitNames) ?? 
          List.generate(AppConstants.circuitCount, (i) => AppConstants.defaultCircuitNames[AppConstants.circuitIds[i]]!);
      
      if (index >= 0 && index < names.length) {
        names[index] = newName;
        await prefs.setStringList(AppConstants.prefCircuitNames, names);
      }
      
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final circuitActionsProvider = StateNotifierProvider<CircuitNotifier, AsyncValue<void>>((ref) {
  return CircuitNotifier();
});