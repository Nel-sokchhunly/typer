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

enum class KeyPage { LETTERS, NUMBERS, SYMBOLS, KHMER }

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
    /** Open the emoji page. */
    data object Emoji : KeyAction
    /** Open Typer's settings (the Companion app): long press on the comma key, as on Gboard. */
    data object Settings : KeyAction
}

/** How a key is drawn: letters and space on the lightest surface, function keys on secondary container. */
enum class KeyStyle { LETTER, FUNCTION, ACTION, MODE }

/**
 * `hint`: the long-press character, drawn small in the top-right corner (digits on the letters page's top row).
 * `more`: several long-press characters, chosen by sliding in a popup (the Khmer page); `hint` is then the first.
 */
data class Key(
    val action: KeyAction, val box: Box, val style: KeyStyle, val hint: String? = null, val more: List<String> = emptyList(),
    /** What a long press does instead of a hint or alternates (the comma key's settings). */
    val long: KeyAction? = null,
)

/** The field's kind, for the bottom row: email fields get @, URL fields /, and both .com on the period. */
enum class FieldKind { TEXT, EMAIL, URL }

/**
 * Sizes in dp from android/docs/reference.md (measured on Gboard): side margin 4.5, gap 1.29% of the width,
 * row pitch from the screen height, keys 80% of the pitch, a 48 dp suggestion strip plus 4 dp above row 1.
 */
/**
 * `extraTop`: room above the strip, e.g. the emoji search results row. `rows`: 4, or 5 on the Khmer page and with the
 * number row. `scale`: the keyboard height setting (rows a little shorter or taller).
 */
class Metrics(val width: Float, screenHeight: Float, val extraTop: Float = 0f, val rows: Int = 4, val scale: Float = 1f) {
    val margin = 4.5f
    val gap = (width * 0.0129f).coerceIn(4f, 6f)
    /** Gboard scales rows with screen height: 59 dp at 914 dp tall, 50.5 dp at 800; a line through both. */
    val pitch = (screenHeight * 0.07456f - 9.15f).coerceIn(46f, 64f) * scale
    val keyHeight = pitch * 0.8f
    val rowGap = pitch - keyHeight
    val stripHeight = 48f
    val stripTop = extraTop
    val rowsTop = extraTop + stripHeight + 4f
    val keyWidth = (width - 2 * margin - 9 * gap) / 10
    /** The Khmer page's keys: 12 to a row. */
    val khmerKeyWidth = (width - 2 * margin - 11 * gap) / 12
    /** Strip, the rows and the padding under the last row; the navigation bar inset comes on top. */
    val height = rowsTop + rows * keyHeight + rows * rowGap
    val bottomRow get() = rows - 1
    /** Rounded keys: Gboard's corner scales with the key (about 7.5 dp at 411 dp wide, 6.5 at 360). */
    val radius = keyWidth * 0.215f
}

object KeyLayout {
    private val letters = listOf("qwertyuiop", "asdfghjkl", "zxcvbnm")
    private const val digits = "1234567890"
    private val numbers = listOf(digits, "@#\$_&-+()/", "*\"':;!?")
    private val symbols = listOf("~`|•√π÷×¶∆", "£¢€¥^°={}\\", "%©®™✓[]")

    /** Long press on rows 2 and 3 of the letters: Gboard's symbol for each key. */
    private val SYMBOLS = mapOf(
        'a' to "@", 's' to "#", 'd' to "$", 'f' to "%", 'g' to "&", 'h' to "-", 'j' to "+", 'k' to "(", 'l' to ")",
        'z' to "*", 'x' to "\"", 'c' to "'", 'v' to ":", 'b' to ";", 'n' to "!", 'm' to "?",
    )

