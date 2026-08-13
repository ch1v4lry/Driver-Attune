/// Show or don't show the on-screen tuning aids (the detector readout overlaid
/// on the camera and the "Simulate moving" override).
///
/// Off unless explicitly switched on at build time, so the App Store builds
/// don't show it, since App Review considers the leftover test controls as
/// unfinished work.
///
/// Deliberately --dart-define instead of kDebugMode. These are used while
/// driving, which means release builds on a real phone, where kDebugMode is
/// already false. Turn them on with:
///
/// flutter run --release --dart-define=DRIVER_FOCUS_DEV_TOOLS=true
const bool kShowDevTools = bool.fromEnvironment('DRIVER_FOCUS_DEV_TOOLS');

/// Starts the app with vehicle movement simulated.
///
/// Lets the full detection and driving-record pipeline be tested while
/// stationary. Off by default and must never be enabled for an App Store build.
///
/// flutter run --release --dart-define=DRIVER_FOCUS_SIMULATE_MOVING=true
const bool kSimulateMoving =
    bool.fromEnvironment('DRIVER_FOCUS_SIMULATE_MOVING');
