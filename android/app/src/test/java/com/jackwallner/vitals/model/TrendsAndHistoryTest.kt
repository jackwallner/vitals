package com.jackwallner.vitals.model

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ports `CalorieTrendSummaryTests` and the report, net-deficit and CSV rules. */
class TrendsAndHistoryTest {
    private val end = LocalDate.of(2026, 4, 26)

    private fun history(count: Int, values: (Int) -> Pair<Double, Double>): List<DayStats> =
        (0 until count).map { index ->
            val (active, resting) = values(index)
            DayStats(end.minusDays((count - index - 1).toLong()), active + resting, active, resting, 0)
        }

    @Test fun weeklyAndMonthlyAveragesExcludeToday() {
        val days = history(60) { i ->
            when {
                i >= 53 -> 700.0 to 1_700.0
                i >= 30 -> 600.0 to 1_600.0
                else -> 500.0 to 1_500.0
            }
        }
        val weekly = Trends.make("Calories", 7, days, emptySet()) { it.total }
        assertEquals(2_371.4286, weekly.average!!, 0.001)
        assertEquals(7, weekly.sampleDays)
        assertEquals(7.7922, weekly.percentChange!!, 0.001)
        val monthly = Trends.make("Calories", 30, days, emptySet()) { it.total }
        assertEquals(2_233.3333, monthly.average!!, 0.001)
        assertEquals(30, monthly.sampleDays)
        assertEquals(11.6667, monthly.percentChange!!, 0.001)
    }

    @Test fun zeroAndNegativeDaysAreExcludedFromAverages() {
        val days = history(14) { i ->
            when (i) {
                7, 8, 9 -> 500.0 to 1_500.0
                10, 11 -> 0.0 to 0.0
                12 -> -100.0 to 0.0
                13 -> 1_000.0 to 1_500.0
                else -> 0.0 to 0.0
            }
        }
        val weekly = Trends.make("Calories", 7, days, emptySet()) { it.total }
        assertEquals(2_000.0, weekly.average!!, 0.001)
        assertEquals(3, weekly.sampleDays)
        assertNull(weekly.percentChange)
    }

    @Test fun emptyHistoryHasNoAverage() {
        val metric = Trends.make("Calories", 7, emptyList(), emptySet()) { it.total }
        assertNull(metric.average)
        assertEquals("No data", metric.changeText)
    }

    @Test fun excludedDaysStayOutOfTheTrendAverage() {
        val days = history(30) { _ -> 500.0 to 1_500.0 }.mapIndexed { i, d -> if (i == 28) d.copy(total = 9_000.0) else d }
        val excluded = setOf(ExcludedDays.key(days[28].date))
        assertEquals(2_000.0, Trends.make("Calories", 7, days, excluded) { it.total }.average!!, 0.001)
    }

    @Test fun changeTextCarriesADirectionArrow() {
        assertEquals("↑ 8%", TrendMetric("Calories", 100.0, 7, 7, 7.8).changeText)
        assertEquals("↓ 5%", TrendMetric("Calories", 100.0, 7, 7, -5.0).changeText)
    }

    // History

    private val sample = listOf(
        DayStats(LocalDate.of(2026, 7, 1), 2_000.0, 500.0, 1_500.0, 8_000),
        DayStats(LocalDate.of(2026, 7, 2), 3_000.0, 1_500.0, 1_500.0, 12_000),
        DayStats(LocalDate.of(2026, 7, 3), 1_000.0, null, null, 4_000, RestingSource.UNSPLIT),
    )

    @Test fun summarySkipsExcludedDays() {
        val summary = HistoryCalculator.summary(sample, setOf("2026-07-03"))
        assertEquals(1, summary.excludedCount)
        assertEquals(5_000.0, summary.totalCalories)
        assertEquals(2_500.0, summary.avgCalories)
        assertEquals(10_000, summary.avgSteps)
    }

    @Test fun emptySummaryDoesNotDivideByZero() {
        val summary = HistoryCalculator.summary(emptyList(), emptySet())
        assertEquals(0.0, summary.avgCalories)
        assertEquals(0, summary.avgSteps)
    }

    @Test fun rangesEndTodayAndCustomIsClamped() {
        val today = LocalDate.of(2026, 7, 16)
        assertEquals(today.minusDays(6) to today, HistoryCalculator.range(HistoryPeriod.WEEK, today, today, today))
        val clamped = HistoryCalculator.range(HistoryPeriod.CUSTOM, today, LocalDate.of(2020, 1, 1), today.plusDays(10))
        assertEquals(today, clamped.second)
        assertEquals(today.minusDays(HistoryCalculator.MAX_CUSTOM_DAYS.toLong()), clamped.first)
    }

    @Test fun previousRangeIsTheEqualWindowBefore() {
        val (start, stop) = HistoryCalculator.previousRange(LocalDate.of(2026, 7, 10), LocalDate.of(2026, 7, 16))
        assertEquals(LocalDate.of(2026, 7, 3), start)
        assertEquals(LocalDate.of(2026, 7, 9), stop)
    }

    // Net deficit

