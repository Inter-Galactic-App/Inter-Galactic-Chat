import 'package:flutter/material.dart';

/// Mobile-only visual tokens that can be tuned without changing navigation,
/// state, or data flow.
class MobileVisuals {
  static const double screenPadding = 16;
  static const double sectionSpacing = 16;
  static const double cardRadius = 28;
  static const double panelRadius = 32;
  static const double pillRadius = 999;
  static const double listItemHeight = 52;
  static const double groupedInset = 14;
  static const double highlightOpacity = 0.12;
  static const double strokeOpacity = 0.18;
  static const double edgeHighlightOpacity = 0.34;
  static const double edgeShadowOpacity = 0.1;
  static const double shadowOpacity = 0.14;
  static const double blurRadius = 26;

  static BorderRadius get cardBorderRadius => BorderRadius.circular(cardRadius);

  static BorderRadius get panelBorderRadius =>
      BorderRadius.circular(panelRadius);

  static BorderRadius get pillBorderRadius => BorderRadius.circular(pillRadius);

  static EdgeInsets get screenEdgeInsets => const EdgeInsets.all(screenPadding);

  static EdgeInsets get sectionEdgeInsets =>
      const EdgeInsets.all(sectionSpacing);

  static EdgeInsets get groupedSectionPadding =>
      const EdgeInsets.symmetric(horizontal: groupedInset, vertical: 12);
}
