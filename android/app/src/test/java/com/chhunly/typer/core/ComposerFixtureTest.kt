package com.chhunly.typer.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.nio.file.Files

/** A text field: `before` + `after` with the caret between; the last `marked` characters of `before` are marked. */
class FakeProxy : TextProxy {
    var before = ""
    var after = ""
    var marked = 0
    var contextHasMarked = true  // whether the host counts marked text as before the caret
    var contextNil = false  // hosts that never report context
    val doc get() = before + after
    val markedText get() = before.takeLast(marked)

    override val documentContextBeforeInput: String?
        get() = if (contextNil) null else if (contextHasMarked) before else before.dropLast(marked)

    override fun setMarkedText(text: String) {
        before = before.dropLast(marked) + text
        marked = text.length
    }

    override fun unmarkText() {
        marked = 0
    }

    override fun insertText(text: String) {
        before = before.dropLast(marked) + text  // inserting replaces the marked text
        marked = 0
    }

    override fun deleteBackward() {
        if (before.isEmpty()) return
        before = before.dropLast(1)
        marked = maxOf(0, marked - 1)
    }

    /** The user taps `n` characters to the left; the host keeps the marked text as plain text. */
    fun moveCaretLeft(n: Int) {
        marked = 0
        after = before.takeLast(n) + after
        before = before.dropLast(n)
    }
}

/** The real engine, counting calls. */
class Spy(val engine: Engine) : Suggester {
    var suggests = 0
    val picks = ArrayList<String>()
    override fun suggest(input: String, k: Int): List<String> {
        suggests++
        return engine.suggest(input, k)
    }

    override fun pick(input: String, index: Int) {
        picks += input
        engine.pick(input, index)
    }
}

/** Holds engine jobs and main hops until the test runs them, to play out any ordering. */
class ManualScheduler {
    val engine = ArrayList<() -> Unit>()
    val main = ArrayList<() -> Unit>()
    val scheduler = Scheduler(async = { engine += it }, sync = { it() }, main = { main += it })
    fun runEngine(i: Int) = engine[i]()
    fun runMain() {
        val m = main.toList()
        main.clear()
        m.forEach { it() }
    }

    fun runAll() {
        engine.toList().forEach { it() }
        runMain()
    }
}

/** Runs every case of fixtures/composer.json, the Composer behaviour shared with iOS (docs/adr/0001). */
@RunWith(Parameterized::class)
class ComposerFixtureTest(private val name: String, private val case: JSONObject) {
    companion object {
        private val fixtures = File(System.getProperty("typer.fixtures") ?: "../../fixtures")
        private val dataDir = System.getProperty("typer.data") ?: "../../data/out"

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> {
            val cases = JSONObject(File(fixtures, "composer.json").readText()).getJSONArray("cases")
            return (0 until cases.length()).map { arrayOf(cases.getJSONObject(it).getString("name"), cases.getJSONObject(it)) }
        }
    }

    private val userDir: File = Files.createTempDirectory("typer-android").toFile()
    private var proxy = FakeProxy()
    private lateinit var spy: Spy
    private lateinit var composer: Composer
    private var manual: ManualScheduler? = null
    private var published = 0
    private val saved = HashMap<String, Any>()

    private fun make(data: String = dataDir, usesMarkedText: Boolean = true) {
        spy = Spy(Engine(data, userDir.path))
        manual = null
        composer = Composer(spy, proxy, usesMarkedText, Scheduler.immediate)
    }

    @Test
    fun run() {
        make()
        assertTrue("no engine data: run python3 data/build.py and build android/jni for this machine", spy.engine.loaded)
        if (composer.mode == "EN") composer.toggleMode()  // the mode is shared: undo other cases
        try {
            val steps = case.getJSONArray("steps")
            for (i in 0 until steps.length()) {
                val step = steps.getJSONObject(i)
                try {
                    step(step)
                } catch (e: AssertionError) {
                    throw AssertionError("step ${i + 1} ${step}: ${e.message}", e)
                }
            }
        } finally {
            userDir.deleteRecursively()
        }
    }

