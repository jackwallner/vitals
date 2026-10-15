package com.jackwallner.vitals.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.model.Bucket
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.pow

/** 1,250 becomes "1.3K"; the same compact style the iOS axis uses. */
fun compact(value: Double): String {
    val a = abs(value)
    return when {
        a >= 1_000_000 -> trimmed(value / 1_000_000) + "M"
        a >= 1_000 -> trimmed(value / 1_000) + "K"
        else -> value.toInt().toString()
    }
}

private fun trimmed(v: Double): String {
    val r = Math.round(v * 10) / 10.0
    return if (r == r.toLong().toDouble()) r.toLong().toString() else r.toString()
}

private fun niceStep(range: Double, ticks: Int): Double {
    if (range <= 0) return 1.0
    val raw = range / ticks
    val magnitude = 10.0.pow(kotlin.math.floor(kotlin.math.log10(raw)))
    val normalized = raw / magnitude
    val nice = when {
        normalized <= 1 -> 1.0
        normalized <= 2 -> 2.0
        normalized <= 2.5 -> 2.5
        normalized <= 5 -> 5.0
        else -> 10.0
    }
    return nice * magnitude
}

/**
 * The History bar chart: one bar per day (or week, or month), excluded days
 * dimmed, a dashed average rule, a tap or drag to select a bar. `signed` draws
 * Net Deficit around a zero line, deficit up and surplus down.
 */
@Composable
fun BarChart(
    buckets: List<Bucket>,
    brush: Brush,
    modifier: Modifier = Modifier,
    average: Double? = null,
    selected: Int? = null,
    onSelect: (Int?) -> Unit = {},
    label: (LocalDate) -> String,
    signed: Boolean = false,
    positiveColor: Color = VitalsColors.netDeficitPositive,
    negativeColor: Color = VitalsColors.netDeficitNegative,
    description: String,
) {
    val measurer = rememberTextMeasurer()
    val pal = palette
    val axisColor = pal.textTertiary
    val gridColor = pal.textTertiary.copy(alpha = 0.3f)
    Canvas(
        modifier
            .fillMaxWidth()
            .height(200.dp)
            .semantics { contentDescription = description }
            .pointerInput(buckets) {
                detectTapGestures { offset ->
                    val index = indexAt(offset.x, size.width.toFloat(), 38.dp.toPx(), buckets.size)
                    onSelect(if (index == selected) null else index)
                }
            }
            .pointerInput(buckets) {
                detectHorizontalDragGestures(onDragEnd = { }, onDragCancel = { }) { change, _ ->
                    onSelect(indexAt(change.position.x, size.width.toFloat(), 38.dp.toPx(), buckets.size))
                }
            },
    ) {
        if (buckets.isEmpty()) return@Canvas
        val axisLabelPx = 22.dp.toPx()
        val leftGutter = 38.dp.toPx()
        val plotTop = 8.dp.toPx()
        val plotBottom = size.height - axisLabelPx
        val plotHeight = plotBottom - plotTop
        val plotWidth = size.width - leftGutter
        val maxValue = max(buckets.maxOf { it.value }, average ?: 0.0).coerceAtLeast(if (signed) 1.0 else 1.0)
        val minValue = if (signed) minOf(buckets.minOf { it.value }, 0.0) else 0.0
        val step = niceStep(maxValue - minValue, 4)
        val top = kotlin.math.ceil(maxValue / step) * step
        val bottom = if (signed) kotlin.math.floor(minValue / step) * step else 0.0
        val span = (top - bottom).coerceAtLeast(1.0)
        fun y(v: Double) = plotBottom - ((v - bottom) / span * plotHeight).toFloat()

        var tick = bottom
        while (tick <= top + step * 0.01) {
            val ty = y(tick)
            drawLine(gridColor, Offset(leftGutter, ty), Offset(size.width, ty), strokeWidth = 0.5.dp.toPx())
            drawLabel(measurer, compact(tick), axisColor, Offset(0f, ty - 7.dp.toPx()))
            tick += step
        }

        val slot = plotWidth / buckets.size
        val barWidth = (slot * 0.68f).coerceAtMost(28.dp.toPx())
        val radius = CornerRadius(4.dp.toPx())
        buckets.forEachIndexed { i, bucket ->
            val x = leftGutter + slot * i + (slot - barWidth) / 2
            val dim = (if (selected == null || selected == i) 1f else 0.3f) * (if (bucket.excluded) 0.25f else 1f)
            if (signed) {
                val zero = y(0.0)
                val top2 = y(bucket.value)
                val color = if (bucket.value >= 0) positiveColor else negativeColor
                val rectTop = minOf(zero, top2)
                val rectHeight = abs(zero - top2).coerceAtLeast(1f)
                drawRoundRect(color.copy(alpha = dim), Offset(x, rectTop), Size(barWidth, rectHeight), radius)
            } else {
                val barTop = y(bucket.value)
                drawRoundRect(brush, Offset(x, barTop), Size(barWidth, (plotBottom - barTop).coerceAtLeast(1f)), radius, alpha = dim)
            }
        }
        if (average != null && (signed || average > 0)) {
            val ay = y(average)
            drawLine(
                VitalsColors.caloriesPrimary.copy(alpha = 0.5f), Offset(leftGutter, ay), Offset(size.width, ay),
                strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 3.dp.toPx())),
            )
            drawLabel(measurer, "avg", axisColor, Offset(size.width - 22.dp.toPx(), ay - 14.dp.toPx()))
        }
        // X labels: enough to read, never crowded.
        val every = max(1, kotlin.math.ceil(buckets.size / 6.0).toInt())
        buckets.forEachIndexed { i, bucket ->
            if (i % every == 0 || i == buckets.lastIndex && every == 1) {
                val cx = leftGutter + slot * i + slot / 2
                drawLabel(measurer, label(bucket.date), axisColor, Offset(cx - 14.dp.toPx(), plotBottom + 4.dp.toPx()))
            }
        }
    }
}

private fun indexAt(x: Float, width: Float, gutter: Float, count: Int): Int? {
    if (count == 0) return null
    val slot = (width - gutter) / count
    if (slot <= 0f) return null
    return ((x - gutter) / slot).toInt().coerceIn(0, count - 1)
}

private fun DrawScope.drawLabel(measurer: TextMeasurer, text: String, color: Color, topLeft: Offset) {
    drawText(measurer, text, topLeft, style = Type.rounded(10.sp).copy(color = color))
}
