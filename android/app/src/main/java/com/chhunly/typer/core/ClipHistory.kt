package com.chhunly.typer.core

/**
 * Clipboard history: the last [max] texts copied, newest first, each kept [keepMs] (an hour, as on Gboard), in
 * memory only. The newest one is "fresh" for [freshMs] after it was copied, until it is pasted or dismissed: the bar
 * then offers it as a one-tap paste. Times come from the caller (elapsed milliseconds). Sensitive clips (passwords)
 * never get here: the service drops them.
 */
class ClipHistory(private val max: Int = 10, private val keepMs: Long = 3_600_000L, val freshMs: Long = 60_000L) {
    private class Clip(val text: String, val at: Long)

    private val clips = ArrayList<Clip>()
    private var usedFresh: Clip? = null

    fun add(text: String, now: Long) {
        clips.removeAll { it.text == text }
        clips.add(0, Clip(text, now))
        while (clips.size > max) clips.removeAt(clips.size - 1)
    }

    /** The clips still kept, newest first. */
    fun list(now: Long): List<String> {
        clips.removeAll { now - it.at > keepMs }
        return clips.map { it.text }
    }

    /** The newest clip if copied less than [freshMs] ago and not pasted or dismissed yet. */
    fun fresh(now: Long): String? = clips.firstOrNull()?.takeIf { now - it.at < freshMs && it !== usedFresh }?.text

    /** The fresh clip was pasted or dismissed: the bar stops offering it. */
    fun freshUsed() {
        usedFresh = clips.firstOrNull()
    }

    fun clear() {
        clips.clear()
        usedFresh = null
    }
}