    private fun type(s: String) {
        var i = 0
        while (i < s.length) {
            val n = Character.charCount(s.codePointAt(i))
            val c = s.substring(i, i + n)
            if (!composer.key(c)) proxy.insertText(c)
            i += n
        }
    }

    private fun field(s: String) = when (s) {
        "text" -> FieldType.TEXT
        "email" -> FieldType.EMAIL
        "url" -> FieldType.URL
        "number" -> FieldType.NUMBER
        else -> error("field $s")
    }

    private val picksFile get() = File(userDir, "picks.tsv").let { if (it.isFile) it.readText() else "" }

    private fun step(s: JSONObject) {
        val consumed: Boolean? = when (val op = s.getString("op")) {
            "type" -> { type(s.getString("text")); null }
            "key" -> composer.key(s.getString("text"))
            "backspace" -> { if (!composer.backspace()) proxy.deleteBackward(); null }
            "return" -> { if (!composer.returnKey()) proxy.insertText("\n"); null }
            "composerBackspace" -> composer.backspace()
            "returnKey" -> composer.returnKey()
            "rawLatin" -> composer.rawLatin()
            "toggle" -> composer.toggleMode()
            "textChanged" -> composer.textChanged()
            "fieldEnded" -> composer.fieldEnded()
            "tap" -> composer.candidateTapped(
                when {
                    s.has("index") -> s.getInt("index")
                    s.has("saved") -> saved[s.getString("saved")] as Int
                    else -> composer.suggestions.indexOf(s.getString("text")).also { assertTrue("no ${s.getString("text")} in ${composer.suggestions}", it >= 0) }
                }
            )
            "traits" -> composer.fieldTraitsChanged(s.getBoolean("secure"), field(s.getString("field")))
            "moveCaretLeft" -> { proxy.moveCaretLeft(s.getInt("n")); null }
            "setBefore" -> { proxy.before = s.getString("text"); proxy.marked = 0; null }
            "proxy" -> {
                if (s.has("contextHasMarked")) proxy.contextHasMarked = s.getBoolean("contextHasMarked")
                if (s.has("contextNil")) proxy.contextNil = s.getBoolean("contextNil")
                null
            }
            "remake" -> {
                spy.engine.close()
                make(if (s.optBoolean("missingData")) "/nonexistent" else dataDir, s.optBoolean("usesMarkedText", true))
                null
            }
            "manual" -> {
                val m = ManualScheduler()
                manual = m
                composer = Composer(spy, proxy, true, m.scheduler)
                composer.onSuggestions = { published++ }
                null
            }
            "runEngine" -> { manual!!.runEngine(s.getInt("index")); null }
            "runMain" -> { manual!!.runMain(); null }
            "runAll" -> { manual!!.runAll(); null }
            "otherToggle" -> Composer(spy, FakeProxy(), true, Scheduler.immediate).toggleMode()
            "otherMode" -> { assertEquals(s.getString("expect"), Composer(spy, proxy, true, Scheduler.immediate).mode); null }
            "setting" -> { Settings(userDir.path).set(s.getString("name"), s.getBoolean("on")); null }
            "writeUserFile" -> { userDir.mkdirs(); File(userDir, s.getString("name")).writeText(s.getString("content")); null }
            "resetLearning" -> { spy.engine.resetLearning(); null }
            "engineSuggest" -> {
                assertEquals(strings(s.getJSONArray("expect")), spy.engine.suggest(s.getString("input"), s.getInt("k")))
                null
            }
            "enginePick" -> { spy.engine.pick(s.getString("input"), s.getInt("index")); null }
            "saveFirst" -> { saved[s.getString("as")] = composer.suggestions[0]; null }
            "saveSuggestions" -> { saved[s.getString("as")] = composer.suggestions.toList(); null }
            "saveIndex" -> {
                val i = composer.suggestions.indexOf(s.getString("of"))
                assertTrue("no ${s.getString("of")} in ${composer.suggestions}", i >= 0)
                saved[s.getString("as")] = i
                null
            }
            "saveEngine" -> { saved[s.getString("as")] = spy.engine.suggest(s.getString("input"), 9); null }
            "saveSuggests" -> { saved[s.getString("as")] = spy.suggests; null }
            "check" -> null
            else -> error("unknown op $op")
        }
        if (s.has("consumed")) assertEquals("consumed", s.getBoolean("consumed"), consumed)
        if (s.has("expect") && s.get("expect") is JSONObject) expect(s.getJSONObject("expect"))
    }

