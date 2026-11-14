package com.chhunly.typer.core

import kotlin.math.hypot
import kotlin.math.max

/** A rectangle in dp, in the Keyboard view's coordinates. */
data class Box(val left: Float, val top: Float, val width: Float, val height: Float) {
    val right: Float get() = left + width
    val bottom: Float get() = top + height
    val centerX: Float get() = left + width / 2
    val centerY: Float get() = top + height / 2
    fun contains(x: Float, y: Float) = x in left..right && y in top..bottom

    /** Distance from a point to the box; 0 inside. */
    fun distance(x: Float, y: Float): Float = hypot(max(max(left - x, 0f), x - right), max(max(top - y, 0f), y - bottom))
}

enum class KeyPage { LETTERS, NUMBERS, SYMBOLS }

sealed interface KeyAction {
    /** A typed character: letter, digit, punctuation or symbol. */
    data class Text(val text: String) : KeyAction
    data object Shift : KeyAction
    /** Numbers page <-> symbols page. */
    data object Symbols : KeyAction
    /** Letters page <-> numbers page. */
    data object Page : KeyAction
    data object Backspace : KeyAction
    /** ខ/EN: Khmer mode <-> English mode. */
    data object Mode : KeyAction
    data object Space : KeyAction
    data object Return : KeyAction
}

/** How a key is drawn: letters and space on the lightest surface, function keys on secondary container. */
enum class KeyStyle { LETTER, FUNCTION, ACTION, MODE }

/** `hint`: the long-press character, drawn small in the top-right corner (digits on the letters page's top row). */
data class Key(val action: KeyAction, val box: Box, val style: KeyStyle, val hint: String? = null)

/**
 * Sizes in dp from android/docs/reference.md (measured on Gboard): side margin 4.5, gap 1.29% of the width,
 * row pitch from the screen height, keys 80% of the pitch, a 48 dp suggestion strip plus 4 dp above row 1.
 */
class Metrics(val width: Float, screenHeight: Float) {
    val margin = 4.5f
    val gap = (width * 0.0129f).coerceIn(4f, 6f)
    /** Gboard scales rows with screen height: 59 dp at 914 dp tall, 50.5 dp at 800; a line through both. */
    val pitch = (screenHeight * 0.07456f - 9.15f).coerceIn(46f, 64f)
    val keyHeight = pitch * 0.8f
    val rowGap = pitch - keyHeight
    val stripHeight = 48f
    val rowsTop = stripHeight + 4f
    val keyWidth = (width - 2 * margin - 9 * gap) / 10
    /** Strip, four rows and the padding under the last row; the navigation bar inset comes on top. */
    val height = rowsTop + 4 * keyHeight + 3 * rowGap + rowGap
    /** Rounded keys: Gboard's corner scales with the key (about 7.5 dp at 411 dp wide, 6.5 at 360). */
    val radius = keyWidth * 0.215f
}

object KeyLayout {
    private val letters = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    private const val digits = "1234567890"
    private val numbers = listOf(digits, "@#\$_&-+()/", "*\"':;!?")
    private val symbols = listOf("~`|•√π÷×¶∆", "£¢€¥^°={}\\", "%©®™✓[]")

    /** The idle strip's keys: Khmer punctuation in Khmer mode, the common English ones in English mode (as iOS). */
    val punctuation = listOf("។", "៕", "ៗ", "៛", "?", "!")
    val englishPunctuation = listOf(",", ".", "'", "\"", "@", "-")

