import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:window_manager/window_manager.dart';

/// Behaviour-neutral diagnostics for BUG-290.
///
/// Flutter mutes every [Ticker] while the app lifecycle is not
/// [AppLifecycleState.resumed]. That silently kills wheel scrolling and every
/// implicit animation app-wide while clicks and text entry keep working, and
/// it logs nothing, because the work is skipped by design rather than failing.
///
/// The reported fault matches that signature exactly, so this records every
/// lifecycle transition and cross-checks it against the native window's own
/// focus state. If the OS says the window is focused while Flutter still
/// believes the app is inactive, that desync is the bug and it is written to
/// the log as a WARN instead of having to be inferred from behaviour.
///
/// This class only observes and logs. It must not change app behaviour.
class LifecycleDiagnostics extends WindowListener with WidgetsBindingObserver {
  LifecycleDiagnostics._();

  static final LifecycleDiagnostics instance = LifecycleDiagnostics._();

  static const String _source = 'lifecycle-diagnostics';

  /// How often to re-check a non-resumed state. Low frequency on purpose: this
  /// only emits while the app is already in the suspect state.
  static const Duration _stuckPollInterval = Duration(seconds: 30);

  /// How long the app may sit in a non-resumed state before it is treated as
  /// wedged rather than legitimately backgrounded.
  static const Duration _stuckThreshold = Duration(seconds: 20);

  bool _isInit = false;
  AppLifecycleState? _lastState;
  DateTime? _lastStateChangeAt;
  bool? _windowFocused;
  Timer? _stuckTimer;
  int _stuckReports = 0;

  void init() {
    if (_isInit) {
      return;
    }
    _isInit = true;

    _lastState = WidgetsBinding.instance.lifecycleState;
    _lastStateChangeAt = DateTime.now();

    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);

    Log.i(
      'app_lifecycle event=diagnostics_started '
      'initial_state=${_stateName(_lastState)} '
      'tickers_muted=${_tickersMuted(_lastState)}',
      category: LogCategory.app,
      source: _source,
    );

    _stuckTimer = Timer.periodic(
      _stuckPollInterval,
      (_) => unawaited(_reportIfStuck()),
    );
  }

  void dispose() {
    if (!_isInit) {
      return;
    }
    _isInit = false;

    _stuckTimer?.cancel();
    _stuckTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final now = DateTime.now();
    final previous = _lastState;
    final heldMs = _lastStateChangeAt == null
        ? -1
        : now.difference(_lastStateChangeAt!).inMilliseconds;

    _lastState = state;
    _lastStateChangeAt = now;
    _stuckReports = 0;

    Log.i(
      'app_lifecycle event=state_changed '
      'from=${_stateName(previous)} to=${_stateName(state)} '
      'held_ms=$heldMs '
      'window_focused=${_windowFocused ?? 'unknown'} '
      'tickers_muted=${_tickersMuted(state)}',
      category: LogCategory.app,
      source: _source,
    );

    super.didChangeAppLifecycleState(state);
  }

  @override
  void onWindowFocus() {
    _recordWindowFocus(true, 'focus');
    super.onWindowFocus();
  }

  @override
  void onWindowBlur() {
    _recordWindowFocus(false, 'blur');
    super.onWindowBlur();
  }

  @override
  void onWindowRestore() {
    // Restore is de-minimization, NOT focus. window_manager exposes
    // onWindowFocus as a separate event precisely because a window can be
    // restored without becoming the active window. This previously defaulted to
    // `true` when focus was unknown, which is the one value that can fabricate a
    // focus_state_desync warning - the very signal this diagnostic exists to
    // report. Ask the OS instead, and stay unknown if it will not say.
    unawaited(_recordRestoreFocus());
    super.onWindowRestore();
  }

  Future<void> _recordRestoreFocus() async {
    bool? focused;
    try {
      focused = await windowManager.isFocused();
    } catch (_) {
      focused = null;
    }
    // Same disposal race as _reportIfStuck: dispose() cannot cancel a call
    // already suspended on this await.
    if (!_isInit) {
      return;
    }
    _recordWindowFocus(focused, 'restore');
  }

  @override
  void onWindowMinimize() {
    _recordWindowFocus(false, 'minimize');
    super.onWindowMinimize();
  }

  /// [focused] is nullable because "the OS would not tell us" is a distinct
  /// state from "not focused", and only the desync check below may collapse it.
  void _recordWindowFocus(bool? focused, String event) {
    _windowFocused = focused;

    Log.i(
      'app_lifecycle event=window_$event '
      'window_focused=${focused ?? 'unknown'} '
      'lifecycle_state=${_stateName(_lastState)} '
      'tickers_muted=${_tickersMuted(_lastState)}',
      category: LogCategory.app,
      source: _source,
    );

    // The desync this bug is looking for: the OS handed the window focus back
    // but Flutter never returned to resumed, so tickers stay muted.
    // Only a CONFIRMED focus counts. An unknown focus state must never raise
    // this, or the diagnostic reports a desync it never actually observed.
    if (focused == true && _tickersMuted(_lastState)) {
      Log.w(
        'app_lifecycle event=focus_state_desync result=suspect '
        'window_focused=true lifecycle_state=${_stateName(_lastState)} '
        'reason=window_focused_while_tickers_muted '
        'expect=scroll_and_animations_dead',
        category: LogCategory.app,
        source: _source,
      );
    }
  }

  Future<void> _reportIfStuck() async {
    final state = _lastState;
    if (!_tickersMuted(state)) {
      _stuckReports = 0;
      return;
    }

    final since = _lastStateChangeAt;
    if (since == null) {
      return;
    }

    final heldMs = DateTime.now().difference(since).inMilliseconds;
    if (heldMs < _stuckThreshold.inMilliseconds) {
      return;
    }

    bool? nativeFocused;
    try {
      nativeFocused = await windowManager.isFocused();
    } catch (_) {
      nativeFocused = null;
    }

    // dispose() cancels _stuckTimer, but that only stops FUTURE firings - a call
    // already suspended on the await above still resumes. Without this re-check
    // a diagnostic line is emitted after the object considers itself disposed.
    if (!_isInit) {
      return;
    }

    _stuckReports += 1;

    Log.w(
      'app_lifecycle event=non_resumed_persisting '
      'lifecycle_state=${_stateName(state)} held_ms=$heldMs '
      'native_focused=${nativeFocused ?? 'unknown'} '
      'last_window_event_focused=${_windowFocused ?? 'unknown'} '
      'tickers_muted=true report=$_stuckReports '
      'impact=wheel_scroll_and_implicit_animations_disabled',
      category: LogCategory.app,
      source: _source,
    );
  }

  static bool _tickersMuted(AppLifecycleState? state) =>
      state != null && state != AppLifecycleState.resumed;

  static String _stateName(AppLifecycleState? state) =>
      state?.name ?? 'unknown';
}
