package com.adhdplanner.adhd_planner.wear

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import androidx.wear.compose.material3.TimeText
import com.google.android.gms.wearable.Wearable

/// The watch alarm: the currently-ringing block name(s) + 끄기/스누즈/건너뛰기, plus the
/// vibration. Names come from the synced checklist (all "current" blocks).
class AlarmActivity : ComponentActivity() {
    private val ringingBlocks: MutableState<List<WatchBlock>> = mutableStateOf(emptyList())
    private val timeoutHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        active = this
        startVibration()
        loadNames()
        setContent {
            AlarmScreen(
                blocks = ringingBlocks.value,
                onDismiss = ::onDismiss,
                onSnooze = ::onSnooze,
                onSkip = ::onSkip,
            )
        }
        // Auto-close when the buzz window ends: with FLAG_KEEP_SCREEN_ON an
        // ignored alarm would otherwise keep the watch screen on indefinitely
        timeoutHandler.postDelayed({ finish() }, WINDOW_MS)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        startVibration()
        loadNames()
    }

    private fun loadNames() {
        ChecklistData.readLatest(this) { data ->
            val b = data?.startingBlocks().orEmpty()
            runOnUiThread { ringingBlocks.value = b }
        }
    }

    private fun sendToPhone(path: String, payload: ByteArray) {
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                Wearable.getMessageClient(this).sendMessage(node.id, path, payload)
            }
        }
    }

    private fun onDismiss() {
        stopVibration()
        sendToPhone(PATH_ALARM_DISMISS_ALL, ByteArray(0))
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        finish()
    }

    private fun onSnooze(minutes: Int = 5) {
        stopVibration()
        val payload = org.json.JSONObject().put("minutes", minutes).toString().toByteArray()
        sendToPhone(PATH_ALARM_SNOOZE, payload)
        finish()
    }

    private fun onSkip() {
        stopVibration()
        val segId = ringingBlocks.value.firstOrNull()?.blockId ?: ""
        val payload = org.json.JSONObject().put("segmentId", segId).toString().toByteArray()
        sendToPhone(PATH_ALARM_SKIP, payload)
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        timeoutHandler.removeCallbacksAndMessages(null)
        if (active === this) {
            stopVibration()
            active = null
        }
    }

    private fun startVibration() {
        val amp = intent.getIntExtra("amplitude", 255)
        val customPattern = intent.getLongArrayExtra("pattern")
        val base = customPattern ?: BASE_PATTERN

        val timings = ArrayList<Long>()
        val amplitudes = ArrayList<Int>()
        var total = 0L
        while (total < WINDOW_MS) {
            for (i in base.indices) {
                val t = base[i]
                if (t <= 0L && i == 0) continue
                timings.add(t)
                amplitudes.add(if (i % 2 == 1) amp.coerceIn(1, 255) else 0)
                total += t
            }
        }

        val effect = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                VibrationEffect.createWaveform(timings.toLongArray(), amplitudes.toIntArray(), -1)
            } catch (_: Exception) {
                VibrationEffect.createWaveform(timings.toLongArray(), -1)
            }
        } else {
            @Suppress("DEPRECATION")
            VibrationEffect.createWaveform(timings.toLongArray(), -1)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            vibratorManager().defaultVibrator.vibrate(effect)
        } else {
            @Suppress("DEPRECATION")
            legacyVibrator().vibrate(effect)
        }
    }

    private fun stopVibration() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            vibratorManager().cancel()
        } else {
            @Suppress("DEPRECATION")
            legacyVibrator().cancel()
        }
    }

    private fun vibratorManager(): VibratorManager =
        getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager

    @Suppress("DEPRECATION")
    private fun legacyVibrator(): Vibrator =
        getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

    companion object {
        private const val PATH_ALARM_DISMISS_ALL = "/alarm_dismiss_all"
        private const val PATH_ALARM_SNOOZE = "/alarm_snooze"
        private const val PATH_ALARM_SKIP = "/alarm_skip"
        private const val WINDOW_MS = 60_000L
        private val BASE_PATTERN = longArrayOf(0, 600, 400)

        private var active: AlarmActivity? = null

        fun dismissActive() {
            active?.let { it.runOnUiThread { it.finish() } }
        }
    }
}

@Composable
private fun AlarmScreen(
    blocks: List<WatchBlock>,
    onDismiss: () -> Unit,
    onSnooze: () -> Unit,
    onSkip: () -> Unit,
) {
    MaterialTheme {
        AppScaffold {
            val listState = androidx.wear.compose.foundation.lazy.rememberScalingLazyListState()
            androidx.wear.compose.material3.ScreenScaffold(
                scrollState = listState,
                timeText = { TimeText() },
            ) { contentPadding ->
                androidx.wear.compose.foundation.lazy.ScalingLazyColumn(
                    state = listState,
                    contentPadding = contentPadding,
                    scalingParams = ScalingLazyColumnDefaults.scalingParams(
                        edgeScale = 1f,
                        minElementHeight = 0f,
                    ),
                    modifier = Modifier.fillMaxSize().padding(horizontal = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    item {
                        val title = if (blocks.isNotEmpty()) blocks.joinToString("\n") { it.name } else "루틴 알람"
                        Text(
                            title,
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(bottom = 2.dp),
                        )
                    }
                    item {
                        Text(
                            "지금 시작할 시간이에요",
                            textAlign = TextAlign.Center,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(bottom = 12.dp),
                        )
                    }
                    item {
                        Button(
                            onClick = onDismiss,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        ) {
                            Text("끄기", textAlign = TextAlign.Center)
                        }
                    }
                    item {
                        androidx.wear.compose.material3.FilledTonalButton(
                            onClick = onSnooze,
                            modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
                        ) {
                            Text("5분 뒤 다시", textAlign = TextAlign.Center)
                        }
                    }
                    item {
                        androidx.wear.compose.material3.CompactButton(
                            onClick = onSkip,
                            modifier = Modifier.padding(top = 4.dp),
                        ) {
                            Text("오늘은 건너뛰기")
                        }
                    }
                }
            }
        }
    }
}
