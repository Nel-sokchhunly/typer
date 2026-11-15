package com.chhunly.typer.core

import java.io.InputStream

/**
 * Next-word suggestions for Khmer, from Typer's own n-gram counts (data/out/ngrams.tsv: "n<TAB>w1 w2 ...<TAB>count",
 * words already segmented). Khmer text has no spaces, so the words before the caret are found by longest match
 * against the known words, from the caret back. The two last words pick the followers seen after them most
 * (trigrams), then the last word alone (bigrams). Pure: no I/O after [load].
 */
class NextWords private constructor(
    private val words: Set<String>,
    private val after1: Map<String, List<String>>,
    private val after2: Map<String, List<String>>,
    private val longest: Int,
) {
    /** Up to `k` words likely to follow the Khmer text before the caret; empty if it doesn't end in a known word. */
    fun khmer(before: String?, k: Int = 3): List<String> {
        if (before.isNullOrEmpty() || before.last() !in KHMER) return emptyList()
        val last = lastWord(before) ?: return emptyList()
        val prev = lastWord(before.dropLast(last.length))
        val out = LinkedHashSet<String>()
        prev?.let { after2["$it $last"]?.let(out::addAll) }
        after1[last]?.let(out::addAll)
        return out.take(k)
    }

    /** The longest known word ending at the end of `s` (Khmer letters only). */
    private fun lastWord(s: String): String? {
        val tail = s.takeLastWhile { it in KHMER }
        for (n in minOf(longest, tail.length) downTo 1) {
            val w = tail.substring(tail.length - n)
            if (w in words) return w
        }
        return null
    }

    companion object {
        private val KHMER = 'ក'..'៿'
        private const val KEEP = 3

        fun load(input: InputStream): NextWords {
            val words = HashSet<String>(32768)
            val follow1 = HashMap<String, ArrayList<Pair<String, Long>>>()
            val follow2 = HashMap<String, ArrayList<Pair<String, Long>>>()
            input.bufferedReader().useLines { lines ->
                for (line in lines) {
                    val f = line.split('\t')
                    if (f.size < 3) continue
                    val gram = f[1].split(' ')
                    val count = f[2].toLongOrNull() ?: continue
                    if (gram.any { it.startsWith("<") || it.isEmpty() || it[0] !in KHMER }) continue
                    when (gram.size) {
                        1 -> words += gram[0]
                        2 -> follow1.getOrPut(gram[0]) { ArrayList() } += gram[1] to count
                        3 -> follow2.getOrPut("${gram[0]} ${gram[1]}") { ArrayList() } += gram[2] to count
                    }
                }
            }
            fun top(m: Map<String, List<Pair<String, Long>>>) =
                m.mapValues { (_, v) -> v.sortedByDescending { it.second }.take(KEEP).map { it.first } }
            return NextWords(words, top(follow1), top(follow2), words.maxOfOrNull { it.length } ?: 0)
        }
    }
}
