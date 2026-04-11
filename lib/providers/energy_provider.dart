import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/energy_data_model.dart';
import '../services/energy_data_service.dart';

/// Provider for the EnergyDataService instance
final energyDataServiceProvider = Provider<EnergyDataService>((ref) {
  final service = EnergyDataService();
  
  // Dispose when provider is destroyed
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

/// Stream provider for live energy data
/// Updates every time Firebase receives new data from ESP32 (every ~1 second)
final liveEnergyStreamProvider = StreamProvider<EnergyData>((ref) {
  final service = ref.watch(energyDataServiceProvider);
  
  return service.getLiveEnergyStream();
});

/// Provider for current energy data with loading state
/// Use this in widgets to display real-time energy information
final liveEnergyProvider = Provider<AsyncValue<EnergyData>>((ref) {
  return ref.watch(liveEnergyStreamProvider);
});

/// Provider for just the total energy value (for simple displays)
final totalEnergyProvider = Provider<AsyncValue<double>>((ref) {
  final energyAsync = ref.watch(liveEnergyProvider);
  
  return energyAsync.when(
    data: (energy) => AsyncValue.data(energy.totalEnergyKWh),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Provider for just the total power value (for simple displays)
final totalPowerProvider = Provider<AsyncValue<double>>((ref) {
  final energyAsync = ref.watch(liveEnergyProvider);
  
  return energyAsync.when(
    data: (energy) => AsyncValue.data(energy.totalPower),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Provider for energy summary calculations
/// Provides weekly and monthly projections
final energySummaryProvider = Provider<AsyncValue<EnergySummary>>((ref) {
  final energyAsync = ref.watch(liveEnergyProvider);
  
  return energyAsync.when(
    data: (energy) => AsyncValue.data(EnergySummary.fromEnergyData(energy)),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Class containing calculated energy summaries
class EnergySummary {
  /// Today's energy consumption in kWh
  final double todayKWh;
  
  /// Today's cost in Rs
  final double todayCost;
  
  /// Estimated weekly energy in kWh
  final double weeklyEstimateKWh;
  
  /// Estimated weekly cost in Rs
  final double weeklyEstimateCost;
  
  /// Projected monthly energy in kWh
  final double monthlyProjectionKWh;
  
  /// Projected monthly cost in Rs
  final double monthlyProjectionCost;
  
  /// Current power in Watts
  final double currentPower;
  
  /// Color for power display based on level
  final int powerColorValue;
  
  /// Formatted strings for display
  final String formattedTodayKWh;
  final String formattedTodayCost;
  final String formattedWeeklyKWh;
  final String formattedWeeklyCost;
  final String formattedMonthlyCost;
  final String formattedPower;
  
  /// Time since last update
  final String timeSinceUpdate;
  
  /// Whether data is fresh (within last 30 seconds)
  final bool isFresh;

  const EnergySummary({
    required this.todayKWh,
    required this.todayCost,
    required this.weeklyEstimateKWh,
    required this.weeklyEstimateCost,
    required this.monthlyProjectionKWh,
    required this.monthlyProjectionCost,
    required this.currentPower,
    required this.powerColorValue,
    required this.formattedTodayKWh,
    required this.formattedTodayCost,
    required this.formattedWeeklyKWh,
    required this.formattedWeeklyCost,
    required this.formattedMonthlyCost,
    required this.formattedPower,
    required this.timeSinceUpdate,
    required this.isFresh,
  });

  /// Create from EnergyData model
  factory EnergySummary.fromEnergyData(EnergyData data) {
    return EnergySummary(
      todayKWh: data.totalEnergyKWh,
      todayCost: data.totalCost,
      weeklyEstimateKWh: data.weeklyEstimateKWh,
      weeklyEstimateCost: data.weeklyEstimateCost,
      monthlyProjectionKWh: data.monthlyProjectionKWh,
      monthlyProjectionCost: data.monthlyProjectionCost,
      currentPower: data.totalPower,
      powerColorValue: data.getPowerColor().value,
      formattedTodayKWh: data.formattedEnergy,
      formattedTodayCost: data.formattedCost,
      formattedWeeklyKWh: '${data.weeklyEstimateKWh.toStringAsFixed(2)} kWh',
      formattedWeeklyCost: 'Rs ${data.weeklyEstimateCost.toStringAsFixed(2)}',
      formattedMonthlyCost: 'Rs ${data.monthlyProjectionCost.toStringAsFixed(2)}',
      formattedPower: data.formattedPower,
      timeSinceUpdate: data.timeSinceUpdate,
      isFresh: data.isFresh,
    );
  }

  /// Get power color based on power level
  /// Green: 0-100W, Yellow: 100-500W, Orange: 500-1000W, Red: >1000W
  static int getPowerColor(double power) {
    if (power <= 100) return 0xFF4CAF50; // Green
    if (power <= 500) return 0xFFFFC107; // Yellow
    if (power <= 1000) return 0xFFFF9800; // Orange
    return 0xFFF44336; // Red
  }
}

/// Provider for circuit breakdown data
final circuitBreakdownProvider = Provider<AsyncValue<CircuitBreakdown>>((ref) {
  final energyAsync = ref.watch(liveEnergyProvider);
  
  return energyAsync.when(
    data: (energy) => AsyncValue.data(CircuitBreakdown.fromEnergyData(energy)),
    loading: () => const AsyncValue.loading(),
    error: (err, stack) => AsyncValue.error(err, stack),
  );
});

/// Circuit breakdown data class
class CircuitBreakdown {
  final double circuit1Energy;
  final double circuit2Energy;
  final double circuit1Power;
  final double circuit2Power;
  final double totalEnergy;
  final double totalPower;
  
  double get circuit1Percentage => 
      totalEnergy > 0 ? (circuit1Energy / totalEnergy) * 100 : 0;
  
  double get circuit2Percentage => 
      totalEnergy > 0 ? (circuit2Energy / totalEnergy) * 100 : 0;

  const CircuitBreakdown({
    required this.circuit1Energy,
    required this.circuit2Energy,
    required this.circuit1Power,
    required this.circuit2Power,
    required this.totalEnergy,
    required this.totalPower,
  });

  factory CircuitBreakdown.fromEnergyData(EnergyData data) {
    return CircuitBreakdown(
      circuit1Energy: data.circuit1Energy,
      circuit2Energy: data.circuit2Energy,
      circuit1Power: data.power1,
      circuit2Power: data.power2,
      totalEnergy: data.totalEnergyKWh,
      totalPower: data.totalPower,
    );
  }
}

/// State class for energy provider with connection status
class EnergyConnectionState {
  final bool isConnected;
  final String? errorMessage;
  final DateTime? lastUpdateTime;

  const EnergyConnectionState({
    this.isConnected = false,
    this.errorMessage,
    this.lastUpdateTime,
  });

  EnergyConnectionState copyWith({
    bool? isConnected,
    String? errorMessage,
    DateTime? lastUpdateTime,
  }) {
    return EnergyConnectionState(
      isConnected: isConnected ?? this.isConnected,
      errorMessage: errorMessage ?? this.errorMessage,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }
}
