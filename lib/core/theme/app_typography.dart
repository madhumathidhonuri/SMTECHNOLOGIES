import 'package:flutter/material.dart';

/// Type system.
///
/// * **Sora** for display/headline — geometric, slightly technical, gives the
///   product a confident "instrument panel" voice.
/// * **Inter** for body/label — the best small-size screen legibility available.
/// * **JetBrains Mono** for telemetry numerals (speed, odometer, coordinates)
///   so digits are tabular and never jitter as values tick up.
///
/// All three are **bundled as variable-font assets** rather than pulled from
/// the Google Fonts CDN at runtime. That avoids a first-launch network
/// round-trip, a flash of fallback type on slow connections, and an extra
/// third-party request to justify in privacy review.
class AppTypography {
  const AppTypography._();

  static const String display = 'Sora';
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono';

  static TextTheme textTheme(Color high, Color medium) => TextTheme(
        displayLarge: TextStyle(
          fontFamily: display,
          fontSize: 52,
          height: 1.06,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.6,
          color: high,
        ),
        displayMedium: TextStyle(
          fontFamily: display,
          fontSize: 42,
          height: 1.08,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
          color: high,
        ),
        displaySmall: TextStyle(
          fontFamily: display,
          fontSize: 34,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: high,
        ),
        headlineLarge: TextStyle(
          fontFamily: display,
          fontSize: 30,
          height: 1.16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: high,
        ),
        headlineMedium: TextStyle(
          fontFamily: display,
          fontSize: 25,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
          color: high,
        ),
        headlineSmall: TextStyle(
          fontFamily: display,
          fontSize: 21,
          height: 1.24,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: high,
        ),
        titleLarge: TextStyle(
          fontFamily: display,
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: high,
        ),
        titleMedium: TextStyle(
          fontFamily: body,
          fontSize: 16,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: high,
        ),
        titleSmall: TextStyle(
          fontFamily: body,
          fontSize: 14,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: high,
        ),
        bodyLarge: TextStyle(
          fontFamily: body,
          fontSize: 16,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: high,
        ),
        bodyMedium: TextStyle(
          fontFamily: body,
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w400,
          color: medium,
        ),
        bodySmall: TextStyle(
          fontFamily: body,
          fontSize: 12.5,
          height: 1.45,
          fontWeight: FontWeight.w400,
          color: medium,
        ),
        labelLarge: TextStyle(
          fontFamily: body,
          fontSize: 14.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: high,
        ),
        labelMedium: TextStyle(
          fontFamily: body,
          fontSize: 12.5,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: medium,
        ),
        labelSmall: TextStyle(
          fontFamily: body,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: medium,
        ),
      );

  /// Tabular numerals for live telemetry so the layout never shifts as
  /// speed/odometer values tick.
  static TextStyle metric({
    double size = 28,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        height: 1.05,
        fontWeight: weight,
        letterSpacing: -0.5,
        color: color,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );

  /// Small uppercase section eyebrow.
  static TextStyle eyebrow(Color color) => TextStyle(
        fontFamily: body,
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: color,
      );
}
