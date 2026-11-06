package bbs.binmt.cc

import androidx.compose.foundation.layout.*
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RefreshBody(
    state: ForumState,
    modifier: Modifier,
    contentAlignment: Alignment,
    content: @Composable BoxScope.() -> Unit,
) {
    if (
        state.screen == "home" &&
            (!state.isRoot || state.tab == 0 || state.tab == 3 && state.authenticated)
    ) {
        val pull = rememberPullToRefreshState()
        PullToRefreshBox(
            isRefreshing = state.refreshing,
            onRefresh = state::refresh,
            modifier = modifier,
            state = pull,
            contentAlignment = contentAlignment,
            indicator = {
                PullToRefreshDefaults.Indicator(
                    modifier =
                        Modifier.align(Alignment.TopCenter).padding(top = LocalContentTop.current),
                    isRefreshing = state.refreshing,
                    state = pull,
                )
            },
            content = content,
        )
    } else Box(modifier, contentAlignment = contentAlignment, content = content)
}
