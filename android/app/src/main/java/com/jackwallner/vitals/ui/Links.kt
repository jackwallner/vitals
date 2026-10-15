package com.jackwallner.vitals.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import com.google.android.play.core.review.ReviewManagerFactory
import com.jackwallner.vitals.BuildConfig
import java.io.File
import java.util.Locale
import java.util.TimeZone

object Links {
    const val PACKAGE = "com.jackwallner.vitals"
    const val PRIVACY = "https://jackwallner.github.io/vitals/android-privacy.html"
    const val TERMS = "https://jackwallner.github.io/vitals/android-terms.html"
    const val SUPPORT = "https://jackwallner.github.io/vitals/support.html"
    const val SUPPORT_EMAIL = "jackwallner+tc@gmail.com"
    const val LISTING = "https://play.google.com/store/apps/details?id=$PACKAGE"
    const val MANAGE_SUBSCRIPTIONS = "https://play.google.com/store/account/subscriptions"
    const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"
}

fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

fun Context.openUrl(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** Opens the Health Connect app on the Play Store listing it asks for, or its own settings when installed. */
fun Context.openHealthConnectSettings() {
    val settings = Intent("android.health.connect.action.HEALTH_HOME_SETTINGS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    val opened = runCatching { startActivity(settings) }.isSuccess
    if (!opened) openHealthConnectStore()
}

fun Context.openHealthConnectStore() {
    openUrl("market://details?id=${Links.HEALTH_CONNECT_PACKAGE}&url=healthconnect%3A%2F%2Fonboarding")
}

/** The Play in-app review card, never from a button and never after a question. */
fun Context.launchPlayReview() {
    val activity = findActivity() ?: return
    val manager = ReviewManagerFactory.create(activity)
    manager.requestReviewFlow().addOnCompleteListener { request ->
        if (request.isSuccessful) manager.launchReviewFlow(activity, request.result)
    }
}

enum class MailKind(val subject: String) {
    FEEDBACK("Total Calories: Feedback"),
    HELP("Total Calories: Get Help"),
    FEATURE("Total Calories: Feature Request"),
}

/** A mail draft to support. Diagnostics are plain app and device facts, never health data. */
fun Context.composeSupportMail(kind: MailKind, isPro: Boolean) {
    val body = buildString {
        append("\n\n\n---\n")
        append("App: ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\n")
        if (kind == MailKind.HELP) {
            append("Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}\n")
            append("Locale/TZ: ${Locale.getDefault()} / ${TimeZone.getDefault().id}\n")
            append("Vitals+: ${if (isPro) "active" else "off"}\n")
        }
    }
    val uri = Uri.parse("mailto:${Links.SUPPORT_EMAIL}").buildUpon()
        .appendQueryParameter("subject", kind.subject)
        .appendQueryParameter("body", body)
        .build()
    runCatching { startActivity(Intent(Intent.ACTION_SENDTO, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

/** Shares a cache file (CSV or PDF) through the app's FileProvider. */
fun Context.shareFile(file: File, mime: String, title: String) {
    val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
    val send = Intent(Intent.ACTION_SEND)
        .setType(mime)
        .putExtra(Intent.EXTRA_STREAM, uri)
        .putExtra(Intent.EXTRA_SUBJECT, title)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    runCatching { startActivity(Intent.createChooser(send, title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
