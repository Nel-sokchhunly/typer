package com.chhunly.typer.ime

import android.content.Context
import android.os.Build

/**
 * The Keyboard's theme, picked in the Companion app as on Gboard: Typer (cream and yellow, like the iOS app; the
 * default), Material You (the phone's wallpaper colours, Gboard's default on Pixel; Android 12+), or plain Light or
 * Dark (Gboard's grey keys with blue accents). Typer and Material You follow the phone's light or dark setting;
 * Light and Dark stay as they are. The Keyboard reads it each time it opens.
 */
enum class ThemeChoice {
    TYPER, MATERIAL_YOU, LIGHT, DARK;

    companion object {
        private const val PREFS = "typer_keyboard"
        private const val KEY = "theme"
        private const val OLD_KEY = "material_you"  // the earlier "Match my wallpaper" switch

        /** Whether this phone has wallpaper colours to offer. */
        val available: Boolean get() = Build.VERSION.SDK_INT >= 31

        /** The themes this phone can show, in the order the Companion app lists them. */
        val offered: List<ThemeChoice> get() = entries.filter { it != MATERIAL_YOU || available }

        fun get(context: Context): ThemeChoice {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val chosen = prefs.getString(KEY, null)?.let { n -> entries.firstOrNull { it.name == n } }
                ?: if (prefs.getBoolean(OLD_KEY, false)) MATERIAL_YOU else TYPER
            return if (chosen == MATERIAL_YOU && !available) TYPER else chosen
        }

        fun set(context: Context, choice: ThemeChoice) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice.name).apply()
        }
    }
}
