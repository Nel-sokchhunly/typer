package com.chhunly.typer.ime

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.text.TextPaint
import android.text.TextUtils
import com.chhunly.typer.core.Box
import com.chhunly.typer.core.EmojiData
import com.chhunly.typer.core.Metrics
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * The emoji page, laid out in dp like the keys: a tab bar in the strip's place (search, recently used, one tab per
 * Unicode group), a scrolling grid of 8 columns with section titles (recently used first), and a skin-tone panel
 * on long press that stays open after lifting. Sizes from the Gboard reference study (8 columns, cells about
 * 52 dp, a 6-column tone panel); everything drawn and laid out here is Typer's own.
 * Pure layout and hit testing over [EmojiData]; [KeyboardView] draws it and routes touches.
 */
class EmojiPanel(private val data: EmojiData) {
    /** One line of the grid: a section title or up to eight emoji. */
    private sealed interface Line {
        data class Title(val text: String, val section: Int) : Line
        data class Cells(val emoji: List<String>, val section: Int) : Line
    }

    data class Tab(val label: String, val icon: String?, val section: Int)  // section -1 = search

    private var lines: List<Line> = emptyList()
    private var lineTop = FloatArray(0)
    var contentHeight = 0f
        private set
    var tabs: List<Tab> = emptyList()
        private set
    private var sectionTop = FloatArray(0)
    private var builtFor: Pair<List<String>, Map<String, String>>? = null
    private var m: Metrics? = null

    val cols = 8
    val titleHeight = 30f
    fun cellWidth(m: Metrics) = (m.width - 2 * m.margin) / cols
    fun cellHeight(m: Metrics) = min(cellWidth(m), 50f)

    /** The grid's viewport, between the tab bar and the bottom row. */
    fun viewport(m: Metrics) = Box(0f, m.rowsTop, m.width, m.rowsTop + 3 * m.pitch - m.rowGap / 2 - m.rowsTop)

    /** (Re)builds the lines when the width, recents or chosen tones change. */
    fun layout(m: Metrics, recents: List<String>, tones: Map<String, String>) {
        if (this.m?.width == m.width && this.m?.pitch == m.pitch && builtFor == (recents to tones)) return
        this.m = m
        builtFor = recents to tones
        val sections = ArrayList<Pair<String, List<String>>>()
        if (recents.isNotEmpty()) sections += RECENT to recents
        for (g in data.groups) sections += g.name to g.emoji.map { tones[it] ?: it }
        val out = ArrayList<Line>()
        val tops = ArrayList<Float>()
        val secTops = FloatArray(sections.size)
        var y = 0f
        val ch = cellHeight(m)
        for ((i, s) in sections.withIndex()) {
            secTops[i] = y
            out += Line.Title(s.first, i); tops += y; y += titleHeight
            for (row in s.second.chunked(cols)) {
                out += Line.Cells(row, i); tops += y; y += ch
            }
        }
        lines = out
        lineTop = tops.toFloatArray()
        sectionTop = secTops
        contentHeight = y
        tabs = listOf(Tab("search emoji", null, -1)) +
            sections.mapIndexed { i, s -> Tab(s.first, if (s.first == RECENT) null else ICONS[s.first] ?: s.second.first(), i) }
    }

    fun maxScroll(m: Metrics): Float = max(0f, contentHeight - viewport(m).height)

    fun scrollFor(section: Int): Float = sectionTop.getOrElse(section) { 0f }

    /** The section showing at the top of the viewport, for the tab underline. */
    fun sectionAt(scroll: Float): Int {
        var s = 0
        for ((i, t) in sectionTop.withIndex()) if (t <= scroll + 1f) s = i
        return s
    }

    fun tabBox(m: Metrics, i: Int): Box {
        val w = (m.width - 2 * m.margin) / tabs.size
        return Box(m.margin + i * w, m.stripTop, w, m.stripHeight)
    }

    /** The emoji under a point in the viewport (dp), with its cell box in view coordinates. */
    fun cellAt(m: Metrics, x: Float, y: Float, scroll: Float): Pair<String, Box>? {
        val vp = viewport(m)
        if (!vp.contains(x, y)) return null
        val cy = y - vp.top + scroll
        val i = lineTop.indexOfLast { it <= cy }.takeIf { it >= 0 } ?: return null
        val line = lines[i] as? Line.Cells ?: return null
        val cw = cellWidth(m)
        val col = ((x - m.margin) / cw).toInt()
        if (col !in line.emoji.indices) return null
        return line.emoji[col] to Box(m.margin + col * cw, vp.top + lineTop[i] - scroll, cw, cellHeight(m))
    }

    /** Every visible cell, for drawing and TalkBack. */
    fun visibleCells(m: Metrics, scroll: Float): List<Pair<String, Box>> {
        val vp = viewport(m)
        val cw = cellWidth(m)
        val ch = cellHeight(m)
        val out = ArrayList<Pair<String, Box>>()
        for ((i, line) in lines.withIndex()) {
            val top = vp.top + lineTop[i] - scroll
            if (top > vp.bottom || top + ch < vp.top || line !is Line.Cells) continue
            for ((c, e) in line.emoji.withIndex()) out += e to Box(m.margin + c * cw, top, cw, ch)
        }
        return out
    }

    fun visibleTitles(m: Metrics, scroll: Float): List<Pair<String, Float>> {
        val vp = viewport(m)
        return lines.indices.mapNotNull { i ->
            val line = lines[i] as? Line.Title ?: return@mapNotNull null
            val top = vp.top + lineTop[i] - scroll
            if (top > vp.bottom || top + titleHeight < vp.top) null else line.text to top
        }
    }

    /** The tone panel for `base`, above `cell`: 6 columns, the base first, kept inside the view. */
    fun tonePanel(m: Metrics, base: String, cell: Box): List<Pair<String, Box>> {
        val options = listOf(base) + (data.variants[base] ?: emptyList())
        val cw = cellWidth(m)
        val ch = cellHeight(m)
        val perRow = min(6, options.size)
        val rows = ceil(options.size / perRow.toFloat()).toInt()
        val w = perRow * cw
        val left = (cell.centerX - w / 2).coerceIn(m.margin, m.width - m.margin - w)
        val top = max(m.rowsTop, cell.top - rows * ch - 4f)
        return options.mapIndexed { i, e -> e to Box(left + (i % perRow) * cw, top + (i / perRow) * ch, cw, ch) }
    }

    // ---- drawing helpers used by KeyboardView ----

    fun drawEmoji(canvas: Canvas, paint: TextPaint, e: String, r: RectF, sizePx: Float) {
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = sizePx
        val fm = paint.fontMetrics
        canvas.drawText(e, r.centerX(), r.centerY() - (fm.ascent + fm.descent) / 2, paint)
    }

    fun ellipsize(paint: TextPaint, s: String, width: Float) = TextUtils.ellipsize(s, paint, width, TextUtils.TruncateAt.END).toString()

    companion object {
        const val RECENT = "Recently used"
        /** One emoji per tab, standing for its Unicode group (drawn with the phone's emoji font; no icon assets). */
        val ICONS = mapOf(
            "Smileys & Emotion" to "😀", "People & Body" to "👋", "Animals & Nature" to "🐻", "Food & Drink" to "🍔",
            "Travel & Places" to "🚗", "Activities" to "⚽", "Objects" to "💡", "Symbols" to "🔣", "Flags" to "🏁",
        )
    }
}
