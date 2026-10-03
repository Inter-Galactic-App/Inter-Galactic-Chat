# Windows receiver texture lifetime

## Incident

The owner was publishing two desktop windows, viewing a focused mobile screen
share, and the mobile participant hung up without stopping the share. The
Windows desktop process exited at 15:48:00 UTC. The prior-run log shows the
remote microphone and screen-share publications removed at 15:47:59 UTC,
followed by a stream-view rebuild. The next-launch shared-audio marker names
an active action but does not establish shared audio as the cause.

The Windows Application Error records `0xc0000005` in `flutter_windows.dll`.
The matching local dump resolves the raster thread through
`ExternalTexturePixelBuffer::CopyPixelBuffer` and the Flutter release callback;
the indirect callback target is `0xdddddddddddddddd`, a freed-memory pattern.
This is distinct from the earlier `libwebrtc.dll` encoder-factory crash.

## Change

`install_patched_libwebrtc.ps1` now patches `FlutterVideoRenderer::CopyPixelBuffer`
to allocate a pixel-buffer lease per upload. The lease owns the converted
pixels and the `FlutterDesktopPixelBuffer` struct until Flutter invokes its
`release_callback`, including if the track or renderer ends meanwhile. The
patch marker was updated so the installer upgrades a package with the older
latest-frame patch rather than treating it as complete. Frame conversion still
occurs outside the renderer frame mutex.

This change does not modify call-view focus selection, mobile publication
teardown, codec policy, or shared-audio capture. Native rebuild and live-call
verification remain separate from the source patch.
