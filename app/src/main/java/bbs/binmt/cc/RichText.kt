package bbs.binmt.cc

import android.text.Html
import android.text.SpannableStringBuilder
import android.text.method.LinkMovementMethod
import android.text.style.BackgroundColorSpan
import android.text.style.ClickableSpan
import android.text.style.ForegroundColorSpan
import android.text.style.LineHeightSpan
import android.text.style.URLSpan
import android.view.View
import android.widget.TextView
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.graphics.ColorUtils
import kotlin.math.roundToInt

internal class OriginalLineHeight(private val height: Int) : LineHeightSpan {
    override fun chooseHeight(
        text: CharSequence,
        start: Int,
        end: Int,
        spanstartv: Int,
        v: Int,
        fm: android.graphics.Paint.FontMetricsInt,
    ) {
        val extra = (height - (fm.descent - fm.ascent)).coerceAtLeast(0)
        fm.ascent -= extra / 2
        fm.descent += extra - extra / 2
        fm.top = fm.ascent
        fm.bottom = fm.descent
    }
}

internal fun readableHtml(
    html: String,
    dark: Boolean,
    foreground: Int,
    surface: Int,
): SpannableStringBuilder {
    val content = SpannableStringBuilder(Html.fromHtml(html, Html.FROM_HTML_MODE_COMPACT))
    if (!dark) return content
    fun readable(text: Int, background: Int) = ColorUtils.calculateContrast(text, background) >= 4.5
    val backgrounds = content.getSpans(0, content.length, BackgroundColorSpan::class.java)
    backgrounds.forEach { span ->
        if (!readable(foreground, ColorUtils.compositeColors(span.backgroundColor, surface))) {
            content.removeSpan(span)
        }
    }
    content.getSpans(0, content.length, ForegroundColorSpan::class.java).forEach { span ->
        val behind =
            content.getSpans(
                content.getSpanStart(span),
                content.getSpanEnd(span),
                BackgroundColorSpan::class.java,
            )
        if (
            !readable(span.foregroundColor, surface) ||
                behind.any {
                    !readable(
                        span.foregroundColor,
                        ColorUtils.compositeColors(it.backgroundColor, surface),
                    )
                }
        ) {
            content.removeSpan(span)
        }
    }
    return content
}

@Composable
fun RichText(
    html: String,
    open: (String) -> Unit,
    style: androidx.compose.ui.text.TextStyle = MaterialTheme.typography.bodyLarge,
) {
    val theme = MaterialTheme.colorScheme
    val color = theme.onSurface.toArgb()
    val dark = theme.surface.luminance() < .5f
    val surface =
        (if (theme.surface == Color.Black) theme.surfaceContainer else theme.surfaceContainerLow)
            .toArgb()
    val linkColor = MaterialTheme.colorScheme.primary.toArgb()
    val density = LocalDensity.current
    val size = style.fontSize.value * density.fontScale
    val lineHeight = style.lineHeight.value * density.fontScale * density.density
    val weight = style.fontWeight?.weight ?: 400
    val currentOpen by rememberUpdatedState(open)
    val content =
        remember(html, dark, color, surface, lineHeight) {
            readableHtml(html, dark, color, surface).apply {
                val visibleEnd = indexOfLast { !it.isWhitespace() } + 1
                if (visibleEnd < length) delete(visibleEnd, length)
                getSpans(0, length, URLSpan::class.java).forEach { span ->
                    val start = getSpanStart(span)
                    val end = getSpanEnd(span)
                    removeSpan(span)
                    setSpan(
                        object : ClickableSpan() {
                            override fun onClick(widget: View) {
                                currentOpen(span.url)
                            }
                        },
                        start,
                        end,
                        android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                }
                if (isNotEmpty())
                    setSpan(
                        OriginalLineHeight(lineHeight.roundToInt()),
                        0,
                        length,
                        android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
            }
        }
    AndroidView(
        modifier = Modifier.fillMaxWidth(),
        factory = { context ->
            TextView(context).apply {
                setTextIsSelectable(true)
                movementMethod = LinkMovementMethod.getInstance()
                includeFontPadding = false
                breakStrategy = android.text.Layout.BREAK_STRATEGY_HIGH_QUALITY
                hyphenationFrequency = android.text.Layout.HYPHENATION_FREQUENCY_NORMAL
                if (android.os.Build.VERSION.SDK_INT >= 28) setFallbackLineSpacing(false)
            }
        },
        update = { view ->
            view.setTextColor(color)
            view.setLinkTextColor(linkColor)
            view.setTextSize(android.util.TypedValue.COMPLEX_UNIT_DIP, size)
            view.typeface =
                if (android.os.Build.VERSION.SDK_INT >= 28)
                    android.graphics.Typeface.create(
                        android.graphics.Typeface.DEFAULT,
                        weight,
                        false,
                    )
                else
                    android.graphics.Typeface.create(
                        android.graphics.Typeface.DEFAULT,
                        if (weight >= 600) android.graphics.Typeface.BOLD
                        else android.graphics.Typeface.NORMAL,
                    )
            if (view.tag !== content) {
                view.text = content
                view.tag = content
            }
        },
    )
}
