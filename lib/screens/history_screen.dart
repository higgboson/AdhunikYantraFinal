import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../core/offline_cache.dart';
import '../providers/settings_provider.dart';
import '../providers/circuit_provider.dart';
import '../providers/connectivity_provider.dart';
import '../providers/live_data_provider.dart';
import '../widgets/live_energy_summary.dart';
import '../widgets/offline_banner.dart';
import '../models/circuit_model.dart';
import 'dart:async';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _selectedRange = '24H';
  final List<String> _timeRanges = ['1H', '6H', '24H', '7D', '30D'];
  
  // Circuit selection for live monitoring
  Circuit? _selectedCircuit;
  
  // Live data history for graphs (last 60 points)
  final List<FlSpot> _powerHistory = [];
  final List<FlSpot> _currentHistory = [];
  int _dataPointCounter = 0;
  static const int _maxDataPoints = 60;
  
  // Live energy tracking
  double _todayKwh = 0.0;
  double _currentPower = 0.0;
  
  // Firebase stream subscription
  StreamSubscription<DatabaseEvent>? _readingsSubscription;
  double _liveCurrent = 0.0;
  double _livePower = 0.0;

  @override
  void initState() {
    super.initState();
    _setupFirebaseListener();
  }

  @override
  void dispose() {
    _readingsSubscription?.cancel();
    super.dispose();
  }

  void _setupFirebaseListener() {
    _readingsSubscription = FirebaseDatabase.instance
        .ref('${AppConstants.deviceId}/readings')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null && _selectedCircuit != null) {
        final readings = Map<String, dynamic>.from(event.snapshot.value as Map);
        
        // Get current based on circuit mapping
        final circuitName = _selectedCircuit!.name.toLowerCase();
        double current = 0.0;
        if (circuitName.contains('living room') || _selectedCircuit!.id == 'circuit_1') {
          current = (readings['current1'] as num?)?.toDouble() ?? 0.0;
        } else if (circuitName.contains('kitchen') || _selectedCircuit!.id == 'circuit_2') {
          current = (readings['current2'] as num?)?.toDouble() ?? 0.0;
        } else {
          current = _selectedCircuit!.current;
        }
        
        // Get power directly from readings or calculate
        double power = 0.0;
        if (_selectedCircuit!.id == 'circuit_1') {
          power = (readings['power1'] as num?)?.toDouble() ?? (current * 230.0);
        } else if (_selectedCircuit!.id == 'circuit_2') {
          power = (readings['power2'] as num?)?.toDouble() ?? (current * 230.0);
        } else {
          power = current * 230.0;
        }
        
        setState(() {
          _liveCurrent = current;
          _livePower = power;
          _currentPower = power;
          _updateLiveData(power, current);
        });
      }
    });
  }

  void _onCircuitSelected(Circuit? circuit) {
    setState(() {
      _selectedCircuit = circuit;
      // Clear history when switching circuits
      _powerHistory.clear();
      _currentHistory.clear();
      _dataPointCounter = 0;
      _liveCurrent = 0.0;
      _livePower = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'History & Analytics',
          style: AppTypography.heading3,
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Offline Banner
          OfflineBanner(isOffline: isOffline),
          
          // Main content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time Range Selector
                  _buildTimeRangeSelector(),
                  const SizedBox(height: 24),
                  
                  // Circuit Selector for Live Monitoring
                  _buildCircuitSelector(),
                  const SizedBox(height: 24),
                  
                  // Live Circuit Monitoring (if circuit selected)
                  if (_selectedCircuit != null) ...[
                    _buildLiveCircuitMonitoring(),
                    const SizedBox(height: 24),
                  ],
                  
                  // Live Energy Summary - Real-time from Firebase
                  const LiveEnergySummary(
                    showTitle: true,
                    showLastUpdated: true,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Total Power Chart (Historical)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Total Power Consumption History',
                          style: AppTypography.heading3,
                        ),
                      ),
                      if (isOffline)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Offline — cached data',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: AppDecorations.card,
                    child: LineChart(
                      isOffline 
                          ? _buildOfflinePowerChart()
                          : _buildTotalPowerChart(),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Recent Faults
                  Text(
                    'Recent Faults',
                    style: AppTypography.heading3,
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFaultHistoryList(),
                  
                  const SizedBox(height: 24),
                  
                  // Export Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: isOffline ? null : () {
                        // Export PDF
                      },
                      icon: const Icon(Icons.download),
                      label: Text(
                        'Export PDF Report',
                        style: AppTypography.dmSans(
                          size: 16,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: _timeRanges.map((range) {
          final isSelected = range == _selectedRange;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedRange = range;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  range,
                  textAlign: TextAlign.center,
                  style: AppTypography.dmSans(
                    size: 14,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.background : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCircuitSelector() {
    final circuitsAsync = ref.watch(circuitsProvider);
    
    return circuitsAsync.when(
      data: (circuits) {
        if (circuits.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: AppDecorations.card,
            child: Text(
              'No circuits available',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          );
        }
        
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Circuit for Live Monitoring',
                style: AppTypography.dmSans(weight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: circuits.map((circuit) {
                  final isSelected = _selectedCircuit?.id == circuit.id;
                  return GestureDetector(
                    onTap: () {
                      _onCircuitSelected(isSelected ? null : circuit);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.electric_bolt,
                            size: 16,
                            color: isSelected ? AppColors.background : AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            circuit.name,
                            style: AppTypography.dmSans(
                              weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected ? AppColors.background : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 80,
        decoration: AppDecorations.card,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppDecorations.card,
        child: Text(
          'Error loading circuits',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildLiveCircuitMonitoring() {
    if (_selectedCircuit == null) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.online_prediction,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Live: ${_selectedCircuit!.name}',
              style: AppTypography.heading3,
            ),
            const SizedBox(width: 12),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Live metrics
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card,
          child: Row(
            children: [
              Expanded(
                child: _buildLiveMetric(
                  'Current',
                  '${_liveCurrent.toStringAsFixed(2)} A',
                  AppColors.secondary,
                ),
              ),
              Container(
                width: 1,
                height: 50,
                color: AppColors.border,
              ),
              Expanded(
                child: _buildLiveMetric(
                  'Power',
                  '${_livePower.toStringAsFixed(0)} W',
                  AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Live Power Graph
        Text(
          'Live Power',
          style: AppTypography.dmSans(weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: AppDecorations.card,
          child: _buildLivePowerChart(),
        ),
        
        const SizedBox(height: 16),
        
        // Live Current Graph
        Text(
          'Live Current',
          style: AppTypography.dmSans(weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          height: 150,
          padding: const EdgeInsets.all(12),
          decoration: AppDecorations.card,
          child: _buildLiveCurrentChart(),
        ),
      ],
    );
  }

  Widget _buildLiveMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.shareTechMono(
            size: 20,
            weight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _updateLiveData(double power, double current) {
    // Add new data points
    _powerHistory.add(FlSpot(_dataPointCounter.toDouble(), power));
    _currentHistory.add(FlSpot(_dataPointCounter.toDouble(), current));
    
    // Keep only last 60 points
    if (_powerHistory.length > _maxDataPoints) {
      _powerHistory.removeAt(0);
      _currentHistory.removeAt(0);
      
      // Re-index spots to maintain continuous X axis
      for (int i = 0; i < _powerHistory.length; i++) {
        _powerHistory[i] = FlSpot(i.toDouble(), _powerHistory[i].y);
        _currentHistory[i] = FlSpot(i.toDouble(), _currentHistory[i].y);
      }
      _dataPointCounter = _maxDataPoints;
    } else {
      _dataPointCounter++;
    }
    
    // Update today's energy (simple integration)
    // Add energy consumed in last second (power in watts -> kWh)
    _todayKwh += (power / 1000.0) * (1.0 / 3600.0); // Convert W to kWh per second
  }

  Widget _buildLivePowerChart() {
    if (_powerHistory.isEmpty) {
      return const Center(child: Text('Collecting data...'));
    }
    
    final maxPower = _powerHistory.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minPower = _powerHistory.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    // Ensure min and max are not equal to avoid range issues
    final yMax = maxPower > minPower ? maxPower * 1.2 : maxPower + 100;
    final yMin = maxPower > minPower ? minPower * 0.8 : 0.0;
    
    return LineChart(
      LineChartData(
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
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}W',
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_maxDataPoints - 1).toDouble(),
        minY: yMin,
        maxY: yMax,
        lineBarsData: [
          LineChartBarData(
            spots: List.from(_powerHistory),
            isCurved: true,
            color: const Color(0xFF00FF88), // Green as requested
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00FF88).withOpacity(0.3),
                  const Color(0xFF00FF88).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCurrentChart() {
    if (_currentHistory.isEmpty) {
      return const Center(child: Text('Collecting data...'));
    }
    
    final maxCurrent = _currentHistory.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minCurrent = _currentHistory.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    // Ensure min and max are not equal to avoid range issues
    final yMax = maxCurrent > minCurrent ? maxCurrent * 1.2 : maxCurrent + 1.0;
    final yMin = maxCurrent > minCurrent ? minCurrent * 0.8 : 0.0;
    
    return LineChart(
      LineChartData(
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
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toStringAsFixed(1)}A',
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_maxDataPoints - 1).toDouble(),
        minY: yMin,
        maxY: yMax,
        lineBarsData: [
          LineChartBarData(
            spots: List.from(_currentHistory),
            isCurved: true,
            color: const Color(0xFF00CCFF), // Blue as requested
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF00CCFF).withOpacity(0.3),
                  const Color(0xFF00CCFF).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveEnergySummary(double rate) {
    final todayCost = _todayKwh * rate;
    final weekKwh = _todayKwh * 7; // Estimate
    final weekCost = weekKwh * rate;
    final projectedMonthly = todayCost * 30;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'Today (Live)',
                  '${_todayKwh.toStringAsFixed(2)} kWh',
                  'Rs ${todayCost.toStringAsFixed(0)}',
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'Est. Week',
                  '${weekKwh.toStringAsFixed(1)} kWh',
                  'Rs ${weekCost.toStringAsFixed(0)}',
                  AppColors.secondary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Projected Monthly',
                style: AppTypography.body,
              ),
              Text(
                'Rs ${projectedMonthly.toStringAsFixed(0)}',
                style: AppTypography.numericLarge,
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Current Power: ${_currentPower.toStringAsFixed(0)}W',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergySummary(double rate) {
    // Mock data for demo
    const todayKwh = 8.5;
    final todayCost = todayKwh * rate;
    const weekKwh = 58.3;
    final weekCost = weekKwh * rate;
    final projectedMonthly = weekCost * 4.3;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Energy Summary',
            style: AppTypography.heading3,
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'Today',
                  '${todayKwh.toStringAsFixed(1)} kWh',
                  'Rs ${todayCost.toStringAsFixed(0)}',
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildSummaryItem(
                  'This Week',
                  '${weekKwh.toStringAsFixed(1)} kWh',
                  'Rs ${weekCost.toStringAsFixed(0)}',
                  AppColors.secondary,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Projected Monthly Bill',
                style: AppTypography.body,
              ),
              Text(
                'Rs ${projectedMonthly.toStringAsFixed(0)}',
                style: AppTypography.numericLarge,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.trending_down,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You are using 12% less energy than last week',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, String cost, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTypography.shareTechMono(
            size: 20,
            weight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          cost,
          style: AppTypography.bodySmall,
        ),
      ],
    );
  }

  Widget _buildFaultHistoryList() {
    // Mock fault data
    final faults = [
      {
        'type': 'OVERLOAD',
        'circuit': 'Living Room',
        'time': '2 hours ago',
        'resolved': true,
      },
      {
        'type': 'THERMAL',
        'circuit': 'Kitchen',
        'time': '1 day ago',
        'resolved': true,
      },
    ];
    
    return Column(
      children: faults.map((fault) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(16),
          decoration: AppDecorations.card,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fault['type'] as String,
                      style: AppTypography.dmSans(
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${fault['circuit']} • ${fault['time']}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Resolved',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryShimmer() {
    return Container(
      height: 200,
      decoration: AppDecorations.card,
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }

  LineChartData _buildTotalPowerChart() {
    // Generate mock data
    final spots = <FlSpot>[
      const FlSpot(0, 120),
      const FlSpot(1, 150),
      const FlSpot(2, 180),
      const FlSpot(3, 160),
      const FlSpot(4, 200),
      const FlSpot(5, 220),
      const FlSpot(6, 190),
      const FlSpot(7, 250),
      const FlSpot(8, 280),
      const FlSpot(9, 240),
      const FlSpot(10, 300),
      const FlSpot(11, 320),
    ];

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 50,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 100,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}W',
                style: AppTypography.caption,
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: 11,
      minY: 0,
      maxY: 400,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppColors.primary.withValues(alpha: 0.1),
          ),
        ),
      ],
    );
  }

  /// Build chart from cached power history when offline
  LineChartData _buildOfflinePowerChart() {
    final cachedHistory = OfflineCache.getPowerHistoryForChart();
    
    if (cachedHistory.isEmpty) {
      return _buildTotalPowerChart(); // Fallback to mock data
    }
    
    // Convert to FlSpot
    final spots = cachedHistory.map((data) {
      return FlSpot(data['x'] as double, data['y'] as double);
    }).toList();
    
    // Calculate min/max for Y axis
    final maxPower = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final minPower = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final yMax = maxPower > minPower ? maxPower * 1.2 : maxPower + 100;
    final yMin = maxPower > minPower ? minPower * 0.8 : 0.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 50,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 100,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}W',
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
            reservedSize: 30,
            interval: cachedHistory.length > 10 ? (cachedHistory.length / 5).ceil().toDouble() : 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < cachedHistory.length) {
                final minutesAgo = cachedHistory[index]['minutes_ago'] as int;
                String label;
                if (minutesAgo < 1) {
                  label = 'now';
                } else if (minutesAgo < 60) {
                  label = '${minutesAgo}m';
                } else {
                  label = '${minutesAgo ~/ 60}h';
                }
                return Text(
                  label,
                  style: AppTypography.caption.copyWith(fontSize: 10),
                );
              }
              return const Text('');
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (spots.length - 1).toDouble(),
      minY: yMin,
      maxY: yMax,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: AppColors.warning, // Use warning color to indicate offline/cached
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppColors.warning.withOpacity(0.3),
                AppColors.warning.withOpacity(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  LineChartData _buildCircuitChart() {
    final colors = [AppColors.primary, AppColors.secondary, AppColors.warning, AppColors.danger];
    
    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: AppColors.border,
            strokeWidth: 1,
          );
        },
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 50,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}W',
                style: AppTypography.caption,
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: List.generate(4, (index) {
        final spots = <FlSpot>[
          FlSpot(0, 30 + index * 20.0),
          FlSpot(1, 40 + index * 25.0),
          FlSpot(2, 35 + index * 22.0),
          FlSpot(3, 50 + index * 20.0),
          FlSpot(4, 45 + index * 24.0),
          FlSpot(5, 60 + index * 18.0),
          FlSpot(6, 55 + index * 22.0),
          FlSpot(7, 70 + index * 16.0),
        ];
        
        return LineChartBarData(
          spots: spots,
          isCurved: true,
          color: colors[index],
          barWidth: 2,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
        );
      }),
    );
  }
}
