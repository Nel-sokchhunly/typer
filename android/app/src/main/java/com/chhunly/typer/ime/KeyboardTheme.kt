package com.chhunly.typer.ime

import android.content.Context
import android.content.res.Configuration
import android.os.Build

/**
 * The Keyboard's colours. By default Typer's own palette, the same as the iOS app (yellow #f5c842, ink, cream, warm
 * greys), light and dark. With "Match my wallpaper" on (Android 12+, [ThemeChoice]) the Material 3 roles from the
 * phone's dynamic colour instead (mapping in android/docs/reference.md): Android 14+ the system's roles, 12-13 the
 * nearest tones of the system palettes. Either way the ខ/EN key and the top Suggestion are Typer yellow.
 */
class KeyboardTheme(
    val dark: Boolean,
    val background: Int,
    val letterKey: Int,
    val onLetter: Int,
    val functionKey: Int,
    val onFunction: Int,
    val action: Int,
    val onAction: Int,
    val outlineVariant: Int,
    val onSurfaceVariant: Int,
    val primary: Int,
    val popup: Int,
) {
    val mode = 0xFFF5C842.toInt()  // Typer yellow
    val onMode = 0xFF1A1A1A.toInt()

    companion object {
        fun from(context: Context): KeyboardTheme {
            val dark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
            return when {
                !ThemeChoice.materialYou(context) -> if (dark) typerDark else typerLight
                Build.VERSION.SDK_INT >= 34 -> system34(context, dark)
                Build.VERSION.SDK_INT >= 31 -> palette31(context, dark)
                else -> if (dark) typerDark else typerLight
            }
        }

        private fun c(context: Context, id: Int) = context.getColor(id)

        @androidx.annotation.RequiresApi(34)
        private fun system34(ctx: Context, dark: Boolean): KeyboardTheme {
            fun r(light: Int, darkId: Int) = c(ctx, if (dark) darkId else light)
            return KeyboardTheme(
                dark = dark,
                background = r(android.R.color.system_surface_container_light, android.R.color.system_surface_container_dark),
                letterKey = r(android.R.color.system_surface_container_lowest_light, android.R.color.system_surface_container_highest_dark),
                onLetter = r(android.R.color.system_on_surface_light, android.R.color.system_on_surface_dark),
                functionKey = r(android.R.color.system_secondary_container_light, android.R.color.system_secondary_container_dark),
                onFunction = r(android.R.color.system_on_secondary_container_light, android.R.color.system_on_secondary_container_dark),
                action = r(android.R.color.system_primary_light, android.R.color.system_primary_dark),
                onAction = r(android.R.color.system_on_primary_light, android.R.color.system_on_primary_dark),
                outlineVariant = r(android.R.color.system_outline_variant_light, android.R.color.system_outline_variant_dark),
                onSurfaceVariant = r(android.R.color.system_on_surface_variant_light, android.R.color.system_on_surface_variant_dark),
                primary = r(android.R.color.system_primary_light, android.R.color.system_primary_dark),
                popup = r(android.R.color.system_surface_container_lowest_light, android.R.color.system_surface_container_highest_dark),
            )
        }

        /** Tonal palettes: _0 = tone 100, _10 = 99, _50 = 95, _100 = 90, _200 = 80, ... _900 = 10, _1000 = 0. */
        @androidx.annotation.RequiresApi(31)
        private fun palette31(ctx: Context, dark: Boolean): KeyboardTheme {
            return if (!dark) KeyboardTheme(
                dark = false,
                background = c(ctx, android.R.color.system_neutral1_50),
                letterKey = c(ctx, android.R.color.system_neutral1_0),
                onLetter = c(ctx, android.R.color.system_neutral1_900),
                functionKey = c(ctx, android.R.color.system_accent2_100),
                onFunction = c(ctx, android.R.color.system_accent2_900),
                action = c(ctx, android.R.color.system_accent1_600),
                onAction = c(ctx, android.R.color.system_accent1_0),
                outlineVariant = c(ctx, android.R.color.system_neutral2_200),
                onSurfaceVariant = c(ctx, android.R.color.system_neutral2_700),
                primary = c(ctx, android.R.color.system_accent1_600),
                popup = c(ctx, android.R.color.system_neutral1_0),
            ) else KeyboardTheme(
                dark = true,
                background = c(ctx, android.R.color.system_neutral1_900),
                letterKey = c(ctx, android.R.color.system_neutral1_800),
                onLetter = c(ctx, android.R.color.system_neutral1_100),
                functionKey = c(ctx, android.R.color.system_accent2_700),
                onFunction = c(ctx, android.R.color.system_accent2_100),
                action = c(ctx, android.R.color.system_accent1_200),
                onAction = c(ctx, android.R.color.system_accent1_800),
                outlineVariant = c(ctx, android.R.color.system_neutral2_700),
                onSurfaceVariant = c(ctx, android.R.color.system_neutral2_200),
                primary = c(ctx, android.R.color.system_accent1_200),
                popup = c(ctx, android.R.color.system_neutral1_800),
            )
        }

        // Typer's palette, from the iOS app (ios/App/TyperApp.swift): yellow f5c842, ink 1a1a1a, cream edeae3,
        // page f7f5f0 / 1d1c1a, card ffffff / 2a2926, muted 5f5b53 / a8a294; keys a step apart like the iOS Keyboard.
        val typerLight = KeyboardTheme(
            dark = false,
            background = 0xFFEDEAE3.toInt(),  // cream
            letterKey = 0xFFFFFFFF.toInt(),
            onLetter = 0xFF1A1A1A.toInt(),  // ink
            functionKey = 0xFFD8D3C7.toInt(),
            onFunction = 0xFF1A1A1A.toInt(),
            action = 0xFF1A1A1A.toInt(),  // ink, as the iOS app's tint
            onAction = 0xFFEDEAE3.toInt(),
            outlineVariant = 0xFFC9C3B6.toInt(),
            onSurfaceVariant = 0xFF5F5B53.toInt(),  // muted
            primary = 0xFF1A1A1A.toInt(),
            popup = 0xFFFFFFFF.toInt(),
        )
        val typerDark = KeyboardTheme(
            dark = true,
            background = 0xFF1D1C1A.toInt(),  // page
            letterKey = 0xFF57554F.toInt(),
            onLetter = 0xFFF4F1EA.toInt(),
            functionKey = 0xFF353430.toInt(),
            onFunction = 0xFFF4F1EA.toInt(),
            action = 0xFFF5C842.toInt(),  // yellow on dark, as the iOS app's accents
            onAction = 0xFF1A1A1A.toInt(),
            outlineVariant = 0xFF46443F.toInt(),
            onSurfaceVariant = 0xFFA8A294.toInt(),  // muted
            primary = 0xFFF5C842.toInt(),
            popup = 0xFF57554F.toInt(),
        )
    }
}
