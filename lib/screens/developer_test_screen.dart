import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import 'package:firebase_core/firebase_core.dart';

/// State class for developer test mode
class DeveloperTestState {
  final bool isSending;
  final bool autoResetEnabled;
  final String? currentFault;
  final bool isTestModeActive;
  final List<FaultLogEntry> faultLog;
  final String? errorMessage;
  
  // Relay states
  final bool relay1On;
  final bool relay2On;
  final bool isSendingRelay1;
  final bool isSendingRelay2;
  
  // Real-time readings
  final double voltage;
  final double current1;
  final double current2;
  final double totalPower;
  final bool faultActive;
  final String? faultType;

  const DeveloperTestState({
    this.isSending = false,
    this.autoResetEnabled = false,
    this.currentFault,
    this.isTestModeActive = false,
    this.faultLog = const [],
    this.errorMessage,
    this.relay1On = true,
    this.relay2On = true,
    this.isSendingRelay1 = false,
    this.isSendingRelay2 = false,
    this.voltage = 0.0,
    this.current1 = 0.0,
    this.current2 = 0.0,
    this.totalPower = 0.0,
    this.faultActive = false,
    this.faultType,
  });

  DeveloperTestState copyWith({
    bool? isSending,
    bool? autoResetEnabled,
    String? currentFault,
    bool? isTestModeActive,
    List<FaultLogEntry>? faultLog,
    String? errorMessage,
    bool? relay1On,
    bool? relay2On,
    bool? isSendingRelay1,
    bool? isSendingRelay2,
    double? voltage,
    double? current1,
    double? current2,
    double? totalPower,
    bool? faultActive,
    String? faultType,
  }) {
    return DeveloperTestState(
      isSending: isSending ?? this.isSending,
      autoResetEnabled: autoResetEnabled ?? this.autoResetEnabled,
      currentFault: currentFault ?? this.currentFault,
      isTestModeActive: isTestModeActive ?? this.isTestModeActive,
      faultLog: faultLog ?? this.faultLog,
      errorMessage: errorMessage ?? this.errorMessage,
      relay1On: relay1On ?? this.relay1On,
      relay2On: relay2On ?? this.relay2On,
      isSendingRelay1: isSendingRelay1 ?? this.isSendingRelay1,
      isSendingRelay2: isSendingRelay2 ?? this.isSendingRelay2,
      voltage: voltage ?? this.voltage,
      current1: current1 ?? this.current1,
      current2: current2 ?? this.current2,
      totalPower: totalPower ?? this.totalPower,
      faultActive: faultActive ?? this.faultActive,
      faultType: faultType ?? this.faultType,
    );
  }
}

/// Individual fault/command log entry
class FaultLogEntry {
  final String commandType; // 'fault', 'relay', 'reset'
  final String faultType;
  final DateTime timestamp;
  final String status;
  final int? circuitNumber; // For relay commands

  const FaultLogEntry({
    this.commandType = 'fault',
    required this.faultType,
    required this.timestamp,
    this.status = 'Triggered',
    this.circuitNumber,
  });
  
  String get displayText {
    switch (commandType) {
      case 'relay':
        return 'Circuit ${circuitNumber ?? 1} ${faultType.toUpperCase()}';
      case 'fault':
        return faultType == 'normal' ? 'System Reset' : '${_capitalize(faultType)} Fault';
      default:
        return _capitalize(faultType);
    }
  }
  
  Color get statusColor {
    switch (commandType) {
      case 'relay':
        return faultType == 'trip' ? const Color(0xFFF44336) : const Color(0xFF4CAF50);
      case 'fault':
        return faultType == 'normal' ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);
      default:
        return const Color(0xFF2196F3);
    }
  }
  
  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// Riverpod state notifier for developer test mode
class DeveloperTestNotifier extends StateNotifier<DeveloperTestState> {
  final DatabaseReference _commandsRef;
  final DatabaseReference _readingsRef;
  final DatabaseReference _relayRef;
  DateTime? _lastButtonPress;
  static const _debounceDuration = Duration(milliseconds: 500);

