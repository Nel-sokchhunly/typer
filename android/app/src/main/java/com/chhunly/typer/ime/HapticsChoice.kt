package com.chhunly.typer.ime

import android.content.Context

/**
 * Key vibration: follow the phone's touch-feedback setting (the default), off, or a fixed light or strong tap.
 * The Companion app sets it; the Keyboard reads it each time it opens.
 */
enum class HapticsChoice {
    SYSTEM, OFF, LIGHT, STRONG;

    companion object {
        private const val PREFS = "typer_keyboard"
        private const val KEY = "haptics"

        fun get(context: Context): HapticsChoice {
            val name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            return entries.firstOrNull { it.name == name } ?: SYSTEM
        }

        fun set(context: Context, choice: HapticsChoice) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice.name).apply()
        }
    }
}
