package com.adhdplanner.adhd_planner

import android.content.Context
import com.google.android.gms.wearable.Wearable

/// Phone → watch alarm signalling over the Data Layer:
///  - "/alarm_ring": a block alarm just fired -> the watch pops its alarm screen
///    (which reads the ringing block names from the synced checklist, so the
///    message itself carries no payload).
///  - "/alarm_stop": the alarm ended on the phone (dismissed/cancelled) -> the
///    watch closes that screen.
/// Best-effort fire-and-forget: MessageClient doesn't queue for a disconnected
/// node, so a watch out of range at the alarm moment simply doesn't ring --
/// a known, accepted limitation (the phone alarm is the primary).
object WearAlarmMessenger {
    private const val PATH_RING = "/alarm_ring"
    private const val PATH_STOP = "/alarm_stop"

    fun sendRing(
        context: Context,
        amplitude: Int = 255,
        pattern: LongArray? = null,
        onComplete: (() -> Unit)? = null,
    ) {
        val json = org.json.JSONObject().apply {
            put("amplitude", amplitude)
            pattern?.let {
                val arr = org.json.JSONArray()
                for (v in it) arr.put(v)
                put("pattern", arr)
            }
        }
        send(context, PATH_RING, json.toString().toByteArray(), onComplete)
    }

    fun sendStop(context: Context, onComplete: (() -> Unit)? = null) =
        send(context, PATH_STOP, ByteArray(0), onComplete)

    private fun send(
        context: Context,
        path: String,
        data: ByteArray,
        onComplete: (() -> Unit)?,
    ) {
        val ctx = context.applicationContext
        val messageClient = Wearable.getMessageClient(ctx)
        Wearable.getNodeClient(ctx).connectedNodes
            .addOnSuccessListener { nodes ->
                if (nodes.isEmpty()) {
                    onComplete?.invoke()
                    return@addOnSuccessListener
                }
                var remaining = nodes.size
                for (node in nodes) {
                    messageClient.sendMessage(node.id, path, data)
                        .addOnCompleteListener {
                            if (--remaining == 0) onComplete?.invoke()
                        }
                }
            }
            .addOnFailureListener { onComplete?.invoke() }
    }
}
