import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/energy_data_model.dart';

/// Service class for handling real-time energy data from Firebase
/// Provides streams and methods for live energy monitoring
class EnergyDataService {
  final FirebaseDatabase _database;
  final String _deviceId;

  // Cache for offline viewing
  EnergyData? _cachedData;
  DateTime? _lastCacheTime;
  static const _cacheValidityDuration = Duration(minutes: 5);

  /// Stream controller for error handling
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  EnergyDataService({
    FirebaseDatabase? database,
    String? deviceId,
  })  : _database = database ?? FirebaseDatabase.instance,
        _deviceId = deviceId ?? AppConstants.deviceId;

  /// Get the Firebase reference for readings
  DatabaseReference get _readingsRef => 
      _database.ref('$_deviceId/readings');

  /// Get real-time stream of energy data
  /// Emits EnergyData every time Firebase updates (typically every 1 second from ESP32)
  Stream<EnergyData> getLiveEnergyStream({double costPerUnit = 8.5}) {
    return _readingsRef.onValue.map((event) {
      try {
        if (event.snapshot.value == null) {
          throw Exception('No data available from device');
        }

        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final energyData = EnergyData.fromFirebase(data, costPerUnit: costPerUnit);
        
        // Cache the data for offline viewing
        _cachedData = energyData;
        _lastCacheTime = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('🔥 EnergyData updated: ${energyData.formattedEnergy}, '
              'Power: ${energyData.formattedPower}');
        }
        
        return energyData;
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('❌ Error parsing energy data: $e');
          debugPrint(stackTrace.toString());
        }
        _errorController.add('Error parsing data: $e');
        
        // Return cached data if available
        if (_cachedData != null) {
          return _cachedData!;
        }
        
        // Return default data with error state
        return EnergyData(
          timestamp: DateTime.now(),
          costPerUnit: costPerUnit,
        );
      }
    }).handleError((error, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Firebase stream error: $error');
      }
      _errorController.add('Connection error: $error');
      
      // Emit cached data on connection error
      if (_cachedData != null && _isCacheValid) {
        return _cachedData!;
      }
    });
  }

  /// Get current energy data as a one-time fetch
  Future<EnergyData> getCurrentEnergy({double costPerUnit = 8.5}) async {
    try {
      final snapshot = await _readingsRef.get();
      
      if (snapshot.value == null) {
        // Return cached data if available
        if (_cachedData != null) {
          return _cachedData!;
        }
        throw Exception('No data available');
      }

      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final energyData = EnergyData.fromFirebase(data, costPerUnit: costPerUnit);
      
      // Update cache
      _cachedData = energyData;
      _lastCacheTime = DateTime.now();
      
      return energyData;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error fetching energy data: $e');
      }
      
      // Return cached data on error
      if (_cachedData != null) {
        return _cachedData!;
      }
      
      rethrow;
    }
  }

  /// Calculate weekly estimate from daily energy
  /// Uses actual historical data if available, otherwise simple projection
  double getWeeklyEstimate(double dailyEnergy) {
    if (dailyEnergy <= 0) return 0.0;
    return dailyEnergy * 7;
  }

  /// Calculate monthly projection from daily energy
  /// Accounts for days elapsed if available for better accuracy
  double getMonthlyProjection(double dailyEnergy, {int? daysElapsed}) {
    if (dailyEnergy <= 0) return 0.0;
    
    if (daysElapsed != null && daysElapsed > 0 && daysElapsed < 30) {
      // Use actual daily average if we have partial data
      final dailyAverage = dailyEnergy / daysElapsed;
      return dailyAverage * 30;
    }
    
    // Simple projection
    return dailyEnergy * 30;
  }

  /// Calculate monthly cost projection
  double getMonthlyCostProjection(double dailyEnergy, {double costPerUnit = 8.5, int? daysElapsed}) {
    final projection = getMonthlyProjection(dailyEnergy, daysElapsed: daysElapsed);
    return projection * costPerUnit;
  }

  /// Format energy value for display (kWh with 3 decimal places)
  String formatEnergy(double kWh) {
    return '${kWh.toStringAsFixed(3)} kWh';
  }

  /// Format cost value for display (Rs with 2 decimal places)
  String formatCost(double cost) {
    return 'Rs ${cost.toStringAsFixed(2)}';
  }

  /// Format power value for display (W with 1 decimal place)
  String formatPower(double watts) {
    return '${watts.toStringAsFixed(1)} W';
  }

  /// Check if cache is still valid
  bool get _isCacheValid {
    if (_lastCacheTime == null || _cachedData == null) return false;
    final age = DateTime.now().difference(_lastCacheTime!);
    return age < _cacheValidityDuration;
  }

  /// Get cached data if available and valid
  EnergyData? getCachedData() {
    if (_isCacheValid) {
      return _cachedData;
    }
    return null;
  }

  /// Clear the cache
  void clearCache() {
    _cachedData = null;
    _lastCacheTime = null;
  }

  /// Dispose of resources
  void dispose() {
    _errorController.close();
  }
}
