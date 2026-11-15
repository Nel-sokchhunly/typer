package com.chhunly.typer.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * The emoji keyboard's data, from data/emoji.py: Unicode's emoji list in order (emoji.json), skin-tone variants
 * (emoji-variants.json) and CLDR names in English and Khmer (emoji-names.tsv) for search and TalkBack.
 */
class EmojiData(
    val groups: List<Group>,
    /** Base emoji -> its skin-tone variants. */
    val variants: Map<String, List<String>>,
    private val names: Map<String, Names>,
) {
    data class Group(val name: String, val emoji: List<String>)

    data class Names(val en: String, val enWords: List<String>, val km: String, val kmWords: List<String>)

    /** English name for TalkBack ("thumbs up"); the emoji itself if it has none. */
    fun label(emoji: String): String = names[emoji]?.en?.takeIf { it.isNotEmpty() } ?: names[base(emoji)]?.en ?: emoji

    /** A skin-tone variant's base emoji ("👍🏽" -> "👍"), else the emoji itself. */
    fun base(emoji: String): String = baseOf[emoji] ?: emoji

    private val baseOf: Map<String, String> = variants.flatMap { (b, vs) -> vs.map { it to b } }.toMap()
    private val order: Map<String, Int> = groups.flatMap { it.emoji }.withIndex().associate { it.value to it.index }

    /**
     * Emoji whose English or Khmer name or keywords match `query`, best first: an exact name, keyword or name word;
     * then a name starting with it; then a keyword or name word starting with it; then anything containing it.
     * Ties: commonly used emoji first ([POPULAR]), then Unicode's order. Skin-tone variants are left out: the base
     * stands for them (long press, remembered tone).
     */
    fun search(query: String, limit: Int = 48): List<String> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val scored = ArrayList<Pair<Int, String>>()
        for ((e, n) in names) {
            if (e in baseOf) continue
            val en = n.en.lowercase()
            val words = (n.enWords + n.kmWords).map { it.lowercase() }
            val nameWords = en.split(' ', ':', '-', ',').filter { it.isNotEmpty() }
            val score = when {
                en == q || n.km == q || q in words || q in nameWords -> 0
                en.startsWith(q) || n.km.startsWith(q) -> 1
                words.any { it.startsWith(q) } || nameWords.any { it.startsWith(q) } -> 2
                en.contains(q) || n.km.contains(q) || words.any { it.contains(q) } -> 3
                else -> continue
            }
            scored += score to e
        }
        return scored.sortedWith(compareBy({ it.first }, { popular[it.second] ?: Int.MAX_VALUE }, { order[it.second] ?: Int.MAX_VALUE }))
            .take(limit).map { it.second }
    }

    private val popular: Map<String, Int> = POPULAR.withIndex().associate { it.value to it.index }

    /**
     * The emoji to suggest for a whole word as it is typed (English or Khmer): one whose name is the word or that has
     * it as a keyword, the most used first; null if none. Words under three letters suggest nothing ("a", "i").
     */
    fun forWord(word: String): String? {
        val q = word.trim().lowercase()
        if (q.length < 3) return null
        return wordIndex[q]
    }

    private val wordIndex: Map<String, String> by lazy {
        val best = HashMap<String, String>()
        fun rank(e: String) = (popular[e] ?: Int.MAX_VALUE).toLong() * 10_000 + (order[e] ?: 9_999)
        for ((e, n) in names) {
            if (e in baseOf) continue
            val keys = HashSet<String>()
            keys += n.en.lowercase(); keys += n.km
            n.enWords.forEach { keys += it.lowercase() }; n.kmWords.forEach { keys += it }
            for (raw in keys) {
                val k = raw.replace("\u200B", "").trim()  // some CLDR Khmer keywords carry a zero-width space
                if (k.isNotEmpty()) best.merge(k, e) { a, b -> if (rank(a) <= rank(b)) a else b }
            }
        }
        best
    }

    companion object {
        /**
         * Roughly the most used emoji, most used first (after the Unicode Consortium's emoji frequency figures), so a
         * search for "heart" or "laugh" starts with ❤️ or 😂 rather than with whatever comes first in Unicode's order.
         */
        val POPULAR = listOf(
            "😂", "❤️", "🤣", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥", "☺️", "🤦", "♥️",
            "🤷", "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎", "👌", "💜", "😔", "💪", "✨", "💖", "👀",
            "😋", "😏", "😢", "👉", "💗", "😩", "💯", "🌹", "💞", "🎈", "💙", "😃", "😡", "💐", "😜", "🙈", "🤞", "😄", "🤤",
            "🙌", "🤪", "❣️", "😀", "💋", "💀", "👇", "💔", "😌", "💓", "🤩", "🙃", "😬", "😱", "😴", "🤭", "😐", "🌞", "😒",
            "😇", "🌸", "😈", "🎶", "✌️", "🎊", "🥵", "😞", "💚", "☀️", "🖤", "💰", "😚", "👑", "🎁", "💥", "🙋", "☹️", "😑",
            "🥴", "👈", "💩", "✅",
        )

        fun load(groupsJson: String, variantsJson: String, namesTsv: String): EmojiData {
            val g = JSONArray(groupsJson)
            val groups = (0 until g.length()).map { i ->
                val pair = g.getJSONArray(i)
                val es = pair.getJSONArray(1)
                Group(pair.getString(0), (0 until es.length()).map { es.getString(it) })
            }
            val v = JSONObject(variantsJson)
            val variants = v.keys().asSequence().associateWith { k ->
                val a = v.getJSONArray(k)
                (0 until a.length()).map { a.getString(it) }
            }
            val names = HashMap<String, Names>(4096)
            for (line in namesTsv.lineSequence()) {
                val f = line.split('\t')
                if (f.size < 5) continue
                fun words(s: String) = s.split(" | ").filter { it.isNotBlank() }
                names[f[0]] = Names(f[1], words(f[2]), f[3], words(f[4]))
            }
            return EmojiData(groups, variants, names)
        }
    }
}

/** Recently used emoji: newest first, no repeats, at most [max] (four rows of eight). */
object EmojiRecents {
    const val max = 32

    fun add(recents: List<String>, emoji: String): List<String> = (listOf(emoji) + recents.filter { it != emoji }).take(max)

    fun decode(s: String?): List<String> = s?.split('\n')?.filter { it.isNotEmpty() } ?: emptyList()

    fun encode(recents: List<String>): String = recents.joinToString("\n")
}
