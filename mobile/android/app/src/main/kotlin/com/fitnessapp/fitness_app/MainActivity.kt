package com.fitnessapp.fitness_app

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Phone-side MainActivity. Hosts the `fitnessapp/wear_sync` MethodChannel
 * the Flutter side speaks to. Methods:
 *   - isPaired(): Bool
 *   - pushState(jsonString: String): Bool
 *
 * The wearable Data Layer transfers happen via MessageClient.sendMessage
 * to every connected node — usually one paired watch.
 */
class MainActivity: FlutterActivity() {

    companion object {
        const val CHANNEL = "fitnessapp/wear_sync"
        const val PATH_WORKOUT_STATE = "/workout_state"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPaired" -> {
                        result.success(connectedNodeIds(this).isNotEmpty())
                    }
                    "pushState" -> {
                        val json = call.arguments as? String
                        if (json == null) {
                            result.error("ARG", "Expected JSON string", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val nodes = connectedNodeIds(this)
                            val client = Wearable.getMessageClient(this)
                            val payload = json.toByteArray(Charsets.UTF_8)
                            for (node in nodes) {
                                client.sendMessage(node, PATH_WORKOUT_STATE, payload)
                            }
                            result.success(nodes.isNotEmpty())
                        } catch (e: Exception) {
                            result.error("WEAR", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Synchronously fetches the list of connected wear nodes. We block
     * briefly because the MethodChannel is invoked on the Flutter
     * platform thread; the Tasks API uses Google Play services so the
     * await is fast even on cold cache.
     */
    private fun connectedNodeIds(context: Context): List<String> {
        return try {
            val nodes = Tasks.await(Wearable.getNodeClient(context).connectedNodes)
            nodes.map { it.id }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
