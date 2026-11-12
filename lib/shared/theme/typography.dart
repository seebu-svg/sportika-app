import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';

/// The two bundled families, mapped onto named roles so screens never invent a
/// one-off [TextStyle]. Barlow Condensed carries anything that should read like
/// sports editorial (scores, tab titles); Inter carries everything readable.
class SportikaType {
  SportikaType._();

  static const String displayFamily = 'Barlow Condensed';
  static const String bodyFamily = 'Inter';

  /// Root-tab title, splash statement.
  static const TextStyle hero = TextStyle(
    fontFamily: displayFamily,
    fontSize: 32,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.6,
    color: SportikaColors.text,
  );

  /// Screen and sheet titles.
  static const TextStyle title = TextStyle(
    fontFamily: displayFamily,
    fontSize: 24,
    height: 1.1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
    color: SportikaColors.text,
  );

  /// Section and card headings.
  static const TextStyle headline = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 19,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
    color: SportikaColors.text,
  );

  /// Big numeric readout (fixture score, dashboard metric).
  static const TextStyle score = TextStyle(
    fontFamily: displayFamily,
    fontSize: 26,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: SportikaColors.text,
  );

  /// Smaller numeric readout inside dense rows.
  static const TextStyle scoreSmall = TextStyle(
    fontFamily: displayFamily,
    fontSize: 20,
    height: 1.05,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.2,
    color: SportikaColors.text,
  );

  /// All-caps eyebrow above a group of content.
  static const TextStyle label = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
    color: SportikaColors.textMuted,
  );

  /// All-caps micro label inside pills and chips.
  static const TextStyle micro = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 9.5,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    color: SportikaColors.textMuted,
  );

  /// Default reading size.
  static const TextStyle body = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13.5,
    height: 1.4,
    fontWeight: FontWeight.w500,
    color: SportikaColors.textBody,
  );

  /// Emphasised reading size (card titles, list rows).
  static const TextStyle bodyStrong = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 13.5,
    height: 1.3,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: SportikaColors.text,
  );

  /// Supporting copy, timestamps, helper text.
  static const TextStyle caption = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 11.5,
    height: 1.35,
    fontWeight: FontWeight.w500,
    color: SportikaColors.textMuted,
  );

  /// Button and chip text.
  static const TextStyle action = TextStyle(
    fontFamily: bodyFamily,
    fontSize: 12.5,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.3,
    color: SportikaColors.text,
  );

  /// Resolves a role by name so widgets can take a `role` parameter.
  static TextStyle of(SportikaTextRole role) => switch (role) {
    SportikaTextRole.hero => hero,
    SportikaTextRole.title => title,
    SportikaTextRole.headline => headline,
    SportikaTextRole.score => score,
    SportikaTextRole.label => label,
    SportikaTextRole.body => body,
    SportikaTextRole.caption => caption,
  };
}

/// Named roles exposed to widgets that need to pick one at runtime.
enum SportikaTextRole { hero, title, headline, score, label, body, caption }

/// Widest layout the app supports; the plan clamps reading width on tablets.
const double sportikaMaxContentWidth = 640;

/// Text-scale ceiling. Beyond 1.3 the densest cards (score rows, bracket chips)
/// cannot avoid clipping, so the app opts out of unlimited scaling rather than
/// shipping a broken accessibility mode.
const double sportikaMaxTextScale = 1.3;

/// Clamps the inherited text scale to [sportikaMaxTextScale].
class ClampedTextScale extends StatelessWidget {
  const ClampedTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: sportikaMaxTextScale,
    child: child,
  );
}
