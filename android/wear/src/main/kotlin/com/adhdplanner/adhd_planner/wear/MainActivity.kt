package com.adhdplanner.adhd_planner.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material3.CheckboxButton
import androidx.wear.compose.material3.CompactButton
import androidx.wear.compose.material3.ListHeader
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

private const val PATH_TOGGLE = "/toggle_item"
private const val PATH_TOGGLE_REST = "/toggle_rest"

class MainActivity : ComponentActivity(), DataClient.OnDataChangedListener {
    private val data = mutableStateOf(WatchData(emptyList()))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ChecklistScreen(data.value, ::onToggle, ::onToggleRest) }
        loadInitial()
    }

    override fun onResume() {
        super.onResume()
        Wearable.getDataClient(this).addListener(this)
        loadInitial()
    }

    override fun onPause() {
        super.onPause()
        Wearable.getDataClient(this).removeListener(this)
    }

    override fun onDataChanged(events: DataEventBuffer) {
        for (event in events) {
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == PATH_CHECKLIST
            ) {
                // Malformed payload (version skew) -> ignore, never crash.
                try {
                    DataMapItem.fromDataItem(event.dataItem).dataMap
                        .getString("json")
                        ?.let { data.value = ChecklistData.parse(it) }
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun loadInitial() {
        ChecklistData.readLatest(this) { parsed ->
            if (parsed != null) runOnUiThread { data.value = parsed }
        }
    }

    private fun onToggle(segmentId: String, index: Int, checked: Boolean) {
        // Optimistic local update; the phone's Firestore write re-pushes the
        // authoritative state.
        data.value = data.value.copy(
            blocks = data.value.blocks.map { block ->
                block.copy(
                    items = block.items.map { item ->
                        if (item.segmentId == segmentId && item.index == index) {
                            item.copy(checked = checked)
                        } else {
                            item
                        }
                    },
                )
            },
        )
        val payload = JSONObject()
            .put("segmentId", segmentId)
            .put("index", index)
            .put("checked", checked)
            .toString()
            .toByteArray()
        sendToPhone(PATH_TOGGLE, payload)
    }

    private fun onToggleRest(resting: Boolean) {
        // Optimistic; the phone writes it to Firestore (rest days) and re-pushes.
        data.value = data.value.copy(restToday = resting)
        sendToPhone(PATH_TOGGLE_REST, resting.toString().toByteArray())
    }

    private fun sendToPhone(path: String, payload: ByteArray) {
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                Wearable.getMessageClient(this).sendMessage(node.id, path, payload)
            }
        }
    }
}

@androidx.compose.runtime.Composable
fun ChecklistScreen(
    data: WatchData,
    onToggle: (String, Int, Boolean) -> Unit,
    onToggleRest: (Boolean) -> Unit,
) {
    MaterialTheme {
        val listState = rememberScalingLazyListState()
        // No AppScaffold/TimeText: the watch face already shows the time, so a
        // clock inside this quick-glance checklist adds little. ScreenScaffold
        // still gives the M3 position scroll indicator.
        ScreenScaffold(scrollState = listState) { contentPadding ->
            Box(modifier = Modifier.fillMaxSize()) {
                ScalingLazyColumn(
                    state = listState,
                    contentPadding = contentPadding,
                    autoCentering = null, // first item hugs the top, not centred
                    modifier = Modifier.fillMaxSize(),
                ) {
                    // The rest-day toggle is ALWAYS the same item 0 (only its
                    // label flips), so "오늘은 쉬기" and "쉬는 날 해제" sit in the
                    // exact same place. Scrolls with the list.
                    item {
                        // Fixed width so "오늘은 쉬기" and "쉬는 날 해제" (which has
                        // an extra space) render the exact same size.
                        CompactButton(
                            onClick = { onToggleRest(!data.restToday) },
                            modifier = Modifier.width(150.dp),
                        ) {
                            Text(
                                if (data.restToday) "🌙 쉬는 날 해제" else "😴 오늘은 쉬기",
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                    if (!data.restToday) {
                        val current = data.currentBlocks()
                        if (current.isEmpty()) {
                            item {
                                Text(
                                    "지금 진행 중인\n구간이 없어요",
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.fillMaxWidth().padding(8.dp),
                                )
                            }
                        } else {
                            for (block in current) {
                                item { ListHeader { Text(block.name) } }
                                for (item in block.items) {
                                    item {
                                        CheckboxButton(
                                            checked = item.checked,
                                            onCheckedChange = {
                                                onToggle(item.segmentId, item.index, it)
                                            },
                                            label = { Text(item.text) },
                                            modifier = Modifier.fillMaxWidth(),
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                // Rest day: message dead-centre of the whole screen, overlaid so
                // it's independent of the toggle's position above.
                if (data.restToday) {
                    Text(
                        "쉬는 날 😴\n푹 쉬어요",
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.align(Alignment.Center).padding(16.dp),
                    )
                }
            }
        }
    }
}
