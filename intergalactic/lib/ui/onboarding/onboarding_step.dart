import 'package:flutter/material.dart';

class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.title,
    required this.body,
    this.icon,
    this.assetPath,
    this.primaryActionLabel,
    this.targetAnchorId,
  });

  final String id;
  final String title;
  final String body;
  final IconData? icon;
  final String? assetPath;
  final String? primaryActionLabel;
  final String? targetAnchorId;
}
