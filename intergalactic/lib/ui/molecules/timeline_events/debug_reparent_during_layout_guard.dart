import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Fails fast, in debug, when a `GlobalKey`-keyed subtree is reactivated while
/// the render tree is laying out.
///
/// **The class of bug this catches (BUG-291, then BUG-298).** A `GlobalKey`
/// element that is deactivated and reactivated is *reparented*. Reactivation
/// walks the subtree, and any `OverlayPortal` inside it re-attaches its deferred
/// child to the enclosing `_RenderTheater` - which calls `markNeedsLayout`. Do
/// that while a `_RenderLayoutBuilder` is mid-`performLayout` and Flutter
/// throws `A _RenderLayoutBuilder was mutated in
/// _RenderLayoutBuilder.performLayout`, the surface dies, and the failure
/// cascades into ~10,000 further exceptions that bury the cause.
///
/// It has now been found at five separate sites across four surfaces, and the
/// reported symptom - a red box and an unresponsive app - is many frames removed
/// from the mutation. The assertion here fires **at the reparent**, naming the
/// widget, instead of leaving the next investigation to reconstruct it from a
/// stack whose relevant 41 frames are collapsed.
///
/// Debug-only: `assert` bodies are stripped in release, so this costs nothing
/// in a shipped build and cannot turn a rendering glitch into a crash for users.
mixin DebugAssertNoReparentDuringLayout<T extends StatefulWidget> on State<T> {
  /// Named in the failure message. Override when the widget type alone is not
  /// enough to find the offending site.
  String get debugReparentContext => '$runtimeType';

  @override
  void activate() {
    assert(() {
      if (!_isDoingLayout) {
        return true;
      }
      // Reported rather than thrown. Throwing from activate() skips the
      // markNeedsBuild() at the end of StatefulElement.activate and aborts the
      // mount half-done, which produced 14 follow-on
      // `_elements.contains(element)` assertions that buried this message and
      // put a meaningless red box on screen. Reporting leaves the framework
      // consistent, so the first error the developer sees is this one.
      FlutterError.reportError(
        FlutterErrorDetails(
          library: 'intergalactic',
          context: ErrorDescription(
            'while reactivating a GlobalKey-keyed subtree during layout',
          ),
          exception: FlutterError.fromParts(<DiagnosticsNode>[
            ErrorSummary(
              'A GlobalKey-keyed subtree was reparented during layout: '
              '$debugReparentContext',
            ),
            ErrorDescription(
              'This widget was deactivated and reactivated while the render tree '
              'was laying out. Reactivation re-attaches any OverlayPortal in the '
              'subtree to its _RenderTheater, which mutates layout mid-flight '
              'and kills the surface.',
            ),
            ErrorHint(
              'Something above this widget replaced its element rather than '
              'updating it - a conditional wrapper appearing or disappearing, a '
              'changed GlobalKey identity, or a keyed child moved between two '
              'sliver delegates. Find that, rather than changing this widget.',
            ),
            ErrorHint(
              'See BUG-298. Set debugPrintGlobalKeyedWidgetLifecycle = true to '
              'print the key being reparented and its old and new parents.',
            ),
          ]),
        ),
      );
      return true;
    }());
    super.activate();
  }
}

/// True while the renderer is in its layout phase.
///
/// Read through `pipelineOwner` rather than a scheduler phase, because the
/// mutation this guards against is only illegal *during layout* - the same
/// widget reparenting between frames is ordinary and must not trip the
/// assertion.
bool get _isDoingLayout {
  var doingLayout = false;
  assert(() {
    doingLayout = RendererBinding.instance.rootPipelineOwner.debugDoingLayout;
    return true;
  }());
  return doingLayout;
}
