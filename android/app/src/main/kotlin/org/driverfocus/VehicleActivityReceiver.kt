package org.driverfocus

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity

class VehicleActivityReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent,
    ) {
        if (ActivityRecognitionResult.hasResult(intent)) {
            val activity =
                ActivityRecognitionResult.extractResult(intent)
                    ?.mostProbableActivity
            if (activity != null) {
                when (activity.type) {
                    DetectedActivity.IN_VEHICLE ->
                        onActivity?.invoke(true, activity.confidence)
                    DetectedActivity.ON_FOOT,
                    DetectedActivity.WALKING,
                    DetectedActivity.RUNNING,
                    DetectedActivity.ON_BICYCLE,
                    -> onActivity?.invoke(false, activity.confidence)
                }
            }
        }

        if (ActivityTransitionResult.hasResult(intent)) {
            val result = ActivityTransitionResult.extractResult(intent) ?: return
            for (event in result.transitionEvents) {
                if (event.activityType != DetectedActivity.IN_VEHICLE) {
                    continue
                }
                when (event.transitionType) {
                    ActivityTransition.ACTIVITY_TRANSITION_ENTER ->
                        onActivity?.invoke(true, 100)
                    ActivityTransition.ACTIVITY_TRANSITION_EXIT ->
                        onActivity?.invoke(false, 100)
                }
            }
        }
    }

    companion object {
        var onActivity: ((Boolean, Int) -> Unit)? = null
    }
}
