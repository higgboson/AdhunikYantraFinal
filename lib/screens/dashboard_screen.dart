import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/live_data_model.dart';
import '../providers/live_data_provider.dart';
import '../providers/circuit_provider.dart';
import '../providers/fault_provider.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/circuit_card.dart';
import '../widgets/fault_banner.dart';
import '../widgets/live_dot.dart';
import '../widgets/summary_card.dart';
import '../widgets/offline_banner.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _alarmPlaying = false;
  bool _faultOverlayDismissed = false;
  Map<String, dynamic>? _currentFault;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAlarm() async {
    if (!_alarmPlaying) {
      // Play alarm sound repeatedly
      _alarmPlaying = true;
      // Using system alarm sound or beep
      await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
      _audioPlayer.onPlayerComplete.listen((_) {
        if (_alarmPlaying && mounted) {
          _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
        }
      });
    }
  }

  void _stopAlarm() {
    _alarmPlaying = false;
    _audioPlayer.stop();
  }

  void _dismissFaultOverlay() {
    setState(() {
      _faultOverlayDismissed = true;
    });
    _stopAlarm();
  }

 @override
Widget build(BuildContext context) {
  final liveDataAsync = ref.watch(liveDataProvider);
  final circuitsAsync = ref.watch(circuitsProvider);
  final faultsAsync = ref.watch(activeFaultsProvider);
  final isOffline = ref.watch(isOfflineProvider);

  return Scaffold(
    backgroundColor: AppColors.background,
    body: SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              // Offline Banner
              OfflineBanner(isOffline: isOffline),
              
              // Main content
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: _buildHeader(context, ref, liveDataAsync),
                    ),
                    
                    // Fault Banner
                    SliverToBoxAdapter(
                      child: faultsAsync.when(
                        data: (faults) => faults.isNotEmpty 
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: FaultBanner(
                                  fault: faults.first,
                                  onTap: () => context.push('/fault/${faults.first.id}'),
                                ),
                              )
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ),
                    
                    // Summary Cards
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: liveDataAsync.when(
                          data: (liveData) => SummaryCard(
                            liveData: liveData,
                            showCachedBadge: isOffline,
                          ),
                          loading: () => _buildSummaryShimmer(),
                          error: (_, __) => _buildSummaryError(),
                        ),
                      ),
                    ),
                    
                    // Ambient Temperature
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: liveDataAsync.when(
                          data: (liveData) => _buildAmbientTemp(liveData),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    
                    // Circuit Cards Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Your Circuits',
                              style: AppTypography.heading3,
                            ),
                            TextButton(
                              onPressed: () => context.push('/circuits'),
                              child: Text(
                                'See All',
                                style: AppTypography.body.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Circuit Cards
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: circuitsAsync.when(
                        data: (circuits) => SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final circuit = circuits[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: CircuitCard(
                                  circuit: circuit,
                                  circuitIndex: index,
                                  onTap: () => context.push('/circuit/${circuit.id}'),
                                  isOffline: isOffline,
                                ),
                              );
                            },
                            childCount: circuits.length,
                          ),
                        ),
                        loading: () => SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildCircuitShimmer(),
                            childCount: 4,
                          ),
                        ),
                        error: (error, _) => SliverToBoxAdapter(
                          child: _buildCircuitsError(),
                        ),
                      ),
                    ),
                    
                    const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
                  ],  // ← closes slivers list
                ),    // ← closes CustomScrollView
              ),      // ← closes Expanded
            ],        // ← closes Column children list
          ),          // ← ✅ ADD THIS: closes Column widget
          
          // Real-time Fault Overlay
          _buildFaultOverlay(),
          
        ],            // ← closes Stack children list
      ),              // ← closes Stack
    ),                // ← closes SafeArea
  );                  // ← closes Scaffold
}
  Widget _buildFaultOverlay() {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance
          .ref('${AppConstants.deviceId}/readings')
          .onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const SizedBox.shrink();
        }

        final readings = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final faultActive = readings['faultActive'] as bool? ?? false;
        final faultType = readings['faultType'] as String? ?? '';
        final voltage = (readings['voltage'] as num?)?.toDouble() ?? 0.0;
        final powerHeavy = (readings['powerHeavy'] as num?)?.toDouble() ?? 0.0;

        if (!faultActive || _faultOverlayDismissed) {
          _stopAlarm();
          return const SizedBox.shrink();
        }

        // Reset dismiss state when new fault comes
        if (_faultOverlayDismissed && faultActive) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _faultOverlayDismissed = false;
            });
          });
        }

        // Play alarm
        _playAlarm();

        return Container(
          color: Colors.red.withOpacity(0.95),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber,
                  color: Colors.white,
                  size: 80,
                ),
                const SizedBox(height: 24),
                Text(
                  '⚡ ${_getFaultDisplayName(faultType).toUpperCase()} DETECTED',
                  style: AppTypography.shareTechMono(
                    size: 24,
                    weight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      _buildFaultDetailRow('Voltage', '${voltage.toStringAsFixed(1)} V'),
                      const SizedBox(height: 8),
                      _buildFaultDetailRow('Power (Heavy)', '${powerHeavy.toStringAsFixed(1)} W'),
                      const SizedBox(height: 8),
                      _buildFaultDetailRow('Relay Status', 'TRIPPED'),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.block, color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'RELAY TRIPPED',
                        style: AppTypography.dmSans(
                          weight: FontWeight.bold,
                          color: Colors.red,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: _dismissFaultOverlay,
                  icon: const Icon(Icons.close),
                  label: const Text('DISMISS (DEV MODE)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    textStyle: AppTypography.dmSans(weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _getFaultDisplayName(String faultType) {
    switch (faultType.toLowerCase()) {
      case 'overvoltage':
        return 'Overvoltage';
      case 'undervoltage':
        return 'Undervoltage';
      case 'overcurrent':
        return 'Overcurrent';
      case 'leakage':
      case 'earth_leakage':
        return 'Earth Leakage';
      case 'thermal':
        return 'Thermal';
      default:
        return 'FAULT';
    }
  }

  Widget _buildFaultDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.body.copyWith(color: Colors.white70),
        ),
        Text(
          value,
          style: AppTypography.shareTechMono(
            size: 16,
            weight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // FIXED: Now determines LIVE status directly from the data stream
  Widget _buildHeader(BuildContext context, WidgetRef ref, AsyncValue<LiveData> liveDataAsync) {
    // If the stream is loading or has an error, show Reconnecting. If data is flowing, show LIVE.
    final isReconnecting = liveDataAsync.isLoading || liveDataAsync.hasError;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Logo
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.bolt,
              color: AppColors.background,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          
          // Title and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ADHUNIK',
                  style: AppTypography.orbitron(
                    size: 14,
                    weight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    const LiveDot(),
                    const SizedBox(width: 6),
                    Text(
                      isReconnecting ? 'RECONNECTING' : 'LIVE',
                      style: AppTypography.caption.copyWith(
                        color: isReconnecting ? AppColors.warning : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Notification bell
          IconButton(
            onPressed: () => context.push('/alerts'),
            icon: const Icon(
              Icons.notifications_outlined,
              color: AppColors.textPrimary,
            ),
          ),
          
          // Settings
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(
              Icons.settings_outlined,
              color: AppColors.textPrimary,
            ),
          ),
          
          // Developer Test Mode (hidden button with long press)
          GestureDetector(
            onLongPress: () => context.push('/developer-test'),
            child: IconButton(
              onPressed: null,
              icon: Icon(
                Icons.construction,
                color: AppColors.textSecondary.withOpacity(0.5),
                size: 20,
              ),
              tooltip: 'Long press for Dev Test',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientTemp(LiveData liveData) {
    // Failsafe in case the ESP32 isn't sending temperature data yet
    final temp = liveData.ambientTemp > 0 ? liveData.ambientTemp : 24.5; 
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.thermostat,
            size: 16,
            color: AppColors.getTempColor(temp),
          ),
          const SizedBox(width: 6),
          Text(
            'Ambient: ${temp.toStringAsFixed(1)}°C',
            style: AppTypography.shareTechMono(
              size: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryShimmer() {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildSummaryError() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Awaiting sensor data...',
              style: AppTypography.body.copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitShimmer() {
    return Container(
      height: 140,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildCircuitsError() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Unable to fetch circuit data',
              style: AppTypography.body.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
