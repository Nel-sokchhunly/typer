package com.chhunly.typer.app

import com.chhunly.typer.ime.FontChoice
import androidx.compose.runtime.CompositionLocalProvider
import android.content.Context
import android.os.Bundle
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue

/** The Companion app: one screen that explains how to turn on the Keyboard, and a field to try it in. */
/** Changes the font choice everywhere at once: saved for the Keyboard, applied to this screen now. */
val LocalSetFont = androidx.compose.runtime.staticCompositionLocalOf<(FontChoice) -> Unit> { {} }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The yellow hero sits under the status bar in both light and dark, so its icons are always dark.
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT))
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        setContent {
            var khmer by remember { mutableStateOf(prefs.getBoolean(KEY_KHMER, true)) }
            var font by remember { mutableStateOf(FontChoice.get(this)) }
            TyperTheme(khmer, systemFont = font == FontChoice.SYSTEM) {
                CompositionLocalProvider(LocalSetFont provides { choice: FontChoice -> font = choice; FontChoice.set(this, choice) }) {
                    CompanionScreen(khmer) {
                        khmer = it
                        prefs.edit().putBoolean(KEY_KHMER, it).apply()
                    }
                }
            }
        }
    }

    private companion object {
        const val PREFS = "typer_app"
        const val KEY_KHMER = "khmer"
    }
}
