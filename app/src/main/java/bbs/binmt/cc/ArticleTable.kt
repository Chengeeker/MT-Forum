package bbs.binmt.cc

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.constrainWidth
import androidx.compose.ui.unit.dp
import kotlin.math.ceil
import kotlin.math.roundToInt
import org.jsoup.Jsoup

internal data class ArticleCell(
    val row: Int,
    val column: Int,
    val rows: Int,
    val columns: Int,
    val html: String,
    val heading: Boolean,
)

internal fun articleTableCells(html: String): List<ArticleCell> {
    val table = Jsoup.parseBodyFragment(html).selectFirst("table") ?: return emptyList()
    val rows = table.select("tr").filter { it.closest("table") === table }
    val occupied = mutableSetOf<Pair<Int, Int>>()
    return buildList {
        rows.forEachIndexed { r, row ->
            var c = 0
            row.children()
                .filter { it.tagName() in setOf("td", "th") }
                .forEach { cell ->
                    val columns = (cell.attr("colspan").toIntOrNull() ?: 1).coerceIn(1, 100)
                    while ((c until c + columns).any { r to it in occupied }) c++
                    val span = cell.attr("rowspan").toIntOrNull() ?: 1
                    val rowSpan = if (span == 0) rows.size - r else span.coerceIn(1, rows.size - r)
                    add(ArticleCell(r, c, rowSpan, columns, cell.html(), cell.tagName() == "th"))
                    for (y in r until r + rowSpan) for (x in c until c + columns) occupied.add(
                        y to x
                    )
                    c += columns
                }
        }
    }
}

