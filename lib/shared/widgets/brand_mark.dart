import 'package:flutter/material.dart';

import '../../core/config/brand_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_assets_base64.dart';

/// The Dealer Brand mark and wordmark, driven by [BrandConfig].
class BrandMark extends StatelessWidget {
  const BrandMark({this.size = 56, this.showWordmark = false, super.key});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final Widget mark = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.memory(
        AppAssetsB64.logoIcon,
        height: size * 0.9,
        fit: BoxFit.contain,
      ),
    );

    if (!showWordmark) return mark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        SizedBox(width: size * 0.28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              BrandConfig.appName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: size * 0.36,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
            Text(
              BrandConfig.tagline.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: size * 0.16,
                    letterSpacing: size * 0.03,
                    color: AppColors.signal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small "LIVE" pill shown when the socket is connected.
class LivePill extends StatefulWidget {
  const LivePill({required this.isLive, this.label, super.key});

  final bool isLive;
  final String? label;

  @override
  State<LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = widget.isLive ? AppColors.moving : AppColors.offline;
    final String text = widget.label ?? (widget.isLive ? 'LIVE' : 'OFFLINE');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: Corners.rPill,
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          FadeTransition(
            opacity: widget.isLive
                ? Tween<double>(begin: 0.35, end: 1).animate(_c)
                : const AlwaysStoppedAnimation<double>(1),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 10,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
