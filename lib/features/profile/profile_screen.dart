import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/config/brand_config.dart';
import '../../core/config/backend_capabilities.dart';
import '../../core/realtime/socket_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../data/models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import 'edit_profile_sheet.dart';
import 'legal_document_sheet.dart';
import 'notification_preferences_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = 'v${info.version} (${info.buildNumber})');
    } catch (_) {
      if (mounted) setState(() => _version = 'v1.0.0');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppUser? user = ref.watch(authProvider).user;
    final AsyncValue<SocketStatus> socket = ref.watch(socketStatusProvider);

    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        centerTitle: true,
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Gap.lg, Gap.lg, Gap.lg, Gap.navClearance),
          children: <Widget>[
            // ── Identity ─────────────────────────────────────────────
            _ProfileHeader(user: user),

            const SizedBox(height: Gap.xxl),

          // ── Account ──────────────────────────────────────────────
          _SettingsGroup(
            title: 'ACCOUNT',
            children: <Widget>[
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'Edit profile',
                subtitle: 'Name, phone and timezone',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const EditProfileSheet(),
                ),
              ),
              if (BackendCapabilities.changePassword)
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'Change password',
                  onTap: () => _changePassword(context),
                )
              else
                _SettingsTile(
                  icon: Icons.lock_reset_rounded,
                  title: 'Reset password',
                  subtitle: 'We will email you a secure link',
                  onTap: () => context.push('/forgot-password'),
                ),
              _SettingsTile(
                icon: Icons.receipt_long_outlined,
                title: 'Renewals & billing',
                subtitle: 'Subscriptions and payment history',
                onTap: () => context.push('/renewals'),
              ),
            ],
          ),

          const SizedBox(height: Gap.lg),

          // ── Fleet tools ──────────────────────────────────────────
          _SettingsGroup(
            title: 'FLEET',
            children: <Widget>[
              _SettingsTile(
                icon: Icons.add_road_rounded,
                title: 'Route Management',
                subtitle: 'Set routes & get trip/deviation alerts',
                onTap: () => context.push('/routes'),
              ),
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Alert & Notification Configuration',
                subtitle: 'Customize alerts, speed, idle & stoppage thresholds',
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  useRootNavigator: true,
                  builder: (_) => const NotificationPreferencesSheet(),
                ),
              ),
            ],
          ),

          const SizedBox(height: Gap.lg),

          // ── Appearance ───────────────────────────────────────────
          _SettingsGroup(
            title: 'APPEARANCE',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.light_mode_rounded,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: Gap.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Theme', style: theme.textTheme.titleSmall),
                          Text('Light Mode',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              )),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),



          // ── Legal & support ──────────────────────────────────────
          _SettingsGroup(
            title: 'SUPPORT & LEGAL',
            children: <Widget>[
              _SettingsTile(
                icon: Icons.help_outline_rounded,
                title: 'Contact support',
                subtitle: AppConfig.supportEmail,
                onTap: () => _email(),
              ),
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy policy',
                subtitle: 'Data handling & security practices',
                onTap: () => LegalDocumentSheet.show(
                  context,
                  LegalDocumentType.privacyPolicy,
                ),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms of service',
                subtitle: 'User agreement & service terms',
                onTap: () => LegalDocumentSheet.show(
                  context,
                  LegalDocumentType.termsOfService,
                ),
              ),
            ],
          ),

          const SizedBox(height: Gap.lg),

          // ── Danger zone ──────────────────────────────────────────
          _SettingsGroup(
            title: 'DANGER ZONE',
            children: <Widget>[
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                onTap: () => _confirmLogout(context),
              ),

            ],
          ),

          const SizedBox(height: Gap.x3l),

          Center(
            child: Column(
              children: <Widget>[
                Opacity(
                  opacity: 0.5,
                  child: Text(BrandConfig.appName, style: theme.textTheme.labelMedium),
                ),
                const SizedBox(height: 2),
                Text(
                  _version,
                  style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to monitor your fleet.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    ref.read(fleetProvider.notifier).clear();
    await ref.read(authProvider.notifier).logout();

    if (!context.mounted) return;
    context.go('/login');
  }

  Future<void> _changePassword(BuildContext context) async {
    final TextEditingController current = TextEditingController();
    final TextEditingController next = TextEditingController();

    final bool? submit = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: Gap.md),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (submit != true || !context.mounted) return;

    final bool ok = await ref.read(authProvider.notifier).changePassword(
          currentPassword: current.text,
          newPassword: next.text,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Password updated.'
              : ref.read(authProvider).error ?? 'Could not update password.',
        ),
      ),
    );
  }


  Future<void> _email() async {
    final Uri uri = Uri(
      scheme: 'mailto',
      path: BrandConfig.supportEmail,
      queryParameters: <String, String>{'subject': '${BrandConfig.appName} Support'},
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              user.initials,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (user.orgName.isNotEmpty) ...<Widget>[
                const SizedBox(height: Gap.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.moving.withOpacity(0.15),
                    borderRadius: Corners.rXs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.business_rounded,
                          size: 11, color: AppColors.moving),
                      const SizedBox(width: 5),
                      Text(
                        user.orgName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.moving,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: Gap.sm),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.outline,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: Corners.rLg,
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < children.length; i++) ...<Widget>[
                children[i],
                if (i < children.length - 1)
                  Divider(
                    height: 1,
                    indent: Gap.x3l + Gap.md,
                    color: colorScheme.outlineVariant.withOpacity(0.5),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color color = danger ? colorScheme.error : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: Corners.rLg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (subtitle != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!danger)
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Gap.md),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
