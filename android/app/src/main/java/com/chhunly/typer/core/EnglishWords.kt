package com.chhunly.typer.core

import java.io.InputStream
import kotlin.math.abs
import kotlin.math.min

/**
 * English word suggestions for English mode, from Typer's own data (data/out/english.tsv: "word<TAB>count" and
 * "w1 w2<TAB>count" lines), standing in for iOS's UITextChecker. Same contract as iOS's englishWords(before:):
 * [the word as typed, best, second], or empty when nothing helps. Prefix completions ranked by count (bigrams with
 * the previous word first); a spelling fix only when nothing completes the word and it isn't a word itself.
 * User-dictionary words that complete the word come first. Pure: no I/O after [load], safe on the main thread.
 */
class EnglishWords private constructor(
    private val sorted: Array<String>,  // unigrams, sorted, for prefix ranges
    private val counts: HashMap<String, Long>,
    private val bigrams: HashMap<String, Long>,
) {
    fun suggest(before: String?, userWords: List<String>): List<String> {
        if (before == null) return emptyList()
        val word = before.takeLastWhile { it.isLetter() || it == '\'' }
        if (word.isEmpty() || word == "'") return emptyList()
        val lower = word.lowercase()
        val prev = before.dropLast(word.length).trimEnd().takeLastWhile { it.isLetter() || it == '\'' }.lowercase()

        val found = ArrayList<String>()
        userWords.firstOrNull { it.length > word.length && it.lowercase().startsWith(lower) }?.let { found += it }
        found += completions(lower, prev)
        if (found.isEmpty() && lower !in counts) found += fixes(lower)

        val seen = hashSetOf(lower)
        val capital = word[0].isUpperCase()
        val picks = found.asSequence()
            .map { if (capital) it.replaceFirstChar { c -> c.uppercaseChar() } else it }
            .filter { seen.add(it.lowercase()) }
            .take(2)
            .toList()
        return if (picks.isEmpty()) emptyList() else listOf(word) + picks
    }

    /** Longer words starting with `prefix`: those that follow `prev` in a bigram first, then by count. */
    private fun completions(prefix: String, prev: String): List<String> {
        var lo = sorted.binarySearch(prefix).let { if (it < 0) -it - 1 else it }
        val out = ArrayList<String>()
        while (lo < sorted.size && sorted[lo].startsWith(prefix)) {
            if (sorted[lo].length > prefix.length) out += sorted[lo]
            lo++
        }
        val bigram = { w: String -> if (prev.isEmpty()) 0L else bigrams["$prev $w"] ?: 0L }
        return out.sortedWith(compareByDescending<String> { bigram(it) }.thenByDescending { counts[it] ?: 0L }).take(3)
    }

    /** Known words one edit away (two for longer words), most common first. */
    private fun fixes(word: String): List<String> {
        val max = if (word.length >= 6) 2 else 1
        return counts.keys.asSequence()
            .filter { abs(it.length - word.length) <= max && distance(word, it, max) <= max }
            .sortedByDescending { counts[it] ?: 0L }
            .take(3)
            .toList()
    }

    companion object {
        fun load(input: InputStream): EnglishWords {
            val counts = HashMap<String, Long>(32768)
            val bigrams = HashMap<String, Long>(32768)
            input.bufferedReader().useLines { lines ->
                for (line in lines) {
                    val tab = line.indexOf('\t')
                    if (tab <= 0) continue
                    val w = line.substring(0, tab)
                    val c = line.substring(tab + 1).toLongOrNull() ?: continue
                    if (' ' in w) bigrams[w] = c else counts[w] = c
                }
            }
            return EnglishWords(counts.keys.sorted().toTypedArray(), counts, bigrams)
        }

        /** Optimal string alignment distance (a swap counts as one edit), stopping early past `max`. */
        fun distance(a: String, b: String, max: Int): Int {
            val n = a.length
            val m = b.length
            var prev2 = IntArray(m + 1)
            var prev = IntArray(m + 1) { it }
            var cur = IntArray(m + 1)
            for (i in 1..n) {
                cur[0] = i
                var best = cur[0]
                for (j in 1..m) {
                    val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                    var v = min(min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
                    if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) v = min(v, prev2[j - 2] + 1)
                    cur[j] = v
                    if (v < best) best = v
                }
                if (best > max) return max + 1
                val t = prev2
                prev2 = prev
                prev = cur
                cur = t
            }
            return prev[m]
        }
    }
}
