class LifecycleManager {
  /// Set to true when intentionally opening external intents like System File Picker or Share Sheet.
  /// This prevents the app from auto-locking prematurely.
  static bool isIntentionalLeave = false;
}
