package com.fitnessapp.fitness_app

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Phone-side MainActivity. Hosts the `fitnessapp/wear_sync` MethodChannel
 * the Flutter side speaks to. Methods:
 *   - isPaired(): Bool
 *   - pushState(jsonString: String): Bool
 *
 * The wearable Data Layer transfers happen via MessageClient.sendMessage
 * to every connected node — usually one paired watch.
 *
 * Extends FlutterFragmentActivity (NOT FlutterActivity): the `health`
 * plugin's Health Connect permission flow uses registerForActivityResult,
 * which needs an androidx FragmentActivity host — with plain
 * FlutterActivity the permission request silently no-ops (health 11.1.1
 * README, "Android 14" section).
 */
class MainActivity: FlutterFragmentActivity() {

    companion object {
        const val CHANNEL = "fitnessapp/wear_sync"
        const val PATH_WORKOUT_STATE = "/workout_state"
        private const val TAG = "WearSync"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPaired" -> {
                        runOffMainThread(result) { connectedNodeIds(this).isNotEmpty() }
                    }
                    "pushState" -> {
                        val json = call.arguments as? String
                        if (json == null) {
                            result.error("ARG", "Expected JSON string", null)
                            return@setMethodCallHandler
                        }
                        runOffMainThread(result) {
                            val nodes = connectedNodeIds(this)
                            val client = Wearable.getMessageClient(this)
                            val payload = json.toByteArray(Charsets.UTF_8)
                            // Success is reported only after every send task completes.
                            val sends = nodes.map { client.sendMessage(it, PATH_WORKOUT_STATE, payload) }
                            for (send in sends) Tasks.await(send)
                            nodes.isNotEmpty()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    // Tasks.await throws on the main thread, so all Data Layer work runs here.
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    private fun runOffMainThread(result: MethodChannel.Result, work: () -> Any?) {
        try {
            executor.execute {
                try {
                    val value = work()
                    runOnUiThread { result.success(value) }
                } catch (e: Exception) {
                    Log.e(TAG, "Wear sync failed", e)
                    runOnUiThread { result.error("WEAR", e.localizedMessage ?: e.toString(), null) }
                }
            }
        } catch (e: RejectedExecutionException) {
            result.error("WEAR", "Wear sync executor is shut down", null)
        }
    }

    /**
     * Fetches the connected wear nodes. Must be called off the main thread.
     * An empty list means "no connected watch"; a failed lookup throws.
     */
    private fun connectedNodeIds(context: Context): List<String> {
        return try {
            Tasks.await(Wearable.getNodeClient(context).connectedNodes).map { it.id }
        } catch (e: Exception) {
            Log.e(TAG, "Connected node lookup failed", e)
            throw e
        }
    }
}
