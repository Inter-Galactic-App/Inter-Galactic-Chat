import 'package:intergalactic/client/components/activity/activity_models.dart';

abstract class ActivitySource {
  String get id;
  ActivityKind get kind;
  UserActivity? get currentActivity;
  Stream<UserActivity?> get onActivityChanged;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();

  Future<void> executeControl(String controlId) async {
    throw UnsupportedError('Activity source $id does not support controls');
  }
}

abstract class GameActivitySource implements ActivitySource {}

abstract class MusicActivitySource implements ActivitySource {}