    private fun strings(a: JSONArray) = (0 until a.length()).map { a.getString(it) }

    @Suppress("UNCHECKED_CAST")
    private fun text(v: Any): String {
        var s = v as String
        for ((k, value) in saved) {
            val str = when (value) {
                is String -> value
                is List<*> -> value.firstOrNull() as String? ?: ""
                else -> continue
            }
            s = s.replace("{$k}", str)
        }
        return s
    }

    @Suppress("UNCHECKED_CAST")
    private fun list(v: Any): List<String> =
        if (v is String && v.startsWith("@")) saved[v.drop(1)] as List<String> else strings(v as JSONArray)

    private fun int(v: Any): Int = if (v is String && v.startsWith("@")) saved[v.drop(1)] as Int else v as Int

    private fun expect(e: JSONObject) {
        for (key in e.keys()) {
            val v = e.get(key)
            when (key) {
                "doc" -> assertEquals("doc", text(v), proxy.doc)
                "markedText" -> assertEquals("markedText", text(v), proxy.markedText)
                "marked" -> assertEquals("marked", int(v), proxy.marked)
                "typed" -> assertEquals("typed", text(v), composer.typed)
                "mode" -> assertEquals("mode", text(v), composer.mode)
                "canToggle" -> assertEquals("canToggle", v, composer.canToggle)
                "isComposing" -> assertEquals("isComposing", v, composer.isComposing)
                "engineLoaded" -> assertEquals("engineLoaded", v, spy.engine.loaded)
                "suggestions" -> assertEquals("suggestions", list(v), composer.suggestions)
                "notSuggestions" -> assertTrue("suggestions should differ", list(v) != composer.suggestions)
                "suggestionsContain" -> assertTrue("${text(v)} in ${composer.suggestions}", text(v) in composer.suggestions)
                "suggestionsNotContain" -> assertTrue("${text(v)} not in ${composer.suggestions}", text(v) !in composer.suggestions)
                "firstSuggestion" -> assertEquals("firstSuggestion", text(v), composer.suggestions.firstOrNull())
                "picks" -> assertEquals("picks", list(v), spy.picks)
                "picksFile" -> assertEquals("picks.tsv", text(v), picksFile)
                "picksFileContains" -> assertTrue("picks.tsv has ${text(v)}: $picksFile", text(v) in picksFile)
                "suggests" -> assertEquals("suggest calls", int(v), spy.suggests)
                "published" -> assertEquals("published", int(v), published)
                "fileExists" -> (v as JSONObject).let { o -> o.keys().forEach { assertEquals("$it exists", o.getBoolean(it), File(userDir, it).exists()) } }
                "file" -> (v as JSONObject).let { o -> assertEquals(o.getString("name"), o.getString("content"), File(userDir, o.getString("name")).readText()) }
                "settingsOn" -> (v as JSONObject).let { o -> o.keys().forEach { assertEquals("setting $it", o.getBoolean(it), Settings(userDir.path).isOn(it)) } }
                "engineSetting" -> (v as JSONObject).let { o -> o.keys().forEach { assertEquals("engine setting $it", o.getBoolean(it), spy.engine.setting(it)) } }
                "indexOf" -> {
                    val o = v as JSONObject
                    val i = composer.suggestions.indexOf(o.getString("text"))
                    assertTrue("no ${o.getString("text")} in ${composer.suggestions}", i >= 0)
                    if (o.has("lt")) assertTrue("index $i < ${int(o.get("lt"))}", i < int(o.get("lt")))
                    if (o.has("gt")) assertTrue("index $i > ${int(o.get("gt"))}", i > int(o.get("gt")))
                    if (o.has("eq")) assertEquals("index", int(o.get("eq")), i)
                }
                else -> fail("unknown expectation $key")
            }
        }
    }
}
