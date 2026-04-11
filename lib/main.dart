import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/offline_cache.dart';
import 'core/connectivity_service.dart';
import 'router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();
  
  // Initialize offline cache
  await OfflineCache.initialize();
  
  // Initialize connectivity service
  await ConnectivityService().initialize();
  
  runApp(
    const ProviderScope(
      child: AdhunikYantraApp(),
    ),
  );
}

class AdhunikYantraApp extends StatelessWidget {
  const AdhunikYantraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ADHUNIK YANTRA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }
}
