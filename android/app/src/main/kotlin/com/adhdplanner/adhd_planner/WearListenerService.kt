package com.adhdplanner.adhd_planner

import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import java.util.concurrent.ConcurrentHashMap
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/// Watch → phone: handles a check toggle (and the "오늘은 쉬기" rest-day toggle)
/// sent from the watch and writes it to the same Firestore docs the app uses,
/// natively. Runs even
/// when the Flutter app isn't foregrounded (Android starts this service for the
/// Data Layer message); Firebase auto-initializes on process start and the
/// signed-in user persists, so the write goes to the right account. When the
/// app IS running, its Firestore listener then re-pushes the updated checklist
/// back to the watch (and reconciles block completion).
class WearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        // A malformed payload (e.g. a version-skewed watch build) must never
        // crash the phone process -- drop the message instead.
        try {
            when (event.path) {
                PATH_TOGGLE -> {
                    val payload = JSONObject(String(event.data))
                    toggle(
                        payload.getString("segmentId"),
                        payload.getInt("index"),
                        payload.getBoolean("checked"),
                    )
                }
                PATH_ALARM_DISMISS_ALL -> {
                    // The watch's 끄기 silences EVERY currently-ringing alarm
                    // (robust when several overlap): cancel each armed alarm
                    // whose notification is still on screen.
                    val nm =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val active = nm.activeNotifications.map { it.id }.toSet()
                    for (id in VibrationAlarmReceiver.armedCodes(applicationContext)) {
                        if (id in active) dismiss(id)
                    }
                }
                PATH_TOGGLE_REST -> setRestDay(String(event.data).toBoolean())
                PATH_TOGGLE_REST_TOMORROW -> setRestDayTomorrow(String(event.data).toBoolean())
                PATH_MOVE_ITEM -> {
                    val payload = JSONObject(String(event.data))
                    moveItem(
                        payload.getString("homeSegmentId"),
                        payload.getInt("stepIndex"),
                        payload.getString("targetSegmentId"),
                    )
                }
                PATH_ALARM_SNOOZE -> {
                    val payload = if (event.data.isNotEmpty()) JSONObject(String(event.data)) else JSONObject()
                    val minutes = payload.optInt("minutes", 5)
                    snoozeAlarms(minutes)
                }
                PATH_ALARM_SKIP -> {
                    val payload = if (event.data.isNotEmpty()) JSONObject(String(event.data)) else JSONObject()
                    val segmentId = payload.optString("segmentId", "")
                    skipAlarms(listOf(segmentId))
                }
                PATH_ADD_MEMO -> {
                    val payload = JSONObject(String(event.data))
                    val text = payload.optString("text", "")
                    val source = payload.optString("source", "voice")
                    addMemo(text, source)
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("WearListener", "malformed wear message dropped", e)
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

    private fun snoozeAlarms(minutes: Int) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val active = nm.activeNotifications.map { it.id }.toSet()
        val armed = VibrationAlarmReceiver.armedCodes(applicationContext)
        for (id in armed) {
            if (id in active) {
                dismiss(id)
                val triggerAt = System.currentTimeMillis() + minutes * 60_000L
                VibrationAlarmReceiver.schedule(
                    context = applicationContext,
                    requestCode = id,
                    triggerAtMillis = triggerAt,
                    pattern = longArrayOf(0, 800, 400),
                    durationMs = 60_000L,
                    repeatIntervalMs = 0L,
                    watchAlarm = true,
                    amplitude = 255,
                )
            }
        }
    }

    private fun skipAlarms(segmentIds: List<String>) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val active = nm.activeNotifications.map { it.id }.toSet()
        for (id in VibrationAlarmReceiver.armedCodes(applicationContext)) {
            if (id in active) dismiss(id)
        }
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        for (segId in segmentIds) {
            if (segId.isNotEmpty()) {
                FirebaseFirestore.getInstance()
                    .collection("users").document(uid)
                    .collection("alarmSkips").document("${dateKey}_$segId")
                    .set(mapOf("dateKey" to dateKey, "segmentId" to segId))
            }
        }
    }

    // Watch → phone "오늘만 여기서" move.
    private fun moveItem(homeSegmentId: String, stepIndex: Int, targetSegmentId: String) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val doc = FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("microStepMoves").document("${dateKey}_${homeSegmentId}_$stepIndex")
        if (homeSegmentId == targetSegmentId) {
            doc.delete()
        } else {
            doc.set(
                mapOf(
                    "dateKey" to dateKey,
                    "homeSegmentId" to homeSegmentId,
                    "stepIndex" to stepIndex,
                    "targetSegmentId" to targetSegmentId,
                )
            )
        }
    }

    // Watch → phone "내일 쉬기" toggle.
    private fun setRestDayTomorrow(resting: Boolean) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val cal = java.util.Calendar.getInstance().apply { add(java.util.Calendar.DAY_OF_YEAR, 1) }
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(cal.time)
        val doc = FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("restDays").document(dateKey)
        if (resting) doc.set(mapOf("dateKey" to dateKey)) else doc.delete()
    }

    // Watch → phone "오늘은 쉬기" toggle. Mirrors the Dart RestDayController:
    // a rest day is just the presence of a restDays/{yyyy-MM-dd} doc. When the
    // app is running its restDaysProvider listener re-pushes the checklist and
    // reschedules today's alarms; when it's closed this native write persists
    // and takes effect on next open.
    private fun setRestDay(resting: Boolean) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val doc = FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("restDays").document(dateKey)
        if (resting) doc.set(mapOf("dateKey" to dateKey)) else doc.delete()
    }

    private fun toggle(segmentId: String, index: Int, checked: Boolean) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val dateKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val doc = FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("microStepProgress").document("${dateKey}_$segmentId")

        // Atomic arrayUnion/arrayRemove (not read-modify-write): two rapid
        // toggles can't race each other and lose an update. Order in the array
        // doesn't matter -- every reader consumes checkedIndices as a Set.
        doc.set(
            mapOf(
                "dateKey" to dateKey,
                "segmentId" to segmentId,
                "checkedIndices" to
                    if (checked) FieldValue.arrayUnion(index)
                    else FieldValue.arrayRemove(index),
            ),
            SetOptions.merge(),
        )
    }

    // Watch → phone voice memo
    private fun addMemo(text: String, source: String = "voice") {
        if (text.isBlank()) {
            android.util.Log.w("WearListener", "addMemo: text is blank, ignored")
            return
        }
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        if (uid == null) {
            android.util.Log.e("WearListener", "addMemo: FirebaseAuth currentUser is null, cannot save memo")
            return
        }
        val memoId = java.util.UUID.randomUUID().toString()
        val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }
        val createdAtIso = isoFormat.format(Date())

        val memoMap = hashMapOf<String, Any?>(
            "id" to memoId,
            "text" to text.trim(),
            "source" to source,
            "createdAtIso" to createdAtIso,
            "reviewed" to false,
            "category" to null
        )
        FirebaseFirestore.getInstance()
            .collection("users").document(uid)
            .collection("memos").document(memoId)
            .set(memoMap)
            .addOnSuccessListener {
                android.util.Log.i("WearListener", "addMemo successfully saved memo: $memoId, text: ${text.trim()}")
                cleanupBackgroundProcessIfIdle()
            }
            .addOnFailureListener { e ->
                android.util.Log.e("WearListener", "addMemo failed to save memo: $memoId", e)
                cleanupBackgroundProcessIfIdle()
            }
    }

    private fun cleanupBackgroundProcessIfIdle() {
        if (!MainActivity.isAppInForeground) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!MainActivity.isAppInForeground) {
                    android.util.Log.i("WearListener", "Cleaning up idle background process to prevent freezing")
                    android.os.Process.killProcess(android.os.Process.myPid())
                }
            }, 800L)
        }
    }

    companion object {
        private const val PATH_TOGGLE = "/toggle_item"
        private const val PATH_TOGGLE_REST = "/toggle_rest"
        private const val PATH_TOGGLE_REST_TOMORROW = "/toggle_rest_tomorrow"
        private const val PATH_MOVE_ITEM = "/move_item"
        private const val PATH_ALARM_DISMISS_ALL = "/alarm_dismiss_all"
        private const val PATH_ALARM_SNOOZE = "/alarm_snooze"
        private const val PATH_ALARM_SKIP = "/alarm_skip"
        private const val PATH_ADD_MEMO = "/add_memo"

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
