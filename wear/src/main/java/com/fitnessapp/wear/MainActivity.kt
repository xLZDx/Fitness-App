package com.fitnessapp.wear

import android.app.Activity
import android.os.Bundle
import androidx.activity.compose.setContent
import com.fitnessapp.wear.data.WearStateRepository
import com.fitnessapp.wear.ui.WatchFace

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WatchFace(state = WearStateRepository.flow.collectAsStateOrNull())
        }
    }
}
