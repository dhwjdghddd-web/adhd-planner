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
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.Text
import com.google.android.gms.wearable.Wearable

/// The watch alarm: the currently-ringing block name(s) + 끄기, plus the
/// vibration (owned here so it lives as long as this FLAG_KEEP_SCREEN_ON
/// screen). Names come from the synced checklist (all "current" blocks), not
/// from the ring messages -- reliable even when several overlap. 끄기 tells the
/// phone to silence everything ringing, then hands off to the checklist.
class AlarmActivity : ComponentActivity() {
    private val names: MutableState<List<String>> = mutableStateOf(emptyList())
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
        setContent { AlarmScreen(names.value, onDismiss = ::onDismiss) }
        // Auto-close when the buzz window ends: with FLAG_KEEP_SCREEN_ON an
        // ignored alarm would otherwise keep the watch screen on indefinitely
        // (a real battery drain if the watch is off-wrist).
        timeoutHandler.postDelayed({ finish() }, WINDOW_MS)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        loadNames() // a second/third alarm may have made more blocks current
    }

    private fun loadNames() {
        // The block(s) STARTING right now (by the watch's own clock) -- an
        // already-running overlapping block isn't what this alarm is for.
        ChecklistData.readLatest(this) { data ->
            val n = data?.startingBlocks()?.map { it.name }.orEmpty()
            runOnUiThread { names.value = n }
        }
    }

    private fun onDismiss() {
        stopVibration()
        // One "silence everything ringing" signal -- robust no matter how many
        // alarms rang (the phone dismisses every currently-active alarm).
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                Wearable.getMessageClient(this)
                    .sendMessage(node.id, PATH_ALARM_DISMISS_ALL, ByteArray(0))
            }
        }
        // Hand off to the checklist (which shows whatever block(s) are current).
        startActivity(
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        timeoutHandler.removeCallbacksAndMessages(null)
        // Only the current instance stops the vibration, so a stale re-created
        // instance's teardown can't cut a fresh alarm's buzzing short.
        if (active === this) {
            stopVibration()
            active = null
        }
    }

    private fun startVibration() {
        val effect = VibrationEffect.createWaveform(finitePattern(WINDOW_MS), -1)
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

    private fun finitePattern(durationMs: Long): LongArray {
        val out = ArrayList<Long>()
        var total = 0L
        while (total < durationMs) {
            for (v in BASE_PATTERN) {
                out.add(v)
                total += v
            }
        }
        return out.toLongArray()
    }

    companion object {
        private const val PATH_ALARM_DISMISS_ALL = "/alarm_dismiss_all"
        private const val WINDOW_MS = 60_000L
        private val BASE_PATTERN = longArrayOf(0, 600, 400)

        private var active: AlarmActivity? = null

        fun dismissActive() {
            active?.let { it.runOnUiThread { it.finish() } }
        }
    }
}

@Composable
private fun AlarmScreen(names: List<String>, onDismiss: () -> Unit) {
    MaterialTheme {
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            if (names.isNotEmpty()) {
                Text(
                    names.joinToString("\n"),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(bottom = 4.dp),
                )
            }
            Text(
                "지금 시작할 시간이에요",
                textAlign = TextAlign.Center,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 16.dp),
            )
            Button(
                onClick = onDismiss,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("끄기", textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}
