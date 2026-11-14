package com.chhunly.typer.core

import java.io.File

/** What the Composer needs from the engine; tests wrap the real one to count calls. */
interface Suggester {
    fun suggest(input: String, k: Int): List<String>
    fun pick(input: String, index: Int)
}

/** A Suggester with nothing to offer: the Keyboard still types Latin when the engine can't load. */
object NoSuggestions : Suggester {
    override fun suggest(input: String, k: Int): List<String> = emptyList()
    override fun pick(input: String, index: Int) {}
}

/** The JNI functions in android/jni (libtyper_jni). Handles are opaque; 0 means "no engine". */
internal object NativeEngine {
    /** False when the library is missing (a broken install): the Keyboard then types Latin. */
    val available: Boolean = try {
        System.loadLibrary("typer_jni")
        true
    } catch (e: UnsatisfiedLinkError) {
        false
    }

    @JvmStatic external fun nativeNew(dataDir: String, userDir: String?): Long
    @JvmStatic external fun nativeFree(handle: Long)
    @JvmStatic external fun nativeSuggest(handle: Long, input: String, k: Int): Array<String>?
    @JvmStatic external fun nativePick(handle: Long, input: String, index: Int)
    @JvmStatic external fun nativeSetting(handle: Long, name: String): Boolean
}

/**
 * Thin wrapper over the Rust engine, like ios/TyperCore Engine.swift. If the data can't load, it suggests
 * nothing and learns nothing, so the Keyboard still types Latin. Not thread-safe: the Keyboard reaches it only
 * through the Composer's one engine thread (Scheduler).
 */
class Engine(private val dataDir: String, private val userDir: String?) : Suggester {
    private var handle = open()

    private fun open(): Long = if (NativeEngine.available) NativeEngine.nativeNew(dataDir, userDir) else 0L

    val loaded: Boolean get() = handle != 0L

    override fun suggest(input: String, k: Int): List<String> {
        if (k <= 0 || handle == 0L) return emptyList()
        return NativeEngine.nativeSuggest(handle, input, k)?.toList() ?: emptyList()
    }

    override fun pick(input: String, index: Int) {
        if (index >= 0 && handle != 0L) NativeEngine.nativePick(handle, input, index)
    }

    /** Settings switch ("learn", "english", "generated"); on when the engine can't load. */
    fun setting(name: String): Boolean = handle == 0L || NativeEngine.nativeSetting(handle, name)

    /**
     * "Reset what Typer learned": deletes user.tsv and picks.tsv, then reloads, because the engine keeps learned
     * counts in memory. Same object, so a Composer holding it needs no rebuild.
     */
    fun resetLearning() {
        userDir?.let { dir -> listOf("user.tsv", "picks.tsv").forEach { File(dir, it).delete() } }
        close()
        handle = open()
    }

    fun close() {
        if (handle != 0L) NativeEngine.nativeFree(handle)
        handle = 0L
    }
}
