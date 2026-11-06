package bbs.binmt.cc

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class SettingsStore(context: Context) {
    private val store = context.getSharedPreferences("compose_preferences", 0)
    private val old = context.getSharedPreferences("FlutterSharedPreferences", 0)
    private val values = mutableStateMapOf<String, Any>()
    private val writes = Mutex()

    init {
        reload()
    }

    fun reload() {
        values.clear()
        val legacy = if (store.getBoolean("_imported", false)) emptyMap() else old.all
        val current = store.all
        defaults.forEach { (key, fallback) ->
            val original = legacy["flutter.$key"]
            values[key] =
                current[key]
                    ?: when {
                        key == "textScale" && original is String ->
                            original
                                .removePrefix("This is the prefix for a double.")
                                .removePrefix("VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGRvdWJsZS4=")
                                .toFloatOrNull() ?: fallback
                        original is Number ->
                            if (fallback is Float) original.toFloat() else original.toInt()
                        original != null && original::class == fallback::class -> original
                        else -> fallback
                    }
        }
        listOf("themeMode", "imageSavePathType", "videoSavePathType").forEach {
            values[it] = int(it).coerceIn(0, 2)
        }
        values["color"] = int("color").coerceIn(0, 7)
        values["textScale"] = float("textScale").takeIf { it.isFinite() }?.coerceIn(.8f, 1.4f) ?: 1f
        if (int("fontWeightAdjustment") !in weights) values["fontWeightAdjustment"] = 0
        if (int("imageCacheThresholdMb") !in thresholds) values["imageCacheThresholdMb"] = 200
        if (!store.getBoolean("_imported", false)) {
            val editor = store.edit()
            values.forEach { (key, value) ->
                when (value) {
                    is Boolean -> editor.putBoolean(key, value)
                    is Int -> editor.putInt(key, value)
                    is Float -> editor.putFloat(key, value)
                    is String -> editor.putString(key, value)
                }
            }
            editor.putBoolean("_imported", true).apply()
        }
    }

    fun int(key: String) = (values[key] as? Number)?.toInt() ?: 0

    fun bool(key: String) = values[key] as? Boolean ?: false

    fun string(key: String) = values[key] as? String ?: ""

    fun float(key: String) = (values[key] as? Number)?.toFloat() ?: 1f

    fun preview(key: String, value: Any) {
        values[key] = value
    }

    suspend fun write(key: String, value: Any) = writeAll(mapOf(key to value))

    suspend fun writeAll(incoming: Map<String, Any?>) =
        writes.withLock {
            withContext(Dispatchers.IO) {
                val editor = store.edit()
                incoming.forEach { (key, raw) ->
                    val value = raw ?: defaults[key] ?: error("未知设置")
                    when (value) {
                        null -> editor.remove(key)
                        is Boolean -> editor.putBoolean(key, value)
                        is Int -> editor.putInt(key, value)
                        is Number -> editor.putFloat(key, value.toFloat())
                        is String -> editor.putString(key, value)
                        else -> error("设置类型无效")
                    }
                }
                check(editor.commit()) { "设置保存失败，请重试" }
            }
            reload()
        }

    fun snapshot() = values.toMap()

    companion object {
        val thresholds = listOf(0, 50, 100, 200, 500, 1024, 2048)
        val weights = listOf(-100, 0, 100, 200, 300)
        val defaults: Map<String, Any> =
            linkedMapOf(
                "themeMode" to 0,
                "color" to 2,
                "pureBlack" to false,
                "dynamicColor" to false,
                "floatingNavigation" to true,
                "liquidGlass" to false,
                "textScale" to 1f,
                "fontWeightAdjustment" to 0,
                "haptics" to true,
                "autoSignIn" to false,
                "imageSavePathType" to 0,
                "videoSavePathType" to 0,
                "imageCacheThresholdMb" to 200,
                "history" to "[]",
                "webdav_url" to "",
                "webdav_username" to "",
                "webdav_password" to "",
                "webdav_directory" to "MT论坛",
            )
    }
}
