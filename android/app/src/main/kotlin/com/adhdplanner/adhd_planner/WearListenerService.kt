package com.adhdplanner.adhd_planner

import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Watch → phone: handles a check toggle sent from the watch and writes it to
/// the same Firestore [MicroStepProgress] doc the app uses, natively. Runs even
/// when the Flutter app isn't foregrounded (Android starts this service for the
/// Data Layer message); Firebase auto-initializes on process start and the
/// signed-in user persists, so the write goes to the right account. When the
/// app IS running, its Firestore listener then re-pushes the updated checklist
/// back to the watch (and reconciles block completion).
class WearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            PATH_TOGGLE -> {
                val payload = JSONObject(String(event.data))
                toggle(
                    payload.getString("segmentId"),
                    payload.getInt("index"),
                    payload.getBoolean("checked"),
                )
            }
            PATH_ALARM_DISMISS -> dismiss(String(event.data).toIntOrNull() ?: return)
            PATH_ALARM_DISMISS_ALL -> {
                // The watch's 끄기 silences EVERY currently-ringing alarm (robust
                // when several overlap), not just one id: cancel each armed alarm
                // whose notification is still on screen.
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val active = nm.activeNotifications.map { it.id }.toSet()
                for (id in VibrationAlarmReceiver.armedCodes(applicationContext)) {
                    if (id in active) dismiss(id)
                }
            }
        }
    }

    // Stops one alarm's vibration/buzz loop + removes its notification, and
    // records the dismiss so the phone's full-screen AlarmScreen (if up) can
    // close itself -- more reliable than watching the notification, which a
    // cold-start rescheduleAll may already have cancelled.
    private fun dismiss(requestCode: Int) {
        VibrationAlarmReceiver.cancel(applicationContext, requestCode)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(requestCode)
        dismissedAt[requestCode] = SystemClock.elapsedRealtime()
    }

    private fun toggle(segmentId: String, index: Int, checked: Boolean) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val doc = FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("microStepProgress").document("${dateKey}_$segmentId")

        // Read-modify-write the checked set (add or remove this index).
        doc.get().addOnSuccessListener { snap ->
            val current = (snap.get("checkedIndices") as? List<*>)
                ?.mapNotNull { (it as? Number)?.toInt() }
                ?.toMutableSet()
                ?: mutableSetOf()
            if (checked) current.add(index) else current.remove(index)
            doc.set(
                mapOf(
                    "dateKey" to dateKey,
                    "segmentId" to segmentId,
                    "checkedIndices" to current.sorted(),
                ),
            )
        }
    }

    companion object {
        private const val PATH_TOGGLE = "/toggle_item"
        private const val PATH_ALARM_DISMISS = "/alarm_dismiss"
        private const val PATH_ALARM_DISMISS_ALL = "/alarm_dismiss_all"

        // Ids the watch dismissed (id -> when), consumed by MainActivity's
        // channel so the phone's full-screen AlarmScreen can close/not-show.
        // A map (not one field) so two alarms dismissed at once are both
        // remembered. Same process as the Activity, so a plain static is enough.
        private val dismissedAt = ConcurrentHashMap<Int, Long>()

        /// True (once) if the watch dismissed [id] within the last few minutes.
        /// The window lets the phone suppress a still-pending full-screen alarm
        /// even if it's opened a while after the watch dismiss, while a stale
        /// cross-day flag (same block next day) is safely ignored.
        fun consumeWatchDismiss(id: Int): Boolean {
            val at = dismissedAt[id] ?: return false
            dismissedAt.remove(id)
            return SystemClock.elapsedRealtime() - at < 300_000L
        }
    }
}
