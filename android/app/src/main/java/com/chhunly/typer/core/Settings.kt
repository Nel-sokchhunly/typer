package com.chhunly.typer.core

import java.io.File

/**
 * The in-Keyboard switches in `user_dir/settings.txt`: the `name=on|off` lines the desktop settings app writes and
 * the engine reads (engine/src/lib.rs, read_settings / write_setting). The engine checks the file's mtime on every
 * suggest and pick, so a write applies on the next keystroke. Port of ios/TyperCore Settings.swift.
 */
class Settings(userDir: String) {
    companion object {
        val names = listOf("generated", "english", "learn")
    }

    private val file = File(userDir, "settings.txt")

    /** On unless a line says `name=off`, like the engine; no file means all on. */
    fun isOn(name: String): Boolean = lines().none { line -> parse(line)?.let { it.first == name && it.second == "off" } == true }

    /** Rewrites `name`'s lines in place, or appends one; every other line keeps its place. */
    fun set(name: String, on: Boolean) {
        val line = "$name=${if (on) "on" else "off"}"
        var found = false
        val out = lines().map { l ->
            if (parse(l)?.first == name) {
                found = true
                line
            } else l
        }.toMutableList()
        if (!found) out += line
        file.parentFile?.mkdirs()
        // atomic: the engine never reads half a file
        val tmp = File(file.parentFile, "settings.txt.tmp")
        tmp.writeText(out.joinToString("\n") + "\n")
        if (!tmp.renameTo(file)) {
            file.writeText(tmp.readText())
            tmp.delete()
        }
    }

    private fun lines(): List<String> {
        if (!file.isFile) return emptyList()
        val lines = file.readText().split("\r\n", "\n", "\r").toMutableList()
        if (lines.lastOrNull() == "") lines.removeAt(lines.size - 1)
        return lines
    }

    /** Rust's `split_once('=')` with both sides trimmed. */
    private fun parse(line: String): Pair<String, String>? {
        val eq = line.indexOf('=')
        if (eq < 0) return null
        return line.substring(0, eq).trim() to line.substring(eq + 1).trim()
    }
}
