import 'dart:convert';

/// Sensitive host-private metadata. Never attach, print, or log this record.
/// This codec does not perform I/O; native persistence must confine its location,
/// verify protection, and atomically replace under one gate.
enum DriftQuarantinePhase {
  unresolved,
  cleanupPending,
  resolved,
  safetyBlocked,
}

enum DriftQuarantineDisposition { none, byteEquivalent, expiredOwnerPolicy }

/// Historical provenance only; neither value recreates live clock trust.
enum DriftQuarantineDetectionClock { corroborated, observed }

/// Historical fallback mapping, never a trusted elapsed-time attestation.
enum DriftQuarantineFallbackOrigin {
  introductionRoster,
  newCreation,
  lateObserved,
}

class DriftQuarantineFallbackState {
  DriftQuarantineFallbackState({
    required this.caseId,
    required this.artifactGeneration,
    required this.nativeIdentity,
    required this.accountIdentity,
    required this.accountEntry,
    required this.introductionIdentity,
    required this.introductionUtc,
    required this.startUtc,
    required this.origin,
  }) {
    if (!_opaqueValid(caseId) ||
        !_opaqueValid(artifactGeneration) ||
        !_entryValid(accountEntry) ||
        !_opaqueValid(accountIdentity) ||
        !_opaqueValid(introductionIdentity) ||
        !_clockTimeValid(introductionUtc) ||
        !_clockTimeValid(startUtc) ||
        (origin == DriftQuarantineFallbackOrigin.introductionRoster &&
            startUtc != introductionUtc) ||
        (origin == DriftQuarantineFallbackOrigin.newCreation &&
            startUtc.isBefore(introductionUtc))) {
      _invalid();
    }
  }

  final String accountIdentity;
  final String accountEntry;
  final String caseId;
  final String artifactGeneration;
  final DriftQuarantineNativeIdentity nativeIdentity;
  final String introductionIdentity;
  final DateTime introductionUtc;
  final DateTime startUtc;
  final DriftQuarantineFallbackOrigin origin;

  Map<String, Object> _json() => {
    'case_id': caseId,
    'artifact_generation': artifactGeneration,
    'native_identity': nativeIdentity._json(),
    'account_identity': accountIdentity,
    'account_entry': accountEntry,
    'introduction_identity': introductionIdentity,
    'introduction_ms': introductionUtc.millisecondsSinceEpoch,
    'start_ms': startUtc.millisecondsSinceEpoch,
    'origin': origin.name,
  };

  static DriftQuarantineFallbackState _decode(Object? raw) {
    if (raw is! Map<String, dynamic>) _invalid();
    String string(String key) {
      final value = raw[key];
      if (value is! String) _invalid();
      return value;
    }

    DateTime time(String key) {
      final value = raw[key];
      if (value is! int ||
          value < 0 ||
          value > driftQuarantineMaxUtcMilliseconds)
        _invalid();
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }

    return DriftQuarantineFallbackState(
      caseId: string('case_id'),
      artifactGeneration: string('artifact_generation'),
      nativeIdentity: DriftQuarantineNativeIdentity._decode(
        raw['native_identity'],
      ),
      accountIdentity: string('account_identity'),
      accountEntry: string('account_entry'),
      introductionIdentity: string('introduction_identity'),
      introductionUtc: time('introduction_ms'),
      startUtc: time('start_ms'),
      origin: DriftQuarantineFallbackOrigin.values.byName(string('origin')),
    );
  }

  bool matches(DriftQuarantineFallbackState other) =>
      caseId == other.caseId &&
      artifactGeneration == other.artifactGeneration &&
      nativeIdentity == other.nativeIdentity &&
      accountEntry == other.accountEntry &&
      accountIdentity == other.accountIdentity &&
      introductionIdentity == other.introductionIdentity &&
      introductionUtc == other.introductionUtc &&
      startUtc == other.startUtc &&
      origin == other.origin;
}

const driftQuarantineMaxUtcMilliseconds = 8640000000000000;

