package com.chhunly.typer.core

import kotlin.math.ln
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Glide (swipe) typing for English words: the finger's path is compared with the path each word would trace through
 * the key centres, as in the published shape-writing method (SHARK2, Kristensson and Zhai, 2004). Two distances,
 * both on paths resampled to [POINTS] evenly spaced points: location (where the paths are, in key widths) and shape
 * (the paths moved to the same centre and size). Common words win close calls. Candidates are the words starting near
 * where the finger went down and ending near where it lifted, whose every letter the path passes near.
 * Pure Kotlin over Typer's own English word counts (data/out/english.tsv); no I/O, no Android.
 */
class GlideDecoder(counts: Map<String, Long>) {
    private class Entry(val word: String, val letters: String, val weight: Float)

    /** Words by first and last letter, for the candidates near the path's two ends. */
    private val buckets = HashMap<Int, ArrayList<Entry>>()

    init {
        for ((word, count) in counts) {
            if (word.length < 2 || count <= 0) continue
            val letters = word.lowercase().filter { it in 'a'..'z' }
            if (letters.length < 2 || letters.length + 1 < word.length) continue  // letters, at most one apostrophe
            val collapsed = StringBuilder().apply { for (c in letters) if (isEmpty() || last() != c) append(c) }.toString()
            buckets.getOrPut(key(letters.first(), letters.last())) { ArrayList() } += Entry(word, collapsed, ln(count.toFloat()))
        }
    }

    private fun key(a: Char, b: Char) = (a - 'a') * 32 + (b - 'a')

    /**
     * The best words for a path (dp, start to end), best first. `keys`: each letter's key centre (dp). `keyWidth`:
     * a letter key's width, the unit for "near".
     */
    fun decode(xs: FloatArray, ys: FloatArray, keys: Map<Char, Pair<Float, Float>>, keyWidth: Float, limit: Int = 3): List<String> {
        if (xs.size < 2) return emptyList()
        val near = keyWidth * 1.25f
        fun around(x: Float, y: Float) = keys.filter { (_, c) -> dist(x, y, c.first, c.second) < near }.keys
        val firsts = around(xs.first(), ys.first())
        val lasts = around(xs.last(), ys.last())
        if (firsts.isEmpty() || lasts.isEmpty()) return emptyList()

        val path = resample(xs, ys, POINTS)
        val dense = resample(xs, ys, POINTS * 2)
        val pathShape = normalise(path)
        val pathLength = length(xs, ys)

        val scored = ArrayList<Pair<Float, String>>()
        for (f in firsts) for (l in lasts) for (e in buckets[key(f, l)] ?: continue) {
            val tx = FloatArray(e.letters.length)
            val ty = FloatArray(e.letters.length)
            var known = true
            for ((i, c) in e.letters.withIndex()) {
                val k = keys[c] ?: run { known = false; null } ?: break
                tx[i] = k.first; ty[i] = k.second
            }
            if (!known) continue
            // the path passes near every letter
            var passes = true
            for (i in tx.indices) {
                var best = Float.MAX_VALUE
                for (j in dense.indices step 2) best = minOf(best, dist(tx[i], ty[i], dense[j], dense[j + 1]))
                if (best > near) { passes = false; break }
            }
            if (!passes) continue
            val wordLength = length(tx, ty)
            if (wordLength > pathLength * 2.2f + keyWidth || pathLength > wordLength * 2.2f + keyWidth) continue
            val template = resample(tx, ty, POINTS)
            val location = mean(path, template) / keyWidth
            val shape = mean(pathShape, normalise(template))
            val cost = location + 2f * shape - FREQUENCY * e.weight
            scored += cost to e.word
        }
        return scored.sortedBy { it.first }.map { it.second }.distinct().take(limit)
    }

    companion object {
        const val POINTS = 32
        /** How much a word's commonness (log count) counts against its distance. */
        const val FREQUENCY = 0.06f

        private fun dist(ax: Float, ay: Float, bx: Float, by: Float): Float {
            val dx = ax - bx
            val dy = ay - by
            return sqrt(dx * dx + dy * dy)
        }

        private fun length(xs: FloatArray, ys: FloatArray): Float {
            var total = 0f
            for (i in 1 until xs.size) total += dist(xs[i - 1], ys[i - 1], xs[i], ys[i])
            return total
        }

        /** `n` points evenly spaced along the polyline, as x0, y0, x1, y1, ... (a single point repeats). */
        fun resample(xs: FloatArray, ys: FloatArray, n: Int): FloatArray {
            val out = FloatArray(n * 2)
            val total = length(xs, ys)
            if (total == 0f) {
                for (i in 0 until n) { out[2 * i] = xs[0]; out[2 * i + 1] = ys[0] }
                return out
            }
            val step = total / (n - 1)
            var seg = 1
            var segStart = 0f  // distance along the path where segment `seg` starts
            for (i in 0 until n) {
                val at = minOf(i * step, total)
                while (seg < xs.size - 1 && segStart + dist(xs[seg - 1], ys[seg - 1], xs[seg], ys[seg]) < at) {
                    segStart += dist(xs[seg - 1], ys[seg - 1], xs[seg], ys[seg])
                    seg++
                }
                val segLength = dist(xs[seg - 1], ys[seg - 1], xs[seg], ys[seg])
                val t = if (segLength == 0f) 0f else ((at - segStart) / segLength).coerceIn(0f, 1f)
                out[2 * i] = xs[seg - 1] + t * (xs[seg] - xs[seg - 1])
                out[2 * i + 1] = ys[seg - 1] + t * (ys[seg] - ys[seg - 1])
            }
            return out
        }

        /** Centred on its centroid and scaled so its bounding box's longer side is 1. */
        private fun normalise(p: FloatArray): FloatArray {
            val n = p.size / 2
            var cx = 0f; var cy = 0f
            var minX = Float.MAX_VALUE; var maxX = -Float.MAX_VALUE; var minY = Float.MAX_VALUE; var maxY = -Float.MAX_VALUE
            for (i in 0 until n) {
                val x = p[2 * i]; val y = p[2 * i + 1]
                cx += x; cy += y
                minX = minOf(minX, x); maxX = maxOf(maxX, x); minY = minOf(minY, y); maxY = maxOf(maxY, y)
            }
            cx /= n; cy /= n
            val scale = max(max(maxX - minX, maxY - minY), 1e-3f)
            return FloatArray(p.size) { if (it % 2 == 0) (p[it] - cx) / scale else (p[it] - cy) / scale }
        }

        private fun mean(a: FloatArray, b: FloatArray): Float {
            var total = 0f
            for (i in 0 until a.size / 2) total += dist(a[2 * i], a[2 * i + 1], b[2 * i], b[2 * i + 1])
            return total / (a.size / 2)
        }
    }
}
