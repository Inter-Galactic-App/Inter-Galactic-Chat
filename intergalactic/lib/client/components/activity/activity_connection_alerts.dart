import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_connection_service.dart';

/// A developer-only, in-memory failure state for exercising the Activity alert
/// surface without touching a provider, relay, credential, or preference.
enum ActivityConnectionAlertSimulation {
  none,
  spotifyReconnectRequired,
  steamUnavailable,
}

/// Publishes actionable in-app alerts for activity integrations that need user
/// attention. Alerts use stable IDs so the shared Alerts list and its sidebar
/// indicator show one entry per unresolved provider.
class ActivityConnectionAlerts {
  ActivityConnectionAlerts({
    required AlertManager alertManager,
    required void Function(BuildContext) openActivitySettings,
  }) : _alertManager = alertManager,
       _openActivitySettings = openActivitySettings;

  static const spotifyAlertId = 'activity-spotify-reconnect-required';
  static const steamAlertId = 'activity-steam-connection-issue';
  static const simulatedSpotifyAlertId =
      'activity-spotify-reconnect-required-simulated';
  static const simulatedSteamAlertId =
      'activity-steam-connection-issue-simulated';

  final AlertManager _alertManager;
  final void Function(BuildContext) _openActivitySettings;
  bool _spotifyAlertVisible = false;
  bool _steamAlertVisible = false;
  String? _steamAlertIssue;
  ActivityConnectionAlertSimulation _developerSimulation =
      ActivityConnectionAlertSimulation.none;

  ActivityConnectionAlertSimulation get developerSimulation =>
      _developerSimulation;

  /// Adds a separately identified local alert for developer smoke testing.
  ///
  /// This deliberately does not alter a provider status, credentials, saved
  /// settings, or network access. Clearing a simulation also leaves any real
  /// provider alert untouched.
  void setDeveloperSimulation(ActivityConnectionAlertSimulation simulation) {
    _clearDeveloperSimulationAlerts();
    _developerSimulation = simulation;

    switch (simulation) {
      case ActivityConnectionAlertSimulation.none:
        return;
      case ActivityConnectionAlertSimulation.spotifyReconnectRequired:
        _alertManager.addAlert(
          Alert(
            AlertType.warning,
            id: simulatedSpotifyAlertId,
            titleGetter: () => 'Spotify activity disconnected (simulated)',
            messageGetter: () =>
                'Spotify access is simulated as expired. No Spotify request or credentials were changed.',
            actionLabel: 'Open Activity settings',
            action: _openActivitySettings,
          ),
        );
        return;
      case ActivityConnectionAlertSimulation.steamUnavailable:
        _alertManager.addAlert(
          Alert(
            AlertType.warning,
            id: simulatedSteamAlertId,
            titleGetter: () => 'Steam activity needs attention (simulated)',
            messageGetter: () =>
                'Steam activity is simulated as unavailable. No relay request or settings were changed.',
            actionLabel: 'Open Activity settings',
            action: _openActivitySettings,
          ),
        );
        return;
    }
  }

  void updateSpotifyStatus(SpotifyConnectionStatus status) {
    switch (status.state) {
      case SpotifyConnectionState.reconnectRequired:
        if (_spotifyAlertVisible) {
          return;
        }
        _spotifyAlertVisible = true;
        _alertManager.addAlert(
          Alert(
            AlertType.warning,
            id: spotifyAlertId,
            titleGetter: () => 'Spotify activity disconnected',
            messageGetter: () =>
                'Spotify access ended. Reconnect Spotify to continue sharing activity.',
            actionLabel: 'Open Activity settings',
            action: _openActivitySettings,
          ),
        );
        break;
      case SpotifyConnectionState.connected:
      case SpotifyConnectionState.disconnected:
      case SpotifyConnectionState.notConfigured:
        _clearSpotifyAlert();
        break;
      case SpotifyConnectionState.connecting:
      case SpotifyConnectionState.cancelled:
      case SpotifyConnectionState.failed:
        break;
    }
  }

  void updateSteamConnectionIssue(String? issue) {
    if (issue == null) {
      _clearSteamAlert();
      return;
    }

    // The message is the issue text itself, so a visible alert that is not
    // re-posted keeps describing a problem the source has already moved on
    // from. Suppress only an unchanged repeat; replace on a changed one.
    if (_steamAlertVisible && issue == _steamAlertIssue) {
      return;
    }
    if (_steamAlertVisible) {
      _alertManager.clearAlertsById(steamAlertId);
    }
    _steamAlertVisible = true;
    _steamAlertIssue = issue;
    _alertManager.addAlert(
      Alert(
        AlertType.warning,
        id: steamAlertId,
        titleGetter: () => 'Steam activity needs attention',
        messageGetter: () => issue,
        actionLabel: 'Open Activity settings',
        action: _openActivitySettings,
      ),
    );
  }

  void _clearSpotifyAlert() {
    if (!_spotifyAlertVisible) {
      return;
    }
    _spotifyAlertVisible = false;
    _alertManager.clearAlertsById(spotifyAlertId);
  }

  void _clearSteamAlert() {
    if (!_steamAlertVisible) {
      return;
    }
    _steamAlertVisible = false;
    _steamAlertIssue = null;
    _alertManager.clearAlertsById(steamAlertId);
  }

  void _clearDeveloperSimulationAlerts() {
    _alertManager.clearAlertsById(simulatedSpotifyAlertId);
    _alertManager.clearAlertsById(simulatedSteamAlertId);
  }
}
