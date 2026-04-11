import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/live_data_model.dart';
import 'offline_banner.dart';

class SummaryCard extends StatelessWidget {
  final LiveData liveData;
  final bool showCachedBadge;

  const SummaryCard({
    super.key,
    required this.liveData,
    this.showCachedBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.cardGlow,
      child: Column(
        children: [
          // Cached badge when offline
          if (showCachedBadge)
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CachedBadge(show: showCachedBadge),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _buildMetric(
                  'Voltage',
                  liveData.voltage.toStringAsFixed(1),
                  'V',
                  AppColors.getVoltageColor(liveData.voltage),
                  Icons.electric_bolt,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: AppColors.border,
              ),
              Expanded(
                child: _buildMetric(
                  'Total Power',
                  liveData.totalPower.toStringAsFixed(0),
                  'W',
                  AppColors.primary,
                  Icons.offline_bolt,
                ),
              ),
              Container(
                width: 1,
                height: 60,
                color: AppColors.border,
              ),
              Expanded(
                child: _buildMetric(
                  'Leakage',
                  liveData.leakage.toStringAsFixed(1),
                  'mA',
                  AppColors.getLeakageColor(liveData.leakage),
                  Icons.water_drop,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    String label,
    String value,
    String unit,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTypography.caption,
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: AppTypography.shareTechMono(
                size: 20,
                weight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(width: 2),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                unit,
                style: AppTypography.caption.copyWith(
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
