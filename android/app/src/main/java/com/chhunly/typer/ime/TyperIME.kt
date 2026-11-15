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
import com.chhunly.typer.core.EmojiData
import com.chhunly.typer.core.EmojiRecents
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
    /**
     * The layout the user chose with the bar's កខគ / abc: Sing's letters or the Khmer layout. Remembered across
     * launches; only that switch changes it.
     */
    private var letters = KeyPage.LETTERS
    /** Password, email and number fields: the Sing layout only, while focused; [letters] is kept for later. */
    private var layoutLocked = false
    private val keyboardPrefs by lazy { getSharedPreferences("typer_keyboard", MODE_PRIVATE) }
    /** The letters page for this field: the chosen layout, or the Sing layout in a locked field. */
    private fun lettersPage() = if (layoutLocked) KeyPage.LETTERS else letters
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

    // emoji page: data loaded once off the main thread; recents and chosen skin tones kept on the phone only
    @Volatile private var emojiData: EmojiData? = null
    private var emojiOpen = false
    private var emojiSearch = false
    private var query = ""
    private var results: List<String> = emptyList()
    private var recents: List<String> = emptyList()
    private var tones: Map<String, String> = emptyMap()
    private val emojiPrefs by lazy { getSharedPreferences("typer_emoji", MODE_PRIVATE) }
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
        letters = if (keyboardPrefs.getString("layout", null) == KeyPage.KHMER.name) KeyPage.KHMER else KeyPage.LETTERS
        scheduler.async {
            val data = EngineData.dataDir(this)
            val e = Engine(data?.path ?: "/nonexistent", EngineData.userDir(this).path)
            engine.loaded = e
            engine.real = if (e.loaded) e else NoSuggestions
        }
        loader.execute {
            val data = try {
                EmojiData.load(asset("data/emoji.json"), asset("data/emoji-variants.json"), asset("data/emoji-names.tsv"))
            } catch (e: Exception) {  // missing or broken data: the emoji key does nothing
                null
            }
            main.post {
                emojiData = data
                view?.emojiData = data
            }
        }
        loader.execute {
            english = try {
                assets.open("data/english.tsv").use { EnglishWords.load(it) }.also { it.glide }  // build the glide index here, not on the first glide
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

    override fun onCreateInputView(): View = KeyboardView(this, this).also {
        view = it
        it.emojiData = emojiData
    }

    private fun asset(path: String) = assets.open(path).use { it.readBytes().toString(Charsets.UTF_8) }

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        proxy.selection(attribute.initialSelStart, attribute.initialSelEnd, -1, -1)
        glided = null
        val type = fieldType(attribute)
        val secure = secure(attribute)
        composer.fieldTraitsChanged(secure, type)
        val variation = attribute.inputType and InputType.TYPE_MASK_VARIATION
        val password = (attribute.inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT && variation in PASSWORDS
        layoutLocked = secure || password || type == FieldType.EMAIL || type == FieldType.NUMBER
        wordsAllowed = type == FieldType.TEXT && !password && variation != InputType.TYPE_TEXT_VARIATION_URI &&
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
            page = if (type == FieldType.NUMBER) KeyPage.NUMBERS else lettersPage()
            shift = Shift.OFF
            shiftChosen = false
            showAll = false
        }
        if (layoutLocked && page == KeyPage.KHMER) page = KeyPage.LETTERS
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
        view?.systemFont = FontChoice.get(this) == FontChoice.SYSTEM
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
        emojiOpen = false
        emojiSearch = false
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
        if (glided != null && (newSelStart != newSelEnd || newSelEnd != glideEnd)) glided = null  // the caret moved away
        composer.textChanged()
        refresh()
    }

    // ---- state -> view ----

    /** iOS refresh(afterKey:): English words, the Composer's state, and auto-cap re-decides shift after a key. */
    private fun refresh(afterKey: Boolean = false) {
        val khmer = composer.mode == "ខ"
        val before = if (khmer) null else currentInputConnection?.getTextBeforeCursor(64, 0)?.toString()  // Khmer needs neither
        words = glided ?: if (!khmer && wordsAllowed && page == KeyPage.LETTERS) english?.suggest(before, userWords) ?: emptyList() else emptyList()
        if (!composer.isComposing) showAll = false
        if (afterKey) shiftChosen = false
        if (shift != Shift.LOCK && !shiftChosen) {
            shift = if (page != KeyPage.KHMER && AutoCap.shouldShift(before, autoCap, khmer)) Shift.ONCE else Shift.OFF
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
            emoji = emojiOpen,
            emojiSearch = emojiSearch,
            query = query,
            results = results,
            recents = recents,
            tones = tones,
            letters = lettersPage(),
            layoutLocked = layoutLocked,
            glide = composer.mode == "EN" && wordsAllowed && english != null,
            glided = glided != null,
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
        if (emojiSearch) return searchKey(action)
        if (glided != null) {
            val word = glided!![0]
            glided = null
            if (action == KeyAction.Backspace) return glideDeleted(word)
        }
        if (emojiOpen && action == KeyAction.Page) return closeEmoji()
        when (action) {
            is KeyAction.Text -> type(action.text)
            KeyAction.Space -> type(" ")
            KeyAction.Backspace -> handle(composer.backspace()) { if (page == KeyPage.KHMER) deleteCodePoint() else deleteBackward() }
            KeyAction.Return -> handle(composer.returnKey()) { returnKey() }
            KeyAction.Shift -> shiftTapped()
            KeyAction.Page -> {
                page = if (page == KeyPage.LETTERS || page == KeyPage.KHMER) KeyPage.NUMBERS else lettersPage()
                refresh()
            }
            KeyAction.Symbols -> {
                page = if (page == KeyPage.NUMBERS) KeyPage.SYMBOLS else KeyPage.NUMBERS
                render()
            }
            KeyAction.Mode -> modeTapped()
            KeyAction.Emoji -> openEmoji()
        }
    }

    // ---- emoji ----

    private fun openEmoji() {
        if (emojiData == null) return
        recents = EmojiRecents.decode(emojiPrefs.getString("recents", null))
        tones = emojiPrefs.getString("tones", null)?.let { s ->
            s.split('\n').mapNotNull { l -> l.split('\t').takeIf { it.size == 2 }?.let { it[0] to it[1] } }.toMap()
        } ?: emptyMap()
        emojiOpen = true
        render()
    }

    private fun closeEmoji() {
        emojiOpen = false
        emojiSearch = false
        refresh()
    }

    /** An emoji from the grid, a tone panel or search: typed like any other key (it ends a Phrase first). */
    override fun onEmoji(emoji: String) {
        type(emoji)
        val data = emojiData ?: return
        val base = data.base(emoji)
        if (data.variants.containsKey(base)) tones = if (base == emoji) tones - base else tones + (base to emoji)
        recents = EmojiRecents.add(recents, emoji)
        emojiPrefs.edit()
            .putString("recents", EmojiRecents.encode(recents))
            .putString("tones", tones.entries.joinToString("\n") { "${it.key}\t${it.value}" })
            .apply()
        render()
    }

    override fun onEmojiSearch(open: Boolean) {
        emojiSearch = open
        query = ""
        results = emptyList()
        if (open) shift = Shift.OFF
        render()
    }

    /** While searching, the letters type the query; return or the emoji key goes back to the emoji page. */
    private fun searchKey(action: KeyAction) {
        when (action) {
            is KeyAction.Text -> query += action.text.lowercase()
            KeyAction.Space -> if (query.isNotEmpty() && !query.endsWith(" ")) query += " "
            KeyAction.Backspace -> query = query.dropLast(1)
            KeyAction.Return, KeyAction.Emoji, KeyAction.Page -> return onEmojiSearch(false)
            KeyAction.Shift -> return shiftTapped()
            else -> return
        }
        results = emojiData?.search(query) ?: emptyList()
        render()
    }

    /** A DEL key event, not deleteSurroundingText: editors then delete whole emoji and selections themselves. */
    private fun deleteBackward() = sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL)

    /**
     * The Khmer layout's backspace: one code point, even inside a stack (គ្រូ -> គ្រ -> គ្), as the keys typed them.
     * A selection, or an emoji or other surrogate pair before the caret, goes through DEL as usual.
     */
    private fun deleteCodePoint() {
        val ic = currentInputConnection ?: return
        val before = ic.getTextBeforeCursor(2, 0)
        val selected = !ic.getSelectedText(0).isNullOrEmpty()
        if (selected || before.isNullOrEmpty() || Character.isSurrogate(before.last())) return deleteBackward()
        ic.deleteSurroundingText(1, 0)
    }

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

    /**
     * The bar's layout switch (no Phrase open): កខគ to the Khmer layout, abc back to the Sing layout, remembered
     * across launches. Inert in password, email and number fields. Shift starts off either way.
     */
    private fun layoutTapped() {
        if (layoutLocked || composer.isComposing) return
        letters = if (letters == KeyPage.KHMER) KeyPage.LETTERS else KeyPage.KHMER
        keyboardPrefs.edit().putString("layout", letters.name).apply()
        page = letters
        shift = Shift.OFF
        shiftChosen = true
        refresh()
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
            StripAction.Layout -> layoutTapped()
            StripAction.Expand -> {
                showAll = !showAll && composer.isComposing
                render()
            }
            is StripAction.Punctuation -> type(action.text)
            is StripAction.Word -> if (glided != null) glideAlternative(action.index) else englishWordTapped(action.index)
        }
    }

    // ---- glide typing (English mode) ----

    /** After a glide: the glided word and its alternatives, for the bar; null once anything else happens. */
    private var glided: List<String>? = null
    /** Where the caret should be while [glided] stands; anywhere else drops it. */
    private var glideEnd = -1

    /**
     * A glide over the letters: the best word goes in at once, with a space before it unless the caret already
     * follows a space or an opening mark, capitalised as shift says; the bar offers the alternatives.
     */
    override fun onGlide(xs: FloatArray, ys: FloatArray, keys: Map<Char, Pair<Float, Float>>, keyWidth: Float) {
        val decoder = english?.glide ?: return
        val found = decoder.decode(xs, ys, keys, keyWidth)
        if (found.isEmpty()) return
        val ic = currentInputConnection ?: return
        val cased = found.map { w ->
            when (shift) {
                Shift.LOCK -> w.uppercase()
                Shift.ONCE -> w.replaceFirstChar { it.uppercaseChar() }
                Shift.OFF -> w
            }
        }
        val prev = ic.getTextBeforeCursor(1, 0)?.lastOrNull()
        val space = if (prev != null && !prev.isWhitespace() && prev !in "([{\"'“‘/@#") " " else ""
        ic.beginBatchEdit()
        ic.commitText(space + cased[0], 1)
        ic.endBatchEdit()
        glideEnd = proxy.selEnd + space.length + cased[0].length
        glided = cased
        if (shift == Shift.ONCE) shift = Shift.OFF
        shiftChosen = true
        render()
        refresh()
    }

    /** Backspace right after a glide takes the whole word back. */
    private fun glideDeleted(word: String) {
        val ic = currentInputConnection ?: return
        if (ic.getTextBeforeCursor(word.length, 0)?.toString() == word) ic.deleteSurroundingText(word.length, 0)
        else deleteBackward()
        refresh(afterKey = true)
    }

    /** An alternative from the bar replaces the glided word; the glided word itself just keeps it. */
    private fun glideAlternative(i: Int) {
        val w = glided ?: return
        glided = null
        val ic = currentInputConnection ?: return
        if (i > 0 && i < w.size && ic.getTextBeforeCursor(w[0].length, 0)?.toString() == w[0]) {
            ic.beginBatchEdit()
            ic.deleteSurroundingText(w[0].length, 0)
            ic.commitText(w[i], 1)
            ic.endBatchEdit()
        }
        refresh(afterKey = true)
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
    override fun onHint(text: String) {
        if (emojiSearch) searchKey(KeyAction.Text(text)) else type(text)
    }

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
                // URL fields have no special rule on Android: Khmer mode and the Khmer layout work there, as in any
                // text field (#79). FieldType.URL stays in the shared Composer until every platform drops it together.
                else -> FieldType.TEXT
            }
        }
    }
}
