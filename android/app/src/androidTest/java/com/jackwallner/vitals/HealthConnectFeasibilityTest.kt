package com.jackwallner.vitals

import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.jackwallner.vitals.data.HealthAccess
import com.jackwallner.vitals.data.HealthConnectSource
import com.jackwallner.vitals.model.RestingSource
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Proves the Health Connect aggregate API gives the app's two figures, total and
 * resting energy, in every combination of record types a real phone can hold.
 * Results are logged under tag VitalsFeasibility for the feasibility write-up.
 *
 * Health Connect only aggregates data from apps in its priority list, which an app joins
 * when Health Connect itself grants it write access. Run `scripts/android-pro.sh grant-health`
 * once on a fresh test AVD before this class.
 */
class HealthConnectFeasibilityTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private lateinit var seeder: HealthSeeder
    private lateinit var source: HealthConnectSource
    private val today = LocalDate.now()
    private fun day(n: Long) = today.minusDays(n)

    @Before
    fun setUp() = runBlocking {
        assertEquals(HealthConnectClient.SDK_AVAILABLE, HealthConnectClient.getSdkStatus(context))
        val client = HealthConnectClient.getOrCreate(context)
        seeder = HealthSeeder(client)
        source = HealthConnectSource(context)
        seeder.clearAll(day(20), today)
    }

    private fun stats(offset: Long) = runBlocking {
        source.stats(day(offset), day(offset), LocalDateTime.now()).single()
    }

    private fun log(label: String, s: com.jackwallner.vitals.model.DayStats) =
        Log.i("VitalsFeasibility", "$label total=${s.total} active=${s.active} resting=${s.resting} source=${s.restingSource} steps=${s.steps}")

    @Test
    fun rawProbe() = runBlocking {
        val client = HealthConnectClient.getOrCreate(context)
        val d = day(15)
        seeder.total(d, 2300.0)
        seeder.active(d, 600.0)
        val start = d.atStartOfDay()
        val end = d.plusDays(1).atStartOfDay()
        val recs = client.readRecords(androidx.health.connect.client.request.ReadRecordsRequest(
            androidx.health.connect.client.records.TotalCaloriesBurnedRecord::class,
            androidx.health.connect.client.time.TimeRangeFilter.between(start, end)))
        Log.i("VitalsFeasibility", "raw total records=${recs.records.size} ${recs.records.firstOrNull()?.energy}")
        val agg = client.aggregate(androidx.health.connect.client.request.AggregateRequest(
            setOf(androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL,
                  androidx.health.connect.client.records.ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                  androidx.health.connect.client.records.BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL),
            androidx.health.connect.client.time.TimeRangeFilter.between(start, end)))
        Log.i("VitalsFeasibility", "raw aggregate total=${agg[androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL]} active=${agg[androidx.health.connect.client.records.ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]} basal=${agg[androidx.health.connect.client.records.BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]} origins=${agg.dataOrigins}")
        val filtered = client.aggregate(androidx.health.connect.client.request.AggregateRequest(
            setOf(androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL,
                  androidx.health.connect.client.records.ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL),
            androidx.health.connect.client.time.TimeRangeFilter.between(start, end),
            setOf(androidx.health.connect.client.records.metadata.DataOrigin(context.packageName))))
        Log.i("VitalsFeasibility", "origin-filtered total=${filtered[androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL]} active=${filtered[androidx.health.connect.client.records.ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]} origins=${filtered.dataOrigins}")
        val grouped = client.aggregateGroupByPeriod(androidx.health.connect.client.request.AggregateGroupByPeriodRequest(
            setOf(androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL),
            androidx.health.connect.client.time.TimeRangeFilter.between(start, end), java.time.Period.ofDays(1)))
        grouped.forEach { Log.i("VitalsFeasibility", "raw grouped ${it.startTime} total=${it.result[androidx.health.connect.client.records.TotalCaloriesBurnedRecord.ENERGY_TOTAL]} origins=${it.result.dataOrigins}") }
        Unit
    }

    @Test
    fun permissionsGrantedAndAccessReady() = runBlocking {
        assertEquals(HealthAccess.READY, source.access())
    }

    @Test
    fun noRecordsIsEmptyNotSynthetic() = runBlocking {
        val s = stats(1)
        log("none", s)
        assertEquals(0.0, s.total, 0.001)
        assertEquals(RestingSource.NONE, s.restingSource)
    }

    @Test
    fun totalAndActiveSplitsIntoResting() = runBlocking {
        seeder.total(day(2), 2300.0)
        seeder.active(day(2), 600.0)
        val s = stats(2)
        log("total+active", s)
        assertEquals(2300.0, s.total, 1.0)
        assertEquals(600.0, s.active!!, 1.0)
        assertEquals(1700.0, s.resting!!, 1.0)
        assertEquals(RestingSource.MEASURED_TOTAL, s.restingSource)
    }

    @Test
    fun activeAndBasalRateSumsToTotal() = runBlocking {
        seeder.active(day(3), 600.0)
        seeder.basalPerDay(day(3), 1700.0)
        val s = stats(3)
        log("active+bmr", s)
        assertEquals(600.0, s.active!!, 1.0)
        assertEquals(1700.0, s.resting!!, 25.0)
        assertEquals(s.active!! + s.resting!!, s.total, 1.0)
    }

    @Test
    fun totalOnlyStaysUnsplit() = runBlocking {
        seeder.total(day(4), 2300.0)
        val s = stats(4)
        log("total only", s)
        assertEquals(2300.0, s.total, 1.0)
        assertEquals(RestingSource.UNSPLIT, s.restingSource)
    }

    @Test
    fun totalAndBasalSplitsTheOtherWay() = runBlocking {
        seeder.total(day(5), 2300.0)
        seeder.basalPerDay(day(5), 1700.0)
        val s = stats(5)
        log("total+bmr", s)
        assertEquals(2300.0, s.total, 1.0)
        assertNotNull(s.resting)
    }

    @Test
    fun activeOnlyUsesPlatformEstimateAndSaysSo() = runBlocking {
        seeder.active(day(6), 600.0)
        val s = stats(6)
        log("active only", s)
        assertEquals(RestingSource.ESTIMATED, s.restingSource)
        assertTrue(s.resting!! > 1000)
    }

    @Test
    fun partialTotalIsGapFilledByThePlatform() = runBlocking {
        seeder.total(day(7), 1000.0, to = LocalTime.NOON)
        seeder.active(day(7), 500.0)
        val s = stats(7)
        log("partial total", s)
        assertTrue("gap after noon is filled from active + basal", s.total > 1000.0)
    }

    @Test
    fun stepsAndFoodAggregate() = runBlocking {
        seeder.steps(day(8), 8123)
        seeder.food(day(8), 1800.0)
        seeder.food(day(8), 400.0, LocalTime.of(19, 0))
        val s = stats(8)
        assertEquals(8123, s.steps)
        val food = source.food(day(8), day(8), LocalDateTime.now())
        assertEquals(2200.0, food[day(8)]!!, 1.0)
    }

    @Test
    fun rangeReturnsOneRowPerDay() = runBlocking {
        seeder.total(day(9), 2000.0)
        val rows = source.stats(day(12), day(9), LocalDateTime.now())
        assertEquals(4, rows.size)
        assertEquals(day(12), rows.first().date)
        InstrumentationRegistry.getInstrumentation().targetContext
        Unit
    }
}
