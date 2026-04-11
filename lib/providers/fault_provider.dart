import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/firebase_paths.dart';
import '../core/offline_cache.dart';
import '../models/fault_model.dart';

final activeFaultsProvider = StreamProvider<List<Fault>>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.faults(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase faults stream error: $error');
  })
      .asyncMap((event) async {
    final faults = <Fault>[];
    
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      
      for (var entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        
        if (value != null && value is Map) {
          final faultMap = Map<dynamic, dynamic>.from(value);
          final resolved = faultMap['resolved'] as bool? ?? false;
          
          if (!resolved) {
            final fault = Fault.fromMap(key.toString(), faultMap);
            faults.add(fault);
            
            // Save fault to cache (fire and forget)
            OfflineCache.saveFault(fault.toMap()..['id'] = key.toString());
          }
        }
      }
    }
    
    // Sort by timestamp descending (most recent first)
    faults.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return faults;
  });
});

final allFaultsProvider = StreamProvider<List<Fault>>((ref) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.faults(deviceId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase faults stream error: $error');
  })
      .asyncMap((event) async {
    final faults = <Fault>[];
    
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      
      for (var entry in data.entries) {
        final key = entry.key;
        final value = entry.value;
        
        if (value != null && value is Map) {
          final faultMap = Map<dynamic, dynamic>.from(value);
          final fault = Fault.fromMap(key.toString(), faultMap);
          faults.add(fault);
          
          // Save fault to cache (fire and forget)
          OfflineCache.saveFault(fault.toMap()..['id'] = key.toString());
        }
      }
    }
    
    faults.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return faults;
  });
});

final faultByIdProvider = StreamProvider.family<Fault?, String>((ref, faultId) {
  const deviceId = AppConstants.deviceId;
  final path = FirebasePaths.fault(deviceId, faultId);
  
  return FirebaseDatabase.instance
      .ref(path)
      .onValue
      .handleError((error) {
    print('Firebase fault stream error: $error');
  })
      .asyncMap((event) async {
    if (event.snapshot.value != null) {
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final fault = Fault.fromMap(faultId, data);
      
      // Save to cache (fire and forget)
      OfflineCache.saveFault(fault.toMap()..['id'] = faultId);
      
      return fault;
    }
    return null;
  });
});

/// Provider for cached fault history (for offline use)
final offlineFaultsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  return OfflineCache.getFaultHistory();
});

class FaultNotifier extends StateNotifier<AsyncValue<void>> {
  FaultNotifier() : super(const AsyncValue.data(null));
  
  Future<void> resolveFault(String deviceId, String faultId, bool resolved) async {
    state = const AsyncValue.loading();
    try {
      final path = FirebasePaths.faultResolved(deviceId, faultId);
      await FirebaseDatabase.instance.ref(path).set(resolved);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final faultActionsProvider = StateNotifierProvider<FaultNotifier, AsyncValue<void>>((ref) {
  return FaultNotifier();
});