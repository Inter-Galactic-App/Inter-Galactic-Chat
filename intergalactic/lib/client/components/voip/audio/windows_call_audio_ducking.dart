/// Windows call-audio stream attenuation ("ducking") control.
///
/// Windows lowers the volume of other applications while a communications
/// audio stream is active. Inter Galactic's call audio runs through the
/// Windows ADM inside the packaged `libwebrtc.dll`, which opens its render
/// stream with the communications category and device role, so calls duck
/// whatever else the user is listening to.
///
/// The patched `libwebrtc.dll` exports
/// `IntergalacticSetCallAudioDuckingEnabled`, which forwards to
/// `IAudioClientDuckingControl::SetDuckingOptionsForCurrentStream()` on the
/// render stream. This only tells Windows not to duck on Inter Galactic's
/// behalf; it cannot re-enable ducking that the user disabled in
/// `mmsys.cpl > Communications`, and it changes no system setting.
///
/// Degrades to a no-op off Windows, and on Windows builds running an older
/// `libwebrtc.zip` artifact that does not export the symbol.
library;

export 'windows_call_audio_ducking_stub.dart'
    if (dart.library.ffi) 'windows_call_audio_ducking_io.dart';
