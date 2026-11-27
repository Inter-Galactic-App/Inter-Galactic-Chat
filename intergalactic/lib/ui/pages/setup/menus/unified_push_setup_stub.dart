import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:flutter/material.dart';

class UnifiedPushSetup implements SetupMenu {
  @override
  Widget builder(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  Stream<SetupMenuState> get onStateChanged => const Stream.empty();

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {}
}

class UnifiedPushSetupView extends StatelessWidget {
  const UnifiedPushSetupView({super.key, this.onToggled});

  final Function(bool enabled)? onToggled;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

