import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/core_providers.dart';

/// Persistent, non-intrusive offline banner.
///
/// Design intent: it must be impossible to miss but must never block content
/// or steal a tap. So it animates down from under the status bar, sits above
/// the app content, and auto-dismisses with a brief green "Back online"
/// confirmation once connectivity returns.
class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool _showRestored = false;

  @override
  Widget build(BuildContext context) {
    final bool isOnline = ref.watch(isOnlineProvider);

    ref.listen<bool>(isOnlineProvider, (bool? prev, bool next) {
      if (prev == false && next == true) {
        setState(() => _showRestored = true);
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showRestored = false);
        });
      }
    });

    final bool show = !isOnline || _showRestored;

    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            duration: Motion.normal,
            curve: Motion.emphasized,
            offset: show ? Offset.zero : const Offset(0, -1.4),
            child: AnimatedOpacity(
              duration: Motion.fast,
              opacity: show ? 1 : 0,
              child: _Banner(isOnline: isOnline && _showRestored),
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double topInset = MediaQuery.paddingOf(context).top;

    final Color bg = isOnline ? AppColors.moving : AppColors.danger;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.fromLTRB(Gap.lg, topInset + 8, Gap.lg, 10),
        decoration: BoxDecoration(
          color: bg,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: bg.withOpacity(0.34),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
              size: 17,
              color: Colors.white,
            ),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Text(
                isOnline
                    ? 'Back online — syncing live data'
                    : 'No internet connection',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact inline variant for use inside a scroll view.
class OfflineNotice extends ConsumerWidget {
  const OfflineNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isOnlineProvider)) return const SizedBox.shrink();

    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: Gap.md),
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.12),
        borderRadius: Corners.rMd,
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.danger),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              'Live updates paused while offline. Data shown may be out of date.',
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
