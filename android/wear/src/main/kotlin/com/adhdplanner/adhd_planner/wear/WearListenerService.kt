package com.adhdplanner.adhd_planner.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/// Receives alarm signals from the phone (even when the watch app is closed --
/// Android starts this service) and drives the full-screen [AlarmActivity].
class WearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            // The payload (rc/name) is ignored -- the alarm reads the ringing
            // block names from the synced checklist instead.
            PATH_ALARM_RING -> WatchAlarm.ring(this)
            PATH_ALARM_STOP -> WatchAlarm.stop(this)
        }
    }

    companion object {
        private const val PATH_ALARM_RING = "/alarm_ring"
        private const val PATH_ALARM_STOP = "/alarm_stop"
    }
}
