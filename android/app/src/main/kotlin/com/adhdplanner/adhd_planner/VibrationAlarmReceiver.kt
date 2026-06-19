package com.adhdplanner.adhd_planner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
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
        }

        fun cancel(context: Context, requestCode: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Extras don't factor into PendingIntent equality (only the
            // Intent's action/component/data and this requestCode do), so
            // dummy values here still resolve to the same pending alarm.
            val pendingIntent = pendingIntentFor(context, requestCode, longArrayOf(0), 0L, 0L)
            alarmManager.cancel(pendingIntent)
            stopVibration(context)
        }

        fun stopVibration(context: Context) {
            vibratorFor(context).cancel()
        }

        private fun startVibration(context: Context, pattern: LongArray, durationMs: Long) {
            val vibrator = vibratorFor(context)
            // repeatIndex 0 (not -1): loops the whole pattern from the
            // start, matching the notification channel's own INSISTENT
            // repeat-until-dismissed behaviour, with the postDelayed below
            // as this path's equivalent of timeoutAfter.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val attrs = VibrationAttributes.Builder()
                    .setUsage(VibrationAttributes.USAGE_ALARM)
                    .build()
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0), attrs)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            }
            if (durationMs > 0L) {
                Handler(Looper.getMainLooper()).postDelayed({ vibrator.cancel() }, durationMs)
            }
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
