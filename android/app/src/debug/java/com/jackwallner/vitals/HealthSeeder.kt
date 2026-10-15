package com.jackwallner.vitals

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Power
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Debug builds only: writes records into Health Connect so an emulator with no
 * wearable has data to read. Every record is written by this app, so it also
 * clears only its own data.
 */
class HealthSeeder(private val client: HealthConnectClient) {
    private val zone = ZoneId.systemDefault()

    private fun instant(day: LocalDate, time: LocalTime): Instant = day.atTime(time).atZone(zone).toInstant()
    private fun offset(at: Instant): ZoneOffset = zone.rules.getOffset(at)

    suspend fun clearAll(from: LocalDate, to: LocalDate) {
        val range = TimeRangeFilter.between(from.atStartOfDay(zone).toInstant(), to.plusDays(1).atStartOfDay(zone).toInstant())
        listOf(
            ActiveCaloriesBurnedRecord::class,
            TotalCaloriesBurnedRecord::class,
            BasalMetabolicRateRecord::class,
            StepsRecord::class,
            NutritionRecord::class,
        ).forEach { runCatching { client.deleteRecords(it, range) } }
    }

    suspend fun active(day: LocalDate, kcal: Double, from: LocalTime = LocalTime.of(7, 0), to: LocalTime = LocalTime.of(21, 0)) {
        val s = instant(day, from)
        val e = instant(day, to)
        client.insertRecords(listOf(ActiveCaloriesBurnedRecord(s, offset(s), e, offset(e), Energy.kilocalories(kcal), Metadata.manualEntry())))
    }

    /** `to = LocalTime.MAX` means end of day. */
    suspend fun total(day: LocalDate, kcal: Double, from: LocalTime = LocalTime.MIN, to: LocalTime = LocalTime.of(23, 59, 59)) {
        val s = instant(day, from)
        val e = instant(day, to)
        client.insertRecords(listOf(TotalCaloriesBurnedRecord(s, offset(s), e, offset(e), Energy.kilocalories(kcal), Metadata.manualEntry())))
    }

    suspend fun basalPerDay(day: LocalDate, kcalPerDay: Double, at: LocalTime = LocalTime.MIN) {
        val t = instant(day, at)
        client.insertRecords(listOf(BasalMetabolicRateRecord(t, offset(t), Power.kilocaloriesPerDay(kcalPerDay), Metadata.manualEntry())))
    }

    suspend fun steps(day: LocalDate, count: Long, from: LocalTime = LocalTime.of(7, 0), to: LocalTime = LocalTime.of(21, 0)) {
        val s = instant(day, from)
        val e = instant(day, to)
        client.insertRecords(listOf(StepsRecord(s, offset(s), e, offset(e), count, Metadata.manualEntry())))
    }

    suspend fun food(day: LocalDate, kcal: Double, at: LocalTime = LocalTime.NOON) {
        val s = instant(day, at)
        val e = s.plusSeconds(60)
        client.insertRecords(
            listOf(
                NutritionRecord(
                    startTime = s,
                    startZoneOffset = offset(s),
                    endTime = e,
                    endZoneOffset = offset(e),
                    energy = Energy.kilocalories(kcal),
                    protein = Mass.grams(kcal * 0.06),
                    totalCarbohydrate = Mass.grams(kcal * 0.11),
                    totalFat = Mass.grams(kcal * 0.03),
                    metadata = Metadata.manualEntry(),
                ),
            ),
        )
    }
}
