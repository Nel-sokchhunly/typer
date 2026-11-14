package com.chhunly.typer.ime

import android.content.Context
import android.content.res.Configuration
import android.os.Build

/**
 * The Material 3 colour roles the Keyboard draws with (mapping in android/docs/reference.md):
 * background = surface container; letter keys = surface container lowest (light) / highest (dark), as Gboard;
 * function keys = secondary container; the return key with an action = primary. The ខ/EN key is Typer yellow in
 * every theme, the one brand colour on the Keyboard.
 *
 * Android 14+: the system's dynamic colour roles. Android 12-13: the same roles approximated from the system's
 * tonal palettes (the nearest tone). Below 12: a fixed scheme generated from Typer yellow #f5c842 (Material
 * colour utilities, tonal spot), see [yellowLight] / [yellowDark].
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
                Build.VERSION.SDK_INT >= 34 -> system34(context, dark)
                Build.VERSION.SDK_INT >= 31 -> palette31(context, dark)
                else -> if (dark) yellowDark else yellowLight
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

        // Material 3 tonal-spot scheme from seed #f5c842 (@material/material-color-utilities 0.3.0).
        val yellowLight = KeyboardTheme(
            dark = false,
            background = 0xFFF6EDDF.toInt(),  // surfaceContainer
            letterKey = 0xFFFFFFFF.toInt(),  // surfaceContainerLowest
            onLetter = 0xFF1F1B13.toInt(),  // onSurface
            functionKey = 0xFFF2E1BB.toInt(),  // secondaryContainer
            onFunction = 0xFF51462A.toInt(),  // onSecondaryContainer
            action = 0xFF745B0C.toInt(),  // primary
            onAction = 0xFFFFFFFF.toInt(),  // onPrimary
            outlineVariant = 0xFFCFC5B4.toInt(),
            onSurfaceVariant = 0xFF4C4639.toInt(),
            primary = 0xFF745B0C.toInt(),
            popup = 0xFFFFFFFF.toInt(),
        )
        val yellowDark = KeyboardTheme(
            dark = true,
            background = 0xFF231F17.toInt(),  // surfaceContainer
            letterKey = 0xFF39342B.toInt(),  // surfaceContainerHighest
            onLetter = 0xFFEAE1D4.toInt(),
            functionKey = 0xFF51462A.toInt(),
            onFunction = 0xFFF2E1BB.toInt(),
            action = 0xFFE4C36C.toInt(),
            onAction = 0xFF3D2E00.toInt(),
            outlineVariant = 0xFF4C4639.toInt(),
            onSurfaceVariant = 0xFFCFC5B4.toInt(),
            primary = 0xFFE4C36C.toInt(),
            popup = 0xFF39342B.toInt(),
        )
    }
}
