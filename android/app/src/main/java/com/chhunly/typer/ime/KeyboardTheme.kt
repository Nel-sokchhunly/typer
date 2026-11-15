package com.chhunly.typer.ime

import android.content.Context
import android.content.res.Configuration
import android.os.Build

/**
 * The Keyboard's colours, from the [ThemeChoice]. Typer: Typer's own palette, the same as the iOS app (yellow
 * #f5c842, ink, cream, warm greys), light and dark. Material You (Android 12+): the Material 3 roles from the phone's
 * dynamic colour (mapping in android/docs/reference.md): Android 14+ the system's roles, 12-13 the nearest tones of
 * the system palettes. Light and Dark: plain grey keys with blue accents, like Gboard's own Light and Dark themes.
 * `mode`: the ខ/EN key, the top Suggestion and the glide trail (Typer yellow only in the Typer theme); `layout`: the
 * bar's កខគ / abc switch (ink with yellow in the Typer theme).
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
    val mode: Int = 0xFFF5C842.toInt(),  // Typer yellow
    val onMode: Int = 0xFF1A1A1A.toInt(),
    val layout: Int = 0xFF1A1A1A.toInt(),  // ink
    val onLayout: Int = 0xFFF5C842.toInt(),
) {

    companion object {
        fun from(context: Context): KeyboardTheme {
            val dark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                Configuration.UI_MODE_NIGHT_YES
            return when (ThemeChoice.get(context)) {
                ThemeChoice.TYPER -> if (dark) typerDark else typerLight
                ThemeChoice.LIGHT -> plainLight
                ThemeChoice.DARK -> plainDark
                ThemeChoice.MATERIAL_YOU -> when {
                    Build.VERSION.SDK_INT >= 34 -> system34(context, dark)
                    Build.VERSION.SDK_INT >= 31 -> palette31(context, dark)
                    else -> if (dark) typerDark else typerLight
                }
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
                mode = r(android.R.color.system_primary_container_light, android.R.color.system_primary_container_dark),
                onMode = r(android.R.color.system_on_primary_container_light, android.R.color.system_on_primary_container_dark),
                layout = r(android.R.color.system_primary_light, android.R.color.system_primary_dark),
                onLayout = r(android.R.color.system_on_primary_light, android.R.color.system_on_primary_dark),
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
                mode = c(ctx, android.R.color.system_accent1_100),
                onMode = c(ctx, android.R.color.system_accent1_900),
                layout = c(ctx, android.R.color.system_accent1_600),
                onLayout = c(ctx, android.R.color.system_accent1_0),
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
                mode = c(ctx, android.R.color.system_accent1_700),
                onMode = c(ctx, android.R.color.system_accent1_100),
                layout = c(ctx, android.R.color.system_accent1_200),
                onLayout = c(ctx, android.R.color.system_accent1_800),
            )
        }

        // Plain Light and Dark, like Gboard's own: neutral greys, Google-blue accents (Material 3 baseline tones).
        val plainLight = KeyboardTheme(
            dark = false,
            background = 0xFFE8EAED.toInt(),
            letterKey = 0xFFFFFFFF.toInt(),
            onLetter = 0xFF1F1F1F.toInt(),
            functionKey = 0xFFD3D6DB.toInt(),
            onFunction = 0xFF1F1F1F.toInt(),
            action = 0xFF0B57D0.toInt(),
            onAction = 0xFFFFFFFF.toInt(),
            outlineVariant = 0xFFC4C7C5.toInt(),
            onSurfaceVariant = 0xFF444746.toInt(),
            primary = 0xFF0B57D0.toInt(),
            popup = 0xFFFFFFFF.toInt(),
            mode = 0xFFD3E3FD.toInt(),
            onMode = 0xFF041E49.toInt(),
            layout = 0xFF0B57D0.toInt(),
            onLayout = 0xFFFFFFFF.toInt(),
        )
        val plainDark = KeyboardTheme(
            dark = true,
            background = 0xFF1F1F1F.toInt(),
            letterKey = 0xFF3C3C3C.toInt(),
            onLetter = 0xFFE3E3E3.toInt(),
            functionKey = 0xFF2B2B2B.toInt(),
            onFunction = 0xFFE3E3E3.toInt(),
            action = 0xFFA8C7FA.toInt(),
            onAction = 0xFF062E6F.toInt(),
            outlineVariant = 0xFF444746.toInt(),
            onSurfaceVariant = 0xFFC4C7C5.toInt(),
            primary = 0xFFA8C7FA.toInt(),
            popup = 0xFF3C3C3C.toInt(),
            mode = 0xFF0842A0.toInt(),
            onMode = 0xFFD3E3FD.toInt(),
            layout = 0xFFA8C7FA.toInt(),
            onLayout = 0xFF062E6F.toInt(),
        )

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
