package com.fitnessapp.wear.data

import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Mirror of the phone-side `WearWorkoutState`.
 * The data-layer service on the watch translates incoming JSON envelopes
 * into this shape.
 */
data class WatchWorkoutState(
    val title: String,
    val setNumber: Int,
    val totalSets: Int,
    val suggestedKg: Double?,
    val restRemainingSeconds: Int,
    val isResting: Boolean,
)

object WearStateRepository {
    private val _state = MutableStateFlow<WatchWorkoutState?>(null)
    val flow: StateFlow<WatchWorkoutState?> get() = _state

    fun update(s: WatchWorkoutState) {
        _state.value = s
    }
}

@androidx.compose.runtime.Composable
fun StateFlow<WatchWorkoutState?>.collectAsStateOrNull(): State<WatchWorkoutState?> =
    collectAsState(initial = null)
