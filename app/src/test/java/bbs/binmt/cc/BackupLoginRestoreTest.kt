package bbs.binmt.cc
import android.content.Context
import android.webkit.CookieManager
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35],manifest=Config.NONE)
class BackupLoginRestoreTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private val settings=SettingsStore(context,WebDavSecrets(context,keyProvider={key}))
    private val backup=BackupService(settings,ForumClient(context))
    private val cookies=CookieManager.getInstance()
    private fun data(full:Boolean=true)=org.json.JSONObject().put("app","bbs.binmt.cc").put("version","1.0").put("backup_mode",if(full)"full"else"safe")
        .put("preferences",org.json.JSONObject().put("themeMode",2)).apply{if(full)put("forum_session",org.json.JSONObject().put("uid","2").put("cookies","synthetic_auth=two"))}
    private suspend fun seed(){cookies.setCookie(ORIGIN,"synthetic_auth=one; Path=/; Secure");settings.writeAll(mapOf("themeMode" to 0))}
    @Test fun verifiedCookiesReplaceParentDomainCookies()=runBlocking{
        seed();cookies.setCookie(ORIGIN,"synthetic_auth=parent; Domain=.binmt.cc; Path=/; Secure")
        assertTrue(backup.restore(data()){_,_->Unit}.contains("验证"))
        assertEquals("synthetic_auth=two",authCookie());assertEquals(2,settings.int("themeMode"))
    }
    @Test fun failedValidationKeepsCurrentLoginAndReportsPartial()=runBlocking{
        seed();assertTrue(backup.restore(data()){_,_->error("synthetic")}.contains("登录未恢复"))
        assertEquals("synthetic_auth=one",authCookie());assertEquals(2,settings.int("themeMode"))
    }
    @Test fun safeRestoreDoesNotValidateOrReplaceCookies()=runBlocking{
        seed();backup.restore(data(false)){_,_->error("must not verify")}
        assertEquals("synthetic_auth=one",authCookie());assertEquals(2,settings.int("themeMode"))
    }
    @Test fun newerLoginAndCancellationLeaveSettingsAlone()=runBlocking{
        seed();try{backup.restore(data()){_,_->cookies.setCookie(ORIGIN,"synthetic_auth=three; Path=/; Secure")};fail()}catch(_:IllegalStateException){}
        assertEquals("synthetic_auth=three",authCookie());assertEquals(0,settings.int("themeMode"))
        try{backup.restore(data()){_,_->throw CancellationException()};fail()}catch(_:CancellationException){}
        assertEquals(0,settings.int("themeMode"))
    }
}
