package com.chhunly.typer.core

import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** The Keyboard's link to the host app. The real one wraps InputConnection (ime/ProxyAdapter.kt). */
interface TextProxy {
    /** Text before the caret, as the host reports it (may or may not include marked text; may be null). */
    val documentContextBeforeInput: String?

    /** Replace the marked text (or insert at the caret) with `text`, marked, caret at its end. "" clears it. */
    fun setMarkedText(text: String)

    /** Keep the marked text as plain text. */
    fun unmarkText()
    fun insertText(text: String)
    fun deleteBackward()

    /**
     * Whether the caret still sits right after the marked text, when the host can tell exactly (Android reports the
     * composing span in onUpdateSelection). Null: unknown, so the Composer judges from the context, as on iOS.
     */
    fun caretAfterMarkedText(typed: String): Boolean? = null
}

/**
 * Where engine work runs. The Rust engine is not thread-safe: every engine call goes through [async] / [sync],
 * which must be one serial thread. [main] hops back to the main thread. Tests use [immediate].
 */
class Scheduler(
    val async: (() -> Unit) -> Unit,
    val sync: (() -> Unit) -> Unit,
    val main: (() -> Unit) -> Unit,
) {
    companion object {
        val immediate = Scheduler({ it() }, { it() }, { it() })

        /** One engine thread; `main` posts to the UI thread (the Keyboard passes Handler::post). */
        fun background(main: (Runnable) -> Unit): Scheduler {
            val engineThread = AtomicInteger()
            val q: ExecutorService = Executors.newSingleThreadExecutor { r ->
                Thread(r, "typer-engine").also { engineThread.set(it.hashCode()); it.priority = Thread.MAX_PRIORITY - 1 }
            }
            return Scheduler(
                async = { job -> q.execute(job) },
                sync = { job ->
                    if (Thread.currentThread().name == "typer-engine") job() else q.submit(Callable { job() }).get()
                },
                main = { job -> main(Runnable(job)) },
            )
        }
    }
}

/** How a field wants its keys. Everything but TEXT passes straight through, like English mode. */
enum class FieldType { TEXT, EMAIL, URL, NUMBER }

/**
 * Sing Khmer typing rules, ported from ios/TyperCore Composer.swift (itself from the macOS input method) and kept
 * in step with it by fixtures/composer.json. Letters, `'`, spaces and ASCII punctuation build a Latin Phrase
 * shown as Marked text; [suggestions] are its Khmer conversions. Every event returns whether it consumed the key;
 * if not, the Keyboard does its normal thing with it.
 */
