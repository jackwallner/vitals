package com.jackwallner.vitals.ui

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import com.jackwallner.vitals.model.ExcludedDays
import com.jackwallner.vitals.model.Format
import com.jackwallner.vitals.model.SummaryReport
import java.io.File
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Draws a `SummaryReport` as a one-page letter PDF: headline figures, goal hits, peaks and two daily charts. */
object ReportPdf {
    private const val WIDTH = 612
    private const val HEIGHT = 792
    private const val MARGIN = 40f
    private val coral = 0xFFFF6B6B.toInt()
    private val teal = 0xFF00B08D.toInt()
    private val ink = 0xFF111111.toInt()
    private val gray = 0xFF666666.toInt()
    private val faint = 0xFFE5E5EA.toInt()

    private fun paint(size: Float, color: Int = ink, bold: Boolean = false) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        textSize = size
        typeface = if (bold) Typeface.create(Typeface.DEFAULT, Typeface.BOLD) else Typeface.DEFAULT
    }

    private fun date(d: LocalDate) = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.getDefault()).format(d)
    private fun short(d: LocalDate) = DateTimeFormatter.ofPattern("MMM d", Locale.getDefault()).format(d)
    private fun signedPercent(v: Double?) = v?.let { val r = it.roundToInt(); if (r > 0) "+$r%" else "$r%" } ?: "n/a"

    fun render(report: SummaryReport, dir: File): File {
        dir.mkdirs()
        val file = File(dir, "vitals-report-${report.start}-${report.end}.pdf")
        val doc = PdfDocument()
        val page = doc.startPage(PdfDocument.PageInfo.Builder(WIDTH, HEIGHT, 1).create())
        draw(page.canvas, report)
        doc.finishPage(page)
        file.outputStream().use { doc.writeTo(it) }
        doc.close()
        return file
    }

    private fun draw(c: Canvas, r: SummaryReport) {
        var y = MARGIN + 18f
        c.drawText(r.title, MARGIN, y, paint(24f, bold = true))
        y += 20f
        c.drawText("Total Calories · Vitals+ report", MARGIN, y, paint(11f, coral, true))
        y += 16f
        c.drawText("${date(r.start)} to ${date(r.end)} · ${r.countedDayCount} days counted" +
            if (r.excludedDayCount > 0) " · ${r.excludedDayCount} excluded" else "", MARGIN, y, paint(11f, gray))
        y += 26f

        val stats = buildList {
            add("Avg calories / day" to Format.number(r.avgCalories))
            add("Total calories" to Format.number(r.totalCalories))
            add("Avg steps / day" to Format.number(r.avgSteps.toDouble()))
            add("Total steps" to Format.number(r.totalSteps.toDouble()))
            if (r.avgActive != null && r.avgResting != null) {
                add("Avg active / day" to Format.number(r.avgActive))
                add("Avg resting / day" to Format.number(r.avgResting))
            }
            add("Days with data" to "${r.activeDayCount} of ${r.countedDayCount}")
            r.avgNet?.let { add("Avg net (burned minus food)" to com.jackwallner.vitals.model.NetDeficit.signed(it)) }
            add("Calories vs. previous period" to signedPercent(r.calorieTrendPct))
            add("Steps vs. previous period" to signedPercent(r.stepTrendPct))
            r.calorieGoal?.let { add("Calorie goal hit" to "${r.calorieGoalHitDays} of ${r.countedDayCount} days") }
            r.stepGoal?.let { add("Step goal hit" to "${r.stepGoalHitDays} of ${r.countedDayCount} days") }
        }
        val columnWidth = (WIDTH - MARGIN * 2) / 2
        stats.chunked(2).forEach { row ->
            row.forEachIndexed { i, (label, value) ->
                val x = MARGIN + columnWidth * i
                c.drawText(label.uppercase(), x, y, paint(8.5f, gray, true))
                c.drawText(value, x, y + 18f, paint(17f, ink, true))
            }
            y += 42f
        }
        r.peakCalorieDay?.takeIf { it.total > 0 }?.let { c.drawText("Peak calories: ${Format.number(it.total)} on ${short(it.date)}", MARGIN, y, paint(11f, gray)); y += 16f }
        r.peakStepDay?.takeIf { it.steps > 0 }?.let { c.drawText("Peak steps: ${Format.number(it.steps.toDouble())} on ${short(it.date)}", MARGIN, y, paint(11f, gray)); y += 16f }
        y += 14f

        y = chart(c, "Daily calories", r.days.map { it.total }, r, coral, y)
        y = chart(c, "Daily steps", r.days.map { it.steps.toDouble() }, r, teal, y)
        c.drawText(
            "Generated on this device from Health Connect data. Excluded days are drawn lighter and counted in no figure above. Not medical advice.",
            MARGIN, HEIGHT - MARGIN, paint(8f, gray),
        )
    }

    private fun chart(c: Canvas, title: String, values: List<Double>, r: SummaryReport, color: Int, top: Float): Float {
        var y = top
        c.drawText(title, MARGIN, y, paint(12f, ink, true))
        y += 10f
        val height = 120f
        val width = WIDTH - MARGIN * 2
        val max = (values.maxOrNull() ?: 0.0).coerceAtLeast(1.0)
        c.drawRect(MARGIN, y, MARGIN + width, y + height, Paint().apply { this.color = 0xFFF7F7FA.toInt() })
        val slot = width / values.size.coerceAtLeast(1)
        val bar = Paint(Paint.ANTI_ALIAS_FLAG)
        values.forEachIndexed { i, v ->
            val excluded = ExcludedDays.contains(r.days[i].date, r.excludedKeys)
            bar.color = color
            bar.alpha = if (excluded) 70 else 255
            val h = (abs(v) / max * (height - 6)).toFloat()
            c.drawRect(MARGIN + slot * i + slot * 0.15f, y + height - h, MARGIN + slot * (i + 1) - slot * 0.15f, y + height, bar)
        }
        val label = paint(8f, gray)
        c.drawText(short(r.start), MARGIN, y + height + 12f, label)
        val endText = short(r.end)
        c.drawText(endText, MARGIN + width - label.measureText(endText), y + height + 12f, label)
        c.drawLine(MARGIN, y + height, MARGIN + width, y + height, Paint().apply { this.color = faint })
        return y + height + 36f
    }
}
