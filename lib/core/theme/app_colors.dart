import 'package:flutter/material.dart';

import '../config/brand_config.dart';

/// ─────────────────────────────────────────────────────────────────────
///  DEALER BRAND COLOR SYSTEM
/// ─────────────────────────────────────────────────────────────────────
///
/// Centralized palette powered by [BrandConfig].
/// All downstream components, widgets, and themes consume these tokens.
class AppColors {
  const AppColors._();

  // ── Brand ────────────────────────────────────────────────────────
  static const Color brand = BrandConfig.primaryColor;
  static const Color brandBright = BrandConfig.primaryBright;
  static const Color brandDeep = BrandConfig.primaryDeep;
  static const Color signal = BrandConfig.accentColor;
  static const Color signalDeep = BrandConfig.accentDeep;

  // ── Dark surfaces (deep sapphire midnight) ──────────────────────
  static const Color night0 = Color(0xFF070E1A); // scrim / deepest midnight
  static const Color night1 = Color(0xFF0B1629); // scaffold
  static const Color night2 = Color(0xFF12213D); // card
  static const Color night3 = Color(0xFF1A2D52); // elevated card
  static const Color night4 = Color(0xFF233B6B); // hover / pressed
  static const Color nightBorder = Color(0xFF284478);

  // ── Light surfaces (Soft Neumorphic Porcelain Ice-Blue) ──────────
  static const Color day0 = Color(0xFFEDF2F9); // main neumorphic canvas
  static const Color day1 = Color(0xFFF7FAFE); // elevated surface
  static const Color day2 = Color(0xFFEFF4FC); // neumorphic card/pill
  static const Color day3 = Color(0xFFE2ECFA); // pressed/inset
  static const Color dayBorder = Color(0xFFD4E2F4);

  // ── Neumorphic shadow tones ──────────────────────────────────────
  static const Color neumorphicHighlight = Colors.white;
  static const Color neumorphicShadow = Color(0xFFC7D7EC);

  // ── Text ─────────────────────────────────────────────────────────
  static const Color textOnNightHigh = Color(0xFFF1F5F9);
  static const Color textOnNightMed = Color(0xFF94A3B8);
  static const Color textOnNightLow = Color(0xFF64748B);

  static const Color textOnDayHigh = Color(0xFF0D1B36); // midnight blue
  static const Color textOnDayMed = Color(0xFF637691); // slate blue
  static const Color textOnDayLow = Color(0xFF8E9EB6); // soft muted/hint

  // ── Fleet status semantics ───────────────────────────────────────
  /// Ignition on, speed > 0 — actively driving.
  static const Color moving = Color(0xFF10B981);
  static const Color movingSoft = Color(0xFF16351F);

  /// Ignition on, speed ≈ 0 — engine burning fuel while parked.
  static const Color idle = Color(0xFFEAB308);
  static const Color idleSoft = Color(0xFF3A2A0A);

  /// Ignition off but reporting — parked (Gray).
  static const Color stopped = Color(0xFF64748B);
  static const Color stoppedSoft = Color(0xFF1E2637);

  /// No packet within the offline threshold — (Red).
  static const Color offline = Color(0xFFEF4444);
  static const Color offlineSoft = Color(0xFF3B1122);

  /// No telemetry or GPS data ever received / unavailable — (Slate Gray).
  static const Color noData = Color(0xFFBE123C);
  static const Color noDataSoft = Color(0xFF1E293B);

  /// Alerts / overspeed / SOS.
  static const Color danger = Color(0xFFFF4D6D);
  static const Color dangerSoft = Color(0xFF3B1122);

  static const Color success = moving;
  static const Color warning = idle;

  // ── Chart ramp (colour-blind safe ordering) ──────────────────────
  static const List<Color> chartRamp = <Color>[
    BrandConfig.primaryColor,
    BrandConfig.accentColor,
    Color(0xFF10B981),
    Color(0xFF06B6D4),
    Color(0xFFFF4D6D),
    Color(0xFF8B5CF6),
  ];

  // ── Signature gradients & Neumorphic Styles ─────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF2E75FF), Color(0xFF0C4CD6)],
  );

  static const LinearGradient brandGlowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFF38BDF8), Color(0xFF1E60FF), Color(0xFF0B4CD8)],
  );

  static const LinearGradient auroraGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF1E3A8A), Color(0xFF0B1629)],
  );

  static const LinearGradient neumorphicCanvasGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0xFFF6FAFE), Color(0xFFE8EEF8)],
  );

  static List<BoxShadow> get neumorphicRaised => const [
        BoxShadow(color: neumorphicHighlight, offset: Offset(-5, -5), blurRadius: 12),
        BoxShadow(color: neumorphicShadow, offset: Offset(6, 6), blurRadius: 14),
      ];

  static List<BoxShadow> get neumorphicPill => const [
        BoxShadow(color: neumorphicHighlight, offset: Offset(-3, -3), blurRadius: 8),
        BoxShadow(color: Color(0xFFC7D7EC), offset: Offset(4, 4), blurRadius: 10),
      ];

  static List<BoxShadow> get neumorphicButtonGlow => [
        BoxShadow(color: BrandConfig.primaryColor.withOpacity(0.4), offset: const Offset(0, 8), blurRadius: 18),
        BoxShadow(color: Colors.white.withOpacity(0.8), offset: const Offset(-2, -2), blurRadius: 6),
      ];

  static const LinearGradient glassSheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[Color(0x1FFFFFFF), Color(0x05FFFFFF)],
  );

  /// Fade used at the top of the live map so status chips stay legible.
  static const LinearGradient mapTopScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xCC041A18), Color(0x00041A18)],
  );

  /// Returns the semantic colour for a vehicle status key.
  static Color forStatus(String status) => switch (status.toLowerCase()) {
        'moving' || 'running' || 'online' => moving,
        'idle' || 'idling' => idle,
        'stopped' || 'parked' => stopped,
        'nodata' || 'no_data' || 'no data' => noData,
        'offline' || 'disconnected' => offline,
        'alert' || 'sos' || 'overspeed' => danger,
        _ => offline,
      };

  static Color softForStatus(String status) => switch (status.toLowerCase()) {
        'moving' || 'running' || 'online' => movingSoft,
        'idle' || 'idling' => idleSoft,
        'stopped' || 'parked' => stoppedSoft,
        'nodata' || 'no_data' || 'no data' => noDataSoft,
        'offline' || 'disconnected' => offlineSoft,
        'alert' || 'sos' || 'overspeed' => dangerSoft,
        _ => offlineSoft,
      };
}
