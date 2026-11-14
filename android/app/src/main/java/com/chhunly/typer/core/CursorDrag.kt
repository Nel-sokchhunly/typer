package com.chhunly.typer.core

/**
 * The UTF-16 offset that moves the caret `clusters` clusters (negative = left, positive = right) without stopping
 * inside one; port of CursorDrag.swift. Clamped to the available context; 0 when it is null or empty that way.
 * A cluster is an extended grapheme cluster (regex \X), except that a coeng (U+17D2) joins the next one: grapheme
 * rules split ខ្ញុំ into ខ្ + ញុំ, which is exactly the break a drag must not stop at.
 */
fun cursorOffset(before: String?, after: String?, clusters: Int): Int {
    fun units(s: String?): List<Int> {  // UTF-16 length of each cluster
        val out = ArrayList<Int>()
        var joined = false
        for (m in GRAPHEME.findAll(s ?: "")) {
            val g = m.value
            if (joined) out[out.size - 1] += g.length else out += g.length
            joined = g.last() == '្'
        }
        return out
    }
    return if (clusters < 0) -units(before).takeLast(-clusters).sum() else units(after).take(clusters).sum()
}

private val GRAPHEME = Regex("\\X")
