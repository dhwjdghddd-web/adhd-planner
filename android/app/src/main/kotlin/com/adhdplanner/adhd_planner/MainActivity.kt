package com.adhdplanner.adhd_planner

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Bridges to Android's own alarm-sound picker (Settings > ... > alarm
/// sound dialog) rather than building a custom one — it already lists every
/// ringtone the system and the user's other apps have installed. Activity
/// results arrive asynchronously on a separate callback, so the pending
/// MethodChannel result has to be held onto between the two.
///
/// Also creates the alarm notification channels directly (rather than via
/// flutter_local_notifications' own `createNotificationChannel`): that
/// plugin builds the channel's `AudioAttributes` with only `setUsage()`,
/// and Android defaults a freshly-built `AudioAttributes` to muting its
/// haptic channel unless `setHapticChannelsMuted(false)` is called
/// explicitly — which silently mutes the *vibration* on a USAGE_ALARM
/// channel even though the sound itself plays fine. Building the channel
/// here instead is the only way to clear that flag.
class MainActivity : FlutterActivity() {
    private val channelName = "com.adhdplanner.adhd_planner/alarm_sound"
    private val pickRequestCode = 4242
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAlarmSound" -> {
                        pendingResult = result
                        val currentUriString = call.argument<String>("currentUri")
                        val existingUri = if (currentUriString != null) Uri.parse(currentUriString) else null
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            putExtra(
                                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                            )
                            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, existingUri)
                        }
                        startActivityForResult(intent, pickRequestCode)
                    }
                    "ensureAlarmChannel" -> {
                        ensureAlarmChannel(call, result)
                    }
                    "previewVibration" -> {
                        previewVibration(call, result)
                    }
                    "scheduleVibrationAlarm" -> {
                        scheduleVibrationAlarm(call, result)
                    }
                    "cancelVibrationAlarm" -> {
                        cancelVibrationAlarm(call, result)
                    }
                    "cancelAllVibrationAlarms" -> {
                        VibrationAlarmReceiver.cancelAll(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureAlarmChannel(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")!!
        val name = call.argument<String>("name")!!
        val description = call.argument<String>("description")
        val importance = call.argument<Int>("importance")!!
        val soundUri = call.argument<String>("soundUri")!!
        // Sent as a plain Dart List<int> rather than Int64List specifically
        // so it arrives as a List of boxed numbers here rather than a raw
        // long[] — whether that box is Integer or Long isn't guaranteed, so
        // converting each element via Number is the safe way to read it.
        val vibrationPattern = call.argument<List<*>>("vibrationPattern")!!
            .map { (it as Number).toLong() }
            .toLongArray()

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setHapticChannelsMuted(false)
            .build()

        val channel = NotificationChannel(id, name, importance).apply {
            this.description = description
            enableVibration(true)
            this.vibrationPattern = vibrationPattern
            setSound(Uri.parse(soundUri), audioAttributes)
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
        result.success(null)
    }

    // Lets the settings screen play a vibration pattern on demand so picking
    // one isn't a guessing game from the label alone.
    private fun previewVibration(call: MethodCall, result: MethodChannel.Result) {
        val vibrationPattern = call.argument<List<*>>("vibrationPattern")!!
            .map { (it as Number).toLong() }
            .toLongArray()

        val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val attrs = VibrationAttributes.Builder()
                .setUsage(VibrationAttributes.USAGE_ALARM)
                .build()
            vibrator.vibrate(VibrationEffect.createWaveform(vibrationPattern, -1), attrs)
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(VibrationEffect.createWaveform(vibrationPattern, -1))
        }
        result.success(null)
    }

    // See VibrationAlarmReceiver's doc comment for why this exists
    // alongside the actual notification: a Notification channel's own
    // vibration is silenced by Samsung OneUI's "무음" ringer mode even on
    // a USAGE_ALARM channel, but a directly-triggered Vibrator call isn't.
    private fun scheduleVibrationAlarm(call: MethodCall, result: MethodChannel.Result) {
        // Read every numeric arg via Number().toLong()/toInt() rather than
        // a direct Int/Long cast -- the platform channel doesn't guarantee
        // which boxed type a given Dart int arrives as.
        val requestCode = (call.argument<Number>("requestCode"))!!.toInt()
        val triggerAtMillis = (call.argument<Number>("triggerAtMillis"))!!.toLong()
        val pattern = call.argument<List<*>>("pattern")!!
            .map { (it as Number).toLong() }
            .toLongArray()
        val durationMs = (call.argument<Number>("durationMs"))!!.toLong()
        val repeatIntervalMs = (call.argument<Number>("repeatIntervalMs"))!!.toLong()

        VibrationAlarmReceiver.schedule(
            applicationContext,
            requestCode,
            triggerAtMillis,
            pattern,
            durationMs,
            repeatIntervalMs,
        )
        result.success(null)
    }

    private fun cancelVibrationAlarm(call: MethodCall, result: MethodChannel.Result) {
        val requestCode = (call.argument<Number>("requestCode"))!!.toInt()
        VibrationAlarmReceiver.cancel(applicationContext, requestCode)
        result.success(null)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return

        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            // "Silent" or an otherwise empty pick — leave the existing choice alone.
            result.success(null)
            return
        }
        val title = RingtoneManager.getRingtone(applicationContext, uri)?.getTitle(applicationContext)
        result.success(mapOf("uri" to uri.toString(), "label" to (title ?: "알람음")))
    }
}
