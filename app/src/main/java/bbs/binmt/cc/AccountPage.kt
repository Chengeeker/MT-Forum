package bbs.binmt.cc

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Logout
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException

@Composable
fun AccountPage(
    state: ForumState,
    modifier: Modifier,
    open: (String) -> Unit,
    website: (String) -> Unit,
    dirty: (Boolean) -> Unit,
) {
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    var revision by remember { mutableIntStateOf(0) }
    var logout by remember { mutableStateOf(false) }
    LaunchedEffect(revision) {
        loading = true
        try {
            state.account = AccountService.validate(state.client) ?: error("账号凭据已失效，请重新登录")
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (e: Exception) {
            error = e.message.orEmpty()
        } finally {
            loading = false
        }
    }
    if (state.account != null) UserHomePage(state, modifier, open, website, dirty)
    else
        Column(modifier.padding(top = LocalContentTop.current).padding(16.dp)) {
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            if (error.isNotEmpty())
                Section {
                    Column(
                        Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Icon(Icons.Outlined.Info, null)
                        Spacer(Modifier.height(12.dp))
                        Text(error, textAlign = TextAlign.Center)
                        Spacer(Modifier.height(12.dp))
                        FilledTonalButton(onClick = { revision++ }) { Text("重试") }
                    }
                }
            Spacer(Modifier.weight(1f))
            OutlinedButton(
                onClick = { logout = true },
                modifier = Modifier.fillMaxWidth().navigationBarsPadding(),
            ) {
                Icon(Icons.Outlined.Logout, null)
                Spacer(Modifier.width(8.dp))
                Text("退出登录")
            }
        }
    if (logout)
        ConfirmDialog("退出当前账号？", "清除本机的论坛登录会话及未提交的编辑内容，之后可以重新登录。", { logout = false }) {
            logout = false
            state.logout()
        }
}
