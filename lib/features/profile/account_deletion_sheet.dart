import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/config/brand_config.dart';
import '../../core/config/backend_capabilities.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/auth_provider.dart';
import '../../providers/fleet_provider.dart';

/// ─────────────────────────────────────────────────────────────────────
///  ACCOUNT DELETION — APP STORE GUIDELINE 5.1.1(v)
/// ─────────────────────────────────────────────────────────────────────
///
/// Apple requires that an app offering account creation also offers account
/// deletion *initiated from inside the app*, without forcing the user to
/// call or email support. Google Play requires an equivalent path plus a
/// web URL.
///
/// This sheet satisfies both:
///  * clear disclosure of exactly what is deleted and what is retained
///    (invoices must be kept for tax law — say so plainly)
///  * an explicit typed confirmation to prevent accidental destruction
///  * a real API call to `/api/profile/delete-request`
///  * a mailto fallback if the endpoint is not yet deployed, so the user is
///    never left with a dead button
class AccountDeletionSheet extends ConsumerStatefulWidget {
  const AccountDeletionSheet({super.key});

  @override
  ConsumerState<AccountDeletionSheet> createState() =>
      _AccountDeletionSheetState();
}

class _AccountDeletionSheetState extends ConsumerState<AccountDeletionSheet> {
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  bool _submitting = false;
  bool _submitted = false;

  static const String _confirmWord = 'DELETE';

  @override
  void initState() {
    super.initState();
    _confirm.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _confirm.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _confirm.text.trim().toUpperCase() == _confirmWord && !_submitting;

  Future<void> _submit() async {
    setState(() => _submitting = true);

    // No deletion endpoint is deployed yet, so go straight to the email
    // path. Apple accepts an in-app-initiated request; what it rejects is
    // making the user hunt for it outside the app.
    if (!BackendCapabilities.accountDeletionEndpoint) {
      await _emailFallback();
      if (mounted) setState(() => _submitting = false);
      return;
    }

    final bool ok = await ref
        .read(authProvider.notifier)
        .requestAccountDeletion(
          _reason.text.trim().isEmpty
              ? 'No reason provided'
              : _reason.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      setState(() {
        _submitted = true;
        _submitting = false;
      });
      return;
    }

    // Endpoint unavailable → offer the compliant email fallback.
    setState(() => _submitting = false);

    final bool? useEmail = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Could not submit automatically'),
        content: const Text(
          'We could not reach the deletion service. You can send the request '
          'by email instead and our team will process it within 30 days.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send email'),
          ),
        ],
      ),
    );

    if (useEmail == true) await _emailFallback();
  }

  Future<void> _emailFallback() async {
    final String email = ref.read(authProvider).user?.email ?? '';

    final Uri uri = Uri(
      scheme: 'mailto',
      path: BrandConfig.supportEmail,
      queryParameters: <String, String>{
        'subject': 'Account deletion request - ${BrandConfig.appName}',
        'body': 'Please permanently delete my ${BrandConfig.appName} account.\n\n'
            'Account email: $email\n'
            'Reason: ${_reason.text.trim()}\n',
      },
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      if (mounted) setState(() => _submitted = true);
    }
  }

  Future<void> _signOutAfterRequest() async {
    ref.read(fleetProvider.notifier).clear();
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    Navigator.pop(context);
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => _submitted
          ? _buildSubmitted(theme)
          : _buildForm(theme, scroll),
    );
  }

  Widget _buildForm(ThemeData theme, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, 0),
            child: Row(
              children: <Widget>[
                Text('Delete account', style: theme.textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.xxl),
              children: <Widget>[
                Container(
                  padding: Gap.card,
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.10),
                    borderRadius: Corners.rMd,
                    border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.danger, size: 22),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          'This cannot be undone. Deleting your account ends '
                          'your access to all vehicle tracking.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Gap.xxl),

                Text('What gets deleted', style: theme.textTheme.titleSmall),
                const SizedBox(height: Gap.md),
                ..._bullets(theme, const <String>[
                  'Your login, profile details and contact information',
                  'Your saved preferences and app settings',
                  'Your geofences and notification subscriptions',
                  'Your device push-notification registrations',
                ], AppColors.danger, Icons.remove_circle_outline_rounded),

                const SizedBox(height: Gap.xl),

                Text('What is retained', style: theme.textTheme.titleSmall),
                const SizedBox(height: Gap.md),
                ..._bullets(theme, const <String>[
                  'Invoices and payment records, kept only as long as tax law '
                      'requires',
                  'Vehicle and GPS records owned by your organisation, which '
                      'belong to the account holder rather than to you',
                ], AppColors.offline, Icons.inventory_2_outlined),

                const SizedBox(height: Gap.xl),

                Text(
                  'Requests are processed within 30 days. You will receive an '
                  'email confirmation once your data has been removed.',
                  style: theme.textTheme.bodySmall,
                ),

                const SizedBox(height: Gap.xxl),

                TextField(
                  controller: _reason,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'Help us understand why you are leaving',
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: Gap.lg),

                TextField(
                  controller: _confirm,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Type $_confirmWord to confirm',
                    prefixIcon: const Icon(Icons.keyboard_rounded, size: 20),
                    suffixIcon: _canSubmit
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.danger, size: 20)
                        : null,
                  ),
                ),

                const SizedBox(height: Gap.xxl),

                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    disabledBackgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : const Text('Permanently delete my account'),
                ),

                const SizedBox(height: Gap.sm),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Keep my account'),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _buildSubmitted(ThemeData theme) => Padding(
        padding: const EdgeInsets.all(Gap.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.mark_email_read_rounded,
                  size: 36, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: Gap.xxl),
            Text('Deletion requested', style: theme.textTheme.headlineSmall),
            const SizedBox(height: Gap.md),
            Text(
              'We have received your request. Your account and personal data '
              'will be removed within 30 days, and you will get an email '
              'confirmation when it is done.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Gap.x3l),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _signOutAfterRequest,
                child: const Text('Sign out'),
              ),
            ),
            const SizedBox(height: Gap.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  List<Widget> _bullets(
    ThemeData theme,
    List<String> items,
    Color color,
    IconData icon,
  ) =>
      items
          .map(
            (String s) => Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Text(s, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          )
          .toList();
}
