package com.jackwallner.vitals.model

import java.time.LocalDate

/** Where a day's resting energy came from. See `project-docs/android/health-connect-feasibility.md`. */
enum class RestingSource {
    /** Health Connect total minus active, both measured. */
    MEASURED_TOTAL,
    /** A basal metabolic rate record, summed over the day. */
    MEASURED_BMR,
    /** Nothing reported resting energy: the platform's profile-based estimate. */
    ESTIMATED,
    /** Total only, with no active record or BMR to split it. */
    UNSPLIT,
    NONE,
}

/**
 * One calendar day. `total` is what the ring shows. `active` and `resting` add
 * up to `total` whenever both are known; otherwise one or both are null.
 */
data class DayStats(
    val date: LocalDate,
    val total: Double,
    val active: Double?,
    val resting: Double?,
    val steps: Int,
    val restingSource: RestingSource = if (resting != null) RestingSource.MEASURED_TOTAL else RestingSource.NONE,
) {
    val hasEnergy: Boolean get() = total > 0
    val hasData: Boolean get() = total > 0 || steps > 0
    val restingIsEstimated: Boolean get() = restingSource == RestingSource.ESTIMATED

    companion object {
        fun empty(date: LocalDate) = DayStats(date, 0.0, null, null, 0, RestingSource.NONE)
    }
}

/** Raw Health Connect aggregates for one day. Null means "no record of this type contributed". */
data class EnergyAggregates(
    val active: Double?,
    val total: Double?,
    val basal: Double?,
    /** The platform's profile-derived basal figure; always present, never measured. */
    val basalDerived: Double?,
)

object EnergyResolver {
    /**
     * Turns the three Health Connect energy aggregates into one consistent day.
     *
     * Health Connect's own total (`ENERGY_TOTAL`) already fills gaps between
     * total records with active + basal, so a measured total is trusted whole.
     * Resting is whatever the total holds beyond active.
     */
    fun resolve(date: LocalDate, energy: EnergyAggregates, steps: Int): DayStats {
        val active = energy.active?.takeIf { it > 0 }
        val total = energy.total?.takeIf { it > 0 }
        val basal = energy.basal?.takeIf { it > 0 }
        return when {
            total != null && active != null -> {
                val a = minOf(active, total)
                DayStats(date, total, a, total - a, steps, RestingSource.MEASURED_TOTAL)
            }
            total != null && basal != null -> {
                val r = minOf(basal, total)
                DayStats(date, total, total - r, r, steps, RestingSource.MEASURED_BMR)
            }
            total != null -> DayStats(date, total, null, null, steps, RestingSource.UNSPLIT)
            active != null && basal != null ->
                DayStats(date, active + basal, active, basal, steps, RestingSource.MEASURED_BMR)
            active != null -> {
                val estimate = energy.basalDerived?.takeIf { it > 0 }
                if (estimate != null) DayStats(date, active + estimate, active, estimate, steps, RestingSource.ESTIMATED)
                else DayStats(date, active, active, null, steps, RestingSource.UNSPLIT)
            }
            basal != null -> DayStats(date, basal, 0.0, basal, steps, RestingSource.MEASURED_BMR)
            else -> DayStats(date, 0.0, null, null, steps, RestingSource.NONE)
        }
    }
}
