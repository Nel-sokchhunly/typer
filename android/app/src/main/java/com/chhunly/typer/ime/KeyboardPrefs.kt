package com.chhunly.typer.ime

import android.content.Context

/**
 * The Keyboard's simple switches, set in the Companion app and read by the Keyboard each time it opens:
 * auto-capitalisation and double-space for a period (English mode), key sound, a number row above the letters, and
 * the keyboard's height.
 */
object KeyboardPrefs {
    private const val PREFS = "typer_keyboard"

    enum class Height(val scale: Float) { SHORT(0.88f), NORMAL(1f), TALL(1.12f) }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun flag(c: Context, key: String, default: Boolean) = prefs(c).getBoolean(key, default)
    private fun set(c: Context, key: String, on: Boolean) = prefs(c).edit().putBoolean(key, on).apply()

    fun autoCap(c: Context) = flag(c, "auto_cap", true)
    fun setAutoCap(c: Context, on: Boolean) = set(c, "auto_cap", on)
    fun doubleSpace(c: Context) = flag(c, "double_space", true)
    fun setDoubleSpace(c: Context, on: Boolean) = set(c, "double_space", on)
    fun keySound(c: Context) = flag(c, "key_sound", false)
    fun setKeySound(c: Context, on: Boolean) = set(c, "key_sound", on)
    fun numberRow(c: Context) = flag(c, "number_row", false)
    fun setNumberRow(c: Context, on: Boolean) = set(c, "number_row", on)

    fun height(c: Context): Height = prefs(c).getString("height", null)?.let { n -> Height.entries.firstOrNull { it.name == n } } ?: Height.NORMAL
    fun setHeight(c: Context, h: Height) = prefs(c).edit().putString("height", h.name).apply()
}
