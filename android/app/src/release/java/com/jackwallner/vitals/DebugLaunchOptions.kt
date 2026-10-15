package com.jackwallner.vitals

import android.content.Intent

/** Release builds ignore launch extras, so nothing here can unlock paid content in production. */
object DebugLaunchOptions {
    /** Extras the UI reads (tab, gallery); always empty in release. */
    var tab: String? = null
    var onboardingStep: String? = null
    var overlay: String? = null

    fun prepare(app: VitalsApplication, intent: Intent?) = Unit

    fun apply(graph: AppGraph, intent: Intent?) = Unit
}
