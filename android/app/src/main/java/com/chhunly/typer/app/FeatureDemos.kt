package com.chhunly.typer.app

import android.content.Context
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/**
 * A small picture of each feature, drawn like the Keyboard's bar: the top Suggestion in bold on a tinted
 * chip, everything else on a plain one. Decorative, so hidden from screen readers (the text below says it).
 */
@Composable
fun FeatureDemo(index: Int) {
    Row(
        Modifier.fillMaxWidth().clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        when (index) {
            0 -> PhraseDemo()
            1 -> {
                listOf("nh", "knh", "knhom").forEach { DemoChip(it, latin = true) }
                Arrow()
                DemoChip("ខ្ញុំ", top = true)
            }
            2 -> {
                DemoChip("sok", latin = true)
                Arrow()
                DemoChip("សុខ", top = true)
                Arrow("↑")
            }
            3 -> {
                DemoChip("ខ្ញុំទៅសាលារៀន", Modifier.weight(1f), top = true)
                DemoChip("abc")
                DemoChip("5 ▾")
            }
            else -> {
                DemoChip("ខ", top = true)
                Arrow()
                DemoChip("EN")
            }
        }
    }
}

@Composable
private fun DemoChip(text: String, modifier: Modifier = Modifier, top: Boolean = false, latin: Boolean = false) {
    val colors = MaterialTheme.colorScheme
    Surface(
        modifier,
        shape = RoundedCornerShape(8.dp),
        color = if (top) colors.primaryContainer else colors.surfaceVariant,
        contentColor = if (top) colors.onPrimaryContainer else colors.onSurfaceVariant,
    ) {
        Text(
            text,
            Modifier.heightIn(min = 34.dp).padding(horizontal = 10.dp, vertical = 4.dp),
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = if (top) FontWeight.Bold else FontWeight.Normal,
            fontFamily = if (latin) FontFamily.Monospace else null,
            maxLines = 1,
        )
    }
}

@Composable
private fun Arrow(glyph: String = "→") {
    Text(glyph, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private const val LATIN = "knhom tov sala rean"
private const val KHMER = "ខ្ញុំទៅសាលារៀន"

/** Types the Latin a letter at a time, then swaps it for the Khmer, on a loop. Static when animations are off. */
@Composable
private fun PhraseDemo() {
    val context = LocalContext.current
    val still = remember { animationsOff(context) }
    var typed by remember { mutableStateOf(if (still) LATIN else "") }
    var done by remember { mutableStateOf(still) }
    LaunchedEffect(still) {
        if (still) return@LaunchedEffect
        while (true) {
            typed = ""
            done = false
            for (c in LATIN) {
                delay(85)
                typed += c
            }
            delay(600)
            done = true
            delay(2200)
        }
    }
    when {
        still -> {
            DemoChip(LATIN, latin = true)
            Arrow()
            DemoChip(KHMER, top = true)
        }
        done -> DemoChip(KHMER, top = true)
        else -> Text(
            typed + "▏",
            Modifier.heightIn(min = 34.dp).padding(vertical = 4.dp),
            style = MaterialTheme.typography.bodyLarge.copy(fontSize = 17.sp),
            fontFamily = FontFamily.Monospace,
            maxLines = 1,
        )
    }
}

private fun animationsOff(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
