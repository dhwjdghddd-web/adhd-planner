package com.adhdplanner.adhd_planner.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/// Receives alarm signals from the phone (even when the watch app is closed --
/// Android starts this service) and drives the full-screen [AlarmActivity].
class WearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            PATH_ALARM_RING -> {
                var amp = 255
                var pattern: LongArray? = null
                if (event.data.isNotEmpty()) {
                    try {
                        val json = org.json.JSONObject(String(event.data))
                        amp = json.optInt("amplitude", 255)
                        json.optJSONArray("pattern")?.let { arr ->
                            val list = LongArray(arr.length())
                            for (i in 0 until arr.length()) list[i] = arr.getLong(i)
                            pattern = list
                        }
                    } catch (_: Exception) {
                    }
                }
                WatchAlarm.ring(this, amp, pattern)
            }
            PATH_ALARM_STOP -> WatchAlarm.stop(this)
        }
    }

    companion object {
        private const val PATH_ALARM_RING = "/alarm_ring"
        private const val PATH_ALARM_STOP = "/alarm_stop"
    }
}
