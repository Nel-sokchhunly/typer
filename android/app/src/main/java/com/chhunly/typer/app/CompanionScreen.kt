package com.chhunly.typer.app

import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.windowInsetsTopHeight
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.chhunly.typer.R
import com.chhunly.typer.ime.HapticsChoice
import com.chhunly.typer.ime.ThemeChoice
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** What the phone says about Typer right now: steps 1 and 2 show these as done or not. */
private data class SetupStatus(val enabled: Boolean, val chosen: Boolean)

private fun readSetupStatus(context: Context): SetupStatus {
    val imm = context.getSystemService(InputMethodManager::class.java)
    val enabled = imm.enabledInputMethodList.any { it.packageName == context.packageName }
    val current = Settings.Secure.getString(context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
    return SetupStatus(enabled, current?.startsWith("${context.packageName}/") == true)
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CompanionScreen(khmer: Boolean, onKhmerChange: (Boolean) -> Unit) {
    val copy = if (khmer) Copy.khmer else Copy.english
    val context = LocalContext.current
    val status = rememberSetupStatus()
    val page = MaterialTheme.colorScheme.background

    // Yellow behind the top half, page colour below, so the yellow shows through any overscroll at the top.
    Box(
        Modifier
            .fillMaxSize()
            .semantics { testTagsAsResourceId = true }
            .drawBehind {
                drawRect(page)
                drawRect(TyperYellow, Offset.Zero, Size(size.width, size.height / 2))
            },
    ) {
        // The keyboard's inset is handled here, so the field can be lifted above it.
        val scroll = rememberScrollState()
        var heroHeight by remember { mutableIntStateOf(Int.MAX_VALUE) }
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(scroll)) {
            Box(Modifier.onGloballyPositioned { heroHeight = it.size.height }) { Hero(copy, khmer, onKhmerChange) }
            Sheet {
                Section(copy.setupTitle) {
                    copy.steps.forEachIndexed { i, step ->
                        val done = when (i) { 0 -> status.enabled; 1 -> status.chosen; else -> null }
                        StepCard(i + 1, step, done, copy.done) {
                            when (i) {
                                0 -> context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                                1 -> context.getSystemService(InputMethodManager::class.java).showInputMethodPicker()
                            }
                        }
                    }
                }
                TryIt(copy, khmer)  // right after the steps: set up, then try it
                Section(copy.keyboardTitle) {
                    if (ThemeChoice.available) WallpaperCard(copy)
                    VibrationCard(copy)
                }
                Section(copy.featuresTitle) {
                    copy.features.forEachIndexed { i, feature -> FeatureCard(i, feature) }
                }
                PrivacyCard(copy)
            }
        }
        // The status bar keeps a backdrop, like iOS's top inset: yellow over the hero, the page colour once the sheet
        // scrolls under it, so text never runs behind the clock.
        val underBar = if (scroll.value > heroHeight - 120) page else TyperYellow
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(underBar.copy(alpha = 0.96f)))
    }
}

/** The yellow header: icon tile, language switch, big name and tagline. Always ink on yellow, light or dark. */
@Composable
private fun Hero(copy: Copy, khmer: Boolean, onKhmerChange: (Boolean) -> Unit) {
    Box(Modifier.fillMaxWidth().background(TyperYellow), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = 640.dp)
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 48.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier.size(64.dp).clip(RoundedCornerShape(16.dp)).background(TyperInk),
                    contentAlignment = Alignment.Center,
                ) { Txt("\u179F", 40, color = TyperCream, khmerLine = 1.3f) }
                Box(Modifier.weight(1f))
                LanguageSwitch(khmer, copy, onKhmerChange)
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Txt("\u179F\u179A\u179F\u17C1\u179A", 52, weight = FontWeight.Bold, color = TyperInk, khmerLine = 1.4f)
                Txt("Typer", 22, weight = FontWeight.SemiBold, color = TyperInk.copy(alpha = 0.6f))
            }
            Txt(copy.tagline, 19, weight = FontWeight.Medium, color = TyperInk)
        }
    }
}

