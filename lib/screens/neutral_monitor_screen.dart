import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme.dart';
import '../core/constants.dart';

class NeutralMonitorScreen extends StatefulWidget {
  const NeutralMonitorScreen({super.key});

  @override
  State<NeutralMonitorScreen> createState() => _NeutralMonitorScreenState();
}

class _NeutralMonitorScreenState extends State<NeutralMonitorScreen> {
  // Firebase reference for live streaming
  late final DatabaseReference _readingsRef;

  @override
  void initState() {
    super.initState();
    _readingsRef = FirebaseDatabase.instance
        .ref('${AppConstants.deviceId}/readings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Neutral Monitor',
          style: AppTypography.heading3,
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _readingsRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildError('Error: ${snapshot.error}');
          }

          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            );
          }

          // Parse readings from Firebase
          final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          
          // Read current values - use currentNeutral key
          final current1 = (data['current1'] as num?)?.toDouble() ?? 0.0;
          final currentNeutral = (data['currentNeutral'] as num?)?.toDouble() ?? 0.0;
          
          // Read leakage directly from Firebase (ESP32 calculates it)
          // Fallback to local calculation if not available
          double leakageMa;
          if (data['leakage_mA'] != null) {
            leakageMa = (data['leakage_mA'] as num).toDouble();
          } else {
            leakageMa = ((current1 - currentNeutral).abs() * 1000);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leakage Status Card at top
                _buildLeakageStatusCard(leakageMa),
                const SizedBox(height: 16),
                
                // Current readings
                _buildCurrentReadings(current1, currentNeutral),
                const SizedBox(height: 24),
                
                // Warning logic cards based on thresholds
                _buildWarningCard(leakageMa),
                const SizedBox(height: 24),
                
                // Live Current Comparison Bar Chart
                Text(
                  'Live Current Comparison',
                  style: AppTypography.heading3,
                ),
                const SizedBox(height: 16),
                
                Container(
                  height: 250,
                  padding: const EdgeInsets.all(16),
                  decoration: AppDecorations.card,
                  child: _buildCurrentComparisonBarChart(current1, currentNeutral),
                ),
                
                const SizedBox(height: 24),
                
                // Explanation
                _buildExplanationCard(),
                
                const SizedBox(height: 100),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeakageStatusCard(double leakageMa) {
    // Color coding: green <10mA, orange 10-25mA, red >25mA
    Color statusColor;
    String statusText;
    
    if (leakageMa < 10) {
      statusColor = const Color(0xFF4CAF50); // Green
      statusText = 'NORMAL';
    } else if (leakageMa <= 25) {
      statusColor = const Color(0xFFFF9800); // Orange
      statusText = 'WARNING';
    } else {
      statusColor = const Color(0xFFF44336); // Red
      statusText = 'CRITICAL';
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                statusText,
                style: AppTypography.orbitron(
                  size: 18,
                  weight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${leakageMa.toStringAsFixed(2)} mA',
            style: AppTypography.shareTechMono(
              size: 36,
              weight: FontWeight.bold,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Earth Leakage Current',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard(double leakageMa) {
    // Warning logic based on thresholds
    if (leakageMa > 25) {
      // RED card: Critical
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF44336).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFF44336),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning_amber,
              color: const Color(0xFFF44336),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CRITICAL: Earth leakage detected',
                    style: AppTypography.dmSans(
                      weight: FontWeight.bold,
                      size: 16,
                      color: const Color(0xFFF44336),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Trip relay immediately. Leakage exceeds safe threshold (>25mA).',
                    style: AppTypography.bodySmall.copyWith(
                      color: const Color(0xFFF44336),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (leakageMa > 10) {
      // ORANGE card: Warning
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFF9800).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFF9800),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.warning,
              color: const Color(0xFFFF9800),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WARNING: Leakage current above safe threshold',
                    style: AppTypography.dmSans(
                      weight: FontWeight.bold,
                      size: 16,
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Leakage is between 10-25mA. Monitor closely.',
                    style: AppTypography.bodySmall.copyWith(
                      color: const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else if (leakageMa < 1.5) {
      // GREEN card: Normal
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF4CAF50),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: const Color(0xFF4CAF50),
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Normal — no leakage detected',
                    style: AppTypography.dmSans(
                      weight: FontWeight.bold,
                      size: 16,
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Leakage is below 1.5mA. System is safe.',
                    style: AppTypography.bodySmall.copyWith(
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    // No card for intermediate values (1.5mA - 10mA)
    return const SizedBox.shrink();
  }

  Widget _buildCurrentReadings(double current1, double currentNeutral) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card,
      child: Row(
        children: [
          Expanded(
            child: _buildCurrentColumn(
              'Live Wire (L)',
              current1,
              const Color(0xFF2196F3), // Blue
              Icons.electric_bolt,
            ),
          ),
          Container(
            width: 1,
            height: 80,
            color: AppColors.border,
          ),
          Expanded(
            child: _buildCurrentColumn(
              'Neutral Wire (N)',
              currentNeutral,
              const Color(0xFFFF9800), // Orange
              Icons.compare_arrows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentColumn(String label, double value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${value.toStringAsFixed(2)} A',
          style: AppTypography.shareTechMono(
            size: 22,
            weight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildExplanationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                color: AppColors.secondary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'What is Neutral Monitoring?',
                style: AppTypography.dmSans(weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'In a healthy electrical system, the current in the live wire should equal the current in the neutral wire. If these differ significantly, it indicates current leakage to earth (earth leakage), which can be a shock hazard or fire risk.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Thresholds:\n• < 1.5mA: Normal, no action needed\n• 10-25mA: Warning, monitor closely\n• > 25mA: Critical, trip relay immediately',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentComparisonBarChart(double current1, double currentNeutral) {
    // Find max value for scaling
    final maxValue = [current1, currentNeutral, 0.1].reduce((a, b) => a > b ? a : b);
    final maxY = (maxValue * 1.2).ceilToDouble(); // Add 20% headroom
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY > 0 ? maxY : 1,
        minY: 0,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: AppColors.border,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toStringAsFixed(1)}A',
                  style: AppTypography.caption,
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final labels = ['Live (L)', 'Neutral (N)'];
                if (value.toInt() >= 0 && value.toInt() < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[value.toInt()],
                      style: AppTypography.bodySmall,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          // Live wire bar (Blue)
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: current1,
                color: const Color(0xFF2196F3),
                width: 40,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          ),
          // Neutral wire bar (Orange)
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: currentNeutral,
                color: const Color(0xFFFF9800),
                width: 40,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ],
          ),
        ],
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: AppColors.cardBackground,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final labels = ['Live Wire', 'Neutral Wire'];
              return BarTooltipItem(
                '${labels[groupIndex]}\n${rod.toY.toStringAsFixed(3)} A',
                AppTypography.body.copyWith(
                  color: groupIndex == 0 
                      ? const Color(0xFF2196F3) 
                      : const Color(0xFFFF9800),
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.danger,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading neutral data',
            style: AppTypography.heading3,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
