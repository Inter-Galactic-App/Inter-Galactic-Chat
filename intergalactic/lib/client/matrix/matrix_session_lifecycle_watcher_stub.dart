class MatrixSessionLifecycleWatcher {
  static final MatrixSessionLifecycleWatcher _singleton =
      MatrixSessionLifecycleWatcher._internal();

  MatrixSessionLifecycleWatcher._internal();

  factory MatrixSessionLifecycleWatcher() {
    return _singleton;
  }

  void init() {}

  void dispose() {}
}
