package com.chhunly.typer.ime

import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.EditorInfo
import com.chhunly.typer.core.Composer
import com.chhunly.typer.core.Engine
import com.chhunly.typer.core.FieldType
import com.chhunly.typer.core.KeyAction
import com.chhunly.typer.core.NoSuggestions
import com.chhunly.typer.core.Scheduler
import com.chhunly.typer.core.StripAction
import com.chhunly.typer.core.Suggester

/** The Keyboard: forwards keys, strip taps, selection and field changes to the Composer, like iOS's controller. */
class TyperIME : InputMethodService(), KeyboardView.Listener {
    private val main = Handler(Looper.getMainLooper())
    private val scheduler = Scheduler.background { main.post(it) }
    private val proxy = ProxyAdapter { currentInputConnection }
    private val engine = LoadingEngine()
    private val composer = Composer(engine, proxy, usesMarkedText = true, scheduler = scheduler).also {
        it.onSuggestions = { render() }  // results arrive after the key
    }
    private var view: KeyboardView? = null

    /** Loads on the engine thread, so every suggest queued behind it waits for it; Latin-only if loading fails. */
    private inner class LoadingEngine : Suggester {
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
    }

    override fun onDestroy() {
        scheduler.async { engine.loaded?.close() }
        super.onDestroy()
    }

    override fun onCreateInputView(): View = KeyboardView(this, this).also { view = it }

    override fun onStartInput(attribute: EditorInfo, restarting: Boolean) {
        super.onStartInput(attribute, restarting)
        proxy.selection(attribute.initialSelStart, attribute.initialSelEnd, -1, -1)
        composer.fieldTraitsChanged(secure(attribute), fieldType(attribute))
    }

    override fun onStartInputView(info: EditorInfo, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        view?.theme = KeyboardTheme.from(this)
        render()
    }

    override fun onFinishInputView(finishingInput: Boolean) {
        composer.fieldEnded()
        view?.reset()
        super.onFinishInputView(finishingInput)
    }

    override fun onFinishInput() {
        composer.fieldEnded()
        super.onFinishInput()
    }

    override fun onUpdateSelection(oldSelStart: Int, oldSelEnd: Int, newSelStart: Int, newSelEnd: Int, candidatesStart: Int, candidatesEnd: Int) {
        super.onUpdateSelection(oldSelStart, oldSelEnd, newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        proxy.selection(newSelStart, newSelEnd, candidatesStart, candidatesEnd)
        if (composer.textChanged()) render()
    }

    private fun render() {
        view?.state = KeyboardView.State(mode = composer.mode, canToggle = composer.canToggle, typed = composer.typed, suggestions = composer.suggestions)
    }

    private fun handle(consumed: Boolean, fallback: () -> Unit = {}) {
        if (!consumed) fallback()
        render()
    }

    private fun type(c: String) = handle(composer.key(c)) { currentInputConnection?.commitText(c, 1) }

    override fun onKey(action: KeyAction) {
        when (action) {
            is KeyAction.Text -> type(action.text)
            KeyAction.Space -> type(" ")
            KeyAction.Backspace -> handle(composer.backspace()) { sendDownUpKeyEvents(KeyEvent.KEYCODE_DEL) }
            KeyAction.Return -> handle(composer.returnKey()) { sendDownUpKeyEvents(KeyEvent.KEYCODE_ENTER) }
            KeyAction.Mode -> handle(composer.toggleMode())
            else -> Unit
        }
    }

    override fun onStrip(action: StripAction) {
        when (action) {
            is StripAction.Suggestion -> handle(composer.candidateTapped(action.index))
            StripAction.Latin -> handle(composer.rawLatin())
            is StripAction.Punctuation -> type(action.text)
            else -> Unit
        }
    }

    override fun onHint(text: String) = type(text)
    override fun onPanel(index: Int) = Unit
    override fun onDragStart() = Unit
    override fun onCaret(clusters: Int) = Unit

    companion object {
        fun secure(info: EditorInfo): Boolean {
            val cls = info.inputType and InputType.TYPE_MASK_CLASS
            val v = info.inputType and InputType.TYPE_MASK_VARIATION
            return (cls == InputType.TYPE_CLASS_TEXT && (v == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                v == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD || v == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)) ||
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
