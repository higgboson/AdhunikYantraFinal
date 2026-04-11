import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../core/offline_cache.dart';
import '../providers/auth_provider.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/offline_banner.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Settings',
          style: AppTypography.heading3,
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Offline Status Card
          _buildOfflineStatusCard(context, isOffline),
          
          const SizedBox(height: 24),
          
          // Profile Section
          _buildSectionHeader('Profile'),
          _buildSettingTile(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: 'Manage your account details',
            onTap: () {
              // Navigate to profile
            },
          ),
          _buildSettingTile(
            icon: Icons.logout,
            title: 'Sign Out',
            subtitle: 'Log out of your account',
            onTap: () => _showSignOutDialog(context, ref),
            isDestructive: true,
          ),
          
          const SizedBox(height: 24),
          
          // Device Section
          _buildSectionHeader('Device & Network'),
          _buildSettingTile(
            icon: Icons.wifi,
            title: 'Device and Network',
            subtitle: 'Connection status, IP, firmware info',
            onTap: () => context.push('/device-network'),
          ),
          _buildSettingTile(
            icon: Icons.update,
            title: 'Firmware Update',
            subtitle: 'Check for device updates',
            onTap: () {
              // Check firmware
            },
          ),
          
          const SizedBox(height: 24),
          
          // Safety Section
          _buildSectionHeader('Safety Thresholds'),
          _buildSettingTile(
            icon: Icons.shield_outlined,
            title: 'Safety Thresholds',
            subtitle: 'Overload, voltage, leakage limits',
            onTap: () => _showSafetyThresholdsDialog(context),
          ),
          
          const SizedBox(height: 24),
          
          // Energy Section
          _buildSectionHeader('Energy Management'),
          _buildSettingTile(
            icon: Icons.psychology,
            title: 'Energy Coach (EWMA)',
            subtitle: 'AI learning and anomaly detection',
            onTap: () => context.push('/ewma-coach'),
          ),
          _buildSettingTile(
            icon: Icons.electric_meter,
            title: 'Motor Health',
            subtitle: 'Power factor and health scores',
            onTap: () => context.push('/motor-health'),
          ),
          _buildSettingTile(
            icon: Icons.compare_arrows,
            title: 'Neutral Monitor',
            subtitle: 'Live vs neutral current monitoring',
            onTap: () => context.push('/neutral-monitor'),
          ),
          _buildSettingTile(
            icon: Icons.analytics_outlined,
            title: 'Circuit Analyzer',
            subtitle: 'Upload and analyze your DB schedule',
            onTap: () => context.push('/circuit-analyzer'),
          ),
          _buildSettingTile(
            icon: Icons.bug_report,
            title: 'Developer Test Mode',
            subtitle: 'Simulate faults for demo purposes',
            onTap: () => context.push('/developer-test'),
          ),
          
          const SizedBox(height: 24),
          
          // Notifications
          _buildSectionHeader('Notifications'),
          _buildSwitchTile(
            icon: Icons.notifications_active,
            title: 'Fault Alerts',
            subtitle: 'Get notified when faults occur',
            value: true,
            onChanged: (value) {},
          ),
          _buildSwitchTile(
            icon: Icons.trending_up,
            title: 'Energy Reports',
            subtitle: 'Daily energy usage summaries',
            value: true,
            onChanged: (value) {},
          ),
          _buildSwitchTile(
            icon: Icons.build,
            title: 'Maintenance Reminders',
            subtitle: 'Motor maintenance predictions',
            value: false,
            onChanged: (value) {},
          ),
          
          const SizedBox(height: 24),
          
          // Display
          _buildSectionHeader('Display'),
          _buildSwitchTile(
            icon: Icons.dark_mode,
            title: 'Dark Theme',
            subtitle: 'Always use dark mode',
            value: true,
            onChanged: (value) {},
          ),
          _buildSettingTile(
            icon: Icons.speed,
            title: 'Data Refresh Rate',
            subtitle: '2 seconds (default)',
            onTap: () {},
          ),
          
          const SizedBox(height: 24),
          
          // About
          _buildSectionHeader('About'),
          _buildSettingTile(
            icon: Icons.info_outline,
            title: 'About ADHUNIK YANTRA',
            subtitle: 'Version 1.0.0 • Hacksagon 2025',
            onTap: () {},
          ),
          _buildSettingTile(
            icon: Icons.help_outline,
            title: 'Help & Support',
            subtitle: 'Documentation and contact',
            onTap: () {},
          ),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  /// Build offline status card showing connection info and cache stats
  Widget _buildOfflineStatusCard(BuildContext context, bool isOffline) {
    final lastUpdate = OfflineCache.getLastUpdateTime();
    final cacheSize = OfflineCache.getCacheSize();
    final hasData = OfflineCache.hasCachedData();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOffline 
            ? AppColors.warning.withOpacity(0.1)
            : AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOffline 
              ? AppColors.warning.withOpacity(0.3)
              : AppColors.success.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ConnectionStatusIndicator(
                isOnline: !isOffline,
                showLabel: false,
              ),
              const SizedBox(width: 12),
              Text(
                isOffline ? 'Offline Mode' : 'Online',
                style: AppTypography.dmSans(
                  size: 16,
                  weight: FontWeight.w600,
                  color: isOffline ? AppColors.warning : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasData) ...[
            _buildInfoRow('Last Sync', OfflineCache.getLastUpdatedString()),
            _buildInfoRow('Cached Data', '${(cacheSize / 1024).toStringAsFixed(1)} KB'),
          ] else
            Text(
              'No cached data available',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: hasData ? () => _showClearCacheDialog(context) : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Clear Cached Data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: hasData ? AppColors.danger : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text('Clear Cached Data?', style: AppTypography.heading3),
        content: Text(
          'This will remove all offline data including readings, power history, and fault records. You will need an internet connection to view data again.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTypography.body),
          ),
          ElevatedButton(
            onPressed: () async {
              await OfflineCache.clearCache();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cached data cleared', style: AppTypography.bodySmall),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: Text(
              'Clear',
              style: AppTypography.body.copyWith(color: AppColors.background),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppDecorations.card,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDestructive
                ? AppColors.danger.withValues(alpha: 0.2)
                : AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isDestructive ? AppColors.danger : AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: AppTypography.dmSans(
            weight: FontWeight.w600,
            color: isDestructive ? AppColors.danger : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.bodySmall,
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppDecorations.card,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: AppTypography.dmSans(
            weight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: AppTypography.bodySmall,
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text('Sign Out?', style: AppTypography.heading3),
        content: Text(
          'You will need to sign in again to access your circuits.',
          style: AppTypography.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTypography.body),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authActionsProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/auth');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: Text(
              'Sign Out',
              style: AppTypography.body.copyWith(color: AppColors.background),
            ),
          ),
        ],
      ),
    );
  }

  void _showSafetyThresholdsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBackground,
        title: Text('Safety Thresholds', style: AppTypography.heading3),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThresholdRow('Overload Limit', '6.0 A'),
              _buildThresholdRow('Short Circuit', '18.0 A'),
              _buildThresholdRow('Overvoltage', '260 V'),
              _buildThresholdRow('Undervoltage', '180 V'),
              _buildThresholdRow('Leakage', '30 mA'),
              _buildThresholdRow('Thermal', '65 °C'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: AppTypography.body),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Open edit thresholds
            },
            child: Text(
              'Edit',
              style: AppTypography.body.copyWith(color: AppColors.background),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThresholdRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body),
          Text(
            value,
            style: AppTypography.shareTechMono(
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
