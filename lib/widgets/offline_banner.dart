import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/offline_cache.dart';

/// Yellow banner shown at top of all screens when offline
/// Displays last updated time from cache
class OfflineBanner extends StatelessWidget {
  final bool isOffline;
  
  const OfflineBanner({
    super.key,
    required this.isOffline,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();
    
    final lastUpdated = OfflineCache.getLastUpdatedString();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.9),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off,
              color: Colors.black87,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Offline — showing data from $lastUpdated',
                style: AppTypography.dmSans(
                  size: 13,
                  weight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small cached badge to show on metric cards when offline
class CachedBadge extends StatelessWidget {
  final bool show;
  
  const CachedBadge({
    super.key,
    required this.show,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.warning.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time,
            size: 10,
            color: AppColors.warning,
          ),
          const SizedBox(width: 2),
          Text(
            'cached',
            style: AppTypography.caption.copyWith(
              fontSize: 9,
              color: AppColors.warning,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Disabled button overlay for relay controls when offline
class OfflineDisabledOverlay extends StatelessWidget {
  final String message;
  final Widget child;
  final bool isDisabled;
  
  const OfflineDisabledOverlay({
    super.key,
    required this.child,
    required this.isDisabled,
    this.message = 'This feature requires internet connection',
  });

  @override
  Widget build(BuildContext context) {
    if (!isDisabled) return child;
    
    return Tooltip(
      message: message,
      child: AbsorbPointer(
        child: Opacity(
          opacity: 0.5,
          child: child,
        ),
      ),
    );
  }
}

/// Status indicator showing online/offline status
class ConnectionStatusIndicator extends StatelessWidget {
  final bool isOnline;
  final bool showLabel;
  
  const ConnectionStatusIndicator({
    super.key,
    required this.isOnline,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: isOnline ? AppColors.success : AppColors.warning,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isOnline ? AppColors.success : AppColors.warning).withOpacity(0.4),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: AppTypography.bodySmall.copyWith(
              color: isOnline ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
