package com.chhunly.typer.ime

import android.inputmethodservice.InputMethodService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.UserDictionary
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsetsController
import android.view.inputmethod.EditorInfo
import com.chhunly.typer.core.AutoCap
import com.chhunly.typer.core.Composer
import com.chhunly.typer.core.Engine
import com.chhunly.typer.core.EnglishWords
import com.chhunly.typer.core.FieldType
import com.chhunly.typer.core.KeyAction
import com.chhunly.typer.core.KeyPage
import com.chhunly.typer.core.NoSuggestions
import com.chhunly.typer.core.Scheduler
import com.chhunly.typer.core.StripAction
import com.chhunly.typer.core.Suggester
import com.chhunly.typer.core.cursorOffset
import com.chhunly.typer.ime.KeyboardView.ReturnKind
import com.chhunly.typer.ime.KeyboardView.Shift
import java.util.concurrent.Executors

/**
 * The Keyboard. Forwards keys, strip taps, selection and field changes to the Composer and keeps the layout state
 * (page, shift, auto-cap, the panel) like iOS's KeyboardViewController. The engine and the English word list load
 * off the main thread; the Keyboard types Latin until (or if never) they are ready.
 */
class TyperIME : InputMethodService(), KeyboardView.Listener {
    private val main = Handler(Looper.getMainLooper())
    private val scheduler = Scheduler.background { main.post(it) }
    private val proxy = ProxyAdapter { currentInputConnection }
    private val engine = LoadingEngine()
    private val composer = Composer(engine, proxy, usesMarkedText = true, scheduler = scheduler).also {
        it.onSuggestions = { render() }  // results arrive after the key
    }
    private var view: KeyboardView? = null

    // layout state (iOS KeyboardModel)
    private var page = KeyPage.LETTERS
    private var shift = Shift.OFF
    /** The user set shift by hand since the last key; auto-cap leaves it alone until a key is typed. */
    private var shiftChosen = false
    private var lastShiftTap = 0L
    private var autoCap = AutoCap.Kind.NONE
    private var showAll = false
    private var returnKind = ReturnKind.NEWLINE
    private var returnAction = false
    private var editorAction = EditorInfo.IME_ACTION_NONE
    /** English word suggestions allowed: plain text fields that don't turn suggestions off, not passwords. */
    private var wordsAllowed = false
    private var words: List<String> = emptyList()
    private var dragCaret = -1

    // English words: loaded once, off the main thread
    @Volatile private var english: EnglishWords? = null
    @Volatile private var userWords: List<String> = emptyList()
    private val loader = Executors.newSingleThreadExecutor { Thread(it, "typer-words").apply { priority = Thread.MIN_PRIORITY } }

    /** Loads on the engine thread, so every suggest queued behind it waits for it; Latin-only if loading fails. */
    private class LoadingEngine : Suggester {
        var real: Suggester = NoSuggestions
        var loaded: Engine? = null
        override fun suggest(input: String, k: Int) = real.suggest(input, k)
        override fun pick(input: String, index: Int) = real.pick(input, index)
    }

    override fun onCreate() {
        super.onCreate()
        scheduler.async {
            val data = EngineData.dataDir(this)
            val e = Engine(data?.path ?: "/nonexistent", EngineData.userDir(this).path)
            engine.loaded = e
            engine.real = if (e.loaded) e else NoSuggestions
        }
        loader.execute {
            english = try {
                assets.open("data/english.tsv").use { EnglishWords.load(it) }
            } catch (e: java.io.IOException) {
                null
            }
        }
    }

    override fun onDestroy() {
        scheduler.async { engine.loaded?.close() }
        loader.shutdown()
        super.onDestroy()
    }

    /** No extract (fullscreen) editor, also in landscape: the Phrase is composed in the app's own field. */
    override fun onEvaluateFullscreenMode() = false

