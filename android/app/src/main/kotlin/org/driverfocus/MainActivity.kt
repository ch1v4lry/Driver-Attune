package org.driverfocus

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Display
import android.view.Surface
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.DetectedActivity
import com.google.android.gms.tasks.Tasks
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), DisplayManager.DisplayListener {
    private lateinit var rotationChannel: MethodChannel
    private lateinit var vehicleActivityChannel: MethodChannel
    private lateinit var displayManager: DisplayManager
    private var pendingActivityStartResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        rotationChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "driver_focus/display_rotation",
            )
        rotationChannel.setMethodCallHandler { call, result ->
            if (call.method == "getOrientation") {
                result.success(currentOrientation())
            } else {
                result.notImplemented()
            }
        }
        vehicleActivityChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "driver_focus/vehicle_activity",
            )
        vehicleActivityChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> startVehicleActivityUpdates(result)
                "stop" -> stopVehicleActivityUpdates(result)
                else -> result.notImplemented()
            }
        }
        VehicleActivityReceiver.onActivity = { inVehicle, confidence ->
            vehicleActivityChannel.invokeMethod(
                "activityChanged",
                mapOf(
                    "type" to if (inVehicle) "inVehicle" else "notInVehicle",
                    "confidence" to confidence,
                ),
            )
        }
        displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        VehicleActivityReceiver.onActivity = null
        vehicleActivityChannel.setMethodCallHandler(null)
        rotationChannel.setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != ACTIVITY_PERMISSION_REQUEST_CODE) {
            return
        }
        val result = pendingActivityStartResult
        pendingActivityStartResult = null
        if (result == null) {
            return
        }
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            registerVehicleActivityUpdates(result)
        } else {
            result.success(false)
        }
    }

    override fun onStart() {
        super.onStart()
        displayManager.registerDisplayListener(this, null)
        window.decorView.post { sendOrientation() }
    }

    override fun onStop() {
        displayManager.unregisterDisplayListener(this)
        removeVehicleActivityUpdates()
        super.onStop()
    }

    override fun onDisplayAdded(displayId: Int) = Unit

    override fun onDisplayRemoved(displayId: Int) = Unit

    override fun onDisplayChanged(displayId: Int) {
        if (displayId == currentDisplayId()) {
            sendOrientation()
        }
    }

    private fun sendOrientation() {
        if (::rotationChannel.isInitialized) {
            rotationChannel.invokeMethod("orientationChanged", currentOrientation())
        }
    }

    private fun currentOrientation(): String {
        val rotation = currentRotation()
        return when (resources.configuration.orientation) {
            Configuration.ORIENTATION_LANDSCAPE ->
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                    "landscapeLeft"
                } else {
                    "landscapeRight"
                }
            Configuration.ORIENTATION_PORTRAIT ->
                if (rotation == Surface.ROTATION_0 || rotation == Surface.ROTATION_90) {
                    "portraitUp"
                } else {
                    "portraitDown"
                }
            else -> "portraitUp"
        }
    }

    private fun currentRotation(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }

    private fun currentDisplayId(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.displayId ?: Display.DEFAULT_DISPLAY
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.displayId
        }

    private fun startVehicleActivityUpdates(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACTIVITY_RECOGNITION,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            pendingActivityStartResult?.success(false)
            pendingActivityStartResult = result
            requestPermissions(
                arrayOf(Manifest.permission.ACTIVITY_RECOGNITION),
                ACTIVITY_PERMISSION_REQUEST_CODE,
            )
            return
        }
        registerVehicleActivityUpdates(result)
    }

    private fun registerVehicleActivityUpdates(result: MethodChannel.Result) {
        val transitions =
            listOf(
                ActivityTransition.Builder()
                    .setActivityType(DetectedActivity.IN_VEHICLE)
                    .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                    .build(),
                ActivityTransition.Builder()
                    .setActivityType(DetectedActivity.IN_VEHICLE)
                    .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                    .build(),
            )
        try {
            val client = ActivityRecognition.getClient(this)
            Tasks.whenAll(
                client.requestActivityTransitionUpdates(
                    ActivityTransitionRequest(transitions),
                    vehicleActivityPendingIntent(),
                ),
                client.requestActivityUpdates(
                    10_000,
                    vehicleActivityPendingIntent(),
                ),
            )
                .addOnSuccessListener { result.success(true) }
                .addOnFailureListener { result.success(false) }
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    private fun stopVehicleActivityUpdates(result: MethodChannel.Result) {
        pendingActivityStartResult?.success(false)
        pendingActivityStartResult = null
        try {
            val client = ActivityRecognition.getClient(this)
            Tasks.whenAll(
                client.removeActivityTransitionUpdates(
                    vehicleActivityPendingIntent(),
                ),
                client.removeActivityUpdates(vehicleActivityPendingIntent()),
            )
                .addOnCompleteListener { result.success(null) }
        } catch (_: SecurityException) {
            result.success(null)
        }
    }

    private fun removeVehicleActivityUpdates() {
        try {
            val client = ActivityRecognition.getClient(this)
            client.removeActivityTransitionUpdates(vehicleActivityPendingIntent())
            client.removeActivityUpdates(vehicleActivityPendingIntent())
        } catch (_: SecurityException) {
            // The optional permission may have been revoked while backgrounded.
        }
    }

    private fun vehicleActivityPendingIntent(): PendingIntent {
        val intent = Intent(this, VehicleActivityReceiver::class.java)
        return PendingIntent.getBroadcast(
            this,
            2048,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
    }

    companion object {
        private const val ACTIVITY_PERMISSION_REQUEST_CODE = 7401
    }
}