  DeveloperTestNotifier()
      : _commandsRef = FirebaseDatabase.instance
            .ref('${AppConstants.deviceId}/commands'),
        _readingsRef = FirebaseDatabase.instance
            .ref('${AppConstants.deviceId}/readings'),
        _relayRef = FirebaseDatabase.instance
            .ref('${AppConstants.deviceId}/relay'),
        super(const DeveloperTestState()) {
    // Listen to Firebase readings for real-time status
    _readingsRef.onValue.listen(
      (event) {
        if (event.snapshot.value != null) {
          final readings = Map<String, dynamic>.from(event.snapshot.value as Map);
          
          // Parse readings
          final faultActive = readings['faultActive'] as bool? ?? false;
          final faultType = readings['faultType'] as String? ?? 'normal';
          final relay1On = readings['relay1_on'] as bool? ?? true;
          final relay2On = readings['relay2_on'] as bool? ?? true;
          final voltage = (readings['voltage'] as num?)?.toDouble() ?? 0.0;
          final current1 = (readings['current1'] as num?)?.toDouble() ?? 0.0;
          final current2 = (readings['current2'] as num?)?.toDouble() ?? 0.0;
          final totalPower = (readings['totalPower'] as num?)?.toDouble() ?? 0.0;
          
          state = state.copyWith(
            isTestModeActive: faultActive,
            currentFault: faultActive ? faultType : null,
            relay1On: relay1On,
            relay2On: relay2On,
            voltage: voltage,
            current1: current1,
            current2: current2,
            totalPower: totalPower,
            faultActive: faultActive,
            faultType: faultType,
          );
        }
      },
      onError: (error) {
        state = state.copyWith(errorMessage: 'Firebase stream error: $error');
      },
    );
  }

  /// Trip a circuit relay (turn OFF)
  Future<void> tripCircuit(int circuitNumber) async {
    if (_shouldDebounce()) return;
    _lastButtonPress = DateTime.now();
    
    await HapticFeedback.mediumImpact();
    
    state = state.copyWith(
      isSendingRelay1: circuitNumber == 1,
      isSendingRelay2: circuitNumber == 2,
      errorMessage: null,
    );
    
    try {
      final path = 'trip_circuit_$circuitNumber';
      await _commandsRef.child(path).set('trip').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Connection timeout'),
      );
      
      // Add to command log
      final newEntry = FaultLogEntry(
        commandType: 'relay',
        faultType: 'trip',
        circuitNumber: circuitNumber,
        timestamp: DateTime.now(),
        status: 'Command Sent',
      );
      
      final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
      
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        faultLog: updatedLog,
      );
      
