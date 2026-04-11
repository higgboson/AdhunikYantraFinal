import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme.dart';
import '../providers/energy_provider.dart';
import '../providers/settings_provider.dart';

/// Live Energy Summary Widget
/// Displays real-time energy data from Firebase with automatic updates
/// Shows: Today's energy, weekly estimate, monthly projection, and current power
class LiveEnergySummary extends ConsumerWidget {
  final bool showTitle;
  final bool showLastUpdated;
  final EdgeInsets padding;
  final VoidCallback? onRefresh;

  const LiveEnergySummary({
    super.key,
    this.showTitle = true,
    this.showLastUpdated = true,
    this.padding = const EdgeInsets.all(16),
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(energySummaryProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return settingsAsync.when(
      data: (settings) {
        return summaryAsync.when(
          data: (summary) => _buildContent(context, summary, settings.electricityRateRs),
          loading: () => _buildLoadingState(),
          error: (err, stack) => _buildErrorState(context, ref, err),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildErrorState(context, ref, 'Settings error'),
    );
  }

  Widget _buildContent(BuildContext context, EnergySummary summary, double rate) {
    final powerColor = Color(summary.powerColorValue);

    return Container(
      padding: padding,
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and live indicator
          if (showTitle) ...[
            Row(
              children: [
                Icon(
                  Icons.bolt,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Energy Summary',
                  style: AppTypography.heading3,
                ),
                const Spacer(),
                // Live indicator with pulsing dot
                _buildLiveIndicator(summary.isFresh),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Today (Live) - Energy and Cost
          _buildSummaryRow(
            label: 'Today (Live):',
            value: '${summary.formattedTodayKWh}, ${summary.formattedTodayCost}',
            icon: Icons.today,
            color: AppColors.primary,
          ),

          const SizedBox(height: 12),

          // Est. Week - Energy and Cost
          _buildSummaryRow(
            label: 'Est. Week:',
            value: '${summary.formattedWeeklyKWh}, ${summary.formattedWeeklyCost}',
            icon: Icons.calendar_view_week,
            color: AppColors.secondary,
          ),

          const SizedBox(height: 12),

          // Projected Monthly Cost
          _buildSummaryRow(
            label: 'Projected Monthly:',
            value: summary.formattedMonthlyCost,
            icon: Icons.calendar_month,
            color: AppColors.success,
          ),

          const SizedBox(height: 12),

          // Current Power with color coding
          _buildPowerRow(
            label: 'Current Power:',
            value: summary.formattedPower,
            powerColor: powerColor,
            powerLevel: summary.currentPower,
          ),

          // Last updated timestamp
          if (showLastUpdated) ...[
            const SizedBox(height: 16),
            const Divider(color: AppColors.border),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Updated: ${summary.timeSinceUpdate}',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (onRefresh != null)
                  GestureDetector(
                    onTap: onRefresh,
                    child: Row(
                      children: [
                        Icon(
                          Icons.refresh,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Refresh',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveIndicator(bool isFresh) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isFresh ? AppColors.success : AppColors.warning,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'LIVE',
          style: AppTypography.caption.copyWith(
            color: isFresh ? AppColors.success : AppColors.warning,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppTypography.shareTechMono(
            size: 16,
            weight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildPowerRow({
    required String label,
    required String value,
    required Color powerColor,
    required double powerLevel,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: powerColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.electric_bolt,
            size: 18,
            color: powerColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: powerColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: powerColor.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Text(
            value,
            style: AppTypography.shareTechMono(
              size: 16,
              weight: FontWeight.bold,
              color: powerColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: padding,
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showTitle) ...[
            Row(
              children: [
                Icon(
                  Icons.bolt,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Energy Summary',
                  style: AppTypography.heading3,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // Skeleton loading rows
          _buildSkeletonRow(),
          const SizedBox(height: 12),
          _buildSkeletonRow(),
          const SizedBox(height: 12),
          _buildSkeletonRow(),
          const SizedBox(height: 12),
          _buildSkeletonRow(),
        ],
      ),
    );
  }

  Widget _buildSkeletonRow() {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 100,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
    return Container(
      padding: padding,
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showTitle) ...[
            Row(
              children: [
                Icon(
                  Icons.bolt,
                  color: AppColors.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Energy Summary',
                  style: AppTypography.heading3,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Icon(
            Icons.error_outline,
            color: AppColors.danger,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'Unable to load energy data',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            error.toString(),
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              // Invalidate the provider to trigger a refresh
              ref.invalidate(liveEnergyStreamProvider);
              if (onRefresh != null) onRefresh!();
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size(120, 36),
            ),
          ),
        ],
      ),
    );
  }
}
