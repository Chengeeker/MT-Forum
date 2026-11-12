package bbs.binmt.cc

import android.content.Context
import androidx.compose.runtime.mutableStateMapOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class SettingsStore(context: Context,private val password:WebDavSecrets=WebDavSecrets(context)) {
    private val store = context.getSharedPreferences("compose_preferences", 0)
    private val old = context.getSharedPreferences("FlutterSharedPreferences", 0)
    private val values = mutableStateMapOf<String, Any>()
    private val writes = Mutex()
    var secretReadError:String?=null;private set
    fun requireReadablePassword():String {secretReadError?.let{error(it)};return string("webdav_password")}
    internal fun passwordSnapshot()=password.snapshot()
    internal fun rollbackPassword(expected:Map<String,*>,original:Map<String,*>) {password.rollback(expected,original);reload()}


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
        try {
            val legacyPassword=(current["webdav_password"] as? String)?:legacy["flutter.webdav_password"] as? String
            if(password.snapshot().isEmpty() && !legacyPassword.isNullOrEmpty())password.save(legacyPassword)
            values["webdav_password"]=password.load();secretReadError=null
            if(current.containsKey("webdav_password"))check(store.edit().remove("webdav_password").commit())
        }catch(e:Exception){secretReadError=if(e is SecretReadFailure)e.message else "WebDAV 密码读取失败，原资料已保留";values["webdav_password"]=""}
        listOf("themeMode", "imageSavePathType", "videoSavePathType").forEach {
            values[it] = int(it).coerceIn(0, 2)
        }
        values["color"] = int("color").coerceIn(0, 7)
        values["textScale"] = float("textScale").takeIf { it.isFinite() }?.coerceIn(.8f, 1.5f) ?: 1f
        if (!current.containsKey("customFontWeight")) values["customFontWeight"] = int("fontWeightAdjustment") != 0
        if (int("fontWeightAdjustment") !in weights) values["fontWeightAdjustment"] = 0
        if (int("imageCacheThresholdMb") !in thresholds) values["imageCacheThresholdMb"] = 200
        if (!store.getBoolean("_imported", false)) {
            val editor = store.edit()
            values.filterKeys{it!="webdav_password"}.forEach { (key, value) ->
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

    suspend fun writeAll(incoming: Map<String, Any?>, expected: Map<String, Any>? = null, recoverPassword:Boolean=false) =
        writes.withLock {
            check(expected==null || incoming.keys.all{snapshot()[it]==expected[it]}){"设置已改变，请重新恢复"}
            withContext(kotlinx.coroutines.NonCancellable + Dispatchers.IO) {
                val before=store.all.toMap();val oldPassword=password.snapshot();var appliedPassword:Map<String,*>?=null
                val editor = store.edit()
                incoming.filterKeys{it!="webdav_password"}.forEach { (key, raw) ->
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
                try {
                    if(incoming.containsKey("webdav_password")) {
                        password.save(incoming["webdav_password"] as? String?:"",recoverPassword)
                        appliedPassword=password.snapshot()
                    }
                    if(!editor.commit()) {
                        val rollback=store.edit()
                        incoming.keys.filter{it!="webdav_password"}.forEach{key->when(val value=before[key]){
                            null->rollback.remove(key);is Boolean->rollback.putBoolean(key,value);is Int->rollback.putInt(key,value);is Float->rollback.putFloat(key,value);is String->rollback.putString(key,value)
                        }}
                        check(rollback.commit()){"设置保存失败且回滚未完成"}
                        error("设置保存失败，请重试")
                    }
                }catch(e:Exception){appliedPassword?.let{password.rollback(it,oldPassword)};throw e}
            }
            reload()
        }

    fun snapshot() = values.toMap()

    companion object {
        val thresholds = listOf(0, 50, 100, 200, 500, 1024, 2048)
        val weights = listOf(-300, -200, -100, 0, 100, 200, 300)
        val defaults: Map<String, Any> =
            linkedMapOf(
                "themeMode" to 0,
                "color" to 2,
                "pureBlack" to false,
                "dynamicColor" to false,
                "floatingNavigation" to true,
                "liquidGlass" to false,
                "translucentNavigationGlass" to false,
                "textScale" to 1f,
                "fontWeightAdjustment" to 0,
                "customFontWeight" to false,
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
