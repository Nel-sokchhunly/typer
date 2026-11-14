package com.chhunly.typer

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.os.SystemClock
import com.chhunly.typer.core.Engine
import com.chhunly.typer.ime.EngineData

/**
 * Debug builds only: loads the engine on the device and asks for one Phrase.
 *   adb shell am instrument -w -e input "knhom tov sala rean" com.chhunly.typer/.EngineCheck
 * prints INSTRUMENTATION_RESULT lines: loaded, first, all, load_ms, suggest_ms.
 * With `-e keys true` it also replays the input one character at a time on the same engine, as typing does (the
 * engine reuses work from the previous keystroke), and reports per_key_ms (each keystroke), mean_ms and max_ms.
 */
class EngineCheck : Instrumentation() {
    private var input = "knhom tov sala rean"
    private var keys = false

    override fun onCreate(arguments: Bundle?) {
        arguments?.getString("input")?.let { input = it }
        keys = arguments?.getString("keys") == "true"
        super.onCreate(arguments)
        start()
    }

    override fun onStart() {
        val out = Bundle()
        val context = targetContext
        val t0 = SystemClock.elapsedRealtime()
        val data = EngineData.dataDir(context)
        val engine = Engine(data?.path ?: "/nonexistent", EngineData.userDir(context).path)
        val t1 = SystemClock.elapsedRealtime()
        val suggestions = engine.suggest(input, 9)
        val t2 = SystemClock.elapsedRealtime()
        if (keys) {
            val times = (1..input.length).map { n ->
                val t = System.nanoTime()
                engine.suggest(input.substring(0, n), 9)
                (System.nanoTime() - t) / 1e6
            }
            out.putString("per_key_ms", times.joinToString(" ") { "%.1f".format(it) })
            out.putString("mean_ms", "%.1f".format(times.average()))
            out.putString("max_ms", "%.1f".format(times.max()))
        }
        val loaded = engine.loaded
        out.putString("loaded", loaded.toString())
        out.putString("first", suggestions.firstOrNull() ?: "")
        out.putString("all", suggestions.joinToString(" | "))
        out.putString("load_ms", (t1 - t0).toString())
        out.putString("suggest_ms", (t2 - t1).toString())
        engine.close()
        finish(if (loaded) Activity.RESULT_OK else Activity.RESULT_CANCELED, out)
    }
}