/** The page-coloured sheet with 28dp top corners that slides up 24dp over the yellow. */
@Composable
private fun Sheet(content: @Composable () -> Unit) {
    val lift = 24.dp
    Box(
        Modifier
            .fillMaxWidth()
            .layout { measurable, constraints ->
                val placeable = measurable.measure(constraints)
                val up = lift.roundToPx()
                layout(placeable.width, placeable.height - up) { placeable.place(0, -up) }
            }
            .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
            .background(MaterialTheme.colorScheme.background),
        contentAlignment = Alignment.TopCenter,
    ) {
        Column(
            Modifier
                .widthIn(max = 640.dp)
                .fillMaxWidth()
                .padding(start = 20.dp, end = 20.dp, top = 28.dp, bottom = 40.dp)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) { content() }
    }
}

/** Re-reads the setup status on resume and when the window regains focus (the keyboard picker is a dialog, so it does not resume us). */
@Composable
private fun rememberSetupStatus(): SetupStatus {
    val context = LocalContext.current
    var refresh by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        refresh++
        onPauseOrDispose { }
    }
    val focused = LocalWindowInfo.current.isWindowFocused
    LaunchedEffect(focused) { if (focused) refresh++ }
    return remember(refresh) { readSetupStatus(context) }
}

/** Khmer / EN capsule switch with an ink outline. Each option is a 48dp touch target around a 40dp pill. */
@Composable
private fun LanguageSwitch(khmer: Boolean, copy: Copy, onChange: (Boolean) -> Unit) {
    Row(Modifier.selectableGroup().border(1.5.dp, TyperInk, CircleShape)) {
        listOf(true to "\u1781\u17D2\u1798\u17C2\u179A", false to "EN").forEach { (isKhmer, label) ->
            val selected = khmer == isKhmer
            Box(
                Modifier
                    .sizeIn(minWidth = 56.dp, minHeight = 48.dp)
                    .clip(CircleShape)
                    .selectable(selected = selected, role = Role.RadioButton, onClick = { onChange(isKhmer) })
                    .semantics { contentDescription = if (isKhmer) copy.languageKhmer else copy.languageEnglish }
                    .padding(4.dp),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .heightIn(min = 40.dp)
                        .sizeIn(minWidth = 48.dp)
                        .clip(CircleShape)
                        .background(if (selected) TyperInk else Color.Transparent)
                        .padding(horizontal = 14.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Txt(label, 15, weight = FontWeight.SemiBold, color = if (selected) TyperYellow else TyperInk, khmerLine = 1.3f)
                }
            }
        }
    }
}

/** A section: small uppercase muted title, then its cards. */
@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        SectionTitle(title)
        content()
    }
}

@Composable
private fun SectionTitle(text: String) {
    Txt(
        text.uppercase(),
        13,
        weight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        tracking = 1.2.sp,
    )
}

private val CardShape = RoundedCornerShape(16.dp)

@Composable
private fun Card(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier.fillMaxWidth().clip(CardShape).background(MaterialTheme.colorScheme.surface)) { content() }
}

/** The yellow capsule with an ink outline and ink text, like iOS "Open Settings". */
@Composable
private fun PillButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier
            .heightIn(min = 48.dp)
            .clip(CircleShape)
            .background(TyperYellow)
            .border(BorderStroke(1.5.dp, TyperInk), CircleShape)
            .semantics(mergeDescendants = true) {}
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
        Txt(text, 16, weight = FontWeight.Bold, color = TyperInk, khmerLine = 1.4f)
    }
}

@Composable
private fun StepCard(number: Int, step: Step, done: Boolean?, doneLabel: String, onClick: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Card {
        Row(Modifier.padding(14.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(TyperYellow)
                    .semantics { contentDescription = if (done == true) "$number, $doneLabel" else "$number" },
                contentAlignment = Alignment.Center,
            ) {
                if (done == true) {
                    Icon(painterResource(R.drawable.ic_done), null, Modifier.size(20.dp), tint = TyperInk)
                } else {
                    Txt(number.toString(), 17, weight = FontWeight.Bold, color = TyperInk, khmerLine = 1.3f)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Txt(step.title, 17, weight = FontWeight.SemiBold)
                if (done == true) Txt(doneLabel, 14, weight = FontWeight.SemiBold)
                Txt(step.detail, 15, color = colors.onSurfaceVariant)
                step.button?.let { PillButton(it, onClick, Modifier.padding(top = 8.dp)) }
            }
        }
    }
}

/** "Match my wallpaper": the Keyboard uses the phone's Material You colours instead of Typer yellow. */
@Composable
private fun WallpaperCard(copy: Copy) {
    val context = LocalContext.current
    var on by remember { mutableStateOf(ThemeChoice.materialYou(context)) }
    val colors = MaterialTheme.colorScheme
    Card {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .toggleable(value = on, role = Role.Switch, onValueChange = {
                    on = it
                    ThemeChoice.setMaterialYou(context, it)
                })
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Txt(copy.wallpaperTitle, 17, weight = FontWeight.SemiBold)
                Txt(copy.wallpaperDetail, 15, color = colors.onSurfaceVariant)
            }
            Switch(
                checked = on,
                onCheckedChange = null,
                colors = SwitchDefaults.colors(
                    checkedTrackColor = TyperYellow,
                    checkedThumbColor = TyperInk,
                    checkedBorderColor = TyperInk,
                    uncheckedTrackColor = Color.Transparent,
                    uncheckedThumbColor = colors.onSurfaceVariant,
                    uncheckedBorderColor = colors.outline,
                ),
            )
        }
    }
}

