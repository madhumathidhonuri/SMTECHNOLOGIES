import 'package:flutter/widgets.dart';

/// 4pt spacing scale. Every gap in the app comes from this ladder so
/// vertical rhythm stays consistent across 40+ screens.
class Gap {
  const Gap._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3l = 32;
  static const double x4l = 40;
  static const double x5l = 56;

  /// Standard horizontal page inset.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets pageV = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets card = EdgeInsets.all(lg);
  static const EdgeInsets cardTight = EdgeInsets.all(md);

  /// Bottom padding that clears the floating nav bar + safe area.
  static const double navClearance = 170;
}

/// Corner radius tokens — generous, Material 3 "expressive" feel.
class Corners {
  const Corners._();

  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const BorderRadius rXs = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius rSm = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius rMd = BorderRadius.all(Radius.circular(md));
  static const BorderRadius rLg = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius rXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius rPill = BorderRadius.all(Radius.circular(pill));

  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Motion tokens — Material 3 emphasized easing.
class Motion {
  const Motion._();

  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 450);
  static const Duration lazy = Duration(milliseconds: 700);

  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve emphasizedIn = Curves.easeInCubic;
  static const Curve spring = Curves.easeOutBack;
  static const Curve standard = Curves.fastOutSlowIn;
}
