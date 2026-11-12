package bbs.binmt.cc

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SettingsMigrationTest {
    @Test
    fun importOnceNeverResurrectsClearedCredentials() = runBlocking {
        val app = RuntimeEnvironment.getApplication()
        val legacy = app.getSharedPreferences("FlutterSharedPreferences", 0)
        legacy
            .edit()
            .putString("flutter.webdav_password", "old-secret")
            .putString("flutter.textScale", "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGRvdWJsZS4=1.2")
            .commit()
        val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
        val password=WebDavSecrets(app,keyProvider={key})
        val settings = SettingsStore(app,password)
        assertEquals(1.2f, settings.float("textScale"))
        assertEquals("old-secret", settings.string("webdav_password"))
        settings.writeAll(mapOf("webdav_password" to null))
        assertEquals("", SettingsStore(app,password).string("webdav_password"))
        assertEquals("old-secret", legacy.getString("flutter.webdav_password", null))
    }

    @Test
    fun androidViewModelFactoryConstructorExists() {
        assertNotNull(ForumState::class.java.getConstructor(android.app.Application::class.java))
    }
}
