package com.fitnessapp.wear.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.fitnessapp.wear.data.WatchWorkoutState

/**
 * Minimal watch face. Three lines + a Done button.
 * Designed to fit on a circular 44mm face with no scrolling.
 */
@Composable
fun WatchFace(state: State<WatchWorkoutState?>) {
    val s = state.value
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (s == null) {
            Text(
                "Open the workout on your phone to start.",
                style = MaterialTheme.typography.body2,
            )
            return@Column
        }

        Text(
            s.title,
            style = MaterialTheme.typography.title2,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "Set ${s.setNumber} of ${s.totalSets}" +
                (s.suggestedKg?.let { "  ·  ${it.toInt()} kg" } ?: ""),
            style = MaterialTheme.typography.body2,
        )
        Spacer(Modifier.height(12.dp))

        if (s.isResting) {
            Text(
                "Rest ${s.restRemainingSeconds}s",
                style = MaterialTheme.typography.title3,
            )
        } else {
            Button(
                onClick = { /* TODO: send `done_set` back over data layer */ },
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape),
            ) {
                Text("Done", style = MaterialTheme.typography.button)
            }
        }
    }
}
