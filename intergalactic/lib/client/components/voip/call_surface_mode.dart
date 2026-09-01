enum CallSurfaceMode {
  inRoom,
  poppedOut,
  pictureInPicture,
  fullscreen;

  bool get usesSecondarySurface =>
      this == CallSurfaceMode.poppedOut ||
      this == CallSurfaceMode.pictureInPicture;

  bool get showsRoomPlaceholder => usesSecondarySurface;
}
