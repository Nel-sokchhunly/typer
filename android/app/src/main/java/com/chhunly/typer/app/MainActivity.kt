package com.chhunly.typer.app

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/** The Companion app: one screen that explains how to turn on the Keyboard, and a field to try it in. */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        setContent {
            var khmer by remember { mutableStateOf(prefs.getBoolean(KEY_KHMER, true)) }
            TyperTheme(khmer) {
                CompanionScreen(khmer) {
                    khmer = it
                    prefs.edit().putBoolean(KEY_KHMER, it).apply()
                }
            }
        }
    }

    private companion object {
        const val PREFS = "typer_app"
        const val KEY_KHMER = "khmer"
    }
}
