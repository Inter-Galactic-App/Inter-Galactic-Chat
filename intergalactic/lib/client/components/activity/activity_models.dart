enum ActivityKind {
  game,
  music,
  call,
  screenShare,
  custom,
}

extension ActivityKindJson on ActivityKind {
  String get jsonName {
    return switch (this) {
      ActivityKind.game => 'game',
      ActivityKind.music => 'music',
      ActivityKind.call => 'call',
      ActivityKind.screenShare => 'screen_share',
      ActivityKind.custom => 'custom',
    };
  }

  static ActivityKind fromJson(String value) {
    return switch (value) {
      'game' => ActivityKind.game,
      'music' => ActivityKind.music,
      'call' => ActivityKind.call,
      'screen_share' => ActivityKind.screenShare,
      _ => ActivityKind.custom,
    };
  }
}

enum ActivityVisibility {
  off,
  selfOnly,
  friendsOrSharedRooms,
}

extension ActivityVisibilityJson on ActivityVisibility {
  String get jsonName {
    return switch (this) {
      ActivityVisibility.off => 'off',
      ActivityVisibility.selfOnly => 'self_only',
      ActivityVisibility.friendsOrSharedRooms => 'shared_rooms',
    };
  }

  static ActivityVisibility fromJson(String value) {
    return switch (value) {
      'self_only' => ActivityVisibility.selfOnly,
      'shared_rooms' => ActivityVisibility.friendsOrSharedRooms,
      _ => ActivityVisibility.off,
    };
  }
}

enum ActivityControlKind {
  playPause,
  previous,
  next,
  like,
  volume,
  openExternal,
  hide,
  custom,
}

extension ActivityControlKindJson on ActivityControlKind {
  String get jsonName {
    return switch (this) {
      ActivityControlKind.playPause => 'play_pause',
      ActivityControlKind.previous => 'previous',
      ActivityControlKind.next => 'next',
      ActivityControlKind.like => 'like',
      ActivityControlKind.volume => 'volume',
      ActivityControlKind.openExternal => 'open_external',
      ActivityControlKind.hide => 'hide',
      ActivityControlKind.custom => 'custom',
    };
  }

  static ActivityControlKind fromJson(String value) {
    return switch (value) {
      'play_pause' => ActivityControlKind.playPause,
      'previous' => ActivityControlKind.previous,
      'next' => ActivityControlKind.next,
      'like' => ActivityControlKind.like,
      'volume' => ActivityControlKind.volume,
      'open_external' => ActivityControlKind.openExternal,
      'hide' => ActivityControlKind.hide,
      _ => ActivityControlKind.custom,
    };
  }
}

enum ActivityControlState {
  available,
  disabled,
  pending,
  failed,
}

extension ActivityControlStateJson on ActivityControlState {
  String get jsonName {
    return switch (this) {
      ActivityControlState.available => 'available',
      ActivityControlState.disabled => 'disabled',
      ActivityControlState.pending => 'pending',
      ActivityControlState.failed => 'failed',
    };
  }

  static ActivityControlState fromJson(String value) {
    return switch (value) {
      'available' => ActivityControlState.available,
      'pending' => ActivityControlState.pending,
      'failed' => ActivityControlState.failed,
      _ => ActivityControlState.disabled,
    };
  }
}

class ActivityControl {
  const ActivityControl({
    required this.id,
    required this.kind,
    required this.label,
    this.state = ActivityControlState.disabled,
    this.tooltip,
    this.metadata = const {},
  });

  final String id;
  final ActivityControlKind kind;
  final String label;
  final ActivityControlState state;
  final String? tooltip;
  final Map<String, Object?> metadata;

  bool get enabled => state == ActivityControlState.available;

  ActivityControl copyWith({
    String? id,
    ActivityControlKind? kind,
    String? label,
    ActivityControlState? state,
    String? tooltip,
    Map<String, Object?>? metadata,
  }) {
    return ActivityControl(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      state: state ?? this.state,
      tooltip: tooltip ?? this.tooltip,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.jsonName,
      'label': label,
      'state': state.jsonName,
      if (tooltip != null) 'tooltip': tooltip,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static ActivityControl fromJson(Map<String, Object?> json) {
    return ActivityControl(
      id: json['id'] as String? ?? '',
      kind: ActivityControlKindJson.fromJson(json['kind'] as String? ?? ''),
      label: json['label'] as String? ?? '',
      state: ActivityControlStateJson.fromJson(json['state'] as String? ?? ''),
      tooltip: json['tooltip'] as String?,
      metadata: _jsonMap(json['metadata']),
    );
  }
}

class UserActivity {
  const UserActivity({
    required this.id,
    required this.kind,
    required this.title,
    this.provider,
    this.subtitle,
    this.details,
    this.status,
    this.artworkUrl,
    this.externalUrl,
    this.startedAt,
    this.endsAt,
    this.visibility = ActivityVisibility.selfOnly,
    this.controls = const [],
    this.metadata = const {},
  });

  final String id;
  final ActivityKind kind;
  final String? provider;
  final String title;
  final String? subtitle;
  final String? details;
  final String? status;
  final String? artworkUrl;
  final String? externalUrl;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final ActivityVisibility visibility;
  final List<ActivityControl> controls;
  final Map<String, Object?> metadata;

  bool get isVisible => visibility != ActivityVisibility.off;

  UserActivity copyWith({
    String? id,
    ActivityKind? kind,
    String? provider,
    String? title,
    String? subtitle,
    String? details,
    String? status,
    String? artworkUrl,
    String? externalUrl,
    DateTime? startedAt,
    DateTime? endsAt,
    ActivityVisibility? visibility,
    List<ActivityControl>? controls,
    Map<String, Object?>? metadata,
  }) {
    return UserActivity(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      provider: provider ?? this.provider,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      details: details ?? this.details,
      status: status ?? this.status,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      externalUrl: externalUrl ?? this.externalUrl,
      startedAt: startedAt ?? this.startedAt,
      endsAt: endsAt ?? this.endsAt,
      visibility: visibility ?? this.visibility,
      controls: controls ?? this.controls,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.jsonName,
      if (provider != null) 'provider': provider,
      'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (details != null) 'details': details,
      if (status != null) 'status': status,
      if (artworkUrl != null) 'artwork_url': artworkUrl,
      if (externalUrl != null) 'external_url': externalUrl,
      if (startedAt != null) 'started_at': startedAt!.millisecondsSinceEpoch,
      if (endsAt != null) 'ends_at': endsAt!.millisecondsSinceEpoch,
      'visibility': visibility.jsonName,
      if (controls.isNotEmpty)
        'controls': controls.map((control) => control.toJson()).toList(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  static UserActivity fromJson(Map<String, Object?> json) {
    return UserActivity(
      id: json['id'] as String? ?? '',
      kind: ActivityKindJson.fromJson(json['kind'] as String? ?? ''),
      provider: json['provider'] as String?,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      details: json['details'] as String?,
      status: json['status'] as String?,
      artworkUrl: json['artwork_url'] as String?,
      externalUrl: json['external_url'] as String?,
      startedAt: _epochMillis(json['started_at']),
      endsAt: _epochMillis(json['ends_at']),
      visibility: ActivityVisibilityJson.fromJson(
        json['visibility'] as String? ?? '',
      ),
      controls: _controls(json['controls']),
      metadata: _jsonMap(json['metadata']),
    );
  }
}

DateTime? _epochMillis(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  return null;
}

List<ActivityControl> _controls(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((entry) => ActivityControl.fromJson(_jsonMap(entry)))
      .toList(growable: false);
}

Map<String, Object?> _jsonMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }

  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return const {};
}
