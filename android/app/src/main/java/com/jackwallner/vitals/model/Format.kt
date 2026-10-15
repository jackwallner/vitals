package com.jackwallner.vitals.model

import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.roundToLong

/** Number and date formatting kept out of the screens so unit tests can pin it. */
object Format {
    fun number(value: Double, locale: Locale = Locale.getDefault()): String =
        NumberFormat.getIntegerInstance(locale).format(value.roundToLong())

    fun shortDate(date: LocalDate, locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofPattern("M/d", locale).format(date)

    fun mediumDate(date: LocalDate, locale: Locale = Locale.getDefault()): String =
        DateTimeFormatter.ofPattern("MMM d", locale).format(date)
}
