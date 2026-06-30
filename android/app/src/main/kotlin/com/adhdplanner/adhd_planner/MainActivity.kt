package com.adhdplanner.adhd_planner

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.Display
import android.view.WindowManager
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

    // Set while an AlarmScreen is showing: lets native treat a power-button
    // press (ACTION_SCREEN_OFF) as "dismiss this alarm" and call back into Dart.
    private var alarmChannel: MethodChannel? = null
    private var screenOffReceiver: BroadcastReceiver? = null
    private var guardedNotificationId: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Screen-wake toggle (settings option). FLAG_KEEP_SCREEN_ON only keeps
        // the screen on while THIS activity is in the foreground, so it
        // naturally scopes to "while the app is showing" with no lifecycle
        // bookkeeping needed -- backgrounding the app lets the screen sleep
        // normally again.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.adhdplanner.adhd_planner/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "getDisplayInfo" -> {
                        // Which physical display this activity is currently on.
                        // A foldable cover screen is a non-default built-in
                        // display (Z Flip7: cover = displayId 1, main = 0,
                        // primary = 0), so isDefault == false means "cover".
                        // getDisplay() is API 30+, hence the windowManager
                        // fallback for older devices.
                        val d = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            display
                        } else {
                            @Suppress("DEPRECATION")
                            windowManager.defaultDisplay
                        }
                        val id = d?.displayId ?: Display.DEFAULT_DISPLAY
                        result.success(
                            mapOf(
                                "displayId" to id,
                                "isDefault" to (id == Display.DEFAULT_DISPLAY),
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        alarmChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAlarmSound" -> {
                        pendingResult = result
                        val currentUriString = call.argument<String>("currentUri")
                        // The *indirection* URI (e.g. content://settings/system/alarm_alert)
                        // -- this is what EXTRA_RINGTONE_DEFAULT_URI must be: the symbolic
                        // marker the picker associates with its own "기본 알람음" list row.
                        val defaultIndirectionUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        // null currentUri means "use the system default" (the app's own
                        // semantics -- see _soundFor in notification_service.dart). The
                        // picker decides which row is *checked* by comparing
                        // EXTRA_RINGTONE_EXISTING_URI against each row's resolved sound
                        // file URI -- the Default row's resolved URI is the *actual*
                        // current default sound file, not the indirection marker above.
                        // Passing the indirection URI there left nothing checked (the
                        // first attempt at this fix); the actual resolved URI is what
                        // matches.
                        val existingUri = if (currentUriString != null) {
                            Uri.parse(currentUriString)
                        } else {
                            RingtoneManager.getActualDefaultRingtoneUri(
                                applicationContext,
                                RingtoneManager.TYPE_ALARM,
                            )
                        }
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI, defaultIndirectionUri)
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
                        // Return the cancelled request codes so Dart can also
                        // cancel each matching flutter_local_notifications alarm
                        // by id (reaches orphans its own cancelAll tracking lost).
                        val cancelled = VibrationAlarmReceiver.cancelAll(applicationContext)
                        result.success(cancelled)
                    }
                    "startScreenOffGuard" -> {
                        guardedNotificationId = (call.argument<Number>("notificationId"))?.toInt() ?: -1
                        startScreenOffGuard()
                        result.success(null)
                    }
                    "stopScreenOffGuard" -> {
                        stopScreenOffGuard()
                        result.success(null)
                    }
                    "openChannelSettings" -> {
                        openChannelSettings(call, result)
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

    // T10: hands off to Android's own per-channel notification settings
    // (sound/importance/vibration override) -- this app's own settings
    // screen only ever exposes broad app-level choices, so adjusting any one
    // channel individually has to go through the system screen directly.
    private fun openChannelSettings(call: MethodCall, result: MethodChannel.Result) {
        val channelId = call.argument<String>("channelId")!!
        val intent = Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
            putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, applicationContext.packageName)
            putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, channelId)
        }
        startActivity(intent)
        result.success(null)
    }

    // Registers a one-shot watcher for the screen turning off (the power button)
    // while an alarm is showing. On the stock clock app the power button stops a
    // ringing alarm; this mirrors that. ACTION_SCREEN_OFF is a protected system
    // broadcast, so a plain context-registered receiver is allowed on all API
    // levels without an exported/not-exported flag.
    private fun startScreenOffGuard() {
        if (screenOffReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != Intent.ACTION_SCREEN_OFF) return
                // Silence the still-ringing alarm without unarming its daily
                // recurrence: dismiss the shown notification (stops its looping
                // sound) and stop the current vibration only -- stopVibration
                // cancels the active buzz, not the scheduled AlarmManager alarm.
                if (guardedNotificationId >= 0) {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(guardedNotificationId)
                }
                VibrationAlarmReceiver.stopVibration(applicationContext)
                // Ask Dart to close the alarm screen (runs on the main thread,
                // since this dynamically-registered receiver fires there).
                alarmChannel?.invokeMethod("onAlarmDismissedByPower", null)
                stopScreenOffGuard()
            }
        }
        screenOffReceiver = receiver
        registerReceiver(receiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }

    private fun stopScreenOffGuard() {
        val receiver = screenOffReceiver ?: return
        screenOffReceiver = null
        guardedNotificationId = -1
        try {
            unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Already unregistered -- harmless.
        }
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
