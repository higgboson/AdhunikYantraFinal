import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/wifi_provisioning_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/fault_detail_screen.dart';
import '../screens/history_screen.dart';
import '../screens/alerts_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/device_network_screen.dart';
import '../screens/ewma_coach_screen.dart';
import '../screens/motor_health_screen.dart';
import '../screens/neutral_monitor_screen.dart';
import '../screens/circuit_analyzer_screen.dart';
import '../screens/developer_test_screen.dart';
import '../widgets/main_scaffold.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    // Splash
    GoRoute(
      path: '/',
      builder: (context, state) => const SplashScreen(),
    ),
    
    // Onboarding flow
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/wifi-setup',
      builder: (context, state) => const WiFiProvisioningScreen(),
    ),
    GoRoute(
      path: '/auth',
      builder: (context, state) => const AuthScreen(),
    ),
    
    // Main scaffold with bottom navigation
    ShellRoute(
      builder: (context, state, child) => MainScaffold(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) => const HistoryScreen(),
        ),
        GoRoute(
          path: '/alerts',
          builder: (context, state) => const AlertsCentreScreen(),
        ),
        GoRoute(
          path: '/board',
          builder: (context, state) => const CircuitAnalyzerScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    
    // Push routes - Fault details
    GoRoute(
      path: '/fault/:id',
      builder: (context, state) {
        final faultId = state.pathParameters['id']!;
        return FaultDetailScreen(faultId: faultId);
      },
    ),
    
    // Settings sub-routes
    GoRoute(
      path: '/device-network',
      builder: (context, state) => const DeviceNetworkScreen(),
    ),
    GoRoute(
      path: '/ewma-coach',
      builder: (context, state) => const EwmaCoachScreen(),
    ),
    GoRoute(
      path: '/motor-health',
      builder: (context, state) => const MotorHealthScreen(),
    ),
    GoRoute(
      path: '/neutral-monitor',
      builder: (context, state) => const NeutralMonitorScreen(),
    ),
    GoRoute(
      path: '/circuit-analyzer',
      builder: (context, state) => const CircuitAnalyzerScreen(),
    ),
    GoRoute(
      path: '/developer-test',
      builder: (context, state) => const DeveloperTestScreen(),
    ),
  ],
);
