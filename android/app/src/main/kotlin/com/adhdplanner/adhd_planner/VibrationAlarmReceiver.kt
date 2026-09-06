package com.adhdplanner.adhd_planner

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/// Fires alongside (not instead of) the flutter_local_notifications alarm
/// notification, calling Vibrator.vibrate() directly. Samsung OneUI's "무음"
/// ringer mode silences a Notification's own vibration even on a
/// USAGE_ALARM channel with AlarmManager.setAlarmClock driving it -- but a
/// direct Vibrator call (confirmed via the settings screen's own
/// 진동 미리듣기 button, which already does this and was felt while the
/// device was in 무음) bypasses that. setAlarmClock still governs *when*
/// this fires, since that part already worked; this only changes *how the
/// device actually buzzes* once it does.
class VibrationAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pattern = intent.getLongArrayExtra(EXTRA_PATTERN) ?: return
        val requestCode = intent.getIntExtra(EXTRA_REQUEST_CODE, 0)
        val amplitude = intent.getIntExtra(EXTRA_AMPLITUDE, 255)

        // A continuation of the in-alarm buzz loop (see below): keep buzzing in
        // short cycles until the window ends OR the user removes the alarm
        // notification. Checked every cycle so swiping the notification away
        // stops the vibration within ~one cycle -- flutter_local_notifications
        // gives no direct "dismissed" callback, so this is how deleting the
        // heads-up alarm makes the buzzing stop.
        if (intent.action == ACTION_BUZZ_LOOP) {
            val buzzUntil = intent.getLongExtra(EXTRA_BUZZ_UNTIL_MS, 0L)
            if (System.currentTimeMillis() >= buzzUntil) return
            if (!isAlarmNotificationActive(context, requestCode)) return
            startVibration(context, pattern, BUZZ_CYCLE_MS, amplitude)
            scheduleBuzzContinuation(context, requestCode, pattern, buzzUntil, amplitude)
            return
        }

        val durationMs = intent.getLongExtra(EXTRA_DURATION_MS, 0L)
        val repeatIntervalMs = intent.getLongExtra(EXTRA_REPEAT_INTERVAL_MS, 0L)
        val watchAlarm = intent.getBooleanExtra(EXTRA_WATCH_ALARM, false)

        // Check dynamic rest-day / work-day guard for this alarm
        val prefs = context.getSharedPreferences("adhd_alarm_prefs", Context.MODE_PRIVATE)
        val restDays = prefs.getStringSet("rest_days", emptySet()) ?: emptySet()
        val scheduleTarget = prefs.getString("target_$requestCode", "everyday") ?: "everyday"
        val todayKey = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.getDefault()).format(java.util.Date())
        val isRestToday = restDays.contains(todayKey)

        val shouldSuppress = (isRestToday && scheduleTarget == "workDaysOnly") || (!isRestToday && scheduleTarget == "restDaysOnly")

        val segmentId = intent.getStringExtra(EXTRA_SEGMENT_ID)

        // Recurring (daily) routine alarms re-arm themselves for next day right
        // here -- mirrors how flutter_local_notifications' own
        // matchDateTimeComponents reschedules itself, so this stays in sync
        // without Dart having to be running when it fires.
        if (repeatIntervalMs > 0L) {
            schedule(
                context,
                requestCode,
                System.currentTimeMillis() + repeatIntervalMs,
                pattern,
                durationMs,
                repeatIntervalMs,
                watchAlarm,
                segmentId,
                amplitude,
            )
        }

        if (shouldSuppress) {
            // Dismiss notification if it was posted by flutter_local_notifications
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            notificationManager?.cancel(requestCode)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notificationManager?.cancel(requestCode)
            }, 300)
            return
        }

        // Buzz now, then hand off to the swipe-aware loop for the rest of the
        // window (durationMs): short cycles that stop as soon as the alarm
        // notification is gone.
        startVibration(context, pattern, BUZZ_CYCLE_MS, amplitude)
        val window = if (durationMs > 0L) durationMs else BUZZ_CYCLE_MS
        scheduleBuzzContinuation(
            context,
            requestCode,
            pattern,
            System.currentTimeMillis() + window,
            amplitude,
        )

        // Block alarms also ring the watch companion. goAsync keeps this
        // (short-lived) process alive while the Data Layer message is sent.
        if (watchAlarm) {
            val pending = goAsync()
            WearAlarmMessenger.sendRing(context) { pending.finish() }
        }

        // Bring MainActivity directly to the foreground so the full-screen AlarmScreen displays immediately
        // without waiting for the user to tap the notification popup banner.
        // Only launch full-screen when segmentId is provided (gentle alarms pass null so they don't take over the screen).
        if (!segmentId.isNullOrEmpty()) {
            try {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("alarm_trigger", true)
                    putExtra("notification_id", requestCode)
                    putExtra("segment_id", segmentId)
                }
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                android.util.Log.w("VibrationAlarmReceiver", "Failed to auto-launch MainActivity for alarm", e)
            }
        }
    }

    companion object {
        private const val EXTRA_PATTERN = "pattern"
        private const val EXTRA_DURATION_MS = "durationMs"
        private const val EXTRA_REPEAT_INTERVAL_MS = "repeatIntervalMs"
        private const val EXTRA_REQUEST_CODE = "requestCode"
        private const val EXTRA_BUZZ_UNTIL_MS = "buzzUntilMs"
        private const val EXTRA_WATCH_ALARM = "watchAlarm"
        private const val EXTRA_SEGMENT_ID = "segmentId"
        private const val EXTRA_AMPLITUDE = "amplitude"

        // Marks the self-rescheduling in-alarm buzz continuations. A distinct
        // action keeps its PendingIntent separate from the daily re-arm's
        // (which has no action) even though both share the requestCode.
        private const val ACTION_BUZZ_LOOP = "com.adhdplanner.adhd_planner.BUZZ_LOOP"

        // How long each buzz cycle lasts and how often the loop re-checks that
        // the alarm notification is still on screen. A swipe stops the buzzing
        // within ~one interval.
        private const val BUZZ_CYCLE_MS = 4500L
        private const val LOOP_INTERVAL_MS = 5000L

        // Every requestCode this app currently has a Vibrator alarm armed for,
        // persisted so [cancelAll] can wipe them without the caller having to
        // already know each id. Needed because AlarmManager can't enumerate its
        // own alarms: after a logout/account switch the previous account's
        // routine list (the only place those ids could be re-derived from) is
        // gone, so an orphaned native alarm would otherwise keep firing with no
        // way left to cancel it. (flutter_local_notifications' own side is
        // separately wiped by cancelAll() there, which is account-global.)
        private const val PREFS = "vibration_alarms"
        private const val KEY_ACTIVE = "active_request_codes"

        private fun activeCodes(context: Context): MutableSet<String> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            // Copy: the Set returned by getStringSet must not be mutated in place.
            return HashSet(prefs.getStringSet(KEY_ACTIVE, emptySet()) ?: emptySet())
        }

        /// Every requestCode this app currently has a Vibrator alarm armed for.
        fun armedCodes(context: Context): List<Int> =
            activeCodes(context).mapNotNull { it.toIntOrNull() }

        private fun setActiveCodes(context: Context, codes: Set<String>) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(KEY_ACTIVE, codes)
                .apply()
        }

        fun schedule(
            context: Context,
            requestCode: Int,
            triggerAtMillis: Long,
            pattern: LongArray,
            durationMs: Long,
            repeatIntervalMs: Long,
            watchAlarm: Boolean = false,
            segmentId: String? = null,
            amplitude: Int = 255,
        ) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = pendingIntentFor(
                context, requestCode, pattern, durationMs, repeatIntervalMs, watchAlarm, segmentId, amplitude,
            )
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, pendingIntent)
            alarmManager.setAlarmClock(info, pendingIntent)
            setActiveCodes(context, activeCodes(context).apply { add(requestCode.toString()) })
        }

        fun cancel(context: Context, requestCode: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Extras don't factor into PendingIntent equality (only the
            // Intent's action/component/data and this requestCode do), so
            // dummy values here still resolve to the same pending alarm.
            alarmManager.cancel(
                pendingIntentFor(context, requestCode, longArrayOf(0), 0L, 0L, false),
            )
            // Also kill any in-flight buzz loop for this alarm.
            alarmManager.cancel(buzzLoopPendingIntent(context, requestCode, longArrayOf(0), 0L))
            stopVibration(context)
            setActiveCodes(context, activeCodes(context).apply { remove(requestCode.toString()) })
            // Tell the watch to close its alarm screen (this alarm is over).
            WearAlarmMessenger.sendStop(context)
        }

        /// Cancels every Vibrator alarm this app has armed, by requestCode, from
        /// the persisted [activeCodes] set -- account-independent, so it clears
        /// alarms left behind by a previous (e.g. logged-out) account whose ids
        /// can no longer be re-derived. Returns those request codes so the Dart
        /// side can also cancel the matching flutter_local_notifications alarm
        /// for each id (its own cancelAll only reaches ids still in *its*
        /// tracking, which a reboot's boot-replay can desync). See
        /// NotificationService.cancelEverything.
        fun cancelAll(context: Context): List<Int> {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val cancelled = ArrayList<Int>()
            for (code in activeCodes(context)) {
                val requestCode = code.toIntOrNull() ?: continue
                alarmManager.cancel(
                    pendingIntentFor(context, requestCode, longArrayOf(0), 0L, 0L, false),
                )
                if (!isAlarmNotificationActive(context, requestCode)) {
                    alarmManager.cancel(buzzLoopPendingIntent(context, requestCode, longArrayOf(0), 0L))
                }
                cancelled.add(requestCode)
            }
            setActiveCodes(context, emptySet())
            // NB: no stopVibration(context) and no WearAlarmMessenger.sendStop here!
            // cancelAll runs during routine rescheduleAll (incl. the cold start when
            // an alarm fires), and stopping vibration here kills the buzz of a
            // legitimately-ringing alarm. Only the explicit single cancel()
            // (a real dismiss) signals the watch and stops the vibration.
            return cancelled
        }

        fun stopVibration(context: Context) {
            vibratorFor(context).cancel()
        }

        // True while the block alarm's notification (posted by
        // flutter_local_notifications with id == requestCode) is still on
        // screen. getActiveNotifications returns only this app's own
        // notifications, so no special permission is needed and the id match is
        // unambiguous.
        private fun isAlarmNotificationActive(context: Context, id: Int): Boolean {
            val nm =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return nm.activeNotifications.any { it.id == id }
        }

        // Schedules the next buzz-loop cycle [LOOP_INTERVAL_MS] out. setAlarmClock
        // (like the initial alarm) so it stays exact and fires even in doze,
        // through the short buzz window.
        private fun scheduleBuzzContinuation(
            context: Context,
            requestCode: Int,
            pattern: LongArray,
            buzzUntil: Long,
            amplitude: Int = 255,
        ) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent =
                buzzLoopPendingIntent(context, requestCode, pattern, buzzUntil, amplitude)
            val triggerAt = System.currentTimeMillis() + LOOP_INTERVAL_MS
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(triggerAt, pendingIntent),
                pendingIntent,
            )
        }

        private fun buzzLoopPendingIntent(
            context: Context,
            requestCode: Int,
            pattern: LongArray,
            buzzUntil: Long,
            amplitude: Int = 255,
        ): PendingIntent {
            val intent = Intent(context, VibrationAlarmReceiver::class.java).apply {
                action = ACTION_BUZZ_LOOP
                putExtra(EXTRA_PATTERN, pattern)
                putExtra(EXTRA_REQUEST_CODE, requestCode)
                putExtra(EXTRA_BUZZ_UNTIL_MS, buzzUntil)
                putExtra(EXTRA_AMPLITUDE, amplitude)
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun createVibrationEffect(vibrator: Vibrator, pattern: LongArray, amplitude: Int): VibrationEffect {
            val clampedAmp = amplitude.coerceIn(1, 255)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (vibrator.hasAmplitudeControl()) {
                    val amplitudes = IntArray(pattern.size) { i ->
                        if (i % 2 == 0) 0 else clampedAmp
                    }
                    return VibrationEffect.createWaveform(pattern, amplitudes, -1)
                }
            }
            return VibrationEffect.createWaveform(pattern, -1)
        }

        private fun startVibration(
            context: Context,
            pattern: LongArray,
            durationMs: Long,
            amplitude: Int = 255,
        ) {
            val vibrator = vibratorFor(context)
            // A *finite* waveform sized to fill durationMs, played once
            // (repeatIndex -1) -- NOT an infinitely-repeating waveform
            // (repeatIndex 0) stopped by a delayed Handler callback. A
            // BroadcastReceiver's process can be killed the moment
            // onReceive() returns (routine when the screen is off / app
            // killed), which would never run that callback -- leaving an
            // infinite vibration buzzing until reboot. A finite effect stops
            // on its own with no callback needed; cancel() (below) still
            // works for an explicit 확인/미루기/넘기기 stop.
            val waveform = if (durationMs > 0L) finitePattern(pattern, durationMs) else pattern
            val effect = createVibrationEffect(vibrator, waveform, amplitude)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(effect, attrs)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(effect)
            }
        }

        // Repeats [pattern]'s buzz cycle (everything after its leading
        // pause at index 0) until the total duration reaches [durationMs],
        // so the resulting one-shot waveform lasts about as long as the old
        // infinite-loop-for-durationMs approach did -- but stops by itself.
        private fun finitePattern(pattern: LongArray, durationMs: Long): LongArray {
            if (pattern.size < 2) return pattern
            // Guard against a degenerate pattern whose buzz cycle sums to 0,
            // which would never reach durationMs and loop forever here.
            var cycleSum = 0L
            for (i in 1 until pattern.size) cycleSum += pattern[i]
            if (cycleSum <= 0L) return pattern

            val out = ArrayList<Long>(pattern.size)
            var total = 0L
            for (v in pattern) {
                out.add(v)
                total += v
            }
            while (total < durationMs) {
                for (i in 1 until pattern.size) {
                    out.add(pattern[i])
                    total += pattern[i]
                }
            }
            return out.toLongArray()
        }

        private fun vibratorFor(context: Context): Vibrator {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager =
                    context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
        }

        private fun pendingIntentFor(
            context: Context,
            requestCode: Int,
            pattern: LongArray,
            durationMs: Long,
            repeatIntervalMs: Long,
            watchAlarm: Boolean,
            segmentId: String? = null,
            amplitude: Int = 255,
        ): PendingIntent {
            val intent = Intent(context, VibrationAlarmReceiver::class.java).apply {
                putExtra(EXTRA_PATTERN, pattern)
                putExtra(EXTRA_DURATION_MS, durationMs)
                putExtra(EXTRA_REPEAT_INTERVAL_MS, repeatIntervalMs)
                putExtra(EXTRA_REQUEST_CODE, requestCode)
                putExtra(EXTRA_WATCH_ALARM, watchAlarm)
                putExtra(EXTRA_AMPLITUDE, amplitude)
                if (segmentId != null) {
                    putExtra(EXTRA_SEGMENT_ID, segmentId)
                }
            }
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