class Composer(
    private val engine: Suggester,
    private val proxy: TextProxy,
    /** `false` is the fallback for hosts that mishandle marked text: the Phrase is typed as plain text, and a
     *  commit deletes its length and inserts the choice. */
    private val usesMarkedText: Boolean,
    private val scheduler: Scheduler,
) {
    companion object {
        /** Shared by every Keyboard instance while the process lives, like macOS and iOS. */
        @Volatile private var english = false
    }

    var suggestions: List<String> = emptyList()
        private set

    /** The Phrase as typed, for the strip's abc control. */
    var typed = ""
        private set
    val isComposing get() = typed.isNotEmpty()

    /** "ខ" or "EN"; a secure, email or number field shows EN, and a URL field starts EN. */
    val mode: String get() = if (passthrough) "EN" else "ខ"

    /** Called on the main thread when new Suggestions arrive after a key (they are computed off-thread). */
    var onSuggestions: (() -> Unit)? = null

    private var suggestionsFor = ""  // the Phrase `suggestions` were computed for
    private var requestSeq = 0  // main thread: bumped on every Phrase change
    private val latest = AtomicInteger()  // same value, readable from the engine thread to skip stale work
    private var secure = false
    private var fieldType = FieldType.TEXT
    private var urlKhmer = false  // ខ tapped in this URL field (a search in Khmer); the global mode stays as it was
    private var anchor: String? = null  // marked text: the context before the caret when the Phrase began
    private var shown = ""  // without marked text: the Phrase as plain text in the document (ASCII)

    private val passthrough: Boolean
        get() = when (fieldType) {
            FieldType.TEXT -> english || secure
            FieldType.URL -> !urlKhmer || secure
            FieldType.EMAIL, FieldType.NUMBER -> true
        }

    /** Passthrough is on. If it came on mid-Phrase (EN toggled in another instance), keep the Phrase as typed. */
    private fun passingThrough(): Boolean {
        if (!passthrough) return false
        keepLatin()
        return true
    }

    /** A typed character: letter, `'`, space, punctuation, digit, emoji, ... */
    fun key(text: String): Boolean {
        if (passingThrough()) return false
        if (text.codePointCount(0, text.length) != 1) return otherKey()
        val c = text[0]
        val starting = !isComposing
        val ascii = c.code < 128
        when {
            ascii && (c.isLetter() || c == '\'') -> typed += c
            c == ' ' && isComposing -> if (!typed.endsWith(" ")) typed += " "  // space separates words, never commits
            isComposing && ascii && c in ASCII_PUNCTUATION -> typed += c  // stays as typed: "knhom," -> ខ្ញុំ,
            else -> return otherKey()
        }
        if (starting) anchor = proxy.documentContextBeforeInput
        update()
        return true
    }

    /** Digit, emoji, ...: insert the top Suggestion, then let the key through. */
    private fun otherKey(): Boolean {
        if (isComposing) commit(0)
        return false
    }

    fun backspace(): Boolean {
        if (passingThrough() || !isComposing) return false
        typed = typed.dropLast(1)
        update()
        return true
    }

    fun returnKey(): Boolean {
        if (passingThrough() || !isComposing) return false
        commit(0)
        return true
    }

    fun candidateTapped(index: Int): Boolean {
        if (passingThrough() || !isComposing) return false
        commit(index)
        return true
    }

    /** The abc control: insert the Phrase exactly as typed, learn nothing. */
    fun rawLatin(): Boolean {
        if (passingThrough() || !isComposing) return false
        write(typed, final = true)
        return true
    }

    /** Whether the ខ/EN key does anything right now; the Keyboard dims it otherwise. */
    val canToggle: Boolean get() = !isComposing && !secure && (fieldType == FieldType.TEXT || fieldType == FieldType.URL)

    /**
     * Khmer <-> English. Ignored mid-Phrase (a stray tap) and in fields that are English anyway. In a URL field it
     * switches only that field, so typing a search in Khmer leaves the global mode alone.
     */
    fun toggleMode(): Boolean {
        if (!canToggle) return false
        if (fieldType == FieldType.URL) urlKhmer = !urlKhmer else english = !english
        return true
    }

    /**
     * The selection or text changed (onUpdateSelection), including the echoes of the Composer's own writes.
     * Mid-Phrase, if the caret no longer sits right after the Phrase, keep the Phrase as typed.
     */
    fun textChanged(): Boolean {
        if (!isComposing || stillAfterPhrase()) return false
        return keepLatin()
    }

    /**
     * Whether the text before the caret is what the Composer left there. A null context counts as yes: some hosts
     * never report it, and a false "moved" would end every Phrase after one letter.
     */
    private fun stillAfterPhrase(): Boolean {
        if (usesMarkedText) proxy.caretAfterMarkedText(typed)?.let { return it }
        val before = proxy.documentContextBeforeInput ?: return true
        if (!usesMarkedText) return before.endsWith(shown)
        return before.endsWith(typed) || before == anchor  // the host may or may not count marked text
    }

    /** Focus left the field or the Keyboard was hidden: keep the Phrase as typed. */
    fun fieldEnded(): Boolean = keepLatin()

    /** A new field, or its traits changed (re-reported unchanged traits are ignored). */
    fun fieldTraitsChanged(secure: Boolean, type: FieldType): Boolean {
        if (secure == this.secure && type == fieldType) return false
        val kept = keepLatin()
        this.secure = secure
        fieldType = type
        urlKhmer = false
        return kept
    }

    /** Marked text updates now; Suggestions follow from the engine thread, the latest request wins. */
    private fun update() {
        invalidate()
        if (typed.isNotEmpty()) {
            val input = typed
            val seq = requestSeq
            scheduler.async {
                if (latest.get() != seq) return@async  // a newer key already superseded this one
                val result = engine.suggest(input, 9)
                scheduler.main {
                    if (requestSeq != seq) return@main
                    suggestions = result
                    suggestionsFor = input
                    onSuggestions?.invoke()
                }
            }
        }
        write(typed, final = typed.isEmpty())
    }

    private fun invalidate() {
        requestSeq++
        latest.set(requestSeq)
    }

    /** A Pick must come from the current Phrase: if its result hasn't landed, compute it now. */
    private fun commit(index: Int) {
        val input = typed
        if (suggestionsFor != input) {
            scheduler.sync { suggestions = engine.suggest(input, 9) }
            suggestionsFor = input
        }
        if (index !in suggestions.indices) {
            write(input, final = true)
            return
        }
        if (write(suggestions[index], final = true)) scheduler.async { engine.pick(input, index) }
    }

    /** Leave the Phrase in the document as it stands (Latin), no learning. */
    private fun keepLatin(): Boolean {
        if (!isComposing) return false
        if (usesMarkedText) proxy.unmarkText()
        reset()
        return true
    }

    /**
     * Show `text` as the Phrase; `final` ends the Phrase with `text` in the document. False if the fallback found
     * the caret moved and kept the Latin instead.
     */
    private fun write(text: String, final: Boolean): Boolean {
        if (usesMarkedText) {
            proxy.setMarkedText(text)
        } else {
            val same = shown.zip(text).takeWhile { it.first == it.second }.size
            val deletes = shown.length - same  // shown is ASCII: one deleteBackward per character
            if (deletes > 0 && proxy.documentContextBeforeInput?.endsWith(shown) != true) {
                keepLatin()  // don't delete blind: that could eat the user's text
                return false
            }
            repeat(deletes) { proxy.deleteBackward() }
            val rest = text.substring(same)
            if (rest.isNotEmpty()) proxy.insertText(rest)
            shown = text
        }
        if (final) {
            if (usesMarkedText) proxy.unmarkText()
            reset()
        }
        return true
    }

    private fun reset() {
        typed = ""
        shown = ""
        anchor = null
        suggestions = emptyList()
        suggestionsFor = ""
        invalidate()
    }
}

/** Swift's Character.isPunctuation || isSymbol over ASCII: every printable character but letters, digits, space. */
private const val ASCII_PUNCTUATION = "!\"#\$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
