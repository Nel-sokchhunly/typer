package com.chhunly.typer.core

import org.junit.Assert.assertEquals
import org.junit.Test

/** EmojiData.keeping: emoji the phone's font can't draw leave the panel, search and skin tones. */
class EmojiKeepingTest {
    private val data = EmojiData.load(
        """[{"group":"Smileys","emoji":[{"e":"😀"},{"e":"🫠"}]},{"group":"New","emoji":[{"e":"🫩"}]},
           {"group":"People","emoji":[{"e":"👍","t":["👍🏻","👍🏼"]},{"e":"🫶","t":["🫶🏻","🫶🏼"]}]}]""",
        "😀\tgrinning face\t\t\t\n🫠\tmelting face\t\t\t\n👍\tthumbs up\t\t\t\n",
    ).keeping { it !in setOf("🫠", "🫩", "🫶🏼") }

    @Test fun dropsWhatCannotDraw() =
        assertEquals(listOf("Smileys" to listOf("😀"), "People" to listOf("👍", "🫶")), data.groups.map { it.name to it.emoji })

    @Test fun keepsTonesOnlyWhenAllDraw() = assertEquals(mapOf("👍" to listOf("👍🏻", "👍🏼")), data.variants)

    @Test fun searchSkipsDropped() = assertEquals(emptyList<String>(), data.search("melting"))
}
