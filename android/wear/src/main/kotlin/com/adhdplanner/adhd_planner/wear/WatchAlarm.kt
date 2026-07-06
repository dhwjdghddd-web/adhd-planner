package com.adhdplanner.adhd_planner.wear

import android.content.Context
import android.content.Intent

/// Watch-side alarm entry points. The vibration + UI live in [AlarmActivity]
/// (a long-lived component) -- NOT here: a vibration started from the
/// short-lived WearableListenerService gets cancelled as that service is torn
/// down (observed on One UI Watch), which cut the buzzing short.
object WatchAlarm {
    fun ring(context: Context) {
        context.startActivity(
            Intent(context, AlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    /// The phone reported the alarm ended -- close the alarm screen, which
    /// stops its vibration in onDestroy.
    fun stop(context: Context) {
        AlarmActivity.dismissActive()
    }
}
