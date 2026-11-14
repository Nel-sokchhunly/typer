package com.chhunly.typer.app

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import com.chhunly.typer.R
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
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

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
fun CompanionScreen(khmer: Boolean, onKhmerChange: (Boolean) -> Unit) {
    val copy = if (khmer) Copy.khmer else Copy.english
    val context = LocalContext.current
    val status = rememberSetupStatus()
    val scrollBehavior = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier
            .semantics { testTagsAsResourceId = true }
            .nestedScroll(scrollBehavior.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = {
                    Text(buildAnnotatedString {
                        append("សរសេរ")
                        withStyle(SpanStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurfaceVariant)) {
                            append("  Typer")
                        }
                    })
                },
                actions = { LanguageSwitch(khmer, copy, onKhmerChange) },
                scrollBehavior = scrollBehavior,
            )
        },
        // The keyboard's inset is handled by imePadding below, so the system bars alone go here.
        contentWindowInsets = WindowInsets.systemBars,
    ) { padding ->
        Box(
            Modifier
                .padding(padding)
                .consumeWindowInsets(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .fillMaxWidth(),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                Modifier.widthIn(max = 640.dp).padding(horizontal = 16.dp).padding(bottom = 32.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(copy.tagline, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(bottom = 4.dp))
                SectionTitle(copy.setupTitle)
                copy.steps.forEachIndexed { i, step ->
                    val done = when (i) { 0 -> status.enabled; 1 -> status.chosen; else -> null }
                    StepCard(i + 1, step, done, copy.done) {
                        when (i) {
                            0 -> context.startActivity(Intent(Settings.ACTION_INPUT_METHOD_SETTINGS))
                            1 -> context.getSystemService(InputMethodManager::class.java).showInputMethodPicker()
                        }
                    }
                }
                TryIt(copy, khmer)
                SectionTitle(copy.featuresTitle)
                copy.features.forEachIndexed { i, feature -> FeatureCard(i, feature) }
                PrivacyCard(copy)
            }
        }
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

@Composable
private fun LanguageSwitch(khmer: Boolean, copy: Copy, onChange: (Boolean) -> Unit) {
    Row(Modifier.selectableGroup().padding(end = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        FilterChip(
            selected = khmer,
            onClick = { onChange(true) },
            label = { Text("ខ្មែរ") },
            modifier = Modifier.semantics { contentDescription = copy.languageKhmer },
        )
        FilterChip(
            selected = !khmer,
            onClick = { onChange(false) },
            label = { Text("EN") },
            modifier = Modifier.semantics { contentDescription = copy.languageEnglish },
        )
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 12.dp, start = 4.dp),
    )
}

@Composable
private fun StepCard(number: Int, step: Step, done: Boolean?, doneLabel: String, onClick: () -> Unit) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh),
    ) {
        Row(Modifier.padding(16.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            val colors = MaterialTheme.colorScheme
            Box(
                Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(if (done == true) colors.primary else colors.secondaryContainer)
                    .semantics { contentDescription = if (done == true) "$number, $doneLabel" else "$number" },
                contentAlignment = Alignment.Center,
            ) {
                if (done == true) {
                    Icon(painterResource(R.drawable.ic_done), null, Modifier.size(20.dp), tint = colors.onPrimary)
                } else {
                    Text(number.toString(), style = MaterialTheme.typography.titleMedium, color = colors.onSecondaryContainer)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(step.title, style = MaterialTheme.typography.titleMedium)
                if (done == true) {
                    Text(doneLabel, style = MaterialTheme.typography.labelLarge, color = colors.primary)
                }
                Text(step.detail, style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                step.button?.let {
                    Button(onClick, Modifier.padding(top = 8.dp)) { Text(it) }
                }
            }
        }
    }
}

@Composable
private fun TryIt(copy: Copy, khmer: Boolean) {
    var text by rememberSaveable { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    val bringIntoView = remember { BringIntoViewRequester() }
    Column(Modifier.bringIntoViewRequester(bringIntoView), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionTitle(copy.tryTitle)
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            modifier = Modifier
                .fillMaxWidth()
                .testTag("try")
                // Wait for the keyboard to take its space, then lift the field above it.
                .onFocusChanged { if (it.isFocused) scope.launch { delay(350); bringIntoView.bringIntoView() } },
            placeholder = { Text(copy.tryHint) },
            textStyle = MaterialTheme.typography.bodyLarge.copy(fontSize = 20.sp, lineHeight = if (khmer) 32.sp else 28.sp),
            minLines = 2,
            maxLines = 5,
        )
    }
}

@Composable
private fun FeatureCard(index: Int, feature: Feature) {
    Card(
        Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            FeatureDemo(index)
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(feature.title, style = MaterialTheme.typography.titleMedium)
                Text(feature.detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PrivacyCard(copy: Copy) {
    val colors = MaterialTheme.colorScheme
    Card(
        Modifier.fillMaxWidth().padding(top = 12.dp),
        colors = CardDefaults.cardColors(containerColor = colors.secondaryContainer, contentColor = colors.onSecondaryContainer),
        shape = RoundedCornerShape(24.dp),
    ) {
        Row(Modifier.padding(20.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            Icon(painterResource(R.drawable.ic_lock), null, Modifier.padding(top = 2.dp).size(24.dp), tint = colors.onSecondaryContainer)
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(copy.aboutTitle, style = MaterialTheme.typography.titleMedium)
                Text(copy.about, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
