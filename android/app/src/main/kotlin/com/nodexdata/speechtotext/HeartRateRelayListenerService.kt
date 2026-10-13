package com.nodexdata.speechtotext

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives heart-rate sessions the watch app relays over Bluetooth via the
 * Wear OS Data Layer (see throughline_watch_app's MainActivity.kt,
 * relayHeartRateViaBluetooth) -- only used when the watch's direct API sync
 * fails (no network of its own). Forwards each session to the backend
 * using NativeAuthStore's own cached auth, so this works even if the
 * Flutter engine isn't running, matching how CallConnection.onReject
 * already calls declineCall() natively.
 */
class HeartRateRelayListenerService : WearableListenerService() {
    private val relayPathPrefix = "/throughline/heart-rate-relay/"

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        for (event in dataEvents) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            val uri = event.dataItem.uri
            if (uri.path?.startsWith(relayPathPrefix) != true) continue

            val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
            val sessionJson = dataMap.getString("session_json") ?: continue
            NativeAuthStore.postJson(applicationContext, "/health/heart-rate", sessionJson)
        }
    }
}
