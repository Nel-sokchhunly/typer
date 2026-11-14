package com.chhunly.typer.ime

import android.content.Context

/**
 * The font for Typer's text: Kantumruy Pro, Typer's own (the default), or the phone's system font. The Companion
 * app sets it and uses it itself; the Keyboard reads it each time it opens.
 */
enum class FontChoice {
    TYPER, SYSTEM;

    companion object {
        private const val PREFS = "typer_keyboard"
        private const val KEY = "font"

        fun get(context: Context): FontChoice {
            val name = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            return entries.firstOrNull { it.name == name } ?: TYPER
        }

        fun set(context: Context, choice: FontChoice) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice.name).apply()
        }
    }
}
