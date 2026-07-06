package com.adhdplanner.adhd_planner

import android.content.Context
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

/// Phone → watch alarm signalling over the Data Layer:
///  - "/alarm_ring": a block alarm just fired -> the watch pops its alarm screen.
///  - "/alarm_stop": the alarm ended on the phone (dismissed/cancelled) -> the
///    watch closes that screen.
/// Best-effort: no watch nearby / not paired just means nothing happens.
object WearAlarmMessenger {
    private const val PATH_RING = "/alarm_ring"
    private const val PATH_STOP = "/alarm_stop"

    fun sendRing(
        context: Context,
        requestCode: Int,
        name: String,
        onComplete: (() -> Unit)? = null,
    ) {
        val json = JSONObject().put("rc", requestCode).put("name", name).toString()
        send(context, PATH_RING, json.toByteArray(), onComplete)
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
