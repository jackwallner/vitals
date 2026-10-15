package com.jackwallner.vitals

import android.app.Application

class VitalsApplication : Application() {
    lateinit var graph: AppGraph
        private set

    override fun onCreate() {
        super.onCreate()
        graph = AppGraph(this)
    }

    /** Debug launch extras only: a fresh graph after the stored state was wiped, so nothing stale survives in memory. */
    fun rebuildGraph() {
        graph = AppGraph(this)
    }
}