      // Auto-reset after 5 seconds if enabled
      if (state.autoResetEnabled) {
        _scheduleRelayReset(circuitNumber);
      }
      
    } on FirebaseException catch (e) {
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        errorMessage: _getFirebaseErrorMessage(e),
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        errorMessage: 'Error: $e',
      );
      rethrow;
    }
  }
  
  /// Reset a circuit relay (turn ON)
  Future<void> resetCircuit(int circuitNumber) async {
    if (_shouldDebounce()) return;
    _lastButtonPress = DateTime.now();
    
    await HapticFeedback.mediumImpact();
    
    state = state.copyWith(
      isSendingRelay1: circuitNumber == 1,
      isSendingRelay2: circuitNumber == 2,
      errorMessage: null,
    );
    
    try {
      final path = 'trip_circuit_$circuitNumber';
      await _commandsRef.child(path).set('reset').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Connection timeout'),
      );
      
      // Add to command log
      final newEntry = FaultLogEntry(
        commandType: 'relay',
        faultType: 'reset',
        circuitNumber: circuitNumber,
        timestamp: DateTime.now(),
        status: 'Command Sent',
      );
      
      final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
      
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        faultLog: updatedLog,
      );
      
    } on FirebaseException catch (e) {
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        errorMessage: _getFirebaseErrorMessage(e),
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isSendingRelay1: circuitNumber == 1 ? false : state.isSendingRelay1,
        isSendingRelay2: circuitNumber == 2 ? false : state.isSendingRelay2,
        errorMessage: 'Error: $e',
      );
      rethrow;
    }
  }
  
  /// Reset all circuits (Emergency Reset) with relay control and fault reset
  Future<void> resetAllCircuits() async {
    await HapticFeedback.heavyImpact();
    
    state = state.copyWith(
      isSendingRelay1: true,
      isSendingRelay2: true,
      errorMessage: null,
    );
    
    try {
      // Reset both circuit relays to true (ON)
      await Future.wait([
        _relayRef.child('circuit_1').set(true).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Timeout on Circuit 1'),
        ),
        _relayRef.child('circuit_2').set(true).timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Timeout on Circuit 2'),
        ),
      ]);
      
      // Reset fault to normal
      await _commandsRef.child('test_fault').set('normal').timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout on fault reset'),
      );
      
      // Add to command log
      final newEntry = FaultLogEntry(
        commandType: 'relay',
        faultType: 'emergency_reset',
        timestamp: DateTime.now(),
        status: 'All Circuits Reset',
      );
      
      final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
      
      // Update local state immediately
      state = state.copyWith(
        isSendingRelay1: false,
        isSendingRelay2: false,
        relay1On: true,
        relay2On: true,
        isTestModeActive: false,
        currentFault: null,
        faultLog: updatedLog,
      );
      
    } catch (e) {
      state = state.copyWith(
        isSendingRelay1: false,
        isSendingRelay2: false,
        errorMessage: 'Emergency reset error: $e',
      );
      rethrow;
    }
  }
  
  /// Schedule auto-reset for relay
  void _scheduleRelayReset(int circuitNumber) {
    Future.delayed(const Duration(seconds: 5), () async {
      final isOn = circuitNumber == 1 ? state.relay1On : state.relay2On;
      if (state.autoResetEnabled && !isOn) {
        try {
          await resetCircuit(circuitNumber);
        } catch (e) {
          debugPrint('Auto relay reset failed: $e');
        }
      }
    });
  }

  /// Check if button press should be debounced
  bool _shouldDebounce() {
    final now = DateTime.now();
    if (_lastButtonPress == null) return false;
    return now.difference(_lastButtonPress!) < _debounceDuration;
  }

  /// Send test fault command to Firebase with debounce and error handling
  /// Also trips both relays immediately and updates local state
  Future<void> sendTestCommand(String faultType) async {
    // Debounce check
    if (_shouldDebounce()) {
      debugPrint('Button press debounced');
      return;
    }
    _lastButtonPress = DateTime.now();

    // Haptic feedback
    await HapticFeedback.mediumImpact();

    state = state.copyWith(isSending: true, errorMessage: null);

    try {
      // STEP 1: Write false to both relay paths (trip both circuits)
      await _relayRef.child('circuit_1').set(false).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout on Relay Circuit 1'),
      );
      await _relayRef.child('circuit_2').set(false).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout on Relay Circuit 2'),
      );

      // STEP 2: Write fault type to commands/test_fault
      await _commandsRef.child('test_fault').set(faultType).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw Exception('Connection timeout - check device connectivity');
        },
      );

      // STEP 3: Update local UI state immediately (without waiting for Firebase roundtrip)
      state = state.copyWith(
        relay1On: false,
        relay2On: false,
        isTestModeActive: faultType != 'normal',
        currentFault: faultType != 'normal' ? faultType : null,
        isSending: false,
        errorMessage: null,
      );

      // Add to fault log (keep only last 5)
      final newEntry = FaultLogEntry(
        commandType: faultType == 'normal' ? 'reset' : 'fault',
        faultType: faultType,
        timestamp: DateTime.now(),
        status: faultType == 'normal' ? 'Reset' : 'Triggered',
      );
      
      final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
      
      state = state.copyWith(faultLog: updatedLog);

      // Auto-reset after 5 seconds if enabled and not a manual reset
      if (state.autoResetEnabled && faultType != 'normal') {
        _scheduleAutoReset();
      }

    } on FirebaseException catch (e) {
      final errorMsg = _getFirebaseErrorMessage(e);
      state = state.copyWith(
        isSending: false,
        errorMessage: errorMsg,
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        errorMessage: 'Error: $e',
      );
      rethrow;
    }
  }

  /// Reset a single circuit (Circuit 1 or 2) and update local state
  Future<void> resetSingleCircuit(int circuitNumber) async {
    if (_shouldDebounce()) return;
    _lastButtonPress = DateTime.now();
    
    await HapticFeedback.mediumImpact();
    
    final isCircuit1 = circuitNumber == 1;
    
    state = state.copyWith(
      isSendingRelay1: isCircuit1,
      isSendingRelay2: !isCircuit1,
      errorMessage: null,
    );
    
    try {
      // Write true to the specific circuit relay path
      await _relayRef.child('circuit_$circuitNumber').set(true).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Timeout on Circuit $circuitNumber'),
      );
      
      // Add to command log
      final newEntry = FaultLogEntry(
        commandType: 'relay',
        faultType: 'reset',
        circuitNumber: circuitNumber,
        timestamp: DateTime.now(),
        status: 'Circuit $circuitNumber Reset',
      );
      
      final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
      
      // Update local state immediately for the specific circuit
      state = state.copyWith(
        isSendingRelay1: isCircuit1 ? false : state.isSendingRelay1,
        isSendingRelay2: !isCircuit1 ? false : state.isSendingRelay2,
        relay1On: isCircuit1 ? true : state.relay1On,
        relay2On: !isCircuit1 ? true : state.relay2On,
        faultLog: updatedLog,
      );
      
    } on FirebaseException catch (e) {
      state = state.copyWith(
        isSendingRelay1: isCircuit1 ? false : state.isSendingRelay1,
        isSendingRelay2: !isCircuit1 ? false : state.isSendingRelay2,
        errorMessage: _getFirebaseErrorMessage(e),
      );
      rethrow;
    } catch (e) {
      state = state.copyWith(
        isSendingRelay1: isCircuit1 ? false : state.isSendingRelay1,
        isSendingRelay2: !isCircuit1 ? false : state.isSendingRelay2,
        errorMessage: 'Error: $e',
      );
      rethrow;
    }
  }

  /// Schedule auto-reset after 5 seconds
  void _scheduleAutoReset() {
    Future.delayed(const Duration(seconds: 5), () async {
      if (state.autoResetEnabled && state.isTestModeActive) {
        try {
          await _commandsRef.child('test_fault').set('normal');
          
          final newEntry = FaultLogEntry(
            commandType: 'reset',
            faultType: 'normal',
            timestamp: DateTime.now(),
            status: 'Auto-Reset',
          );
          
          final updatedLog = [newEntry, ...state.faultLog].take(5).toList();
          
          state = state.copyWith(faultLog: updatedLog);
        } catch (e) {
          debugPrint('Auto-reset failed: $e');
        }
      }
    });
  }

  /// Toggle auto-reset feature
  void toggleAutoReset(bool enabled) {
    state = state.copyWith(autoResetEnabled: enabled);
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// Clear fault log
  void clearFaultLog() {
    state = state.copyWith(faultLog: []);
  }

  String _getFirebaseErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied - check Firebase rules';
      case 'disconnected':
        return 'Disconnected from Firebase - check internet';
      case 'network-request-failed':
        return 'Network error - check connectivity';
      default:
        return 'Firebase error: ${e.message}';
    }
  }
}