    @Test fun netDaysNeedBurnAndFoodUnlessFasting() {
        val food = mapOf(LocalDate.of(2026, 7, 1) to 1_800.0)
        assertEquals(1, NetDeficit.days(sample, food, false, emptySet()).size)
        assertEquals(3, NetDeficit.days(sample, food, true, emptySet()).size)
    }

    @Test fun netSummaryDropsExcludedDaysAndKeepsTheSign() {
        val food = mapOf(LocalDate.of(2026, 7, 1) to 1_800.0, LocalDate.of(2026, 7, 2) to 2_000.0)
        val net = HistoryCalculator.net(sample, food, false, setOf("2026-07-02"))
        assertEquals(1, net.days.size)
        assertEquals(200.0, net.total)
        assertEquals("+200", NetDeficit.signed(200.0))
        assertEquals("-1,000".replace(",", java.text.DecimalFormatSymbols.getInstance().groupingSeparator.toString()), NetDeficit.signed(-1_000.0))
    }

    // CSV

    @Test fun csvHasTheIosColumnsAndFlagsExcludedDays() {
        val csv = CsvExport.make(sample, includeNet = false, food = emptyMap(), excludedKeys = setOf("2026-07-02"))
        val lines = csv.split("\n")
        assertEquals("Date,Active Calories,Resting Calories,Total Calories,Steps,Excluded", lines[0])
        assertEquals("2026-07-01,500,1500,2000,8000,", lines[1])
        assertEquals("2026-07-02,1500,1500,3000,12000,yes", lines[2])
        assertEquals("2026-07-03,,,1000,4000,", lines[3])
    }

    @Test fun csvOmitsTheExcludedColumnWhenNothingIsExcludedAndAddsNetOnRequest() {
        val csv = CsvExport.make(sample, includeNet = true, food = mapOf(LocalDate.of(2026, 7, 1) to 1_800.0), excludedKeys = emptySet())
        val lines = csv.split("\n")
        assertEquals("Date,Active Calories,Resting Calories,Total Calories,Steps,Food Calories,Net Deficit", lines[0])
        assertEquals("2026-07-01,500,1500,2000,8000,1800,200", lines[1])
        assertEquals("2026-07-02,1500,1500,3000,12000,,", lines[2])
    }

    // Reports and deep trends

    @Test fun reportQuotesOnlyCountedDays() {
        val report = SummaryReports.make("Report", sample.first().date, sample.last().date, sample, emptyList(), setOf("2026-07-03"), 2_500.0, 10_000)
        assertEquals(2, report.countedDayCount)
        assertEquals(1, report.excludedDayCount)
        assertEquals(5_000.0, report.totalCalories)
        assertEquals(1, report.calorieGoalHitDays)
        assertEquals(1, report.stepGoalHitDays)
        assertEquals(sample[1], report.peakCalorieDay)
        assertEquals(1_000.0, report.avgActive!!, 0.001)
    }

    @Test fun reportTrendComparesToThePriorWindow() {
        val prior = listOf(DayStats(LocalDate.of(2026, 6, 1), 1_000.0, null, null, 5_000, RestingSource.UNSPLIT))
        val report = SummaryReports.make("Report", sample.first().date, sample.last().date, sample, prior, emptySet(), null, null)
        assertNotNull(report.calorieTrendPct)
        assertEquals(100.0, report.calorieTrendPct!!, 0.001)
    }

    @Test fun deepTrendsReportsDirectionAndSkipsMissingBaselines() {
        val current = listOf(TestDays.day(LocalDate.of(2026, 7, 10), 2_200.0, 9_000))
        val previous = listOf(TestDays.day(LocalDate.of(2026, 7, 3), 2_000.0, 10_000))
        val insights = DeepTrends.insights(current, previous)
        assertEquals(listOf("Calories", "Steps"), insights.map { it.title })
        assertTrue(insights[0].isUp)
        assertEquals("+10%", insights[0].percent)
        assertEquals(false, insights[1].isUp)
        assertTrue(DeepTrends.insights(current, emptyList()).isEmpty())
    }

    @Test fun deepTrendsLabelsMatchEachPeriod() {
        assertEquals("vs. previous week", HistoryCalculator.deepTrendsLabel(HistoryPeriod.WEEK))
        assertEquals("vs. previous 30 days", HistoryCalculator.deepTrendsLabel(HistoryPeriod.MONTH))
    }

    @Test fun longPeriodsAverageIntoWeeklyAndMonthlyBuckets() {
        val days = (0 until 14).map { TestDays.day(LocalDate.of(2026, 7, 5).plusDays(it.toLong()), 2_000.0 + it) }
        val daily = Buckets.make(days, HistoryPeriod.MONTH, emptySet()) { it.total }
        assertEquals(14, daily.size)
        val weekly = Buckets.make(days, HistoryPeriod.THREE_MONTHS, emptySet()) { it.total }
        assertEquals(2, weekly.size)
        assertEquals(LocalDate.of(2026, 7, 5), weekly[0].date)
        assertEquals(2_003.0, weekly[0].value, 0.001)
    }
}