/** "Key vibration": System, Off, Light or Strong, as a compact segmented choice. */
@Composable
private fun VibrationCard(copy: Copy) {
    val context = LocalContext.current
    var choice by remember { mutableStateOf(HapticsChoice.get(context)) }
    val colors = MaterialTheme.colorScheme
    Card {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Txt(copy.vibrationTitle, 17, weight = FontWeight.SemiBold)
                Txt(copy.vibrationDetail, 15, color = colors.onSurfaceVariant)
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .selectableGroup()
                    .clip(RoundedCornerShape(12.dp))
                    .background(colors.surfaceVariant),
            ) {
                HapticsChoice.entries.forEachIndexed { i, option ->
                    val selected = choice == option
                    Box(
                        Modifier
                            .weight(1f)
                            .heightIn(min = 48.dp)
                            .padding(3.dp)
                            .clip(RoundedCornerShape(9.dp))
                            .background(if (selected) TyperYellow else Color.Transparent)
                            .selectable(selected = selected, role = Role.RadioButton, onClick = {
                                choice = option
                                HapticsChoice.set(context, option)
                            })
                            .padding(horizontal = 2.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Txt(
                            copy.vibrationOptions[i],
                            14,
                            weight = if (selected) FontWeight.Bold else FontWeight.Medium,
                            color = if (selected) TyperInk else colors.onSurface,
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TryIt(copy: Copy, khmer: Boolean) {
    var text by rememberSaveable { mutableStateOf("") }
    var focused by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val bringIntoView = remember { BringIntoViewRequester() }
    val colors = MaterialTheme.colorScheme
    Column(Modifier.bringIntoViewRequester(bringIntoView), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionTitle(copy.tryTitle)
        BasicTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("try")
                .clip(CardShape)
                .background(colors.surface)
                .border(2.5.dp, if (focused) TyperYellow else Color.Transparent, CardShape)
                // Wait for the keyboard to take its space, then lift the field above it.
                .onFocusChanged {
                    focused = it.isFocused
                    if (it.isFocused) scope.launch { delay(350); bringIntoView.bringIntoView() }
                },
            textStyle = TextStyle(
                fontFamily = KantumruyPro,
                fontSize = 20.sp,
                lineHeight = if (khmer) 32.sp else 28.sp,
                color = colors.onSurface,
            ),
            cursorBrush = SolidColor(colors.onSurface),
            minLines = 2,
            maxLines = 5,
            decorationBox = { inner ->
                Box(Modifier.padding(16.dp)) {
                    if (text.isEmpty()) {
                        Txt(copy.tryHint, 20, color = colors.onSurfaceVariant, khmerLine = 1.6f)
                    }
                    inner()
                }
            },
        )
    }
}

@Composable
private fun FeatureCard(index: Int, feature: Feature) {
    Card {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            FeatureDemo(index)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Txt(feature.title, 17, weight = FontWeight.SemiBold)
                Txt(feature.detail, 15, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

/** Always ink with a yellow title and cream text, like iOS, in light and dark. */
@Composable
private fun PrivacyCard(copy: Copy) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(TyperInk)) {
        Row(Modifier.padding(18.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(painterResource(R.drawable.ic_lock), null, Modifier.padding(top = 2.dp).size(22.dp), tint = TyperYellow)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Txt(copy.aboutTitle, 17, weight = FontWeight.SemiBold, color = TyperYellow)
                Txt(copy.about, 15, color = TyperCream.copy(alpha = 0.85f))
            }
        }
    }
}
