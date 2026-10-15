package com.jackwallner.vitals.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

fun Modifier.tappable(label: String? = null, role: Role = Role.Button, onClick: () -> Unit): Modifier =
    this.clickable(
        interactionSource = MutableInteractionSource(),
        indication = null,
        role = role,
        onClick = onClick,
    ).let { if (label != null) it.semantics { contentDescription = label } else it }

/** A rounded card on the secondary surface, `Theme.cardSurface` at the card radius. */
@Composable
fun Card(modifier: Modifier = Modifier, padding: Dp = Geo.cardPadding, content: @Composable () -> Unit) {
    Box(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Geo.cardRadius))
            .background(palette.cardSurface)
            .padding(padding),
    ) { content() }
}

/** `ProgressRing`: a track, a gradient arc with round caps, and a soft glow under the arc. */
@Composable
fun ProgressRing(progress: Float, size: Dp, lineWidth: Dp, modifier: Modifier = Modifier) {
    val animated = remember { Animatable(0f) }
    LaunchedEffect(progress) { animated.animateTo(progress.coerceIn(0f, 1f), tween(900)) }
    val track = palette.ringTrack
    Canvas(modifier.size(size)) {
        val stroke = lineWidth.toPx()
        val inset = stroke / 2 + 6.dp.toPx()
        val arcSize = Size(this.size.width - inset * 2, this.size.height - inset * 2)
        val topLeft = Offset(inset, inset)
        drawArc(track, 0f, 360f, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
        if (animated.value > 0.001f) {
            val sweep = 360f * animated.value
            drawArc(
                VitalsColors.caloriesGlow, -90f, sweep, false, topLeft, arcSize,
                style = Stroke(stroke + 8.dp.toPx(), cap = StrokeCap.Round), alpha = 0.55f,
            )
            drawArc(
                Brush.sweepGradient(listOf(VitalsColors.caloriesSecondary, VitalsColors.caloriesPrimary, VitalsColors.caloriesSecondary), center),
                -90f, sweep, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round),
            )
        }
    }
}

@Composable
fun StepProgressBar(progress: Float, modifier: Modifier = Modifier) {
    val animated = remember { Animatable(0f) }
    LaunchedEffect(progress) { animated.animateTo(progress.coerceIn(0f, 1f), tween(900)) }
    Box(modifier.fillMaxWidth().height(10.dp).clip(CircleShape).background(palette.ringTrack)) {
        Box(Modifier.fillMaxWidth(animated.value).height(10.dp).clip(CircleShape).background(Gradients.steps))
    }
}

@Composable
fun MetricPill(label: String, value: Double, color: Color) {
    Row(
        Modifier.clip(CircleShape).background(palette.cardSurface).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Text(com.jackwallner.vitals.model.Format.number(value), style = Type.rounded(15.sp, FontWeight.Bold), color = palette.textPrimary)
        Text(label, style = Type.caption, color = palette.textSecondary)
    }
}

/** A tinted capsule: `foreground` text on a 10 percent wash of itself. */
@Composable
fun TintPill(text: String, tint: Color, modifier: Modifier = Modifier, leading: ImageVector? = null, trailing: ImageVector? = null) {
    Row(
        modifier.clip(CircleShape).background(tint.copy(alpha = 0.1f)).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        leading?.let { Icon(it, null, tint = tint, modifier = Modifier.size(12.dp)) }
        Text(text, style = Type.caption2, color = tint, maxLines = 1)
        trailing?.let { Icon(it, null, tint = tint.copy(alpha = 0.7f), modifier = Modifier.size(12.dp)) }
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, loading: Boolean = false) {
    Box(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(VitalsColors.caloriesPrimary)
            .alpha(if (enabled || loading) 1f else 0.5f)
            .tappable(text) { if (enabled && !loading) onClick() }
            .padding(vertical = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (loading) {
            CircularProgressIndicator(Modifier.size(22.dp), color = Color.White, strokeWidth = 2.5.dp)
        } else {
            Text(text, style = Type.headline, color = Color.White, maxLines = 1, textAlign = TextAlign.Center)
        }
    }
}

@Composable
fun SegmentedControl(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, locked: Set<Int> = emptySet()) {
    Row(
        modifier.fillMaxWidth().clip(CircleShape).background(palette.cardSurface).padding(3.dp),
    ) {
        options.forEachIndexed { index, title ->
            val isSelected = index == selected
            val isLocked = index in locked
            Row(
                Modifier
                    .weight(1f)
                    .clip(CircleShape)
                    .background(if (isSelected) palette.cardSurfaceLight else Color.Transparent)
                    .tappable("$title${if (isLocked) ", Vitals+" else ""}", Role.Tab) { onSelect(index) }
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isLocked) {
                    Icon(Icons.Filled.Lock, null, tint = palette.textTertiary, modifier = Modifier.size(11.dp))
                    Spacer(Modifier.width(3.dp))
                }
                Text(
                    title,
                    style = Type.rounded(12.sp, FontWeight.Bold),
                    color = if (isLocked) palette.textTertiary else if (isSelected) palette.textPrimary else palette.textSecondary,
                )
            }
        }
    }
}

/** Section header and footer around a grouped list, like an iOS `Form` section. */
@Composable
fun FormSection(header: String? = null, footer: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (header != null) {
            Text(header.uppercase(), style = Type.rounded(12.sp), color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, bottom = 6.dp))
        }
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.cardSurface)) { content() }
        if (footer != null) {
            Text(footer, style = Type.rounded(12.sp), color = palette.textSecondary, modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 6.dp))
        }
    }
}

