package com.chhunly.typer.core

import kotlin.math.abs

sealed interface KeyEffect {
    /** Touch-down feedback: haptic and the key preview. */
    data object Press : KeyEffect
    data class Fire(val action: KeyAction) : KeyEffect
    /** Backspace auto-repeat; the caller owns the timer (400 ms, then every 50 ms). */
    data object StartRepeat : KeyEffect
    data object StopRepeat : KeyEffect
    /** Arm the long-press timer (300 ms); the caller calls `longPress` when it fires. */
    data object StartLongPress : KeyEffect
    /** The long-press character of a key (its hint digit). */
    data class FireHint(val text: String) : KeyEffect
    /** Space-bar drag: move the caret by this many clusters (negative = left). */
    data class MoveCaret(val clusters: Int) : KeyEffect
    data object DragStarted : KeyEffect
    /** The drag is over (finger up, cancelled, or a new touch took over): the caret is the user's again. */
    data object DragEnded : KeyEffect
}

/**
 * Touch rules, ported from ios/TyperCore KeyLayout.swift (KeyTouches) and extended for Android: keys fire on
 * touch-up for the key under the finger; a new touch finishes every earlier one at once (rollover), so at most one
 * touch is live; backspace fires on touch-down and repeats. Android adds long-press for the hint digit and a
 * space-bar drag that moves the caret (`step` dp of travel per cluster).
 */
class KeyTouches(private val step: Float = 10f) {
    private class Held(val id: Int, var key: Key, val repeating: Boolean, val startX: Float) {
        var long = false  // long-press fired: the touch-up types nothing
        var dragging = false
        var movedClusters = 0
        /** Space held, then released without sliding: still a space. */
        val spaceAfterAll get() = dragging && movedClusters == 0 && !moved
        var moved = false
    }

    private var held: Held? = null

    /** The key(s) to highlight. */
    val pressed: List<Key> get() = held?.let { if (it.long || it.dragging) emptyList() else listOf(it.key) } ?: emptyList()
    val dragging: Boolean get() = held?.dragging == true

    fun down(id: Int, key: Key, x: Float): List<KeyEffect> {
        val fx = ArrayList<KeyEffect>()
        held?.let { fx += finish(it) }
        fx += KeyEffect.Press
        val backspace = key.action == KeyAction.Backspace
        held = Held(id, key, backspace, x)
        if (backspace) fx += listOf(KeyEffect.Fire(KeyAction.Backspace), KeyEffect.StartRepeat)
        else if (key.hint != null || key.action == KeyAction.Space) fx += KeyEffect.StartLongPress
        return fx
    }

    /** What an earlier touch does when a new one lands (rollover). */
    private fun finish(h: Held): List<KeyEffect> = when {
        h.repeating -> listOf(KeyEffect.StopRepeat)
        h.spaceAfterAll -> listOf(KeyEffect.DragEnded, KeyEffect.Fire(KeyAction.Space))
        h.dragging -> listOf(KeyEffect.DragEnded)
        h.long -> emptyList()
        else -> listOf(KeyEffect.Fire(h.key.action))
    }

    fun move(id: Int, key: Key, x: Float): List<KeyEffect> {
        val h = held ?: return emptyList()
        if (h.id != id) return emptyList()
        if (h.key.action == KeyAction.Space && !h.repeating && !h.long) {
            if (!h.dragging && abs(x - h.startX) > step * 1.5f) {
                h.dragging = true
                return listOf(KeyEffect.DragStarted) + drag(h, x)
            }
            if (h.dragging) return drag(h, x)
        }
        if (h.dragging || h.long || h.key == key) return emptyList()
        val wasRepeating = h.repeating
        held = Held(id, key, false, x)
        return if (wasRepeating) listOf(KeyEffect.StopRepeat) else emptyList()
    }

    private fun drag(h: Held, x: Float): List<KeyEffect> {
        val target = ((x - h.startX) / step).toInt()
        val delta = target - h.movedClusters
        if (delta == 0) return emptyList()
        h.moved = true
        h.movedClusters = target
        return listOf(KeyEffect.MoveCaret(delta))
    }

    /** The long-press timer fired for touch `id`. */
    fun longPress(id: Int): List<KeyEffect> {
        val h = held ?: return emptyList()
        if (h.id != id || h.long || h.dragging || h.repeating) return emptyList()
        if (h.key.action == KeyAction.Space) {
            h.dragging = true  // hold space, then slide: the caret follows
            return listOf(KeyEffect.DragStarted)
        }
        val hint = h.key.hint ?: return emptyList()
        h.long = true
        return listOf(KeyEffect.FireHint(hint))
    }

    fun up(id: Int, key: Key): List<KeyEffect> {
        val h = held ?: return emptyList()
        if (h.id != id) return emptyList()
        held = null
        return when {
            h.repeating -> listOf(KeyEffect.StopRepeat)
            h.spaceAfterAll -> listOf(KeyEffect.DragEnded, KeyEffect.Fire(KeyAction.Space))
            h.dragging -> listOf(KeyEffect.DragEnded)
            h.long -> emptyList()
            else -> listOf(KeyEffect.Fire(key.action))
        }
    }

    fun cancel(id: Int): List<KeyEffect> {
        val h = held ?: return emptyList()
        if (h.id != id) return emptyList()
        held = null
        return when {
            h.repeating -> listOf(KeyEffect.StopRepeat)
            h.dragging -> listOf(KeyEffect.DragEnded)
            else -> emptyList()
        }
    }

    /** Drop the live touch; a drag in progress ends. */
    fun reset(): List<KeyEffect> {
        val h = held ?: return emptyList()
        held = null
        return if (h.dragging) listOf(KeyEffect.DragEnded) else emptyList()
    }
}
