import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────
///  CENTRAL BRAND CONFIGURATION (WHITE-LABEL DEALER SPECIFICATION)
/// ─────────────────────────────────────────────────────────────────────────
///
/// Single source of truth for all dealer branding across the application.
/// Changing values in this file updates:
/// - App name, display titles, and headers
/// - Legal business entity name across terms, policy, and fitment certificates
/// - Contact and support endpoints
/// - Colors (primary brand palette and signal accents)
/// - Deep linking scheme and notification channel identifiers
/// - Logo and image asset references
///
class BrandConfig {
  const BrandConfig._();

  // ── Core Brand Identity ──────────────────────────────────────────────────
  static const String appName = 'SM TECH';
  static const String legalEntityName = 'SM Technologies Pvt Ltd';
  static const String tagline = 'Fleet tracking made simple';
  static const String subTagline = 'Fleet intelligence, live';
  static const String loginHeaderSubtext = 'SM TECH FLEET TELEMETRY';

  // ── Platform & Application Identifiers ───────────────────────────────────
  static const String applicationId = 'com.dealer.fleet';
  static const String deepLinkScheme = 'dealerfleet';
  static const String batteryChannel = 'com.dealer.fleet/battery';
  static const String tileUserAgent = 'com.dealer.fleet.app';

  // ── Contact & Compliance Links ───────────────────────────────────────────
  static const String supportEmail = 'support@dealer.example';
  static const String privacyPolicyUrl = 'https://dealer.example/privacy';
  static const String termsUrl = 'https://dealer.example/terms';
  static const String verificationBaseUrl = 'https://dealer.example/verify';

  // ── Push Notification Channels ───────────────────────────────────────────
  static const String criticalChannelId = 'dealerfleet_critical_v4';
  static const String criticalChannelName = 'Critical Fleet Alerts';
  static const String criticalChannelDesc = 'SOS, power disconnection and tamper alerts.';

  static const String alertsChannelId = 'dealerfleet_alerts_v4';
  static const String alertsChannelName = 'Fleet Alerts';
  static const String alertsChannelDesc = 'Overspeeding, geofence and ignition notifications.';

  static const String theftChannelId = 'theft_alarm_channel';
  static const String theftChannelName = 'Theft Alarm (Safety Parking)';
  static const String theftChannelDesc = 'Emergency siren alerts when vehicle theft is detected.';

  // ── Brand Color Palette (Soft Neumorphic Ice-Blue & Azure) ───────────────
  /// Primary brand color: Royal Azure Blue (#1E60FF)
  static const Color primaryColor = Color(0xFF1E60FF);
  static const Color primaryBright = Color(0xFF3B82F6); // Blue 500
  static const Color primaryDeep = Color(0xFF0B4CD8); // Deep Cobalt
  static const Color primaryContainer = Color(0xFFE2ECFA); // Ice Blue container
  static const Color onPrimaryContainer = Color(0xFF082B73); // Deep Navy

  /// Accent / Cyan-Sky highlight color: Sky (#00C2FF)
  static const Color accentColor = Color(0xFF00C2FF);
  static const Color accentBright = Color(0xFF38BDF8); // Sky 400
  static const Color accentDeep = Color(0xFF0284C7); // Sky 600
  static const Color accentContainer = Color(0xFFE0F2FE); // Sky 100
  static const Color onAccentContainer = Color(0xFF075985); // Sky 800

  // ── Logo & Image Asset Paths ─────────────────────────────────────────────
  static const String logoIconAsset = 'assets/images/logo_icon_transparent.png';
  static const String logoEmblemAsset = 'assets/images/logo_emblem.png';
  static const String logoFullAsset = 'assets/images/logo_full.jpg';
  static const String splashLogoAsset = 'assets/images/splash_logo.png';
  static const String appIconMasterAsset = 'assets/images/app_icon_master.png';
  static const String appIconForegroundAsset = 'assets/images/app_icon_foreground.png';
  static const String loginBgAsset = 'assets/images/login_bg_trucks.png';
}