@Composable
fun RowDivider() {
    Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(0.5.dp).background(palette.textTertiary.copy(alpha = 0.4f)))
}

@Composable
fun ToggleRow(title: String, checked: Boolean, onChange: (Boolean) -> Unit, locked: Boolean = false, info: (() -> Unit)? = null, infoOpen: Boolean = false, enabled: Boolean = true) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp).height(40.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = Type.body, color = palette.textPrimary)
        if (locked) {
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Filled.Lock, "Vitals+", tint = VitalsColors.caloriesPrimary, modifier = Modifier.size(13.dp))
        }
        if (info != null) {
            Box(Modifier.size(40.dp).tappable("About $title", onClick = info), contentAlignment = Alignment.Center) {
                Icon(
                    if (infoOpen) Icons.Filled.Info else Icons.Outlined.Info,
                    null, tint = palette.textTertiary.copy(alpha = 0.9f), modifier = Modifier.size(20.dp),
                )
            }
        }
        Spacer(Modifier.weight(1f))
        Switch(
            checked = checked, onCheckedChange = onChange, enabled = enabled,
            colors = SwitchDefaults.colors(checkedTrackColor = VitalsColors.streakPrimary, checkedThumbColor = Color.White, uncheckedBorderColor = Color.Transparent, uncheckedTrackColor = palette.ringTrack, uncheckedThumbColor = Color.White),
        )
    }
}

@Composable
fun InfoCallout(message: String, detail: String? = null) {
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(message, style = Type.footnote, color = palette.textSecondary)
        if (detail != null) Text(detail, style = Type.caption, color = palette.textSecondary)
    }
}

@Composable
fun NavRow(title: String, subtitle: String? = null, onClick: () -> Unit, trailing: String? = null) {
    Row(
        Modifier.fillMaxWidth().tappable(title, onClick = onClick).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = palette.textPrimary)
            if (subtitle != null) Text(subtitle, style = Type.footnote, color = palette.textSecondary)
        }
        if (trailing != null) Text(trailing, style = Type.body, color = palette.textSecondary)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = palette.textTertiary)
    }
}

@Composable
fun StreakBadge(count: Int, metric: String, compact: Boolean = false) {
    Row(
        Modifier
            .clip(CircleShape)
            .background(VitalsColors.streakPrimary.copy(alpha = 0.12f))
            .padding(horizontal = if (compact) 8.dp else 10.dp, vertical = 4.dp)
            .semantics { contentDescription = "$count day $metric goal streak" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(Icons.Filled.LocalFireDepartment, null, tint = VitalsColors.streakPrimary, modifier = Modifier.size(12.dp))
        Text(if (compact) "${count}d" else "$count-day streak", style = Type.rounded(11.sp, FontWeight.SemiBold), color = VitalsColors.streakPrimary)
    }
}

@Composable
fun LoadingBar(color: Color = VitalsColors.caloriesPrimary, modifier: Modifier = Modifier) {
    val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "bar")
    val x by transition.animateFloat(
        -0.4f, 1f,
        androidx.compose.animation.core.infiniteRepeatable(tween(1100, easing = androidx.compose.animation.core.LinearEasing)),
        label = "x",
    )
    Box(modifier.height(4.dp).clip(CircleShape).background(color.copy(alpha = 0.18f))) {
        Canvas(Modifier.fillMaxWidth().height(4.dp)) {
            val w = size.width * 0.4f
            drawRect(color, topLeft = Offset(size.width * x, 0f), size = Size(w, size.height))
        }
    }
}

/** Paints a vector icon with a brush instead of a flat tint. */
fun Modifier.drawWithBrush(brush: Brush): Modifier = this
    .graphicsLayer(alpha = 0.99f)
    .drawWithContent {
        drawContent()
        drawRect(brush, blendMode = BlendMode.SrcAtop)
    }
