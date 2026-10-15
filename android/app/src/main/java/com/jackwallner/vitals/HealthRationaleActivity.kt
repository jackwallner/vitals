package com.jackwallner.vitals

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.jackwallner.vitals.ui.Links
import com.jackwallner.vitals.ui.openUrl
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.VitalsColors
import com.jackwallner.vitals.ui.theme.VitalsTheme
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable

/**
 * Health Connect opens this from its permission screen ("Privacy policy") and,
 * on Android 14 and later, from Settings > Health Connect > App permissions.
 * It says what each permission is for, in plain words, and nothing else.
 */
class HealthRationaleActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            VitalsTheme {
                val context = LocalContext.current
                Column(
                    Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding()
                        .verticalScroll(rememberScrollState()).padding(24.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Text("How Total Calories uses Health Connect", style = Type.title3, color = palette.textPrimary)
                    Text(
                        "Total Calories reads your calories burned and steps from Health Connect and shows them as today's ring, daily history and trends. If you turn on Net Deficit, it also reads the food energy you log there.",
                        style = Type.body, color = palette.textPrimary,
                    )
                    Reason("Active and total calories", "Today's burn, the active and resting split, and your history.")
                    Reason("Basal metabolic rate", "Your measured resting burn, used for BMR and TDEE.")
                    Reason("Steps", "Today's step count and history.")
                    Reason("Nutrition", "Optional. Food energy for Net Deficit, read only if you turn it on.")
                    Reason("History and background access", "Optional. Lets history go back past 30 days and the widget refresh in the background.")
                    Text(
                        "Everything is read-only and stays on your device. Total Calories never writes to Health Connect, never sells or shares it, and has no account or server for your health data.",
                        style = Type.body, color = palette.textSecondary,
                    )
                    Box(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(VitalsColors.caloriesPrimary)
                            .tappable("Read the privacy policy") { context.openUrl(Links.PRIVACY) }.padding(vertical = 14.dp),
                        contentAlignment = Alignment.Center,
                    ) { Text("Privacy Policy", style = Type.headline, color = Color.White) }
                    Box(
                        Modifier.fillMaxWidth().tappable("Close") { finish() }.padding(vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) { Text("Close", style = Type.body, color = palette.textSecondary) }
                }
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun Reason(title: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, style = Type.headline, color = palette.textPrimary)
        Text(detail, style = Type.subhead, color = palette.textSecondary)
    }
}
