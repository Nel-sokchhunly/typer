package com.chhunly.typer.ime

import android.view.KeyEvent
import android.view.inputmethod.ExtractedTextRequest
import android.view.inputmethod.InputConnection
import com.chhunly.typer.core.TextProxy

/**
 * InputConnection as the Composer's TextProxy. Marked text is the composing text (setComposingText); the caret
 * check uses the composing span that onUpdateSelection reports (see [selection]) instead of iOS's context guess.
 */
class ProxyAdapter(private val connection: () -> InputConnection?) : TextProxy {
    /** The latest onUpdateSelection: selection start/end and composing span start/end (-1: no composing text). */
    var selStart = -1
    var selEnd = -1
    var composeStart = -1
    var composeEnd = -1

    fun selection(selStart: Int, selEnd: Int, composeStart: Int, composeEnd: Int) {
        this.selStart = selStart
        this.selEnd = selEnd
        this.composeStart = composeStart
        this.composeEnd = composeEnd
    }

    override val documentContextBeforeInput: String?
        get() = connection()?.getTextBeforeCursor(CONTEXT, 0)?.toString()

    override fun setMarkedText(text: String) {
        connection()?.setComposingText(text, 1)
    }

    override fun unmarkText() {
        connection()?.finishComposingText()
    }

    override fun insertText(text: String) {
        connection()?.commitText(text, 1)
    }

    override fun deleteBackward() {
        val ic = connection() ?: return
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_DEL))
        ic.sendKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DEL))
    }

    /**
     * Caret right after the composing span: still in the Phrase. Otherwise the update may be a late echo of an
     * earlier write (fast typing after a commit), so ask the editor now: if the Phrase is right before the caret and
     * nothing is selected, it is. If the editor dropped the composing span itself, put it back over the Phrase so
     * the next key replaces the Phrase instead of typing a second copy.
     */
    override fun caretAfterMarkedText(typed: String): Boolean? {
        if (composeStart >= 0 && selStart == selEnd && selEnd == composeEnd) return true
        val ic = connection() ?: return null
        val before = ic.getTextBeforeCursor(typed.length, 0)?.toString() ?: return null
        val selected = ic.getSelectedText(0)
        if (before != typed || !selected.isNullOrEmpty()) return false
        if (composeStart < 0) {
            ic.getExtractedText(ExtractedTextRequest(), 0)?.let { t ->
                val caret = t.startOffset + t.selectionEnd
                ic.setComposingRegion(caret - typed.length, caret)
            }
        }
        return true
    }

    companion object {
        private const val CONTEXT = 256
    }
}