    override fun onCreateInputView(): View = KeyboardView(this, this).also { view = it }

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        proxy.selection(attribute.initialSelStart, attribute.initialSelEnd, -1, -1)
        val type = fieldType(attribute)
        val secure = secure(attribute)
        composer.fieldTraitsChanged(secure, type)
        val variation = attribute.inputType and InputType.TYPE_MASK_VARIATION
        val password = (attribute.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT && variation in PASSWORDS
        wordsAllowed = type == FieldType.TEXT && !password &&
            (attribute.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
            (attribute.inputType and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) == 0
        autoCap = when {
            attribute.inputType and InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS != 0 -> AutoCap.Kind.ALL_CHARACTERS
            attribute.inputType and InputType.TYPE_TEXT_FLAG_CAP_WORDS != 0 -> AutoCap.Kind.WORDS
            attribute.inputType and InputType.TYPE_TEXT_FLAG_CAP_SENTENCES != 0 -> AutoCap.Kind.SENTENCES
            else -> AutoCap.Kind.NONE
        }
        returnFor(attribute)
        if (!restarting) {
            page = if (type == FieldType.NUMBER) KeyPage.NUMBERS else KeyPage.LETTERS
            shift = Shift.OFF
            shiftChosen = false
            showAll = false
        }
    }

    /** The return key shows the field's action (search, send, go, ...), drawn in primary; else a newline. */
    private fun returnFor(info: EditorInfo) {
        val action = info.imeOptions and EditorInfo.IME_MASK_ACTION
        val noAction = info.imeOptions and EditorInfo.IME_FLAG_NO_ENTER_ACTION != 0
        val multiLine = info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
        returnKind = if (noAction) ReturnKind.NEWLINE else when (action) {
            EditorInfo.IME_ACTION_GO -> ReturnKind.GO
            EditorInfo.IME_ACTION_SEARCH -> ReturnKind.SEARCH
            EditorInfo.IME_ACTION_SEND -> ReturnKind.SEND
            EditorInfo.IME_ACTION_NEXT -> ReturnKind.NEXT
            EditorInfo.IME_ACTION_PREVIOUS -> ReturnKind.PREVIOUS
            EditorInfo.IME_ACTION_DONE -> if (multiLine) ReturnKind.NEWLINE else ReturnKind.DONE
            else -> ReturnKind.NEWLINE
        }
        returnAction = returnKind != ReturnKind.NEWLINE
        editorAction = if (returnAction) action else EditorInfo.IME_ACTION_NONE
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        val theme = KeyboardTheme.from(this)
        view?.theme = theme
        view?.haptics = HapticsChoice.get(this)
        colorNavigationBar(theme)
        loadUserWords()
        refresh()
    }

    /** The navigation bar under the Keyboard takes the Keyboard's background (on Android 15+ the view draws behind it). */
    @Suppress("DEPRECATION")
    private fun colorNavigationBar(theme: KeyboardTheme) {
        val w = window?.window ?: return
        if (Build.VERSION.SDK_INT < 35) w.navigationBarColor = theme.background
        if (Build.VERSION.SDK_INT >= 30) {
            w.insetsController?.setSystemBarsAppearance(
                if (theme.dark) 0 else WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS,
            )
        } else if (Build.VERSION.SDK_INT >= 26) {
            val d = w.decorView
            d.systemUiVisibility = if (theme.dark) d.systemUiVisibility and View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
            else d.systemUiVisibility or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        }
    }

    /** Words the user added to Android's personal dictionary, the counterpart of iOS's text replacements. */
    private fun loadUserWords() {
        loader.execute {
            userWords = try {
                contentResolver.query(UserDictionary.Words.CONTENT_URI, arrayOf(UserDictionary.Words.WORD), null, null,
                    "${UserDictionary.Words.FREQUENCY} DESC")?.use { c ->
                    val out = ArrayList<String>(c.count)
                    while (c.moveToNext()) c.getString(0)?.let { out += it }
                    out
                } ?: emptyList()
            } catch (e: Exception) {  // SecurityException when not the enabled Keyboard; no provider on some builds
                emptyList()
            }
        }
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        composer.fieldEnded()
        view?.reset()
        showAll = false
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        composer.fieldEnded()
        super.onFinishInput()
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        proxy.selection(newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        if (dragCaret >= 0) return  // our own caret moves while dragging on the space bar
        composer.textChanged()
        refresh()
    }

    // ---- state -> view ----

    /** iOS refresh(afterKey:): English words, the Composer's state, and auto-cap re-decides shift after a key. */
    private fun refresh(afterKey: Boolean = false) {
        val khmer = composer.mode == "ខ"
        val before = if (khmer) null else currentInputConnection?.getTextBeforeCursor(64, 0)?.toString()  // Khmer needs neither
        words = if (!khmer && wordsAllowed && page == KeyPage.LETTERS) english?.suggest(before, userWords) ?: emptyList() else emptyList()
        if (!composer.isComposing) showAll = false
        if (afterKey) shiftChosen = false
        if (shift != Shift.LOCK && !shiftChosen) {
            shift = if (AutoCap.shouldShift(before, autoCap, khmer)) Shift.ONCE else Shift.OFF
        }
        render()
    }

    private fun render() {
        view?.state = KeyboardView.State(
            page = page,
            shift = shift,
            mode = composer.mode,
            canToggle = composer.canToggle,
            typed = composer.typed,
            suggestions = composer.suggestions,
            words = words,
            showAll = showAll,
            returnKind = returnKind,
            returnAction = returnAction,
        )
    }

    /** If the Composer declined the key, do the normal thing. */
    private fun handle(consumed: Boolean, fallback: () -> Unit = {}) {
        if (!consumed) fallback()
        refresh(afterKey = true)
    }

    private fun type(c: String) = handle(composer.key(c)) { currentInputConnection?.commitText(c, 1) }

    // ---- view events ----

    override fun onKey(action: KeyAction) {
        when (action) {
            is KeyAction.Text -> type(action.text)
            KeyAction.Space -> type(" ")
            KeyAction.Backspace -> handle(composer.backspace()) { deleteBackward() }
            KeyAction.Return -> handle(composer.returnKey()) { returnKey() }
            KeyAction.Shift -> shiftTapped()
            KeyAction.Page -> {
                page = if (page == KeyPage.LETTERS) KeyPage.NUMBERS else KeyPage.LETTERS
                refresh()
            }
            KeyAction.Symbols -> {
                page = if (page == KeyPage.NUMBERS) KeyPage.SYMBOLS else KeyPage.NUMBERS
                render()
            }
            KeyAction.Mode -> modeTapped()
        }
    }

    /** A DEL key event, not deleteSurroundingText: editors then delete whole emoji and selections themselves. */
    private fun deleteBackward() = sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)

    private fun returnKey() {
        val ic = currentInputConnection ?: return
        if (returnAction && editorAction != EditorInfo.IME_ACTION_NONE) ic.performEditorAction(editorAction)
        else sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER)
    }

