package com.adhdplanner.adhd_planner.wear

import android.content.Context
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import java.util.Calendar
import org.json.JSONObject

const val PATH_CHECKLIST = "/today_checklist"

data class WatchItem(
    val segmentId: String,
    val index: Int,
    val text: String,
    val checked: Boolean,
)

data class WatchBlock(
    val blockId: String,
    val name: String,
    val start: Int, // minute-of-day
    val end: Int,
    val items: List<WatchItem>,
) {
    // Mirrors Segment.containsMinute (handles midnight-wrapping ranges).
    fun contains(minute: Int): Boolean {
        if (start == end) return false
        return if (start < end) minute in start until end else minute >= start || minute < end
    }
}

data class WatchData(val blocks: List<WatchBlock>) {
    // Computed from the WATCH's own clock, so it's correct at the exact alarm
    // moment regardless of when the phone last pushed (block times are static).
    fun currentBlocks(nowMinute: Int = nowMinute()): List<WatchBlock> =
        blocks.filter { it.contains(nowMinute) }

    // Blocks whose start IS this minute -- i.e. the ones the alarm is for
    // (an already-running overlapping block isn't starting now).
    fun startingBlocks(nowMinute: Int = nowMinute()): List<WatchBlock> =
        blocks.filter { it.start == nowMinute }
}

fun nowMinute(): Int {
    val c = Calendar.getInstance()
    return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
}

/// Reads/parses the phone-pushed "/today_checklist" Data Layer item.
object ChecklistData {
    fun parse(json: String): WatchData {
        val root = JSONObject(json)
        val blocks = ArrayList<WatchBlock>()
        root.optJSONArray("blocks")?.let { arr ->
            for (i in 0 until arr.length()) {
                val b = arr.getJSONObject(i)
                val items = ArrayList<WatchItem>()
                val itemsArr = b.getJSONArray("items")
                for (j in 0 until itemsArr.length()) {
                    val it = itemsArr.getJSONObject(j)
                    items.add(
                        WatchItem(
                            it.getString("segmentId"),
                            it.getInt("index"),
                            it.getString("text"),
                            it.getBoolean("checked"),
                        ),
                    )
                }
                blocks.add(
                    WatchBlock(
                        b.getString("blockId"),
                        b.getString("name"),
                        b.getInt("start"),
                        b.getInt("end"),
                        items,
                    ),
                )
            }
        }
        return WatchData(blocks)
    }

    fun readLatest(context: Context, onResult: (WatchData?) -> Unit) {
        Wearable.getDataClient(context).dataItems
            .addOnSuccessListener { buffer ->
                var data: WatchData? = null
                for (item in buffer) {
                    if (item.uri.path == PATH_CHECKLIST) {
                        DataMapItem.fromDataItem(item).dataMap
                            .getString("json")
                            ?.let { data = parse(it) }
                    }
                }
                buffer.release()
                onResult(data)
            }
            .addOnFailureListener { onResult(null) }
    }
}
