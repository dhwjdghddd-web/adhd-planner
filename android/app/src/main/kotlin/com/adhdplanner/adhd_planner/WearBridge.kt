package com.adhdplanner.adhd_planner

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable

/// Phone → watch: publishes today's checklist onto the Wearable Data Layer so
/// the watch companion can render it. The watch reads the same "/today_checklist"
/// DataItem (see the wear module). A changing "ts" guarantees each push is a
/// distinct DataItem so the watch's listener always fires.
object WearBridge {
    private const val PATH_CHECKLIST = "/today_checklist"

    fun pushChecklist(context: Context, json: String) {
        val request = PutDataMapRequest.create(PATH_CHECKLIST).apply {
            dataMap.putString("json", json)
            dataMap.putLong("ts", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(context.applicationContext).putDataItem(request)
    }
}
