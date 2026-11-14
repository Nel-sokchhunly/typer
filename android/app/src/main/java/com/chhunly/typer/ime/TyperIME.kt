package com.chhunly.typer.ime

import android.inputmethodservice.InputMethodService
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.inputmethod.EditorInfo
import com.chhunly.typer.core.Engine
import com.chhunly.typer.core.KeyAction
import com.chhunly.typer.core.StripAction
import java.util.concurrent.Executors

/** Tracer bullet: letters, space and backspace build the Phrase as composing text; the strip shows the first Suggestion. */
class TyperIME : InputMethodService(), KeyboardView.Listener {
    private val engineThread = Executors.newSingleThreadExecutor { Thread(it, "typer-engine") }
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var view: KeyboardView? = null
    private var typed = ""
    private var suggestions = emptyList<String>()
    private var seq = 0

    override fun onCreate() {
        super.onCreate()
        engineThread.execute {
            val data = EngineData.dataDir(this)
            engine = Engine(data?.path ?: "/nonexistent", EngineData.userDir(this).path)
        }
    }

    override fun onDestroy() {
        engineThread.execute { engine?.close() }
        engineThread.shutdown()
        super.onDestroy()
    }

    override fun onCreateInputView(): View = KeyboardView(this, this).also { view = it }

    override fun onStartInputView(info: EditorInfo?, restarting: Boolean) {
        super.onStartInputView(info, restarting)
        view?.theme = KeyboardTheme.from(this)
        reset()
    }

    private fun reset() {
        typed = ""
        suggestions = emptyList()
        seq++
        render()
    }

    private fun render() {
        view?.state = KeyboardView.State(typed = typed, suggestions = suggestions)
    }

    private fun update() {
        val ic = currentInputConnection ?: return
        ic.setComposingText(typed, 1)
        val mine = ++seq
        val input = typed
        if (input.isEmpty()) {
            suggestions = emptyList()
            ic.finishComposingText()
        } else engineThread.execute {
            val result = engine?.suggest(input, 9) ?: emptyList()
            main.post { if (mine == seq) { suggestions = result; render() } }
        }
        render()
    }

    override fun onKey(action: KeyAction) {
        val ic = currentInputConnection ?: return
        when (action) {
            is KeyAction.Text -> if (action.text.length == 1 && action.text[0].isLetter()) { typed += action.text; update() } else ic.commitText(action.text, 1)
            KeyAction.Space -> if (typed.isNotEmpty()) { if (!typed.endsWith(" ")) typed += " "; update() } else ic.commitText(" ", 1)
            KeyAction.Backspace -> if (typed.isNotEmpty()) { typed = typed.dropLast(1); update() } else ic.deleteSurroundingText(1, 0)
            else -> Unit
        }
    }

    override fun onStrip(action: StripAction) {
        val ic = currentInputConnection ?: return
        if (action is StripAction.Suggestion && typed.isNotEmpty()) {
            val pick = suggestions.getOrNull(action.index) ?: typed
            val input = typed
            ic.commitText(pick, 1)
            if (action.index < suggestions.size) engineThread.execute { engine?.pick(input, action.index) }
            reset()
        }
    }

    override fun onHint(text: String) = Unit
    override fun onPanel(index: Int) = Unit
    override fun onDragStart() = Unit
    override fun onCaret(clusters: Int) = Unit
}
