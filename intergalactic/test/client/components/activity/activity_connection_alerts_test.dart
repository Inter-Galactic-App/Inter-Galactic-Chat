import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/components/activity/activity_connection_alerts.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_connection_service.dart';

void main() {
  group('ActivityConnectionAlerts', () {
    test('keeps one Spotify alert visible until the connection recovers', () {
      final alertManager = AlertManager();
      final alerts = ActivityConnectionAlerts(
        alertManager: alertManager,
        openActivitySettings: (_) {},
      );

      alerts.updateSpotifyStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.reconnectRequired,
        ),
      );
      alerts.updateSpotifyStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.reconnectRequired,
        ),
      );

      final alert = alertManager.alerts.single;
      expect(alert.id, ActivityConnectionAlerts.spotifyAlertId);
      expect(alert.type, AlertType.warning);
      expect(alert.title, 'Spotify activity disconnected');
      expect(alert.actionLabel, 'Open Activity settings');

      alerts.updateSpotifyStatus(
        const SpotifyConnectionStatus(state: SpotifyConnectionState.failed),
      );
      expect(alertManager.alerts, hasLength(1));

      alerts.updateSpotifyStatus(
        const SpotifyConnectionStatus(state: SpotifyConnectionState.connected),
      );
      expect(alertManager.alerts, isEmpty);
    });

    test('shows and clears the Steam alert with its connection issue', () {
      final alertManager = AlertManager();
      final alerts = ActivityConnectionAlerts(
        alertManager: alertManager,
        openActivitySettings: (_) {},
      );

      alerts.updateSteamConnectionIssue(
        'Steam activity could not be reached. Check your Steam connection and try again.',
      );

      final alert = alertManager.alerts.single;
      expect(alert.id, ActivityConnectionAlerts.steamAlertId);
      expect(alert.type, AlertType.warning);
      expect(alert.title, 'Steam activity needs attention');
      expect(alert.message, contains('could not be reached'));

      alerts.updateSteamConnectionIssue(null);
      expect(alertManager.alerts, isEmpty);
    });

    test('replaces the Steam alert when the reported issue changes', () {
      final alertManager = AlertManager();
      final alerts = ActivityConnectionAlerts(
        alertManager: alertManager,
        openActivitySettings: (_) {},
      );

      alerts.updateSteamConnectionIssue('Steam could not be reached.');
      // An unchanged repeat must not stack a second alert.
      alerts.updateSteamConnectionIssue('Steam could not be reached.');
      expect(alertManager.alerts, hasLength(1));
      expect(alertManager.alerts.single.message, 'Steam could not be reached.');

      // A different issue must be shown, not silently suppressed behind the
      // stale one the user is still looking at.
      alerts.updateSteamConnectionIssue('Steam is not signed in.');
      expect(alertManager.alerts, hasLength(1));
      expect(alertManager.alerts.single.message, 'Steam is not signed in.');
      expect(
        alertManager.alerts.single.id,
        ActivityConnectionAlerts.steamAlertId,
      );

      alerts.updateSteamConnectionIssue(null);
      expect(alertManager.alerts, isEmpty);
    });

    test('developer simulation is local and leaves real alerts untouched', () {
      final alertManager = AlertManager();
      final alerts = ActivityConnectionAlerts(
        alertManager: alertManager,
        openActivitySettings: (_) {},
      );

      alerts.updateSpotifyStatus(
        const SpotifyConnectionStatus(
          state: SpotifyConnectionState.reconnectRequired,
        ),
      );
      alerts.setDeveloperSimulation(
        ActivityConnectionAlertSimulation.steamUnavailable,
      );

      expect(
        alerts.developerSimulation,
        ActivityConnectionAlertSimulation.steamUnavailable,
      );
      expect(
        alertManager.alerts.map((alert) => alert.id).toList(),
        containsAll([
          ActivityConnectionAlerts.spotifyAlertId,
          ActivityConnectionAlerts.simulatedSteamAlertId,
        ]),
      );
      final simulatedSteamAlert = alertManager.alerts.singleWhere(
        (alert) => alert.id == ActivityConnectionAlerts.simulatedSteamAlertId,
      );
      expect(simulatedSteamAlert.type, AlertType.warning);
      expect(simulatedSteamAlert.title, contains('simulated'));
      expect(simulatedSteamAlert.message, contains('No relay request'));
      expect(simulatedSteamAlert.actionLabel, 'Open Activity settings');

      alerts.setDeveloperSimulation(ActivityConnectionAlertSimulation.none);

      expect(alertManager.alerts.map((alert) => alert.id).toList(), [
        ActivityConnectionAlerts.spotifyAlertId,
      ]);
      expect(
        alerts.developerSimulation,
        ActivityConnectionAlertSimulation.none,
      );
    });
  });
}
