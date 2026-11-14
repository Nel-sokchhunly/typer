package com.chhunly.typer.core

/** Whether shift should start on, following the field's capitalisation like the system keyboard. Port of AutoCap.swift. */
object AutoCap {
    enum class Kind { NONE, WORDS, SENTENCES, ALL_CHARACTERS }

    /** Khmer mode never auto-capitalises (Sing is typed lower case); English mode follows the field. */
    fun shouldShift(before: String?, kind: Kind, khmerMode: Boolean): Boolean {
        if (khmerMode) return false
        val text = before ?: ""
        return when (kind) {
            Kind.NONE -> false
            Kind.ALL_CHARACTERS -> true
            Kind.WORDS -> text.lastOrNull()?.isWhitespace() ?: true
            Kind.SENTENCES -> {
                val last = text.lastOrNull() ?: return true
                if (last == '\n' || last == '\r') return true
                if (!last.isWhitespace()) return false
                // whitespace after a sentence end; the end itself must come right before the spaces
                val end = text.trimEnd().lastOrNull() ?: return true
                end in ".?!"
            }
        }
    }
}
