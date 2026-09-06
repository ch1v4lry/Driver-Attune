import CoreMotion
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let motionActivityManager = CMMotionActivityManager()
  private var vehicleActivityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeDrowsinessEvidenceFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    motionActivityManager.stopActivityUpdates()
    super.applicationDidEnterBackground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "driver_attune/vehicle_activity",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        self?.startVehicleActivityUpdates(result: result)
      case "stop":
        self?.motionActivityManager.stopActivityUpdates()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    vehicleActivityChannel = channel
  }

  private func startVehicleActivityUpdates(result: @escaping FlutterResult) {
    guard CMMotionActivityManager.isActivityAvailable() else {
      result(false)
      return
    }
    let authorization = CMMotionActivityManager.authorizationStatus()
    guard authorization != .denied && authorization != .restricted else {
      result(false)
      return
    }

    motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
      guard let self, let activity else {
        return
      }
      let type: String
      if activity.automotive {
        type = "inVehicle"
      } else if activity.walking || activity.running || activity.cycling {
        type = "notInVehicle"
      } else {
        return
      }
      let confidence: Int
      switch activity.confidence {
      case .high:
        confidence = 100
      case .medium:
        confidence = 60
      case .low:
        confidence = 30
      @unknown default:
        confidence = 0
      }
      self.vehicleActivityChannel?.invokeMethod(
        "activityChanged",
        arguments: ["type": type, "confidence": confidence]
      )
    }
    result(true)
  }

  /// Evidence photos are deliberately device-local and must not be copied into
  /// iCloud or Finder backups.
  private func excludeDrowsinessEvidenceFromBackup() {
    guard let supportDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return
    }

    let evidenceDirectory = supportDirectory.appendingPathComponent(
      "drowsiness_evidence",
      isDirectory: true
    )

    do {
      try FileManager.default.createDirectory(
        at: evidenceDirectory,
        withIntermediateDirectories: true
      )
      var resourceValues = URLResourceValues()
      resourceValues.isExcludedFromBackup = true
      var mutableDirectory = evidenceDirectory
      try mutableDirectory.setResourceValues(resourceValues)
    } catch {
      // Evidence capture remains best-effort. A storage setup failure must not
      // prevent the app from launching or the detector from warning the driver.
    }
  }
}
