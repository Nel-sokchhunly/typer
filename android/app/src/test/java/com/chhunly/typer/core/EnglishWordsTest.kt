package com.chhunly.typer.core

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/**
 * English word suggestions (English mode), written before the suggester: what the strip must show for the text
 * before the caret. Result: [the word as typed, best, second], or empty when nothing helps. Real data/out/english.tsv.
 */
class EnglishWordsTest {
    private val words = EnglishWords.load(File(System.getProperty("typer.data") ?: "../../data/out", "english.tsv").inputStream())

    private fun s(before: String?, user: List<String> = emptyList()) = words.suggest(before, user)

    @Test fun completesThePartWordMostCommonFirst() = assertEquals(listOf("hel", "help", "hell"), s("hel"))

    @Test fun onlyTheLastWordCounts() = assertEquals(listOf("hel", "help", "hell"), s("I said hel"))

    @Test fun previousWordBoostsItsBigrams() {
        assertEquals(listOf("bi", "big", "bit"), s("bi"))
        assertEquals("birthday", s("happy bi")[1])
    }

    @Test fun capitalisedWordGetsCapitalisedSuggestions() = assertEquals(listOf("Hel", "Help", "Hell"), s("Hel"))

    @Test fun spellingFixOnlyWhenNothingCompletes() {
        assertEquals(listOf("teh", "the"), s("teh").take(2))  // nothing starts with "teh"
        assertEquals("help", s("hel")[1])  // "hel" completes: no fix to "he"
    }

    @Test fun nothingWhenNothingHelps() {
        assertEquals(emptyList<String>(), s("xqzvw"))
        assertEquals(emptyList<String>(), s("yourself"))  // a whole word with no longer completion
    }

    @Test fun nothingBetweenWords() {
        assertEquals(emptyList<String>(), s(""))
        assertEquals(emptyList<String>(), s(null))
        assertEquals(emptyList<String>(), s("hello "))
        assertEquals(emptyList<String>(), s("hello."))
    }

    @Test fun loneApostropheIsNotAWord() = assertEquals(emptyList<String>(), s("'"))

    @Test fun userDictionaryWordComesFirst() {
        val r = s("Sok", listOf("Sokchhunly"))
        assertEquals("Sok", r[0])
        assertEquals("Sokchhunly", r[1])
    }

    @Test fun neverSuggestsTheWordAsTyped() = assertEquals(false, s("hell").drop(1).any { it.equals("hell", ignoreCase = true) })

    @Test fun multiWordLinesAreNotWords() = assertEquals(false, s("yo").any { ' ' in it })
}
