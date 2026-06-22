package com.adhdplanner.adhd_planner

import android.app.AlarmManager
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
        val durationMs = intent.getLongExtra(EXTRA_DURATION_MS, 0L)
        val repeatIntervalMs = intent.getLongExtra(EXTRA_REPEAT_INTERVAL_MS, 0L)
        val requestCode = intent.getIntExtra(EXTRA_REQUEST_CODE, 0)

        startVibration(context, pattern, durationMs)

        // Recurring (weekly) routine alarms re-arm themselves for next
        // week right here -- mirrors how flutter_local_notifications'
        // own matchDateTimeComponents reschedules itself, so this stays in
        // sync without Dart having to be running when it fires.
        if (repeatIntervalMs > 0L) {
            schedule(
                context,
                requestCode,
                System.currentTimeMillis() + repeatIntervalMs,
                pattern,
                durationMs,
                repeatIntervalMs,
            )
        }
    }

    companion object {
        private const val EXTRA_PATTERN = "pattern"
        private const val EXTRA_DURATION_MS = "durationMs"
        private const val EXTRA_REPEAT_INTERVAL_MS = "repeatIntervalMs"
        private const val EXTRA_REQUEST_CODE = "requestCode"

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
        ) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent =
                pendingIntentFor(context, requestCode, pattern, durationMs, repeatIntervalMs)
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, pendingIntent)
            alarmManager.setAlarmClock(info, pendingIntent)
            setActiveCodes(context, activeCodes(context).apply { add(requestCode.toString()) })
        }

        fun cancel(context: Context, requestCode: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Extras don't factor into PendingIntent equality (only the
            // Intent's action/component/data and this requestCode do), so
            // dummy values here still resolve to the same pending alarm.
            val pendingIntent = pendingIntentFor(context, requestCode, longArrayOf(0), 0L, 0L)
            alarmManager.cancel(pendingIntent)
            stopVibration(context)
            setActiveCodes(context, activeCodes(context).apply { remove(requestCode.toString()) })
        }

        /// Cancels every Vibrator alarm this app has armed, by requestCode, from
        /// the persisted [activeCodes] set -- account-independent, so it clears
        /// alarms left behind by a previous (e.g. logged-out) account whose ids
        /// can no longer be re-derived. See [Dart] NotificationService.cancelEverything.
        fun cancelAll(context: Context) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            for (code in activeCodes(context)) {
                val requestCode = code.toIntOrNull() ?: continue
                val pendingIntent = pendingIntentFor(context, requestCode, longArrayOf(0), 0L, 0L)
                alarmManager.cancel(pendingIntent)
            }
            setActiveCodes(context, emptySet())
            stopVibration(context)
        }

        fun stopVibration(context: Context) {
            vibratorFor(context).cancel()
        }

        private fun startVibration(context: Context, pattern: LongArray, durationMs: Long) {
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(VibrationEffect.createWaveform(waveform, -1), attrs)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(VibrationEffect.createWaveform(waveform, -1))
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
        ): PendingIntent {
            val intent = Intent(context, VibrationAlarmReceiver::class.java).apply {
                putExtra(EXTRA_PATTERN, pattern)
                putExtra(EXTRA_DURATION_MS, durationMs)
                putExtra(EXTRA_REPEAT_INTERVAL_MS, repeatIntervalMs)
                putExtra(EXTRA_REQUEST_CODE, requestCode)
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