    /** Long press on a letter: its accented forms, after the digit or symbol. */
    private val ACCENTS = mapOf(
        'a' to listOf("à", "á", "â", "ä", "æ", "ã", "å", "ā"),
        'c' to listOf("ç", "ć", "č"),
        'e' to listOf("è", "é", "ê", "ë", "ē", "ė", "ę"),
        'i' to listOf("î", "ï", "í", "ī", "į", "ì"),
        'l' to listOf("ł"),
        'n' to listOf("ñ", "ń"),
        'o' to listOf("ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"),
        's' to listOf("ß", "ś", "š"),
        'u' to listOf("û", "ü", "ù", "ú", "ū"),
        'y' to listOf("ÿ"),
        'z' to listOf("ž", "ź", "ż"),
    )

    /** Long press on the period: more punctuation in text fields, domain endings in email and URL fields. */
    private val PERIOD_MORE = listOf(".", "!", "?", ",", ";", ":", "'", "\"", "-")
    private val DOMAINS = listOf(".", ".com", ".net", ".org", ".edu")

    /** The idle strip's keys: Khmer punctuation in Khmer mode, the common English ones in English mode (as iOS). */
    val punctuation = listOf("។", "៕", "ៗ", "៛", "?", "!")
    val englishPunctuation = listOf(",", ".", "'", "\"", "@", "-")
    /** The Khmer layout's bar: the Khmer punctuation, plus comma and period (the layout has no keys for them). */
    val khmerLayoutPunctuation = punctuation + listOf(",", ".")

    /**
     * `upper`: letters page with shift on. `khmerLayout`: the numbers and symbols pages were opened from the Khmer
     * layout, so they leave out the ខ/EN key (Khmer mode means nothing there) and ?123's way back reads កខគ.
     */
    fun keys(m: Metrics, page: KeyPage, upper: Boolean, khmerLayout: Boolean = false, numberRow: Boolean = false, field: FieldKind = FieldKind.TEXT): List<Key> {
        if (page == KeyPage.KHMER) return khmer(m, upper)
        val out = ArrayList<Key>(40)
        val k = m.keyWidth
        val g = m.gap
        val wide = 1.5f * k + 0.5f * g  // shift, backspace, ?123 and return: one and a half keys
        val digitsRow = numberRow && page == KeyPage.LETTERS  // the digits get their own row above the letters
        val off = if (digitsRow) 1 else 0
        fun rowTop(i: Int) = m.rowsTop + (i + off) * m.pitch
        fun add(a: KeyAction, x: Float, row: Int, w: Float, style: KeyStyle, hint: String? = null, more: List<String> = emptyList()) =
            out.add(Key(a, Box(x, rowTop(row), w, m.keyHeight), style, hint, more))

        val rows = when (page) {
            KeyPage.LETTERS, KeyPage.KHMER -> letters
            KeyPage.NUMBERS -> numbers
            KeyPage.SYMBOLS -> symbols
        }
        if (digitsRow) {
            for ((j, c) in digits.withIndex()) add(KeyAction.Text(c.toString()), m.margin + j * (k + g), -1, k, KeyStyle.LETTER)
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
                if (page == KeyPage.LETTERS) {
                    // long press: the digit (top row) or Gboard's symbol (rows 2 and 3) first, then accents
                    val first = if (i == 0) (if (digitsRow) null else digits[j].toString()) else SYMBOLS[c]
                    val accents = ACCENTS[c].orEmpty().mapNotNull { a -> if (upper) a.uppercase().takeIf { it.length == 1 } else a }
                    val options = listOfNotNull(first) + accents
                    add(KeyAction.Text(label), x, i, k, KeyStyle.LETTER, options.firstOrNull(), if (options.size > 1) options else emptyList())
                } else {
                    add(KeyAction.Text(label), x, i, k, KeyStyle.LETTER)
                }
                x += k + g
            }
            if (i == 2) add(KeyAction.Backspace, m.width - m.margin - wide, i, wide, KeyStyle.FUNCTION)
        }

