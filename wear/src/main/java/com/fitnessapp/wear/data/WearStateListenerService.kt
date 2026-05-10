package com.fitnessapp.wear.data

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/**
 * Receives `/workout_state` messages from the phone APK and translates
 * them into the in-process [WearStateRepository].
 *
 * The phone side encodes via `MethodChannelWearSyncService.pushState`
 * (jsonEncode of WearWorkoutState.toMessage()).
 */
class WearStateListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != "/workout_state") return
        val raw = String(event.data, Charsets.UTF_8)
        val obj = runCatching { JSONObject(raw) }.getOrNull() ?: return
        WearStateRepository.update(
            WatchWorkoutState(
                title = obj.optString("title", "Workout"),
                setNumber = obj.optInt("set", 1),
                totalSets = obj.optInt("totalSets", 1),
                suggestedKg = if (obj.has("kg")) obj.optDouble("kg") else null,
                restRemainingSeconds = obj.optInt("rest", 0),
                isResting = obj.optBoolean("isResting", false),
            )
        )
    }
}
