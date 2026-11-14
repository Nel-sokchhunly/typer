package com.chhunly.typer.app

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.LineHeightStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.isSpecified
import androidx.compose.ui.unit.sp
import com.chhunly.typer.R

// Typer's palette, the same as the iOS Companion app: the app icon's ink and cream, and the yellow of the
// mode key. Page, card and muted follow light and dark.
val TyperYellow = Color(0xFFF5C842)
val TyperInk = Color(0xFF1A1A1A)
val TyperCream = Color(0xFFEDEAE3)

private val PageLight = Color(0xFFF7F5F0)
private val PageDark = Color(0xFF1D1C1A)
private val CardLight = Color(0xFFFFFFFF)
private val CardDark = Color(0xFF2A2926)
private val MutedLight = Color(0xFF5F5B53)
private val MutedDark = Color(0xFFA8A294)

/** Kantumruy Pro, one variable font (axis wght 100-700) with the four weights the app uses. */
@OptIn(ExperimentalTextApi::class)
val KantumruyPro = FontFamily(
    listOf(
        FontWeight.Normal to 400,
        FontWeight.Medium to 500,
        FontWeight.SemiBold to 600,
        FontWeight.Bold to 700,
    ).map { (weight, value) ->
        Font(R.font.kantumruy_pro, weight = weight, variationSettings = FontVariation.Settings(FontVariation.weight(value)))
    },
)

// Material 3 mapped onto the Typer palette (no dynamic colour in the app itself): page = background,
// card = surface, muted = onSurfaceVariant, ink and cream = inverse colours (the privacy card).
private val LightScheme = lightColorScheme(
    primary = TyperYellow,
    onPrimary = TyperInk,
    primaryContainer = TyperYellow,
    onPrimaryContainer = TyperInk,
    secondary = TyperInk,
    onSecondary = TyperCream,
    background = PageLight,
    onBackground = TyperInk,
    surface = CardLight,
    onSurface = TyperInk,
    surfaceVariant = Color(0x14000000),
    onSurfaceVariant = MutedLight,
    outline = MutedLight,
    outlineVariant = Color(0x1F000000),
    inverseSurface = TyperInk,
    inverseOnSurface = TyperCream,
    inversePrimary = TyperYellow,
)

private val DarkScheme = darkColorScheme(
    primary = TyperYellow,
    onPrimary = TyperInk,
    primaryContainer = TyperYellow,
    onPrimaryContainer = TyperInk,
    secondary = TyperYellow,
    onSecondary = TyperInk,
    background = PageDark,
    onBackground = TyperCream,
    surface = CardDark,
    onSurface = TyperCream,
    surfaceVariant = Color(0x14FFFFFF),
    onSurfaceVariant = MutedDark,
    outline = MutedDark,
    outlineVariant = Color(0x1FFFFFFF),
    inverseSurface = TyperInk,
    inverseOnSurface = TyperCream,
    inversePrimary = TyperYellow,
)

/** Whether the app is showing Khmer, which stacks vowels and subscripts above and below the line. */
val LocalKhmer = compositionLocalOf { true }

/**
 * The Typer palette (light and dark, following the system) and Kantumruy Pro for all text. [khmer] loosens
 * every text style to 1.6x line height.
 */
@Composable
fun TyperTheme(khmer: Boolean, content: @Composable () -> Unit) {
    val colors = if (isSystemInDarkTheme()) DarkScheme else LightScheme
    val base = Typography().withFont()
    MaterialTheme(colorScheme = colors, typography = if (khmer) base.forKhmer() else base) {
        CompositionLocalProvider(LocalKhmer provides khmer, LocalContentColor provides colors.onSurface, content = content)
    }
}

private fun TextStyle.font() = copy(fontFamily = KantumruyPro)

private fun TextStyle.airy(): TextStyle {
    val target = fontSize * 1.6f
    return if (lineHeight.isSpecified && lineHeight > target) this else copy(lineHeight = target)
}

private fun Typography.withFont() = copy(
    displayLarge = displayLarge.font(), displayMedium = displayMedium.font(), displaySmall = displaySmall.font(),
    headlineLarge = headlineLarge.font(), headlineMedium = headlineMedium.font(), headlineSmall = headlineSmall.font(),
    titleLarge = titleLarge.font(), titleMedium = titleMedium.font(), titleSmall = titleSmall.font(),
    bodyLarge = bodyLarge.font(), bodyMedium = bodyMedium.font(), bodySmall = bodySmall.font(),
    labelLarge = labelLarge.font(), labelMedium = labelMedium.font(), labelSmall = labelSmall.font(),
)

private fun Typography.forKhmer() = copy(
    displayLarge = displayLarge.airy(), displayMedium = displayMedium.airy(), displaySmall = displaySmall.airy(),
    headlineLarge = headlineLarge.airy(), headlineMedium = headlineMedium.airy(), headlineSmall = headlineSmall.airy(),
    titleLarge = titleLarge.airy(), titleMedium = titleMedium.airy(), titleSmall = titleSmall.airy(),
    bodyLarge = bodyLarge.airy(), bodyMedium = bodyMedium.airy(), bodySmall = bodySmall.airy(),
    labelLarge = labelLarge.airy(), labelMedium = labelMedium.airy(), labelSmall = labelSmall.airy(),
)

/**
 * The app's text: Kantumruy Pro at an exact size, with Khmer's generous line height (1.6x, or [khmerLine] for
 * big type) and the Latin's tighter one. [tracking] only applies to Latin: letter spacing pulls Khmer's
 * combining marks off their base letters.
 */
@Composable
fun Txt(
    text: String,
    size: Int,
    modifier: Modifier = Modifier,
    weight: FontWeight = FontWeight.Normal,
    color: Color = Color.Unspecified,
    khmerLine: Float = 1.6f,
    tracking: TextUnit = TextUnit.Unspecified,
    family: FontFamily = KantumruyPro,
    textAlign: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    val khmer = LocalKhmer.current
    Text(
        text,
        modifier,
        color = color,
        fontSize = size.sp,
        fontWeight = weight,
        fontFamily = family,
        letterSpacing = if (khmer) TextUnit.Unspecified else tracking,
        textAlign = textAlign,
        maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
        style = TextStyle(
            lineHeight = (size * if (khmer) khmerLine else 1.3f).sp,
            lineHeightStyle = LineHeightStyle(LineHeightStyle.Alignment.Center, LineHeightStyle.Trim.None),
            platformStyle = PlatformTextStyle(includeFontPadding = false),
        ),
    )
}