        bottomRow(m, out, mode = page == KeyPage.LETTERS || !khmerLayout, punctuation = true, field = field)
        return out
    }

    /**
     * The bottom row: ?123, ខ/EN (`mode`), comma, emoji, space, period, return. The Khmer layout has no ខ/EN key and
     * no comma or period keys (they are in its bar); space takes the room left.
     */
    private fun bottomRow(m: Metrics, out: MutableList<Key>, mode: Boolean, punctuation: Boolean, field: FieldKind = FieldKind.TEXT) {
        val k = m.keyWidth
        val g = m.gap
        val wide = 1.5f * k + 0.5f * g
        val top = m.rowsTop + m.bottomRow * m.pitch
        val right = m.width - m.margin - wide  // the return key's left edge
        var x = m.margin
        fun next(a: KeyAction, w: Float, style: KeyStyle, more: List<String> = emptyList(), long: KeyAction? = null) {
            out.add(Key(a, Box(x, top, w, m.keyHeight), style, null, more, long))
            x += w + g
        }
        next(KeyAction.Page, wide, KeyStyle.FUNCTION)
        if (mode) next(KeyAction.Mode, k, KeyStyle.MODE)
        val comma = when (field) {
            FieldKind.EMAIL -> "@"
            FieldKind.URL -> "/"
            FieldKind.TEXT -> ","
        }
        if (punctuation) next(KeyAction.Text(comma), k, KeyStyle.FUNCTION, long = KeyAction.Settings)
        next(KeyAction.Emoji, k, KeyStyle.FUNCTION)  // where Gboard has it, after the comma
        val after = if (punctuation) k + g else 0f  // the period, after space
        next(KeyAction.Space, right - g - after - x, KeyStyle.LETTER)
        if (punctuation) next(KeyAction.Text("."), k, KeyStyle.FUNCTION, if (field == FieldKind.TEXT) PERIOD_MORE else DOMAINS)
        out.add(Key(KeyAction.Return, Box(right, top, wide, m.keyHeight), KeyStyle.ACTION))
    }

    /**
     * The Khmer page: the standard Khmer keyboard arrangement (as on Gboard's Khmer layout): Khmer digits, three
     * rows of letters and signs, 12 keys to a row, shift for the second level. Each key is "text" or
     * "text alternate alternate..." (long press). It types characters as they are: no Sing, no Learning.
     */
    private val khmerBase = listOf(
        listOf("១ 1 ៱", "២ 2 ៲", "៣ 3 ៳", "៤ 4 ៴", "៥ 5 ៵", "៦ 6 ៶", "៧ 7 ៷", "៨ 8 ៸", "៩ 9 ៹", "០ 0 ៰", "ឥ ឦ", "ឲ ឱ"),
        listOf("ឆ", "ឹ", "េ", "រ", "ត", "យ", "ុ", "ិ", "ោ", "ផ", "ៀ", "ឪ ឧ ឱ ឳ ឩ ឨ"),
        listOf("ា", "ស", "ដ", "ថ", "ង", "ហ", "្", "ក", "ល", "ើ", "់", "ឮ ឭ ឰ"),
        listOf("ឋ", "ខ", "ច", "វ", "ប", "ន", "ម", "ុំ", "។", "៊ ៘"),
    )
    private val khmerShift = listOf(
        listOf("! \u200D", "ៗ \u200C", "\" ៑", "៛ $ €", "% ៖", "៍ ៙", "័ ៚", "៏ ៗ", "( { «", ") } »", "៌ ×", "៎"),
        listOf("ឈ ៜ", "ឺ ៝", "ែ", "ឬ ឫ", "ទ", "ួ", "ូ", "ី", "ៅ", "ភ", "ឿ", "ឰ"),
        listOf("ាំ", "ៃ", "ឌ", "ធ", "អ", "ះ ៈ", "ញ", "គ ឝ", "ឡ", "ោះ", "៉", "ឯ"),
        listOf("ឍ", "ឃ", "ជ", "េះ", "ព ឞ", "ណ", "ំ", "ុះ", "៕", "?"),
    )

    private fun khmer(m: Metrics, upper: Boolean): List<Key> {
        val out = ArrayList<Key>(56)
        val k = m.khmerKeyWidth
        val g = m.gap
        for ((i, row) in (if (upper) khmerShift else khmerBase).withIndex()) {
            val top = m.rowsTop + i * m.pitch
            var x = m.margin
            if (i == 3) {
                out.add(Key(KeyAction.Shift, Box(x, top, k, m.keyHeight), KeyStyle.FUNCTION))
                x += k + g
            }
            for (spec in row) {
                val parts = spec.split(' ')
                val more = parts.drop(1)
                out.add(Key(KeyAction.Text(parts[0]), Box(x, top, k, m.keyHeight), KeyStyle.LETTER, more.firstOrNull(), if (more.size > 1) more else emptyList()))
                x += k + g
            }
            if (i == 3) out.add(Key(KeyAction.Backspace, Box(x, top, m.width - m.margin - x, m.keyHeight), KeyStyle.FUNCTION))
        }
        bottomRow(m, out, mode = false, punctuation = false)
        return out
    }

    /**
     * How a key's text is drawn: a combining sign (ិ, ្, ុំ) sits on a dotted circle, as in Khmer keyboard charts;
     * the invisible joiners (long press on ! and ៗ) by name.
     */
    fun label(text: String): String {
        if (text == "\u200D") return "ZWJ"
        if (text == "\u200C") return "ZWNJ"
        val t = Character.getType(text.codePointAt(0))
        return if (t == Character.NON_SPACING_MARK.toInt() || t == Character.COMBINING_SPACING_MARK.toInt()) "\u25CC$text" else text
    }

    /** The emoji page's bottom row: back to the letters, space, delete. */
    fun emojiRow(m: Metrics): List<Key> {
        val k = m.keyWidth
        val g = m.gap
        val wide = 1.5f * k + 0.5f * g
        val top = m.rowsTop + m.bottomRow * m.pitch
        return listOf(
            Key(KeyAction.Page, Box(m.margin, top, wide, m.keyHeight), KeyStyle.FUNCTION),
            Key(KeyAction.Space, Box(m.margin + wide + g, top, m.width - 2 * m.margin - 2 * wide - 2 * g, m.keyHeight), KeyStyle.LETTER),
            Key(KeyAction.Backspace, Box(m.width - m.margin - wide, top, wide, m.keyHeight), KeyStyle.FUNCTION),
        )
    }

    /** The key containing the point, else the nearest: no dead zones in the gaps or at the edges. */
    fun hit(x: Float, y: Float, keys: List<Key>): Key? = keys.minByOrNull { it.box.distance(x, y) }
}

