import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/connectivity_service.dart';

/// Provider for the connectivity service
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.initialize();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider that emits true when online, false when offline
final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOnline;
});

/// Provider for current online status (synchronous)
final onlineStatusProvider = Provider<bool>((ref) {
  final asyncValue = ref.watch(isOnlineProvider);
  return asyncValue.when(
    data: (isOnline) => isOnline,
    loading: () => true, // Assume online while loading
    error: (_, __) => false, // Assume offline on error
  );
});

/// Provider for offline status (inverse of online)
final isOfflineProvider = Provider<bool>((ref) {
  return !ref.watch(onlineStatusProvider);
});
