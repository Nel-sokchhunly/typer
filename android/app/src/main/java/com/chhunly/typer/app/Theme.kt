package com.chhunly.typer.app

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.isSpecified

// Fallback schemes for Android 11 and below, which have no dynamic colour. Generated from Typer
// yellow #f5c842 with @material/material-color-utilities 0.3.0 (tonal spot).
private val LightScheme = lightColorScheme(
    primary = Color(0xFF745B0C),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFFFE08F),
    onPrimaryContainer = Color(0xFF584400),
    secondary = Color(0xFF695D3F),
    onSecondary = Color(0xFFFFFFFF),
    secondaryContainer = Color(0xFFF2E1BB),
    onSecondaryContainer = Color(0xFF51462A),
    tertiary = Color(0xFF47664A),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFC9ECC8),
    onTertiaryContainer = Color(0xFF304D33),
    error = Color(0xFFBA1A1A),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFFDAD6),
    onErrorContainer = Color(0xFF93000A),
    background = Color(0xFFFFF8F1),
    onBackground = Color(0xFF1F1B13),
    surface = Color(0xFFFFF8F1),
    onSurface = Color(0xFF1F1B13),
    surfaceVariant = Color(0xFFECE1CF),
    onSurfaceVariant = Color(0xFF4C4639),
    outline = Color(0xFF7E7667),
    outlineVariant = Color(0xFFCFC5B4),
    inverseSurface = Color(0xFF343027),
    inverseOnSurface = Color(0xFFF8F0E2),
    inversePrimary = Color(0xFFE4C36C),
    surfaceDim = Color(0xFFE1D9CC),
    surfaceBright = Color(0xFFFFF8F1),
    surfaceContainerLowest = Color(0xFFFFFFFF),
    surfaceContainerLow = Color(0xFFFBF2E5),
    surfaceContainer = Color(0xFFF6EDDF),
    surfaceContainerHigh = Color(0xFFF0E7D9),
    surfaceContainerHighest = Color(0xFFEAE1D4),
    scrim = Color(0xFF000000),
    surfaceTint = Color(0xFF745B0C),
)

private val DarkScheme = darkColorScheme(
    primary = Color(0xFFE4C36C),
    onPrimary = Color(0xFF3D2E00),
    primaryContainer = Color(0xFF584400),
    onPrimaryContainer = Color(0xFFFFE08F),
    secondary = Color(0xFFD5C5A0),
    onSecondary = Color(0xFF392F15),
    secondaryContainer = Color(0xFF51462A),
    onSecondaryContainer = Color(0xFFF2E1BB),
    tertiary = Color(0xFFADCFAD),
    onTertiary = Color(0xFF1A361E),
    tertiaryContainer = Color(0xFF304D33),
    onTertiaryContainer = Color(0xFFC9ECC8),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
    errorContainer = Color(0xFF93000A),
    onErrorContainer = Color(0xFFFFDAD6),
    background = Color(0xFF16130B),
    onBackground = Color(0xFFEAE1D4),
    surface = Color(0xFF16130B),
    onSurface = Color(0xFFEAE1D4),
    surfaceVariant = Color(0xFF4C4639),
    onSurfaceVariant = Color(0xFFCFC5B4),
    outline = Color(0xFF989080),
    outlineVariant = Color(0xFF4C4639),
    inverseSurface = Color(0xFFEAE1D4),
    inverseOnSurface = Color(0xFF343027),
    inversePrimary = Color(0xFF745B0C),
    surfaceDim = Color(0xFF16130B),
    surfaceBright = Color(0xFF3D392F),
    surfaceContainerLowest = Color(0xFF110E07),
    surfaceContainerLow = Color(0xFF1F1B13),
    surfaceContainer = Color(0xFF231F17),
    surfaceContainerHigh = Color(0xFF2E2A21),
    surfaceContainerHighest = Color(0xFF39342B),
    scrim = Color(0xFF000000),
    surfaceTint = Color(0xFFE4C36C),
)

/**
 * Material 3 with dynamic colour on Android 12+, following the system dark setting. [khmer] loosens every
 * text style to 1.6x line height, because Khmer stacks vowels and subscripts above and below the line.
 */
@Composable
fun TyperTheme(khmer: Boolean, content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val context = LocalContext.current
    val colors = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
            if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        dark -> DarkScheme
        else -> LightScheme
    }
    val base = Typography()
    MaterialTheme(colorScheme = colors, typography = if (khmer) base.forKhmer() else base, content = content)
}

private fun TextStyle.airy(): TextStyle {
    val target = fontSize * 1.6f
    return if (lineHeight.isSpecified && lineHeight > target) this else copy(lineHeight = target)
}

private fun Typography.forKhmer() = copy(
    displayLarge = displayLarge.airy(), displayMedium = displayMedium.airy(), displaySmall = displaySmall.airy(),
    headlineLarge = headlineLarge.airy(), headlineMedium = headlineMedium.airy(), headlineSmall = headlineSmall.airy(),
    titleLarge = titleLarge.airy(), titleMedium = titleMedium.airy(), titleSmall = titleSmall.airy(),
    bodyLarge = bodyLarge.airy(), bodyMedium = bodyMedium.airy(), bodySmall = bodySmall.airy(),
    labelLarge = labelLarge.airy(), labelMedium = labelMedium.airy(), labelSmall = labelSmall.airy(),
)