/** What a strip slot does when tapped. */
sealed interface StripAction {
    data class Suggestion(val index: Int) : StripAction
    /** Keep the Phrase as typed (Latin), learn nothing. */
    data object Latin : StripAction
    /** The bar's last slot when no Phrase is open: កខគ to the Khmer layout, abc back to the Sing layout. */
    data object Layout : StripAction
    /** The bar's first slot when idle: open or close clipboard history. */
    data object Clipboard : StripAction
    /** Text copied in the last minute, offered as a one-tap paste. */
    data object Paste : StripAction
    /** A next-word suggestion (index into the list). */
    data class Next(val index: Int) : StripAction
    /** An emoji for the word just typed ("love" -> ❤️). */
    data object Emoji : StripAction
    /** Open or close the all-Suggestions panel. */
    data object Expand : StripAction
    data class Punctuation(val text: String) : StripAction
    /** English mode: word suggestion `index` (0 = the word as typed). */
    data class Word(val index: Int) : StripAction
}

data class StripSlot(val action: StripAction, val box: Box)

/**
 * The strip, as on iOS: pills in the 48 dp strip, 6 dp apart. Composing: the top Suggestion fills the
 * width (the others are in the panel), then abc and the expand control with the count.
 */
object StripLayout {
    /** Width of the abc and expand controls at the strip's right end. */
    const val CONTROL = 52f
    /** Width of the layout switch (កខគ / abc), the bar's last slot when no Phrase is open. */
    const val LAYOUT = 60f
    const val PILL = 40f  // iOS uses 36; Khmer stacks want a little more
    const val GAP = 6f

    private fun pill(m: Metrics, left: Float, width: Float) = Box(left, m.stripTop + (m.stripHeight - PILL) / 2, width, PILL)

