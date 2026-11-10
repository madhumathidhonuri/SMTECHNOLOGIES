import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/config/brand_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/brand_mark.dart';

/// Shown while `/auth/me` resolves the session on cold boot.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.night1,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppColors.auroraGradient),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandMark(size: 78)
                    .animate(onPlay: (AnimationController c) => c.repeat(reverse: true))
                    .scaleXY(
                      begin: 1,
                      end: 1.05,
                      duration: 1600.ms,
                      curve: Curves.easeInOut,
                    ),
                const SizedBox(height: Gap.xxl),
                Text(
                  BrandConfig.appName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: AppColors.textOnNightHigh,
                  ),
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
                const SizedBox(height: Gap.xs),
                Text(
                  BrandConfig.tagline,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textOnNightMed,
                  ),
                ).animate().fadeIn(delay: 380.ms, duration: 500.ms),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Column(
              children: <Widget>[
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(height: Gap.lg),
                Text(
                  'Securing your session',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textOnNightLow,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ).animate().fadeIn(delay: 600.ms),
          ),
        ],
      ),
    );
  }
}
