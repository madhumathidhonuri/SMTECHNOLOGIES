import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/config/brand_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

enum LegalDocumentType { privacyPolicy, termsOfService }

class LegalDocumentSheet extends StatelessWidget {
  const LegalDocumentSheet({
    required this.type,
    super.key,
  });

  final LegalDocumentType type;

  static void show(BuildContext context, LegalDocumentType type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => LegalDocumentSheet(type: type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isPrivacy = type == LegalDocumentType.privacyPolicy;
    final String title = isPrivacy ? 'Privacy Policy' : 'Terms of Service';
    final IconData icon = isPrivacy
        ? Icons.privacy_tip_outlined
        : Icons.description_outlined;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: <Widget>[
            // Grab handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.xs, Gap.sm, Gap.sm),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppColors.brand, size: 22),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Last updated: August 2026',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.xxl),
                children: isPrivacy
                    ? _buildPrivacyPolicySections(theme)
                    : _buildTermsOfServiceSections(theme),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildPrivacyPolicySections(ThemeData theme) {
    return <Widget>[
      _buildIntroCard(
        theme,
        '${BrandConfig.appName} is committed to protecting your privacy and ensuring your vehicle data and fleet telemetry remain secure and confidential.',
      ),
      const SizedBox(height: Gap.lg),
      _buildSection(
        theme,
        number: '1',
        title: 'Information We Collect',
        content:
            'We collect information to provide intelligent fleet tracking and management services:\n\n'
            '• Account Information: Name, email address, phone number, and organization details.\n'
            '• Vehicle & Telemetry Data: Real-time GPS location (latitude/longitude), speed, ignition state, heading, odometer readings, device time, and sensor data transmitted by GPS tracking devices.\n'
            '• Device & App Diagnostics: Operating system version, app logs, and network connectivity state.',
      ),
      _buildSection(
        theme,
        number: '2',
        title: 'How We Use Your Information',
        content:
            'Your fleet data is utilized solely for operational tracking and analytics:\n\n'
            '• Displaying real-time vehicle locations and live tracking on maps.\n'
            '• Generating trip history, stoppage, day-wise distance, overspeeding, and idling reports.\n'
            '• Delivering instant safety notifications (Geofence entry/exit, SOS, overspeed, vibration, battery disconnect).\n'
            '• Managing subscription validity and renewals.',
      ),
      _buildSection(
        theme,
        number: '3',
        title: 'Data Security & Storage',
        content:
            '• All telemetry in transit is encrypted using industry-standard TLS/HTTPS and secure WebSockets.\n'
            '• Stored data is hosted in high-security cloud environments with strict role-based access controls.\n'
            '• We do not sell, rent, or trade your fleet telemetry or personal information to third parties.',
      ),
      _buildSection(
        theme,
        number: '4',
        title: 'Data Retention & User Rights',
        content:
            '• Telemetry and reports are retained in accordance with your organization’s subscription plan.\n'
            '• You have the right to request access to your data, update account details, or initiate complete account and data deletion directly from within the app settings.',
      ),
      _buildSection(
        theme,
        number: '5',
        title: 'Contact Support',
        content:
            'If you have any questions regarding this Privacy Policy or data security, please reach out to us at ${AppConfig.supportEmail}.',
      ),
      const SizedBox(height: Gap.md),
      _buildFooter(theme),
    ];
  }

  List<Widget> _buildTermsOfServiceSections(ThemeData theme) {
    return <Widget>[
      _buildIntroCard(
        theme,
        'Welcome to ${BrandConfig.appName}. By accessing or using our mobile application and fleet management platform, you agree to comply with these terms.',
      ),
      const SizedBox(height: Gap.lg),
      _buildSection(
        theme,
        number: '1',
        title: 'User Accounts & Access',
        content:
            '• You are responsible for maintaining the confidentiality of your credentials and all activities occurring under your account.\n'
            '• You agree to provide accurate registration details and promptly notify us of any unauthorized access.',
      ),
      _buildSection(
        theme,
        number: '2',
        title: 'Authorized Fleet Tracking',
        content:
            '• The ${BrandConfig.appName} service is designed for tracking and managing vehicles owned or legitimately operated by your organization.\n'
            '• You represent that you have obtained all necessary consent from vehicle operators/drivers in compliance with applicable local laws and regulations.',
      ),
      _buildSection(
        theme,
        number: '3',
        title: 'Service Availability & GPS Telemetry',
        content:
            '• GPS positioning and telemetry transmission depend on satellite visibility, cellular network coverage, and functional hardware trackers.\n'
            '• While we strive for 99.9% uptime, ${BrandConfig.appName} is not liable for temporary service interruptions caused by third-party telecom outages or atmospheric GPS interference.',
      ),
      _buildSection(
        theme,
        number: '4',
        title: 'Subscriptions & Renewals',
        content:
            '• Access to live tracking and reports requires an active vehicle subscription.\n'
            '• Subscriptions can be reviewed and renewed through the in-app Renewals center or via authorized dealers.',
      ),
      _buildSection(
        theme,
        number: '5',
        title: 'Prohibited Uses',
        content:
            'You agree not to reverse engineer, decompile, interfere with server integrity, abuse API rate limits, or use the service for any unlawful surveillance purposes.',
      ),
      _buildSection(
        theme,
        number: '6',
        title: 'Limitation of Liability',
        content:
            '${BrandConfig.appName} provides tracking data for management and informative purposes. We are not liable for indirect, incidental, or consequential damages arising from vehicle operation or hardware malfunction.',
      ),
      _buildSection(
        theme,
        number: '7',
        title: 'Support & Assistance',
        content:
            'For inquiries regarding subscriptions, hardware support, or service terms, please contact ${AppConfig.supportEmail}.',
      ),
      const SizedBox(height: Gap.md),
      _buildFooter(theme),
    ];
  }

  Widget _buildIntroCard(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.brand,
            size: 20,
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme, {
    required String number,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  number,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.colorScheme.onSurface.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          '© 2026 ${BrandConfig.legalEntityName}. All rights reserved.',
          style: AppTypography.eyebrow(theme.colorScheme.onSurfaceVariant)
              .copyWith(fontSize: 11),
        ),
      ),
    );
  }
}
