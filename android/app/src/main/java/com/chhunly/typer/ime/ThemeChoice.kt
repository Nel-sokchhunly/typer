package com.chhunly.typer.ime

import android.content.Context
import android.os.Build

/**
 * The Keyboard's colours: Typer yellow (the default, the same palette as the iOS app) or the phone's wallpaper
 * colours (Material You), which only Android 12+ offers. The Companion app sets it; the Keyboard reads it each time
 * it opens. Both run in this app's process, so a plain SharedPreferences file is enough.
 */
object ThemeChoice {
    private const val PREFS = "typer_keyboard"
    private const val KEY = "material_you"

    /** Whether this phone has wallpaper colours to offer. */
    val available: Boolean get() = Build.VERSION.SDK_INT >= 31

    fun materialYou(context: Context): Boolean =
        available && context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setMaterialYou(context: Context, on: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY, on).apply()
    }
}
