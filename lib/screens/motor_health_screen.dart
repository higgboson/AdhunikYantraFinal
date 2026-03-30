import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import '../providers/circuit_provider.dart';

class MotorHealthScreen extends ConsumerWidget {
  const MotorHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circuitsAsync = ref.watch(circuitsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Motor Health',
          style: AppTypography.heading3,
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall Health Score
            _buildOverallHealthCard(),
            const SizedBox(height: 24),
            
            // Per Circuit Motors
            Text(
              'Motor Status by Circuit',
              style: AppTypography.heading3,
            ),
            const SizedBox(height: 16),
            
            circuitsAsync.when(
              data: (circuits) {
                return Column(
                  children: circuits.map((circuit) {
                    return _buildMotorCard(circuit);
                  }).toList(),
                );
              },
              loading: () => _buildLoadingCard(),
              error: (error, _) => _buildError(error.toString()),
            ),
            
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildOverallHealthCard() {
    // Mock overall health score
    const healthScore = 87;
    const color = healthScore > 80 
        ? AppColors.primary 
        : healthScore > 60 
            ? AppColors.warning 
            : AppColors.danger;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppDecorations.cardGlow,
      child: Column(
        children: [
          Text(
            'Overall Motor Health',
            style: AppTypography.heading3.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 24),
          
          // Circular gauge
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: healthScore / 100,
                  strokeWidth: 12,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$healthScore',
                        style: AppTypography.orbitron(
                          size: 48,
                          weight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        'out of 100',
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              healthScore > 80 ? 'HEALTHY' : healthScore > 60 ? 'CAUTION' : 'CRITICAL',
              style: AppTypography.dmSans(
                weight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMotorCard(dynamic circuit) {
    // Mock motor data
    final powerFactor = 0.85 + (circuit.id.hashCode % 10) / 100;
    final healthScore = 75 + (circuit.id.hashCode % 20);
    final maintenanceDays = 30 - (circuit.id.hashCode % 15);
    
    final color = healthScore > 80 
        ? AppColors.primary 
        : healthScore > 60 
            ? AppColors.warning 
            : AppColors.danger;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  circuit.name,
                  style: AppTypography.heading3.copyWith(fontSize: 18),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  healthScore > 80 ? 'Healthy' : healthScore > 60 ? 'Fair' : 'Poor',
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Power factor gauge
          Row(
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: powerFactor,
                      strokeWidth: 8,
                      backgroundColor: AppColors.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        powerFactor > 0.8 ? AppColors.primary : AppColors.warning,
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'PF',
                            style: AppTypography.caption,
                          ),
                          Text(
                            powerFactor.toStringAsFixed(2),
                            style: AppTypography.shareTechMono(
                              size: 16,
                              weight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Power Factor: ${(powerFactor * 100).toInt()}%',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Health Score: $healthScore/100',
                      style: AppTypography.body,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Maintenance due in $maintenanceDays days',
                      style: AppTypography.bodySmall.copyWith(
                        color: maintenanceDays < 15 ? AppColors.warning : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),
          
          // Explanation
          Text(
            'This motor is operating within normal parameters. Power factor indicates electrical efficiency.',
            style: AppTypography.bodySmall,
          ),
          
          const SizedBox(height: 16),
          
          // Schedule maintenance button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: () {
                // Schedule maintenance
              },
              icon: const Icon(Icons.build),
              label: const Text('Schedule Maintenance'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
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

  Widget _buildError(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppDecorations.card,
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 48),
          const SizedBox(height: 16),
          Text('Error loading motor data', style: AppTypography.heading3),
          const SizedBox(height: 8),
          Text(message, style: AppTypography.bodySmall),
        ],
      ),
    );
  }
}
