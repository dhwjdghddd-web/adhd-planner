package com.adhdplanner.adhd_planner.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.ToggleChip
import androidx.wear.compose.material.ToggleChipDefaults
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

private const val PATH_TOGGLE = "/toggle_item"

class MainActivity : ComponentActivity(), DataClient.OnDataChangedListener {
    private val data = mutableStateOf(WatchData(emptyList()))

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { ChecklistScreen(data.value, ::onToggle) }
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
                DataMapItem.fromDataItem(event.dataItem).dataMap
                    .getString("json")
                    ?.let { data.value = ChecklistData.parse(it) }
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
        Wearable.getNodeClient(this).connectedNodes.addOnSuccessListener { nodes ->
            for (node in nodes) {
                Wearable.getMessageClient(this)
                    .sendMessage(node.id, PATH_TOGGLE, payload)
            }
        }
    }
}

@androidx.compose.runtime.Composable
fun ChecklistScreen(
    data: WatchData,
    onToggle: (String, Int, Boolean) -> Unit,
) {
    // The block(s) in progress right now -- one, or several when they overlap.
    val current = data.currentBlocks()
    ScalingLazyColumn {
        if (current.isEmpty()) {
            item {
                Text(
                    "지금 진행 중인\n구간이 없어요",
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                )
            }
        } else {
            for (block in current) {
                item {
                    Text(
                        block.name,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp),
                    )
                }
                for (item in block.items) {
                    item {
                        ToggleChip(
                            checked = item.checked,
                            onCheckedChange = { onToggle(item.segmentId, item.index, it) },
                            label = { Text(item.text) },
                            toggleControl = {
                                ToggleChipDefaults.checkboxIcon(checked = item.checked)
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                }
            }
        }
    }
}
