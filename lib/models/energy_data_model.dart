import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Model class for live energy data from Firebase
/// Contains all energy-related readings and calculated projections
class EnergyData {
  /// Total energy consumed today in kWh (from Firebase totalEnergy_kWh)
  final double totalEnergyKWh;

  /// Energy consumed by circuit 1 in kWh
  final double circuit1Energy;

  /// Energy consumed by circuit 2 in kWh
  final double circuit2Energy;

  /// Total cost in Rs (from Firebase totalCost)
  final double totalCost;

  /// Current total power in Watts (from Firebase totalPower)
  final double totalPower;

  /// Current voltage reading
  final double voltage;

  /// Current for circuit 1
  final double current1;

  /// Current for circuit 2
  final double current2;

  /// Device temperature
  final double temperature;

  /// Power for circuit 1
  final double power1;

  /// Power for circuit 2
  final double power2;

  /// Timestamp of the reading
  final DateTime timestamp;

  /// Cost per unit (Rs per kWh) - default 8.5
  final double costPerUnit;

  const EnergyData({
    this.totalEnergyKWh = 0.0,
    this.circuit1Energy = 0.0,
    this.circuit2Energy = 0.0,
    this.totalCost = 0.0,
    this.totalPower = 0.0,
    this.voltage = 0.0,
    this.current1 = 0.0,
    this.current2 = 0.0,
    this.temperature = 0.0,
    this.power1 = 0.0,
    this.power2 = 0.0,
    required this.timestamp,
    this.costPerUnit = 8.5,
  });

  /// Create from Firebase data snapshot
  factory EnergyData.fromFirebase(Map<String, dynamic> data, {double costPerUnit = 8.5}) {
    // Helper to safely parse numeric values
    double parseDouble(String key, {double defaultValue = 0.0}) {
      final value = data[key];
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Parse timestamp - can be int (Unix timestamp) or string
    DateTime parseTimestamp() {
      final ts = data['timestamp'];
      if (ts == null) return DateTime.now();
      if (ts is int) {
        // Handle both seconds and milliseconds
        if (ts > 10000000000) {
          return DateTime.fromMillisecondsSinceEpoch(ts);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        }
      }
      if (ts is String) {
        final parsed = int.tryParse(ts);
        if (parsed != null) {
          if (parsed > 10000000000) {
            return DateTime.fromMillisecondsSinceEpoch(parsed);
          } else {
            return DateTime.fromMillisecondsSinceEpoch(parsed * 1000);
          }
        }
      }
      return DateTime.now();
    }

    return EnergyData(
      totalEnergyKWh: parseDouble('totalEnergy_kWh'),
      circuit1Energy: parseDouble('circuit1Energy_kWh'),
      circuit2Energy: parseDouble('circuit2Energy_kWh'),
      totalCost: parseDouble('totalCost'),
      totalPower: parseDouble('totalPower'),
      voltage: parseDouble('voltage'),
      current1: parseDouble('current1'),
      current2: parseDouble('current2'),
      temperature: parseDouble('temperature'),
      power1: parseDouble('power1'),
      power2: parseDouble('power2'),
      timestamp: parseTimestamp(),
      costPerUnit: costPerUnit,
    );
  }

  /// Calculate weekly estimate: daily × 7
  double get weeklyEstimateKWh => totalEnergyKWh * 7;

  /// Calculate weekly cost estimate
  double get weeklyEstimateCost => weeklyEstimateKWh * costPerUnit;

  /// Calculate monthly projection: daily × 30
  double get monthlyProjectionKWh => totalEnergyKWh * 30;

  /// Calculate monthly cost projection
  double get monthlyProjectionCost => monthlyProjectionKWh * costPerUnit;

  /// Format energy with proper units (kWh)
  String get formattedEnergy => '${totalEnergyKWh.toStringAsFixed(3)} kWh';

  /// Format cost in Rs
  String get formattedCost => 'Rs ${totalCost.toStringAsFixed(2)}';

  /// Format power with color indication
  String get formattedPower => '${totalPower.toStringAsFixed(1)} W';

  /// Get color based on power level
  /// Green: 0-100W, Yellow: 100-500W, Orange: 500-1000W, Red: >1000W
  Color getPowerColor() {
    if (totalPower <= 100) return const Color(0xFF4CAF50); // Green
    if (totalPower <= 500) return const Color(0xFFFFC107); // Yellow
    if (totalPower <= 1000) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFF44336); // Red
  }

  /// Check if data is fresh (within last 30 seconds)
  bool get isFresh {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    return diff.inSeconds < 30;
  }

  /// Get time since last update as readable string
  String get timeSinceUpdate {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inSeconds < 5) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  /// Create a copy with updated values
  EnergyData copyWith({
    double? totalEnergyKWh,
    double? circuit1Energy,
    double? circuit2Energy,
    double? totalCost,
    double? totalPower,
    double? voltage,
    double? current1,
    double? current2,
    double? temperature,
    double? power1,
    double? power2,
    DateTime? timestamp,
    double? costPerUnit,
  }) {
    return EnergyData(
      totalEnergyKWh: totalEnergyKWh ?? this.totalEnergyKWh,
      circuit1Energy: circuit1Energy ?? this.circuit1Energy,
      circuit2Energy: circuit2Energy ?? this.circuit2Energy,
      totalCost: totalCost ?? this.totalCost,
      totalPower: totalPower ?? this.totalPower,
      voltage: voltage ?? this.voltage,
      current1: current1 ?? this.current1,
      current2: current2 ?? this.current2,
      temperature: temperature ?? this.temperature,
      power1: power1 ?? this.power1,
      power2: power2 ?? this.power2,
      timestamp: timestamp ?? this.timestamp,
      costPerUnit: costPerUnit ?? this.costPerUnit,
    );
  }

  @override
  String toString() {
    return 'EnergyData(energy: ${formattedEnergy}, cost: ${formattedCost}, '
        'power: ${formattedPower}, timestamp: $timestamp)';
  }
}
