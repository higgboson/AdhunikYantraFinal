import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/circuit_model.dart';
import '../providers/device_provider.dart';
import '../widgets/current_bar.dart';
import '../widgets/ewma_chip.dart';
import '../widgets/offline_banner.dart';

class CircuitCard extends ConsumerWidget {
  final Circuit circuit;
  final int circuitIndex;
  final VoidCallback? onTap;
  final bool isOffline;

  const CircuitCard({
    super.key,
    required this.circuit,
    required this.circuitIndex,
    this.onTap,
    this.isOffline = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch live ADS readings for real-time current mapping
    final adsReadingsAsync = ref.watch(adsReadingsProvider);
    
    // Calculate mapped current based on circuit name/area
    final double liveCurrent = adsReadingsAsync.when(
      data: (readings) => _getMappedCurrent(readings),
      loading: () => circuit.current,
      error: (_, __) => circuit.current,
    );
    
    // Get live power from readings
    final double livePower = adsReadingsAsync.when(
      data: (readings) => _getMappedPower(readings),
      loading: () => circuit.power,
      error: (_, __) => circuit.power,
    );
    
    // Get live temp from readings
    final double liveTemp = adsReadingsAsync.when(
      data: (readings) => _getMappedTemp(readings),
      loading: () => circuit.temp,
      error: (_, __) => circuit.temp,
    );

    return Container(
      decoration: AppDecorations.cardGlow,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with StreamBuilder for relay switch
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          circuit.name,
                          style: AppTypography.heading3.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        if (circuit.faultActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              circuit.faultType.displayName,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Real-time toggle switch with StreamBuilder
                  _buildRealtimeSwitch(),
                ],
              ),
              
              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),
              
              // Metrics with live mapped current
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMetric(
                    'Current',
                    '${liveCurrent.toStringAsFixed(2)} A',
                    AppColors.getCurrentColor(liveCurrent),
                  ),
                  _buildMetric(
                    'Power',
                    '${livePower.toStringAsFixed(0)} W',
                    AppColors.primary,
                  ),
                  _buildMetric(
                    'Temp',
                    '${liveTemp.toStringAsFixed(1)}°C',
                    AppColors.getTempColor(liveTemp),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Current bar with live current
              CurrentBar(
                current: liveCurrent,
                maxCurrent: circuit.mcbRating,
              ),
              
              const SizedBox(height: 12),
              
              // EWMA Status
              Row(
                children: [
                  EwmaChip(status: circuit.ewmaStatus),
                  const Spacer(),
                  if (circuit.ewmaTrained)
                    Text(
                      'Baseline: ${circuit.ewmaBaseline.toStringAsFixed(0)}W',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get live power from readings based on circuit index
  double _getMappedPower(Map<String, dynamic> readings) {
    // Use power1 for Circuit 1, power2 for Circuit 2
    if (circuitIndex == 0) {
      // Circuit 1 (Living Room) - use power1
      final power1 = (readings['power1'] as num?)?.toDouble() ?? 0.0;
      if (power1 > 0) return power1;
      
      // Calculate from current if available
      final current1 = (readings['current1'] as num?)?.toDouble() ?? 0.0;
      final voltage = (readings['voltage'] as num?)?.toDouble() ?? 230.0;
      if (current1 > 0) return voltage * current1;
    } else if (circuitIndex == 1) {
      // Circuit 2 (Kitchen) - use power2
      final power2 = (readings['power2'] as num?)?.toDouble() ?? 0.0;
      if (power2 > 0) return power2;
      
      // Calculate from current if available
      final current2 = (readings['current2'] as num?)?.toDouble() ?? 0.0;
      final voltage = (readings['voltage'] as num?)?.toDouble() ?? 230.0;
      if (current2 > 0) return voltage * current2;
    }
    
    return circuit.power;
  }
  
  /// Get live temp from readings
  double _getMappedTemp(Map<String, dynamic> readings) {
    return (readings['temperature'] as num?)?.toDouble() ?? 
           (readings['temp_c'] as num?)?.toDouble() ?? 
           circuit.temp;
  }
  
  /// Map circuit index to current readings
  /// - Circuit 1 (index 0) -> current1
  /// - Circuit 2 (index 1) -> current2
  double _getMappedCurrent(Map<String, dynamic> readings) {
    if (circuitIndex == 0) {
      // Circuit 1: use current1
      return (readings['current1'] as num?)?.toDouble() ?? circuit.current;
    } else if (circuitIndex == 1) {
      // Circuit 2: use current2
      return (readings['current2'] as num?)?.toDouble() ?? circuit.current;
    }
    
    return circuit.current;
  }

  /// Task 3: Real-time toggle switch with StreamBuilder - disabled when offline
  Widget _buildRealtimeSwitch() {
    final circuitId = AppConstants.circuitIds[circuitIndex];
    
    return OfflineDisabledOverlay(
      isDisabled: isOffline,
      message: 'Relay control requires internet connection',
      child: StreamBuilder<DatabaseEvent>(
        stream: FirebaseDatabase.instance
            .ref('${AppConstants.deviceId}/relay/$circuitId')
            .onValue,
        builder: (context, snapshot) {
          // Get relay state from Firebase stream - default to FALSE (OFF) if no data
          final relayState = snapshot.data?.snapshot.value as bool? ?? false;
          
          return Switch(
            value: relayState,
            onChanged: circuit.faultActive || isOffline
                ? null 
                : (value) async {
                    // Update Firebase relay state
                    await FirebaseDatabase.instance
                        .ref('${AppConstants.deviceId}/relay/$circuitId')
                        .set(value);
                  },
            activeThumbColor: AppColors.primary,
            inactiveThumbColor: AppColors.textSecondary,
          );
        },
      ),
    );
  }

  Widget _buildMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.caption,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.shareTechMono(
            size: 14,
            weight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
