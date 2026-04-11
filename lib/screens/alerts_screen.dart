import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../core/offline_cache.dart';
import '../models/circuit_model.dart';
import '../models/fault_model.dart';
import '../providers/fault_provider.dart';
import '../providers/connectivity_provider.dart';
import '../widgets/offline_banner.dart';

class AlertsCentreScreen extends ConsumerStatefulWidget {
  const AlertsCentreScreen({super.key});

  @override
  ConsumerState<AlertsCentreScreen> createState() => _AlertsCentreScreenState();
}

class _AlertsCentreScreenState extends ConsumerState<AlertsCentreScreen> {
  AlertType _selectedFilter = AlertType.all;

  @override
  Widget build(BuildContext context) {
    final faultsAsync = ref.watch(allFaultsProvider);
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          'Alerts Centre',
          style: AppTypography.heading3,
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Offline Banner
          OfflineBanner(isOffline: isOffline),
          
          // Filter tabs
          _buildFilterTabs(),
          
          // Alerts list
          Expanded(
            child: isOffline
                ? _buildOfflineAlertsList()
                : faultsAsync.when(
                    data: (faults) {
                      final filteredAlerts = _getFilteredAlerts(faults);
                      
                      if (filteredAlerts.isEmpty) {
                        return _buildEmptyState();
                      }
                      
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredAlerts.length,
                        itemBuilder: (context, index) {
                          return _buildAlertCard(filteredAlerts[index]);
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    ),
                    error: (error, _) => _buildError(error.toString()),
                  ),
          ),
        ],
      ),
    );
  }

  /// Build alerts list from cache when offline
  Widget _buildOfflineAlertsList() {
    final cachedFaults = OfflineCache.getFaultHistory();
    
    if (cachedFaults.isEmpty) {
      return _buildEmptyState();
    }
    
    // Convert cached data to Fault objects
    final faults = cachedFaults.map((data) {
      return Fault.fromMap(
        data['id']?.toString() ?? '',
        data,
      );
    }).toList();
    
    final filteredAlerts = _getFilteredAlerts(faults);
    
    if (filteredAlerts.isEmpty) {
      return _buildEmptyState();
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredAlerts.length,
      itemBuilder: (context, index) {
        return _buildAlertCard(filteredAlerts[index]);
      },
    );
  }

  Widget _buildFilterTabs() {
    const filters = AlertType.values;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(
          bottom: BorderSide(color: AppColors.border),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final isSelected = filter == _selectedFilter;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFilter = filter;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Text(
                    filter.displayName,
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
      ),
    );
  }

  Widget _buildAlertCard(Fault fault) {
    final icon = _getAlertIcon(fault.type);
    final color = _getAlertColor(fault.type);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: fault.resolved ? AppColors.border : color.withValues(alpha: 0.5),
          width: fault.resolved ? 1 : 2,
        ),
        boxShadow: !fault.resolved
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: () => context.push('/fault/${fault.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fault.type.displayName,
                          style: AppTypography.dmSans(
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${fault.circuit} • ${fault.timeAgo}',
                          style: AppTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!fault.resolved)
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(color: AppColors.border),
              const SizedBox(height: 12),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    fault.resolved ? 'Resolved' : 'Active',
                    style: AppTypography.bodySmall.copyWith(
                      color: fault.resolved ? AppColors.primary : color,
                    ),
                  ),
                  if (!fault.resolved)
                    TextButton(
                      onPressed: () => context.push('/fault/${fault.id}'),
                      child: Text(
                        'View Details',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 48,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'All Clear!',
            style: AppTypography.orbitron(
              size: 24,
              weight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No active alerts at the moment',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
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
            size: 48,
            color: AppColors.danger,
          ),
          const SizedBox(height: 16),
          Text(
            'Error loading alerts',
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

  List<Fault> _getFilteredAlerts(List<Fault> faults) {
    switch (_selectedFilter) {
      case AlertType.all:
        return faults;
      case AlertType.active:
        return faults.where((f) => !f.resolved).toList();
      case AlertType.fault:
        return faults.where((f) => 
          f.type != FaultType.none && 
          (f.type == FaultType.overload || 
           f.type == FaultType.short ||
           f.type == FaultType.overvoltage ||
           f.type == FaultType.undervoltage)
        ).toList();
      case AlertType.energy:
        return faults.where((f) => 
          f.type == FaultType.thermal || f.type == FaultType.leakage
        ).toList();
      case AlertType.maintenance:
        return [];
    }
  }

  IconData _getAlertIcon(FaultType type) {
    switch (type) {
      case FaultType.short:
        return Icons.flash_on;
      case FaultType.thermal:
        return Icons.local_fire_department;
      case FaultType.overload:
        return Icons.bolt;
      case FaultType.leakage:
        return Icons.water_drop;
      default:
        return Icons.warning;
    }
  }

  Color _getAlertColor(FaultType type) {
    switch (type) {
      case FaultType.short:
      case FaultType.thermal:
        return AppColors.danger;
      case FaultType.overload:
        return AppColors.warning;
      case FaultType.leakage:
        return AppColors.secondary;
      default:
        return AppColors.primary;
    }
  }
}