bool _clockTimeValid(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.millisecondsSinceEpoch <= driftQuarantineMaxUtcMilliseconds &&
    value.microsecondsSinceEpoch % 1000 == 0;

class DriftQuarantineClockState {
  DriftQuarantineClockState({
    required this.detectionClock,
    required this.observedHighWaterUtc,
    this.lastTrustedObservedUtc,
  }) {
    if (!_clockTimeValid(observedHighWaterUtc) ||
        (lastTrustedObservedUtc != null &&
            !_clockTimeValid(lastTrustedObservedUtc!))) {
      _invalid();
    }
  }

  final DriftQuarantineDetectionClock detectionClock;
  final DateTime observedHighWaterUtc;
  final DateTime? lastTrustedObservedUtc;

  DriftQuarantineClockState observeDeviceUtc(DateTime observedUtc) {
    if (!_clockTimeValid(observedUtc)) _invalid();
    return DriftQuarantineClockState(
      detectionClock: detectionClock,
      observedHighWaterUtc: observedUtc.isAfter(observedHighWaterUtc)
          ? observedUtc
          : observedHighWaterUtc,
      lastTrustedObservedUtc: lastTrustedObservedUtc,
    );
  }
}

class DriftQuarantineRecordException implements Exception {
  const DriftQuarantineRecordException();

  @override
  String toString() => 'DriftQuarantineRecordException';
}

Never _invalid() => throw const DriftQuarantineRecordException();

bool _entryValid(String value) =>
    value.isNotEmpty &&
    value.length <= 255 &&
    value != '.' &&
    value != '..' &&
    !RegExp(r'[/\\\x00-\x1f\x7f]').hasMatch(value);

bool _opaqueValid(String value) => RegExp(r'^[0-9a-f]{32}$').hasMatch(value);

/// Sensitive native identity metadata, not a hash or deletion capability.
/// A coordinator must obtain/revalidate it from confined native descriptors.
/// The codec requires native VM integer precision and a signed 64-bit inode.
/// Browser numeric metadata must not be used as native identity evidence.
class DriftQuarantineFileIdentity {
  DriftQuarantineFileIdentity({
    required this.device,
    required this.inode,
    required this.generation,
    required this.birthSeconds,
    required this.birthNanoseconds,
  }) {
    if (device < -0x80000000 ||
        device > 0x7fffffff ||
        inode <= 0 ||
        inode > 0x7fffffffffffffff ||
        generation < 0 ||
        generation > 0xffffffff ||
        birthSeconds < 0 ||
        birthNanoseconds < 0 ||
        birthNanoseconds >= 1000000000) {
      _invalid();
    }
  }

  final int device;
  final int inode;
  final int generation;
  final int birthSeconds;
  final int birthNanoseconds;

  Map<String, Object> _json() => {
    'device': device,
    'inode': inode,
    'generation': generation,
    'birth_seconds': birthSeconds,
    'birth_nanoseconds': birthNanoseconds,
  };

  static DriftQuarantineFileIdentity _decode(Object? raw) {
    if (raw is! Map<String, dynamic>) _invalid();
    int number(String key) {
      final value = raw[key];
      if (value is! int) _invalid();
      return value;
    }

    return DriftQuarantineFileIdentity(
      device: number('device'),
      inode: number('inode'),
      generation: number('generation'),
      birthSeconds: number('birth_seconds'),
      birthNanoseconds: number('birth_nanoseconds'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DriftQuarantineFileIdentity &&
      device == other.device &&
      inode == other.inode &&
      generation == other.generation &&
      birthSeconds == other.birthSeconds &&
      birthNanoseconds == other.birthNanoseconds;

  @override
  int get hashCode =>
      Object.hash(device, inode, generation, birthSeconds, birthNanoseconds);
}

class DriftQuarantineNativeIdentity {
  DriftQuarantineNativeIdentity({
    required this.directory,
    required this.database,
  }) {
    if (directory == database) _invalid();
  }
  final DriftQuarantineFileIdentity directory;
  final DriftQuarantineFileIdentity database;
  Map<String, Object> _json() => {
    'directory': directory._json(),
    'database': database._json(),
  };

  static DriftQuarantineNativeIdentity _decode(Object? raw) {
    if (raw is! Map<String, dynamic>) _invalid();
    return DriftQuarantineNativeIdentity(
      directory: DriftQuarantineFileIdentity._decode(raw['directory']),
      database: DriftQuarantineFileIdentity._decode(raw['database']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DriftQuarantineNativeIdentity &&
      directory == other.directory &&
      database == other.database;
  @override
  int get hashCode => Object.hash(directory, database);
}

class DriftQuarantineCase {
  DriftQuarantineCase({
    required this.caseId,
    required this.artifactGeneration,
    required this.relativeEntry,
    required this.firstDetectedUtc,
    required this.lastObservedUtc,
    this.activeAccountEntry,
    this.nativeIdentity,
    this.clockState,
    this.fallbackState,
    this.legacyAgeUnknown = false,
    this.firstNoticeRecorded = false,
    this.daySevenReminderRecorded = false,
    this.phase = DriftQuarantinePhase.unresolved,
    this.disposition = DriftQuarantineDisposition.none,
  }) {
    if (!_opaqueValid(caseId) ||
        !_opaqueValid(artifactGeneration) ||
        !_entryValid(relativeEntry) ||
        (activeAccountEntry != null && !_entryValid(activeAccountEntry!)) ||
        !firstDetectedUtc.isUtc ||
        !lastObservedUtc.isUtc ||
        firstDetectedUtc.millisecondsSinceEpoch < 0 ||
        lastObservedUtc.isBefore(firstDetectedUtc) ||
        (daySevenReminderRecorded && !firstNoticeRecorded) ||
        ((phase == DriftQuarantinePhase.cleanupPending ||
                phase == DriftQuarantinePhase.resolved) &&
            disposition == DriftQuarantineDisposition.none)) {
      _invalid();
    }
    final clock = clockState;
    if (fallbackState != null &&
        (nativeIdentity == null ||
            activeAccountEntry == null ||
            clock == null ||
            fallbackState!.caseId != caseId ||
            fallbackState!.artifactGeneration != artifactGeneration ||
            fallbackState!.nativeIdentity != nativeIdentity ||
            fallbackState!.accountEntry != activeAccountEntry)) {
      _invalid();
    }
    if (clock != null &&
        (!_clockTimeValid(firstDetectedUtc) ||
            !_clockTimeValid(lastObservedUtc) ||
            clock.observedHighWaterUtc != lastObservedUtc ||
            (clock.lastTrustedObservedUtc != null &&
                clock.lastTrustedObservedUtc!.isBefore(firstDetectedUtc)))) {
      _invalid();
    }
  }

  final String caseId;
  // Opaque identity token, NOT a hash, filename, account id or inode proof.
  // Native code must establish/revalidate artifact identity separately.
  final String artifactGeneration;
  final String relativeEntry;
  final String? activeAccountEntry;
  // null means historical identity is unknown: never retrofit expiry proof.
  final DriftQuarantineNativeIdentity? nativeIdentity;
  final DriftQuarantineClockState? clockState;
  final DriftQuarantineFallbackState? fallbackState;
  final DateTime firstDetectedUtc;
  final DateTime lastObservedUtc;
  final bool legacyAgeUnknown;
  final bool firstNoticeRecorded;
  final bool daySevenReminderRecorded;
  final DriftQuarantinePhase phase;
  final DriftQuarantineDisposition disposition;

  /// Update observation without ever changing case identity or detection age.
  /// No transition grants deletion: the coordinator must re-prove safety.
  DriftQuarantineCase observe({
    required DateTime nowUtc,
    bool recordFirstNotice = false,
    bool recordDaySevenReminder = false,
    DriftQuarantinePhase? phase,
    DriftQuarantineDisposition? disposition,
  }) {
    if (!nowUtc.isUtc || nowUtc.isBefore(lastObservedUtc)) _invalid();
    if (this.phase == DriftQuarantinePhase.resolved &&
        phase != null &&
        phase != DriftQuarantinePhase.resolved) {
      _invalid();
    }
    return DriftQuarantineCase(
      caseId: caseId,
      artifactGeneration: artifactGeneration,
      relativeEntry: relativeEntry,
      activeAccountEntry: activeAccountEntry,
      nativeIdentity: nativeIdentity,
      clockState: clockState?.observeDeviceUtc(nowUtc),
      fallbackState: fallbackState,
      firstDetectedUtc: firstDetectedUtc,
      lastObservedUtc: nowUtc,
      legacyAgeUnknown: legacyAgeUnknown,
      firstNoticeRecorded: firstNoticeRecorded || recordFirstNotice,
      daySevenReminderRecorded:
          daySevenReminderRecorded || recordDaySevenReminder,
      phase: phase ?? this.phase,
      disposition: disposition ?? this.disposition,
    );
  }

  /// Pure candidate only. Rollback never renews the anchor or lowers high-water.
  /// The caller must commit these exact bytes with CAS before claiming durability.
  DriftQuarantineCase observeDeviceClock(DateTime observedUtc) {
    final clock = clockState;
    if (clock == null) _invalid();
    return _withClock(clock.observeDeviceUtc(observedUtc));
  }

  DriftQuarantineCase _withClock(DriftQuarantineClockState clock) =>
      DriftQuarantineCase(
        caseId: caseId,
        artifactGeneration: artifactGeneration,
        relativeEntry: relativeEntry,
        activeAccountEntry: activeAccountEntry,
        nativeIdentity: nativeIdentity,
        firstDetectedUtc: firstDetectedUtc,
        lastObservedUtc: clock.observedHighWaterUtc,
        clockState: clock,
        fallbackState: fallbackState,
        legacyAgeUnknown: legacyAgeUnknown,
        firstNoticeRecorded: firstNoticeRecorded,
        daySevenReminderRecorded: daySevenReminderRecorded,
        phase: phase,
        disposition: disposition,
      );

  /// Pure immutable candidate only: no store write, history or identity proof.
  DriftQuarantineCase fallbackCandidate(DriftQuarantineFallbackState state) {
    if (fallbackState != null && !fallbackState!.matches(state)) _invalid();
    return DriftQuarantineCase(
      caseId: caseId,
      artifactGeneration: artifactGeneration,
      relativeEntry: relativeEntry,
      activeAccountEntry: activeAccountEntry,
      nativeIdentity: nativeIdentity,
      clockState: clockState,
      fallbackState: fallbackState ?? state,
      firstDetectedUtc: firstDetectedUtc,
      lastObservedUtc: lastObservedUtc,
      legacyAgeUnknown: legacyAgeUnknown,
      firstNoticeRecorded: firstNoticeRecorded,
      daySevenReminderRecorded: daySevenReminderRecorded,
      phase: phase,
      disposition: disposition,
    );
  }

  Map<String, Object?> _json(int version) => {
    'case_id': caseId,
    'artifact_generation': artifactGeneration,
    'relative_entry': relativeEntry,
    'active_account_entry': activeAccountEntry,
    'first_detected_ms': firstDetectedUtc.millisecondsSinceEpoch,
    'last_observed_ms': lastObservedUtc.millisecondsSinceEpoch,
    'legacy_age_unknown': legacyAgeUnknown,
    'first_notice_recorded': firstNoticeRecorded,
    'day_seven_reminder_recorded': daySevenReminderRecorded,
    'phase': phase.name,
    'disposition': disposition.name,
    if (version >= 2) 'native_identity': nativeIdentity?._json(),
    if (version >= 3) ...{
      'detection_clock': clockState!.detectionClock.name,
      'observed_high_water_ms':
          clockState!.observedHighWaterUtc.millisecondsSinceEpoch,
      'last_trusted_observed_ms':
          clockState!.lastTrustedObservedUtc?.millisecondsSinceEpoch,
    },
    if (version == 4) 'fallback_start': fallbackState?._json(),
  };
}

class DriftQuarantineRecord {
  DriftQuarantineRecord(Iterable<DriftQuarantineCase> cases, {this.version = 2})
    : cases = List.unmodifiable(cases) {
    if (version < 1 || version > 4 || this.cases.length > maxCases) _invalid();
    final ids = <String>{};
    final generations = <String>{};
    final entries = <String>{};
    final directories = <DriftQuarantineFileIdentity>{};
    final databases = <DriftQuarantineFileIdentity>{};
    for (final item in this.cases) {
      if ((version >= 3) != (item.clockState != null) ||
          (version < 4 && item.fallbackState != null) ||
          (version == 1 && item.nativeIdentity != null)) {
        _invalid();
      }
      if (!ids.add(item.caseId) ||
          !generations.add(item.artifactGeneration) ||
          !entries.add(item.relativeEntry)) {
        _invalid();
      }
      final native = item.nativeIdentity;
      if (native != null &&
          (!directories.add(native.directory) ||
              !databases.add(native.database)))
        _invalid();
    }
  }

  static const maxBytes = 65536;
  static const maxCases = 64;
  final List<DriftQuarantineCase> cases;
  final int version;

  /// Reading/encoding historical records never performs an implicit upgrade.
  List<int> encode() => _encodeVersion(version);

  /// Explicit pure upgrade candidate, not a write or an anchor attestation.
  /// Original raw committed bytes must remain the store's CAS expected value.
  DriftQuarantineRecord version3Candidate() => version >= 3
      ? this
      : DriftQuarantineRecord(
          cases.map(
            (item) => item._withClock(
              DriftQuarantineClockState(
                detectionClock: DriftQuarantineDetectionClock.observed,
                observedHighWaterUtc: item.lastObservedUtc,
              ),
            ),
          ),
          version: 3,
        );

  /// Schema-only candidate. Null fallback means unknown, not no prior anchor.
  DriftQuarantineRecord version4Candidate() => version == 4
      ? this
      : DriftQuarantineRecord(version3Candidate().cases, version: 4);

  List<int> _encodeVersion(int version) {
    final bytes = utf8.encode(
      jsonEncode({
        'version': version,
        'cases': cases.map((item) => item._json(version)).toList(),
      }),
    );
    if (bytes.length > maxBytes) _invalid();
    return bytes;
  }

  /// Rejects unknown fields/versions, duplicates, noncanonical bytes, invalid
  /// UTF-8, oversized input and malformed state. No parse error contains data.
  /// Strict canonical encoding makes jsonDecode's duplicate-key collapse fail
  /// closed rather than accepting a second first-detection/source value.
  static DriftQuarantineRecord decode(List<int> bytes) {
    if (bytes.length > maxBytes) _invalid();
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          (decoded['version'] != 1 &&
              decoded['version'] != 2 &&
              decoded['version'] != 3 &&
              decoded['version'] != 4) ||
          decoded['version'] is! int ||
          decoded['cases'] is! List) {
        _invalid();
      }
      final values = decoded['cases'] as List;
      final version = decoded['version'] as int;
      if (values.length > maxCases) _invalid();
      final cases = values.map((raw) {
        if (raw is! Map<String, dynamic>) _invalid();
        DateTime time(String key) {
          final value = raw[key];
          if (value is! int ||
              value < 0 ||
              value > driftQuarantineMaxUtcMilliseconds)
            _invalid();
          return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        }

        bool flag(String key) {
          final value = raw[key];
          if (value is! bool) _invalid();
          return value;
        }

        String string(String key) {
          final value = raw[key];
          if (value is! String) _invalid();
          return value;
        }

        final active = raw['active_account_entry'];
        if (active != null && active is! String) _invalid();
        return DriftQuarantineCase(
          caseId: string('case_id'),
          artifactGeneration: string('artifact_generation'),
          relativeEntry: string('relative_entry'),
          activeAccountEntry: active as String?,
          nativeIdentity: version == 1 || raw['native_identity'] == null
              ? null
              : DriftQuarantineNativeIdentity._decode(raw['native_identity']),
          clockState: version >= 3
              ? DriftQuarantineClockState(
                  detectionClock: DriftQuarantineDetectionClock.values.byName(
                    string('detection_clock'),
                  ),
                  observedHighWaterUtc: time('observed_high_water_ms'),
                  lastTrustedObservedUtc:
                      raw['last_trusted_observed_ms'] == null
                      ? null
                      : time('last_trusted_observed_ms'),
                )
              : null,
          fallbackState: version == 4 && raw['fallback_start'] != null
              ? DriftQuarantineFallbackState._decode(raw['fallback_start'])
              : null,
          firstDetectedUtc: time('first_detected_ms'),
          lastObservedUtc: time('last_observed_ms'),
          legacyAgeUnknown: flag('legacy_age_unknown'),
          firstNoticeRecorded: flag('first_notice_recorded'),
          daySevenReminderRecorded: flag('day_seven_reminder_recorded'),
          phase: DriftQuarantinePhase.values.byName(string('phase')),
          disposition: DriftQuarantineDisposition.values.byName(
            string('disposition'),
          ),
        );
      });
      final record = DriftQuarantineRecord(cases, version: version);
      if (utf8.decode(record._encodeVersion(version)) != text) _invalid();
      return record;
    } catch (_) {
      _invalid();
    }
  }
}
