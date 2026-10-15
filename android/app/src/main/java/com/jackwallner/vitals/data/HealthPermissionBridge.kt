package com.jackwallner.vitals.data

import kotlinx.coroutines.CompletableDeferred

/** Lets a coroutine ask Health Connect for permissions and wait for the answer the Activity receives. */
class HealthPermissionBridge {
    private var pending: CompletableDeferred<Set<String>>? = null
    var launch: ((Set<String>) -> Unit)? = null

    /** The permissions actually granted after the dialog; empty if it could not be shown. */
    suspend fun request(permissions: Set<String>): Set<String> {
        val launcher = launch ?: return emptySet()
        val deferred = CompletableDeferred<Set<String>>()
        pending = deferred
        launcher(permissions)
        return deferred.await()
    }

    fun complete(granted: Set<String>) {
        pending?.complete(granted)
        pending = null
    }
}
