package com.jackwallner.vitals.widget

import android.content.Context
import android.content.Intent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
import com.jackwallner.vitals.MainActivity
import com.jackwallner.vitals.data.SharedPreferencesStore
import com.jackwallner.vitals.data.WidgetSnapshot
import com.jackwallner.vitals.model.Format
import java.time.LocalDate

/** What the widget draws, read from the snapshot the app wrote at its last refresh. */
data class WidgetState(
    val calories: Double,
    val steps: Int,
    val calorieGoal: Double?,
    val stepGoal: Int?,
    val showCalories: Boolean,
    val showSteps: Boolean,
    val hasData: Boolean,
    val stale: Boolean,
) {
    companion object {
        fun read(context: Context, today: LocalDate = LocalDate.now()): WidgetState {
            val store = SharedPreferencesStore(context)
            val calories = store.getString(WidgetSnapshot.CALORIES)?.toDoubleOrNull()
            return WidgetState(
                calories = calories ?: 0.0,
                steps = store.getInt(WidgetSnapshot.STEPS, 0),
                calorieGoal = store.getString(WidgetSnapshot.CALORIE_GOAL)?.toDoubleOrNull(),
                stepGoal = if (store.contains(WidgetSnapshot.STEP_GOAL)) store.getInt(WidgetSnapshot.STEP_GOAL, 0) else null,
                showCalories = store.getBoolean("showCalories", true),
                showSteps = store.getBoolean("showSteps", true),
                hasData = calories != null,
                stale = store.getString(WidgetSnapshot.DAY) != today.toString(),
            )
        }
    }
}

private val Coral = Color(0xFFFF6B4A)
private val Teal = Color(0xFF14B8A6)

private fun fixed(color: Color) = androidx.glance.unit.ColorProvider(color)

private fun ink(day: Long, night: Long) = ColorProvider(day = Color(day), night = Color(night))

class VitalsWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = WidgetState.read(context)
        provideContent { WidgetContent(state, context) }
    }
}

@androidx.compose.runtime.Composable
private fun WidgetContent(state: WidgetState, context: Context) {
    val primary = ink(0xFF1C1C1E, 0xFFFFFFFF)
    val secondary = ink(0xFF6B6B70, 0xFFA1A1A8)
    val open = actionStartActivity(Intent(context, MainActivity::class.java))
    Column(
        GlanceModifier.fillMaxSize().background(ink(0xFFFFFFFF, 0xFF1C1C1E)).cornerRadius(20.dp).padding(14.dp).clickable(open),
        verticalAlignment = Alignment.Vertical.CenterVertically,
    ) {
        if (!state.hasData) {
            Text("Total Calories", style = TextStyle(color = primary, fontSize = 15.sp, fontWeight = FontWeight.Bold))
            Spacer(GlanceModifier.height(4.dp))
            Text("Open the app to load today.", style = TextStyle(color = secondary, fontSize = 12.sp))
            return@Column
        }
        if (state.showCalories) {
            Text("Calories burned", style = TextStyle(color = secondary, fontSize = 11.sp))
            Text(Format.number(state.calories), style = TextStyle(color = fixed(Coral), fontSize = 28.sp, fontWeight = FontWeight.Bold))
            state.calorieGoal?.takeIf { it > 0 }?.let { goal ->
                LinearProgressIndicator((state.calories / goal).toFloat().coerceIn(0f, 1f), GlanceModifier.fillMaxWidth(), fixed(Coral), ink(0xFFE5E5EA, 0xFF3A3A3C))
            }
            Spacer(GlanceModifier.height(10.dp))
        }
        if (state.showSteps) {
            Text("Steps", style = TextStyle(color = secondary, fontSize = 11.sp))
            Text(Format.number(state.steps.toDouble()), style = TextStyle(color = fixed(Teal), fontSize = 22.sp, fontWeight = FontWeight.Bold))
            state.stepGoal?.takeIf { it > 0 }?.let { goal ->
                LinearProgressIndicator((state.steps.toFloat() / goal).coerceIn(0f, 1f), GlanceModifier.fillMaxWidth(), fixed(Teal), ink(0xFFE5E5EA, 0xFF3A3A3C))
            }
        }
        if (state.stale) {
            Spacer(GlanceModifier.height(6.dp))
            Text("Last update was not today", style = TextStyle(color = secondary, fontSize = 10.sp))
        }
    }
}

class VitalsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = VitalsWidget()
}
