import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Service to monitor network connectivity state
/// Provides a Stream<bool> isOnline that emits true when connected, false when offline
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _isOnlineController = StreamController<bool>.broadcast();
  StreamSubscription<ConnectivityResult>? _subscription;
  
  bool _isOnline = true;
  bool get currentStatus => _isOnline;
  
  /// Stream that emits true when online, false when offline
  Stream<bool> get isOnline => _isOnlineController.stream;

  /// Initialize the service and start listening to connectivity changes
  Future<void> initialize() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
    
    // Listen to connectivity changes
    _subscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  /// Dispose the service and cancel subscriptions
  void dispose() {
    _subscription?.cancel();
    _isOnlineController.close();
  }

  /// Update connection status based on connectivity result
  void _updateConnectionStatus(ConnectivityResult result) {
    final wasOnline = _isOnline;
    
    switch (result) {
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
      case ConnectivityResult.mobile:
      case ConnectivityResult.vpn:
      case ConnectivityResult.other:
        _isOnline = true;
        break;
      case ConnectivityResult.none:
      case ConnectivityResult.bluetooth:
        _isOnline = false;
        break;
    }
    
    // Only emit if status changed
    if (wasOnline != _isOnline || !_isOnlineController.hasListener) {
      _isOnlineController.add(_isOnline);
      if (kDebugMode) {
        print('Connectivity changed: ${_isOnline ? "ONLINE" : "OFFLINE"}');
      }
    }
  }

  /// Check if currently connected to internet
  Future<bool> checkConnection() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
    return _isOnline;
  }
}

/// Provider class for Riverpod integration
class ConnectivityNotifier extends ChangeNotifier {
  final ConnectivityService _service = ConnectivityService();
  bool _isOnline = true;
  StreamSubscription<bool>? _subscription;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  ConnectivityNotifier() {
    _init();
  }

  Future<void> _init() async {
    await _service.initialize();
    _isOnline = _service.currentStatus;
    
    _subscription = _service.isOnline.listen((online) {
      if (_isOnline != online) {
        _isOnline = online;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    super.dispose();
  }

  Future<bool> checkConnection() async {
    return await _service.checkConnection();
  }
}
