package com.jackwallner.vitals.ui.screens

import android.graphics.Bitmap
import android.graphics.Color as AndroidColor
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.vitals.ui.shareFile
import com.jackwallner.vitals.ui.theme.PrimaryButton
import com.jackwallner.vitals.ui.theme.Type
import com.jackwallner.vitals.ui.theme.palette
import com.jackwallner.vitals.ui.theme.tappable
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** `PDFPreviewSheet`: the generated report on screen before it is shared. */
@Composable
fun ReportPreviewScreen(title: String, file: File, shareText: String, onClose: () -> Unit) {
    val context = LocalContext.current
    var page by remember { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(file) {
        page = withContext(Dispatchers.IO) {
            runCatching {
                ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                    PdfRenderer(fd).use { renderer ->
                        renderer.openPage(0).use { p ->
                            val scale = 2f
                            val bitmap = Bitmap.createBitmap((p.width * scale).toInt(), (p.height * scale).toInt(), Bitmap.Config.ARGB_8888)
                            bitmap.eraseColor(AndroidColor.WHITE)
                            p.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            bitmap
                        }
                    }
                }
            }.getOrNull()
        }
    }
    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(40.dp).tappable("Close", onClick = onClose), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Close, null, tint = palette.textSecondary)
            }
            Text(title, style = Type.headline, color = palette.textPrimary, modifier = Modifier.weight(1f).padding(start = 8.dp))
        }
        Box(Modifier.weight(1f).fillMaxWidth().background(palette.cardSurface).verticalScroll(rememberScrollState()).padding(16.dp)) {
            page?.let { Image(it.asImageBitmap(), "Report preview", Modifier.fillMaxWidth()) }
        }
        Column(Modifier.padding(horizontal = 24.dp, vertical = 12.dp)) {
            PrimaryButton("Share PDF", onClick = { context.shareFile(file, "application/pdf", shareText) })
        }
    }
}