    /** `upper`: letters page with shift on. */
    fun keys(m: Metrics, page: KeyPage, upper: Boolean): List<Key> {
        val out = ArrayList<Key>(40)
        val k = m.keyWidth
        val g = m.gap
        val wide = 1.5f * k + 0.5f * g  // shift, backspace, ?123 and return: one and a half keys
        fun rowTop(i: Int) = m.rowsTop + i * m.pitch
        fun add(a: KeyAction, x: Float, row: Int, w: Float, style: KeyStyle, hint: String? = null) =
            out.add(Key(a, Box(x, rowTop(row), w, m.keyHeight), style, hint))

        val rows = when (page) {
            KeyPage.LETTERS -> letters
            KeyPage.NUMBERS -> numbers
            KeyPage.SYMBOLS -> symbols
        }
        for (i in 0..2) {
            var x = m.margin
            if (i == 2) {
                add(if (page == KeyPage.LETTERS) KeyAction.Shift else KeyAction.Symbols, x, i, wide, KeyStyle.FUNCTION)
                x += wide + g
            }
            if (i == 1 && rows[1].length == 9) x += (k + g) / 2
            for ((j, c) in rows[i].withIndex()) {
                val s = c.toString()
                val label = if (page == KeyPage.LETTERS && upper) s.uppercase() else s
                val hint = if (page == KeyPage.LETTERS && i == 0) digits[j].toString() else null
                add(KeyAction.Text(label), x, i, k, KeyStyle.LETTER, hint)
                x += k + g
            }
            if (i == 2) add(KeyAction.Backspace, m.width - m.margin - wide, i, wide, KeyStyle.FUNCTION)
        }

        var x = m.margin
        fun next(a: KeyAction, w: Float, style: KeyStyle) {
            add(a, x, 3, w, style)
            x += w + g
        }
        next(KeyAction.Page, wide, KeyStyle.FUNCTION)
        next(KeyAction.Mode, k, KeyStyle.MODE)
        next(KeyAction.Text(","), k, KeyStyle.FUNCTION)
        next(KeyAction.Space, 4 * k + 3 * g, KeyStyle.LETTER)
        next(KeyAction.Text("."), k, KeyStyle.FUNCTION)
        add(KeyAction.Return, m.width - m.margin - wide, 3, wide, KeyStyle.ACTION)
        return out
    }

    /** The key containing the point, else the nearest: no dead zones in the gaps or at the edges. */
    fun hit(x: Float, y: Float, keys: List<Key>): Key? = keys.minByOrNull { it.box.distance(x, y) }
}

/** What a strip slot does when tapped. */
sealed interface StripAction {
    data class Suggestion(val index: Int) : StripAction
    /** Keep the Phrase as typed (Latin), learn nothing. */
    data object Latin : StripAction
    /** Open or close the all-Suggestions panel. */
    data object Expand : StripAction
    data class Punctuation(val text: String) : StripAction
    /** English mode: word suggestion `index` (0 = the word as typed). */
    data class Word(val index: Int) : StripAction
}

data class StripSlot(val action: StripAction, val box: Box)

object StripLayout {
    /** Width of the abc and expand controls at the strip's right end. */
    const val CONTROL = 52f

    /** Composing: up to three Suggestions side by side, then abc and the expand control with the count. */
    fun composing(m: Metrics, suggestions: Int): List<StripSlot> {
        val right = m.width - m.margin
        val expand = StripSlot(StripAction.Expand, Box(right - CONTROL, 0f, CONTROL, m.stripHeight))
        val latin = StripSlot(StripAction.Latin, Box(right - 2 * CONTROL, 0f, CONTROL, m.stripHeight))
        val n = suggestions.coerceIn(1, 3)
        val w = (right - 2 * CONTROL - m.margin) / n
        return List(n) { StripSlot(StripAction.Suggestion(it), Box(m.margin + it * w, 0f, w, m.stripHeight)) } +
            listOf(latin, expand)
    }

    /** Idle: the punctuation row across the whole strip. */
    fun punctuation(m: Metrics, marks: List<String>): List<StripSlot> {
        val w = (m.width - 2 * m.margin) / marks.size
        return marks.mapIndexed { i, p -> StripSlot(StripAction.Punctuation(p), Box(m.margin + i * w, 0f, w, m.stripHeight)) }
    }

    /** English words in Typer's order: best, second, then the word as typed (index 0) in quotes. */
    fun words(m: Metrics, count: Int): List<StripSlot> {
        val order = (1 until count) + 0
        val w = (m.width - 2 * m.margin) / order.size
        return order.mapIndexed { i, idx -> StripSlot(StripAction.Word(idx), Box(m.margin + i * w, 0f, w, m.stripHeight)) }
    }
}