@Composable
internal fun ArticleTable(
    html: String,
    open: (String) -> Unit,
    images: ((ImageAnchor) -> Unit)?,
    video: ((String) -> Unit)?,
    textStyle: TextStyle,
) {
    val table = remember(html) { Jsoup.parseBodyFragment(html).selectFirst("table")!! }
    val cells = remember(html) { articleTableCells(html) }
    if (cells.isEmpty()) return
    fun number(attribute: String, fallback: Float) =
        table
            .attr(attribute)
            .toFloatOrNull()
            ?.takeIf { it.isFinite() && it >= 0 }
            ?.coerceAtMost(100f) ?: fallback
    val padding = number("cellpadding", 1f).dp
    val border = number("border", 0f).dp
    val gap = number("cellspacing", 2f).dp
    val foreground = MaterialTheme.colorScheme.onSurface
    val bold = MaterialTheme.typography.titleLarge.fontWeight
    var rectangles by
        remember(html) { mutableStateOf(emptyList<androidx.compose.ui.geometry.Rect>()) }
    val screenWidth =
        with(LocalDensity.current) { LocalConfiguration.current.screenWidthDp.dp.roundToPx() }
    BoxWithConstraints {
        val availableWidth = if (constraints.hasBoundedWidth) constraints.maxWidth else screenWidth
        Column(Modifier.horizontalScroll(rememberScrollState())) {
            table
                .children()
                .firstOrNull { it.tagName() == "caption" }
                ?.let { RichText(it.html(), open, textStyle) }
            SubcomposeLayout(
                Modifier.drawBehind {
                    if (border.value > 0) {
                        val stroke = border.toPx()
                        drawRect(
                            foreground,
                            Offset(stroke / 2, stroke / 2),
                            Size(
                                (size.width - stroke).coerceAtLeast(0f),
                                (size.height - stroke).coerceAtLeast(0f),
                            ),
                            style = Stroke(stroke),
                        )
                        rectangles.forEach { rect ->
                            drawRect(
                                foreground,
                                rect.topLeft + Offset(stroke / 2, stroke / 2),
                                Size(
                                    (rect.width - stroke).coerceAtLeast(0f),
                                    (rect.height - stroke).coerceAtLeast(0f),
                                ),
                                style = Stroke(stroke),
                            )
                        }
                    }
                }
            ) { constraints ->
                val columnCount = cells.maxOf { it.column + it.columns }
                val rowCount = cells.maxOf { it.row + it.rows }
                val spacing = gap.roundToPx()
                val edge = border.roundToPx()
                val widths = IntArray(columnCount)
                val natural =
                    cells.mapIndexed { i, cell ->
                        subcompose("natural:$i") {
                                Column(Modifier.padding(padding + border)) {
                                    ArticleBody(
                                        cell.html,
                                        open,
                                        images,
                                        video,
                                        textStyle.copy(
                                            fontWeight =
                                                if (cell.heading) bold else textStyle.fontWeight
                                        ),
                                    )
                                }
                            }
                            .single()
                            .measure(Constraints())
                    }
                cells.forEachIndexed { i, cell ->
                    val width =
                        ceil(
                                (natural[i].width - spacing * (cell.columns - 1))
                                    .coerceAtLeast(1)
                                    .toFloat() / cell.columns
                            )
                            .toInt()
                    for (c in cell.column until cell.column + cell.columns) widths[c] =
                        maxOf(widths[c], width)
                }
                val target =
                    (availableWidth - edge * 2 - spacing * (columnCount + 1)).coerceAtLeast(
                        columnCount
                    )
                if (widths.sum() > target) {
                    val ratio = target.toFloat() / widths.sum()
                    widths.indices.forEach {
                        widths[it] = (widths[it] * ratio).roundToInt().coerceAtLeast(1)
                    }
                }
                val placed =
                    cells.mapIndexed { i, cell ->
                        val width =
                            (cell.column until cell.column + cell.columns).sumOf { widths[it] } +
                                spacing * (cell.columns - 1)
                        subcompose("cell:$i") {
                                Column(Modifier.padding(padding + border)) {
                                    ArticleBody(
                                        cell.html,
                                        open,
                                        images,
                                        video,
                                        textStyle.copy(
                                            fontWeight =
                                                if (cell.heading) bold else textStyle.fontWeight
                                        ),
                                    )
                                }
                            }
                            .single()
                            .measure(Constraints.fixedWidth(width))
                    }
                val heights = IntArray(rowCount)
                cells.indices
                    .sortedBy { cells[it].rows }
                    .forEach { i ->
                        val cell = cells[i]
                        val existing =
                            (cell.row until cell.row + cell.rows).sumOf { heights[it] } +
                                spacing * (cell.rows - 1)
                        val extra = (placed[i].height - existing).coerceAtLeast(0)
                        for (r in cell.row until cell.row + cell.rows) heights[r] +=
                            extra / cell.rows + if (r - cell.row < extra % cell.rows) 1 else 0
                    }
                val bounds =
                    cells.map { cell ->
                        val x = edge + spacing * (cell.column + 1) + widths.take(cell.column).sum()
                        val y = edge + spacing * (cell.row + 1) + heights.take(cell.row).sum()
                        val w =
                            (cell.column until cell.column + cell.columns).sumOf { widths[it] } +
                                spacing * (cell.columns - 1)
                        val h =
                            (cell.row until cell.row + cell.rows).sumOf { heights[it] } +
                                spacing * (cell.rows - 1)
                        androidx.compose.ui.geometry.Rect(
                            x.toFloat(),
                            y.toFloat(),
                            (x + w).toFloat(),
                            (y + h).toFloat(),
                        )
                    }
                rectangles = bounds
                layout(
                    constraints.constrainWidth(
                        widths.sum() + spacing * (columnCount + 1) + edge * 2
                    ),
                    constraints.constrainHeight(heights.sum() + spacing * (rowCount + 1) + edge * 2),
                ) {
                    placed.forEachIndexed { i, cell ->
                        val rect = bounds[i]
                        cell.placeRelative(
                            rect.left.roundToInt(),
                            (rect.top + (rect.height - cell.height) / 2).roundToInt(),
                        )
                    }
                }
            }
        }
    }
}
