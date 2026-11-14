package com.chhunly.typer.ime

import android.content.Context
import android.os.Build
import java.io.File

/**
 * The engine reads its TSVs from a directory, so the APK's assets are copied to filesDir/data on first run and
 * whenever the app version changes. Learning lives in filesDir/user.
 */
object EngineData {
    private val files = listOf("lexicon", "ngrams", "english", "generated")

    fun userDir(context: Context): File = File(context.filesDir, "user")

    /** The data directory, copied if needed; null if the assets are missing (the Keyboard then types Latin). */
    fun dataDir(context: Context): File? {
        val dir = File(context.filesDir, "data")
        val stamp = File(dir, ".version")
        val version = version(context)
        if (stamp.isFile && stamp.readText() == version) return dir
        return try {
            dir.mkdirs()
            for (name in files) {
                val tmp = File(dir, "$name.tsv.tmp")
                context.assets.open("data/$name.tsv").use { input -> tmp.outputStream().use { input.copyTo(it) } }
                if (!tmp.renameTo(File(dir, "$name.tsv"))) return null
            }
            stamp.writeText(version)
            dir
        } catch (e: java.io.IOException) {
            null
        }
    }

    private fun version(context: Context): String {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
        return "$code-${info.lastUpdateTime}"  // lastUpdateTime: a reinstalled debug build with the same code recopies
    }
}