    /** The top Suggestion, the expand control, then abc (keep Latin) in the last slot. */
    fun composing(m: Metrics): List<StripSlot> {
        val right = m.width - m.margin
        val latin = StripSlot(StripAction.Latin, pill(m, right - CONTROL, CONTROL))
        val expand = StripSlot(StripAction.Expand, pill(m, right - 2 * CONTROL - GAP, CONTROL))
        val top = StripSlot(StripAction.Suggestion(0), pill(m, m.margin, right - 2 * CONTROL - 2 * GAP - m.margin))
        return listOf(top, expand, latin)
    }

    /** `items` pills of equal width, then the layout switch in the last slot. */
    private fun row(m: Metrics, items: Int): List<Box> {
        val w = (m.width - 2 * m.margin - LAYOUT - items * GAP) / items
        return List(items) { pill(m, m.margin + it * (w + GAP), w) }
    }

    private fun layout(m: Metrics) = StripSlot(StripAction.Layout, pill(m, m.width - m.margin - LAYOUT, LAYOUT))

    /** Width of the clipboard button, the idle bar's first slot. */
    const val CLIPBOARD = 44f

    /**
     * Idle: the clipboard button, the punctuation row (or, with `paste`, the freshly copied text to paste), then the
     * layout switch.
     */
    fun punctuation(m: Metrics, marks: List<String>, paste: Boolean = false): List<StripSlot> {
        val clip = StripSlot(StripAction.Clipboard, pill(m, m.margin, CLIPBOARD))
        val left = m.margin + CLIPBOARD + GAP
        val right = m.width - m.margin - LAYOUT - GAP
        if (paste) return listOf(clip, StripSlot(StripAction.Paste, pill(m, left, right - left)), layout(m))
        val w = (right - left - (marks.size - 1) * GAP) / marks.size
        return listOf(clip) + marks.mapIndexed { i, s -> StripSlot(StripAction.Punctuation(s), pill(m, left + i * (w + GAP), w)) } + layout(m)
    }

    /**
     * After a word, idle: the clipboard button, `count` next words, then `marks` (Khmer keeps ។ here), then the
     * layout switch.
     */
    fun next(m: Metrics, count: Int, marks: List<String>, emoji: Boolean = false): List<StripSlot> {
        val clip = StripSlot(StripAction.Clipboard, pill(m, m.margin, CLIPBOARD))
        val markW = 40f
        val all = if (emoji) listOf<StripAction>(StripAction.Emoji) + marks.map { StripAction.Punctuation(it) } else marks.map { StripAction.Punctuation(it) }
        val right = m.width - m.margin - LAYOUT - GAP - all.size * (markW + GAP)
        val left = m.margin + CLIPBOARD + GAP
        val w = (right - left - (count - 1) * GAP) / count
        val out = arrayListOf(clip)
        for (i in 0 until count) out += StripSlot(StripAction.Next(i), pill(m, left + i * (w + GAP), w))
        for ((i, a) in all.withIndex()) out += StripSlot(a, pill(m, right + GAP + i * (markW + GAP), markW))
        return out + layout(m)
    }

    /**
     * English words in Typer's order: best, second, then the word as typed (index 0) in quotes; then the layout
     * switch. `glided`: the glided word (index 0) first, then its alternatives.
     */
    fun words(m: Metrics, count: Int, glided: Boolean = false, emoji: Boolean = false): List<StripSlot> {
        val order = if (glided) (0 until count).toList() else (1 until count) + 0
        if (!emoji) return row(m, order.size).mapIndexed { i, b -> StripSlot(StripAction.Word(order[i]), b) } + layout(m)
        val e = 44f
        val w = (m.width - 2 * m.margin - LAYOUT - e - (order.size + 1) * GAP) / order.size
        return order.mapIndexed { i, o -> StripSlot(StripAction.Word(o), pill(m, m.margin + i * (w + GAP), w)) } +
            StripSlot(StripAction.Emoji, pill(m, m.width - m.margin - LAYOUT - GAP - e, e)) + layout(m)
    }
}
