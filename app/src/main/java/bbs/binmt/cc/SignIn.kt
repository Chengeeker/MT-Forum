package bbs.binmt.cc

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import org.jsoup.nodes.Element

fun signRankTarget(anchor: Element, base: String): String? {
    val value =
        Regex("ajaxget\\('([^']+)'\\s*,\\s*'ranklist'\\)")
            .find(anchor.attr("onclick"))
            ?.groupValues
            ?.get(1) ?: return null
    return safeUrl(value, base)?.takeIf { sameOrigin(it) && query(it, "operation") == "list" }
}

@Composable
fun SignInView(data: SignInInfo, state: ForumState, open: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Section(radius = 16) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(data.avatar, 48)
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        if (data.name.isNotEmpty())
                            Text(data.name, style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.height(4.dp))
                        Text(data.status, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                Button(
                    onClick = state::signIn,
                    enabled = !state.utilityBusy && !data.signed && data.action != null,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.EventAvailable, null)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        if (state.utilityBusy) "处理中…"
                        else if (data.signed) "当前已签到"
                        else if (data.action != null) "立即签到" else "当前不可签到"
                    )
                }
                val columns = if (LocalDensity.current.fontScale * 14 > 22) 1 else 2
                data.stats.chunked(columns).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        row.forEach { (label, value) ->
                            Column(Modifier.weight(1f)) {
                                Text(
                                    label,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Spacer(Modifier.height(4.dp))
                                Text(value, style = MaterialTheme.typography.titleLarge)
                            }
                        }
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        Section(radius = 16) {
            Column(Modifier.padding(16.dp)) {
                if (data.participants.isNotEmpty())
                    Text("今日签到 · ${data.participants}", style = MaterialTheme.typography.titleSmall)
                data.highlights.forEach {
                    Text(
                        it,
                        Modifier.padding(top = 8.dp),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                data.rules?.let {
                    TextButton(onClick = { open(it) }, enabled = !state.utilityBusy) {
                        Icon(Icons.Outlined.Info, null, Modifier.size(18.dp))
                        Text("奖励规则")
                    }
                }
            }
        }
    }
}
