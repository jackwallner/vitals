package com.jackwallner.vitals.data

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.jackwallner.vitals.model.DayStats
import com.jackwallner.vitals.model.EnergyAggregates
import com.jackwallner.vitals.model.EnergyResolver
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.Period
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Where the app stands with Health Connect, as the Today screen needs to tell the user. */
enum class HealthAccess {
    /** Health Connect is not installed or needs an update (Android 13 and earlier). */
    UNAVAILABLE,
    /** Energy permissions are missing: ask, or send the user to Health Connect settings. */
    NEEDS_PERMISSION,
    READY,
}

/** Everything the screens read. A fake implements it for unit tests and the debug gallery. */
interface HealthSource {
    suspend fun access(): HealthAccess
    suspend fun hasFoodAccess(): Boolean
    suspend fun hasHistoryAccess(): Boolean

    /** One row per day from `start` through `end` inclusive; `end == today` stops at `now`. */
    suspend fun stats(start: LocalDate, end: LocalDate, now: LocalDateTime): List<DayStats>

    /** Food energy in kcal per day, zero-filled; a day with no entry is 0. */
    suspend fun food(start: LocalDate, end: LocalDate, now: LocalDateTime): Map<LocalDate, Double>
}

object HealthPermissions {
    val energy: Set<String> = setOf(
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(BasalMetabolicRateRecord::class),
    )
    val steps: String = HealthPermission.getReadPermission(StepsRecord::class)
    val food: String = HealthPermission.getReadPermission(NutritionRecord::class)
    const val HISTORY = HealthPermission.PERMISSION_READ_HEALTH_DATA_HISTORY
    const val BACKGROUND = HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND

    /** What the first prompt asks for. Food joins it only when the user said they log food. */
    fun core(includeFood: Boolean): Set<String> =
        energy + steps + HISTORY + BACKGROUND + (if (includeFood) setOf(food) else emptySet())

    fun requestContract() = PermissionController.createRequestPermissionResultContract()
}

/**
 * Health Connect reads. Every figure comes from the aggregate API so the platform
 * deduplicates overlapping records by the user's own app priority; see
 * `project-docs/android/health-connect-feasibility.md`.
 */
class HealthConnectSource(private val context: Context) : HealthSource {
    private val client: HealthConnectClient? by lazy {
        if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) HealthConnectClient.getOrCreate(context) else null
    }

    private suspend fun granted(): Set<String> = client?.permissionController?.getGrantedPermissions().orEmpty()

    override suspend fun access(): HealthAccess {
        if (client == null) return HealthAccess.UNAVAILABLE
        val granted = granted()
        return if (HealthPermissions.energy.any { it in granted }) HealthAccess.READY else HealthAccess.NEEDS_PERMISSION
    }

    override suspend fun hasFoodAccess() = HealthPermissions.food in granted()
    override suspend fun hasHistoryAccess() = HealthPermissions.HISTORY in granted()

    private fun range(start: LocalDate, end: LocalDate, now: LocalDateTime): TimeRangeFilter {
        val today = now.toLocalDate()
        val endExclusive = if (end < today) end.plusDays(1).atStartOfDay() else now
        return TimeRangeFilter.between(start.atStartOfDay(), endExclusive)
    }

    private data class Daily(val value: Map<LocalDate, Double>, val present: Set<LocalDate>)

    private suspend fun daily(
        metric: androidx.health.connect.client.aggregate.AggregateMetric<*>,
        filter: TimeRangeFilter,
        permission: String,
    ): Daily {
        val c = client ?: return Daily(emptyMap(), emptySet())
        if (permission !in granted()) return Daily(emptyMap(), emptySet())
        val rows = c.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(setOf(metric), filter, Period.ofDays(1)),
        )
        val values = HashMap<LocalDate, Double>()
        val present = HashSet<LocalDate>()
        for (row in rows) {
            val day = row.startTime.toLocalDate()
            val raw = row.result[metric] ?: continue
            val number = when (raw) {
                is androidx.health.connect.client.units.Energy -> raw.inKilocalories
                is Long -> raw.toDouble()
                is Double -> raw
                else -> continue
            }
            values[day] = number
            if (row.result.dataOrigins.isNotEmpty()) present += day
        }
        return Daily(values, present)
    }

    override suspend fun stats(start: LocalDate, end: LocalDate, now: LocalDateTime): List<DayStats> = coroutineScope {
        val filter = range(start, end, now)
        val activeJob = async { daily(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL, filter, HealthPermissions.energy.first { "ACTIVE" in it }) }
        val totalJob = async { daily(TotalCaloriesBurnedRecord.ENERGY_TOTAL, filter, HealthPermissions.energy.first { "TOTAL" in it }) }
        val basalJob = async { daily(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL, filter, HealthPermissions.energy.first { "BASAL" in it }) }
        val stepsJob = async { daily(StepsRecord.COUNT_TOTAL, filter, HealthPermissions.steps) }
        val active = activeJob.await()
        val total = totalJob.await()
        val basal = basalJob.await()
        val steps = stepsJob.await()
        generateSequence(start) { it.plusDays(1) }.takeWhile { !it.isAfter(end) }.map { day ->
            EnergyResolver.resolve(
                day,
                EnergyAggregates(
                    active = active.value[day]?.takeIf { day in active.present },
                    total = total.value[day]?.takeIf { day in total.present },
                    basal = basal.value[day]?.takeIf { day in basal.present },
                    basalDerived = basal.value[day],
                ),
                steps = steps.value[day]?.toInt() ?: 0,
            )
        }.toList()
    }

    override suspend fun food(start: LocalDate, end: LocalDate, now: LocalDateTime): Map<LocalDate, Double> {
        val daily = daily(NutritionRecord.ENERGY_TOTAL, range(start, end, now), HealthPermissions.food)
        return generateSequence(start) { it.plusDays(1) }.takeWhile { !it.isAfter(end) }
            .associateWith { daily.value[it] ?: 0.0 }
    }
}