    /** Shift once; a quick second tap locks caps; tapping a lock (or a lone shift) turns it off. */
    private fun shiftTapped() {
        val now = SystemClock.uptimeMillis()
        shift = when (shift) {
            Shift.LOCK -> Shift.OFF
            Shift.ONCE -> if (now - lastShiftTap < 400) Shift.LOCK else Shift.OFF
            Shift.OFF -> Shift.ONCE
        }
        lastShiftTap = now
        shiftChosen = true
        render()
    }

    /** Switching mode never turns shift on: the keys stay as they are until the next letter. */
    private fun modeTapped() {
        composer.toggleMode()
        if (shift == Shift.ONCE) shift = Shift.OFF
        shiftChosen = true
        refresh()
    }

    override fun onStrip(action: StripAction) {
        when (action) {
            is StripAction.Suggestion -> handle(composer.candidateTapped(action.index))
            StripAction.Latin -> handle(composer.rawLatin())
            StripAction.Expand -> {
                showAll = !showAll && composer.isComposing
                render()
            }
            is StripAction.Punctuation -> type(action.text)
            is StripAction.Word -> englishWordTapped(action.index)
        }
    }

    /** The word being typed becomes the tapped one, then a space; index 0 keeps it as typed. Never learned. */
    private fun englishWordTapped(i: Int) {
        val w = words
        val ic = currentInputConnection ?: return
        if (i !in w.indices) return
        ic.beginBatchEdit()
        if (i > 0) {
            ic.deleteSurroundingText(w[0].length, 0)
            ic.commitText(w[i], 1)
        }
        ic.commitText(" ", 1)
        ic.endBatchEdit()
        refresh(afterKey = true)
    }

    override fun onPanel(index: Int) {
        showAll = false
        if (index < 0) handle(composer.rawLatin()) else handle(composer.candidateTapped(index))
    }

    /** Long press on the top row: the hint digit, typed like any digit (it commits the Phrase first). */
    override fun onHint(text: String) = type(text)

    /** Hold or slide on the space bar: the caret follows, cluster by cluster. Mid-Phrase, the Phrase stays Latin. */
    override fun onDragStart() {
        composer.fieldEnded()
        dragCaret = proxy.selEnd
        refresh()
    }

    override fun onCaret(clusters: Int) {
        val ic = currentInputConnection ?: return
        if (dragCaret < 0) return
        val before = ic.getTextBeforeCursor(64, 0)?.toString()
        val after = ic.getTextAfterCursor(64, 0)?.toString()
        val offset = cursorOffset(before, after, clusters)
        if (offset == 0) return
        dragCaret += offset
        ic.setSelection(dragCaret, dragCaret)
    }

    override fun onDragEnd() {
        dragCaret = -1
        refresh()
    }

    companion object {
        private val PASSWORDS = setOf(
            InputType.TYPE_TEXT_VARIATION_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
            InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        )

        /** Password fields and fields that ask for no personalised learning never reach the engine or Learning. */
        fun secure(info: EditorInfo): Boolean {
            val cls = info.inputType and InputType.TYPE_MASK_CLASS
            val v = info.inputType and InputType.TYPE_MASK_VARIATION
            return (cls == InputType.TYPE_CLASS_TEXT && v in PASSWORDS) ||
                (cls == InputType.TYPE_CLASS_NUMBER && v == InputType.TYPE_NUMBER_VARIATION_PASSWORD) ||
                (info.imeOptions and EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING) != 0
        }

        fun fieldType(info: EditorInfo): FieldType {
            val cls = info.inputType and InputType.TYPE_MASK_CLASS
            val v = info.inputType and InputType.TYPE_MASK_VARIATION
            return when {
                cls == InputType.TYPE_CLASS_NUMBER || cls == InputType.TYPE_CLASS_PHONE || cls == InputType.TYPE_CLASS_DATETIME -> FieldType.NUMBER
                cls != InputType.TYPE_CLASS_TEXT -> FieldType.TEXT
                v == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS || v == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS -> FieldType.EMAIL
                v == InputType.TYPE_TEXT_VARIATION_URI -> FieldType.URL
                else -> FieldType.TEXT
            }
        }
    }
}