/// Riverpod provider for developer test state
final developerTestProvider = StateNotifierProvider<DeveloperTestNotifier, DeveloperTestState>(
  (ref) => DeveloperTestNotifier(),
);

/// Main Developer Test Screen
class DeveloperTestScreen extends ConsumerWidget {
  const DeveloperTestScreen({super.key});

  @override
    // Add this method before the build() method
Widget _buildFaultLogSection(DeveloperTestState state, DeveloperTestNotifier notifier) {
  return Container(
    margin: const EdgeInsets.only(top: 24),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Command Log',
                  style: AppTypography.dmSans(
                    weight: FontWeight.w600,
                    size: 16,
                  ),
                ),
              ],
            ),
            if (state.faultLog.isNotEmpty)
              TextButton.icon(
                onPressed: () => notifier.clearFaultLog(),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (state.faultLog.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No commands sent yet',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          )
        else
          Column(
            children: state.faultLog.map((entry) {
              final time = DateFormat('HH:mm:ss').format(entry.timestamp);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: entry.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: entry.statusColor.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: entry.statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayText,
                            style: AppTypography.dmSans(
                              weight: FontWeight.w600,
                              size: 14,
                            ),
                          ),
                          Text(
                            '${entry.status} • $time',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    ),
  );
}
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(developerTestProvider);
    final notifier = ref.read(developerTestProvider.notifier);

    // Show error snackbar if there's an error
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showErrorSnackbar(context, state.errorMessage!, notifier);
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.construction, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(
              'Developer Test',
              style: AppTypography.shareTechMono(size: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.success),
            onPressed: state.isSending 
                ? null 
                : () => _sendCommandWithDialog(context, notifier, 'normal'),
            tooltip: 'Reset to Normal',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBanner(state),
              const SizedBox(height: 16),
              _buildWarningBanner(),
              const SizedBox(height: 24),
              
              // Real-Time Readings Panel
              _buildReadingsPanel(state),
              const SizedBox(height: 24),
              
              // Relay Control Section
              _buildRelayControlSection(context, state, notifier),
              const SizedBox(height: 24),
              
              _buildAutoResetToggle(state, notifier),
              const SizedBox(height: 24),
              Text(
                'FAULT SIMULATION',
                style: AppTypography.shareTechMono(
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  return isWide 
                      ? _buildWideFaultGrid(context, state, notifier)
                      : _buildNarrowFaultList(context, state, notifier);
                },
              ),
              const SizedBox(height: 24),
              _buildResetSection(context, state, notifier),
              const SizedBox(height: 24),
              _buildFaultLogSection(state, notifier),
              const SizedBox(height: 24),
              _buildInfoCard(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(DeveloperTestState state) {
    final isActive = state.isTestModeActive;
    final faultType = state.currentFault ?? 'normal';
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.danger.withOpacity(0.2) : AppColors.success.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.danger : AppColors.success,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: isActive ? AppColors.danger : AppColors.success,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'TEST MODE: ACTIVE' : 'Normal Operation',
                  style: AppTypography.dmSans(
                    weight: FontWeight.w600,
                    color: isActive ? AppColors.danger : AppColors.success,
                    size: 16,
                  ),
                ),
                if (isActive && faultType != 'normal') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Current Fault: ${_getFaultDisplayName(faultType)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: AppColors.warning, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For Demo Purposes Only',
                  style: AppTypography.dmSans(
                    weight: FontWeight.w600,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'These controls simulate fault conditions for testing and demonstration.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingsPanel(DeveloperTestState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Real-Time Status',
                style: AppTypography.dmSans(
                  weight: FontWeight.w600,
                  size: 16,
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: state.faultActive ? AppColors.danger : AppColors.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                state.faultActive ? 'FAULT' : 'NORMAL',
                style: AppTypography.caption.copyWith(
                  color: state.faultActive ? AppColors.danger : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildReadingItem(
                  'Voltage',
                  '${state.voltage.toStringAsFixed(1)} V',
                  Icons.electric_bolt,
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildReadingItem(
                  'Total Power',
                  '${state.totalPower.toStringAsFixed(0)} W',
                  Icons.power,
                  AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildReadingItem(
                  'Current 1',
                  '${state.current1.toStringAsFixed(2)} A',
                  Icons.electric_meter,
                  AppColors.secondary,
                ),
              ),
              Expanded(
                child: _buildReadingItem(
                  'Current 2',
                  '${state.current2.toStringAsFixed(2)} A',
                  Icons.electric_meter,
                  AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRelayStatusItem(
                  'Relay 1',
                  state.relay1On,
                ),
              ),
              Expanded(
                child: _buildRelayStatusItem(
                  'Relay 2',
                  state.relay2On,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReadingItem(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                style: AppTypography.shareTechMono(
                  size: 14,
                  weight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRelayStatusItem(String label, bool isOn) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isOn ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isOn ? 'ON' : 'OFF',
          style: AppTypography.shareTechMono(
            size: 14,
            weight: FontWeight.bold,
            color: isOn ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
          ),
        ),
      ],
    );
  }

  Widget _buildRelayControlSection(BuildContext context, DeveloperTestState state, DeveloperTestNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.toggle_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Relay Control',
                style: AppTypography.dmSans(
                  weight: FontWeight.w600,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Control ESP32 relays remotely',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          
          // Circuit 1 Control
          _buildCircuitControlCard(
            context: context,
            circuitNumber: 1,
            isOn: state.relay1On,
            isSending: state.isSendingRelay1,
            state: state,
            notifier: notifier,
          ),
          const SizedBox(height: 12),
          
          // Circuit 2 Control
          _buildCircuitControlCard(
            context: context,
            circuitNumber: 2,
            isOn: state.relay2On,
            isSending: state.isSendingRelay2,
            state: state,
            notifier: notifier,
          ),
          const SizedBox(height: 16),
          
          // Emergency Reset All
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (state.isSendingRelay1 || state.isSendingRelay2)
                  ? null
                  : () => _showEmergencyResetDialog(context, notifier),
              icon: const Icon(Icons.emergency, size: 18),
              label: const Text('Emergency Reset All'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircuitControlCard({
    required BuildContext context,
    required int circuitNumber,
    required bool isOn,
    required bool isSending,
    required DeveloperTestState state,
    required DeveloperTestNotifier notifier,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOn 
            ? const Color(0xFF4CAF50).withOpacity(0.1) 
            : const Color(0xFFF44336).withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOn 
              ? const Color(0xFF4CAF50).withOpacity(0.5) 
              : const Color(0xFFF44336).withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isOn ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isOn ? Icons.power : Icons.power_off,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Circuit $circuitNumber',
                  style: AppTypography.dmSans(
                    weight: FontWeight.w600,
                    size: 16,
                  ),
                ),
                Text(
                  isOn ? 'Status: ON (Powered)' : 'Status: OFF (Tripped)',
                  style: AppTypography.bodySmall.copyWith(
                    color: isOn ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                  ),
                ),
              ],
            ),
          ),
          if (isSending)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // TRIP Button (Red)
                ElevatedButton(
                  onPressed: isOn 
                      ? () => _showTripConfirmationDialog(context, notifier, circuitNumber)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF44336),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('TRIP'),
                ),
                const SizedBox(width: 8),
                // RESET Button (Green)
                ElevatedButton(
                  onPressed: !isOn 
                      ? () => _sendRelayCommand(context, notifier, circuitNumber, 'reset')
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade800,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('RESET'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _showTripConfirmationDialog(BuildContext context, DeveloperTestNotifier notifier, int circuitNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.danger),
            const SizedBox(width: 8),
            Text(
              'TRIP Circuit $circuitNumber?',
              style: AppTypography.heading3,
            ),
          ],
        ),
        content: Text(
          'This will physically disconnect Circuit $circuitNumber and turn OFF the connected device. The relay will open and power will be cut.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('TRIP'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _sendRelayCommand(context, notifier, circuitNumber, 'trip');
    }
  }

  Future<void> _showEmergencyResetDialog(BuildContext context, DeveloperTestNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Row(
          children: [
            Icon(Icons.emergency, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(
              'Emergency Reset All?',
              style: AppTypography.heading3,
            ),
          ],
        ),
        content: Text(
          'This will reset ALL circuits to ON state immediately.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
            ),
            child: const Text('RESET ALL'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await notifier.resetAllCircuits();
        _showSuccessSnackbar(context, 'All circuits reset successfully');
      } catch (e) {
        _showErrorSnackbar(context, e.toString(), notifier);
      }
    }
  }

  Future<void> _sendRelayCommand(BuildContext context, DeveloperTestNotifier notifier, int circuitNumber, String command) async {
    try {
      if (command == 'trip') {
        await notifier.tripCircuit(circuitNumber);
      } else {
        await notifier.resetSingleCircuit(circuitNumber);
      }
      if (context.mounted) {
        _showSuccessSnackbar(context, 'Circuit $circuitNumber ${command.toUpperCase()}PED');
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(context, e.toString(), notifier);
      }
    }
  }

  Widget _buildAutoResetToggle(DeveloperTestState state, DeveloperTestNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: state.autoResetEnabled 
                  ? AppColors.primary.withOpacity(0.2) 
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.timer,
              color: state.autoResetEnabled ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Reset After 5s',
                  style: AppTypography.dmSans(weight: FontWeight.w600),
                ),
                Text(
                  'Automatically return to normal after fault',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: state.autoResetEnabled,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              notifier.toggleAutoReset(value);
            },
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildWideFaultGrid(BuildContext context, DeveloperTestState state, DeveloperTestNotifier notifier) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.5,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildFaultButton(
          icon: Icons.bolt,
          title: 'Overvoltage',
          subtitle: '265V (Trip: 260V)',
          color: Colors.red,
          faultType: 'overvoltage',
          state: state,
          notifier: notifier,
          context: context,
        ),
        _buildFaultButton(
          icon: Icons.bolt_outlined,
          title: 'Undervoltage',
          subtitle: '175V (Trip: 180V)',
          color: Colors.orange,
          faultType: 'undervoltage',
          state: state,
          notifier: notifier,
          context: context,
        ),
        _buildFaultButton(
          icon: Icons.local_fire_department,
          title: 'Overcurrent',
          subtitle: '16.5A (Trip: 15A)',
          color: Colors.red.shade800,
          faultType: 'overcurrent',
          state: state,
          notifier: notifier,
          context: context,
        ),
        _buildFaultButton(
          icon: Icons.warning,
          title: 'Earth Leakage',
          subtitle: '50mA (Trip: 25mA)',
          color: Colors.purple,
          faultType: 'leakage',
          state: state,
          notifier: notifier,
          context: context,
        ),
      ],
    );
  }

  Widget _buildNarrowFaultList(BuildContext context, DeveloperTestState state, DeveloperTestNotifier notifier) {
    return Column(
      children: [
        _buildFaultButton(
          icon: Icons.bolt,
          title: 'Overvoltage',
          subtitle: 'Simulate 265V (Trip threshold: 260V)',
          color: Colors.red,
          faultType: 'overvoltage',
          state: state,
          notifier: notifier,
          context: context,
        ),
        const SizedBox(height: 12),
        _buildFaultButton(
          icon: Icons.bolt_outlined,
          title: 'Undervoltage',
          subtitle: 'Simulate 175V (Trip threshold: 180V)',
          color: Colors.orange,
          faultType: 'undervoltage',
          state: state,
          notifier: notifier,
          context: context,
        ),
        const SizedBox(height: 12),
        _buildFaultButton(
          icon: Icons.local_fire_department,
          title: 'Overcurrent',
          subtitle: 'Simulate 16.5A (Trip threshold: 15A)',
          color: Colors.red.shade800,
          faultType: 'overcurrent',
          state: state,
          notifier: notifier,
          context: context,
        ),
        const SizedBox(height: 12),
        _buildFaultButton(
          icon: Icons.warning,
          title: 'Earth Leakage',
          subtitle: 'Simulate 50mA (Trip threshold: 25mA)',
          color: Colors.purple,
          faultType: 'leakage',
          state: state,
          notifier: notifier,
          context: context,
        ),
      ],
    );
  }

  Widget _buildFaultButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required String faultType,
    required DeveloperTestState state,
    required DeveloperTestNotifier notifier,
    required BuildContext context,
  }) {
    final isSending = state.isSending;
    
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isSending 
            ? null 
            : () => _sendCommandWithDialog(context, notifier, faultType),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.dmSans(
                        weight: FontWeight.w600,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSending)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(Icons.arrow_forward_ios, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResetSection(BuildContext context, DeveloperTestState state, DeveloperTestNotifier notifier) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              Text(
                'Reset System',
                style: AppTypography.dmSans(
                  weight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Return system to normal operating conditions',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: state.isSending 
                  ? null 
                  : () => _sendCommandWithDialog(context, notifier, 'normal'),
              icon: state.isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh),
              label: Text(
                state.isSending ? 'Sending...' : 'Reset to Normal',
                style: AppTypography.dmSans(weight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'How It Works',
                style: AppTypography.dmSans(
                  weight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '1. Select a fault condition to simulate\n'
            '2. App writes test command to Firebase\n'
            '3. ESP32 receives command and simulates fault\n'
            '4. Dashboard shows fault overlay with alarm\n'
            '5. Use Reset or enable Auto-Reset to return to normal',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendCommandWithDialog(
    BuildContext context, 
    DeveloperTestNotifier notifier, 
    String faultType
  ) async {
    if (faultType == 'normal') {
      try {
        await notifier.sendTestCommand(faultType);
        if (context.mounted) {
          _showSuccessSnackbar(context, 'System reset to normal');
        }
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackbar(context, e.toString(), notifier);
        }
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning),
            const SizedBox(width: 8),
            Text(
              'Simulate Fault?',
              style: AppTypography.heading3,
            ),
          ],
        ),
        content: Text(
          'This will simulate a "${_getFaultDisplayName(faultType)}" fault condition on the device. Continue?',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await notifier.sendTestCommand(faultType);
        if (context.mounted) {
          _showSuccessSnackbar(context, 'Fault triggered: ${_getFaultDisplayName(faultType)}');
        }
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackbar(context, e.toString(), notifier);
        }
      }
    }
  }

  void _showSuccessSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackbar(BuildContext context, String message, DeveloperTestNotifier notifier) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.danger,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            notifier.clearError();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
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
      case 'normal':
        return 'Normal';
      default:
        return faultType.toUpperCase();
    }
  }
}
