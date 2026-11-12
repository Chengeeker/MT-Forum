package bbs.binmt.cc
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
class WebDavSecrets(private val context: Context, private val namespace: String = "webdav_password_cipher", private val keyProvider: ((Boolean)->SecretKey)? = null) {
    private val prefs = context.getSharedPreferences(namespace, Context.MODE_PRIVATE)
    private fun key(create: Boolean = true): SecretKey {
        keyProvider?.let { return it(create) }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("mtforum-$namespace", null) as? SecretKey)?.let { return it }
        if(!create)throw SecretReadFailure(SecretFailureKind.MISSING_KEY)
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("mtforum-$namespace", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun save(cookie: String, recoverUnreadable: Boolean = false) {
        val before=snapshot()
        try {load()}catch(e:SecretReadFailure){
            if(!recoverUnreadable || !e.recoverable)throw e
            archiveEncryptedFile(context,java.io.File(context.applicationInfo.dataDir,"shared_prefs/$namespace.xml"))
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key()) }
        val saved=prefs.edit().putString("iv",Base64.encodeToString(cipher.iv,Base64.NO_WRAP))
            .putString("data",Base64.encodeToString(cipher.doFinal(cookie.toByteArray()),Base64.NO_WRAP)).commit()
        if(!saved){rollback(snapshot(),before);error("密码保存失败，请检查存储空间")}
        if(namespace=="webdav_password_cipher")revision.incrementAndGet()
    }
    fun load(): String = readEncrypted {
        val data = prefs.getString("data", null) ?: return@readEncrypted ""
        require(Base64.decode(data,Base64.NO_WRAP).size in 16..(16*1024*1024) && Base64.decode(prefs.getString("iv",""),Base64.NO_WRAP).size==12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, Base64.decode(prefs.getString("iv", ""), Base64.NO_WRAP)))
        }
        String(cipher.doFinal(Base64.decode(data, Base64.NO_WRAP)), Charsets.UTF_8)
    }
    fun clear() { check(prefs.edit().clear().commit());if(namespace=="webdav_password_cipher")revision.incrementAndGet() }
    internal fun snapshot():Map<String,*> = prefs.all.toMap()
    internal fun rollback(expected:Map<String,*>, original:Map<String,*>) {
        check(prefs.all==expected){"账号资料已改变，保留最新资料"}
        check(prefs.edit().clear().also { edit->original.forEach{(key,value)->if(value is String)edit.putString(key,value)} }.commit())
        if(namespace=="webdav_password_cipher")revision.incrementAndGet()
    }
    companion object {
        internal val accountWrites=kotlinx.coroutines.sync.Mutex()
        internal val revision=java.util.concurrent.atomic.AtomicLong()
    }
}
