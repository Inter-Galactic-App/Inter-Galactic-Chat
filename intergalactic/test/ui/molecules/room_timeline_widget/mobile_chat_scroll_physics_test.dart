import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';

void main() {
  group('MobileChatScrollPhysics', () {
    test('treats short chat flicks as flings', () {
      const physics = MobileChatScrollPhysics();
      const platformDefault = ClampingScrollPhysics();

      expect(
          physics.minFlingDistance, lessThan(platformDefault.minFlingDistance));
      expect(
          physics.minFlingVelocity, lessThan(platformDefault.minFlingVelocity));
    });

    test('preserves custom physics when composed with a parent', () {
      const physics = MobileChatScrollPhysics();
      final composed = physics.applyTo(const AlwaysScrollableScrollPhysics());

      expect(composed, isA<MobileChatScrollPhysics>());
      expect(composed.parent, isA<AlwaysScrollableScrollPhysics>());
    });
  });
}
