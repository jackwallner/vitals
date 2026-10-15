package com.jackwallner.vitals

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import com.jackwallner.vitals.data.HealthPermissions

/**
 * Debug only. Opens Health Connect's real permission dialog for every read
 * permission the app declares plus the debug-only write permissions, so the
 * seeder's records count in aggregates (Health Connect only aggregates data from
 * apps that were granted write access through its own flow).
 */
class DebugPermissionActivity : ComponentActivity() {
    private val request = registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
        setResult(RESULT_OK, intent.putExtra("granted", granted.size))
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val writes = setOf(
            "android.permission.health.WRITE_ACTIVE_CALORIES_BURNED",
            "android.permission.health.WRITE_TOTAL_CALORIES_BURNED",
            "android.permission.health.WRITE_BASAL_METABOLIC_RATE",
            "android.permission.health.WRITE_STEPS",
            "android.permission.health.WRITE_NUTRITION",
        )
        request.launch(HealthPermissions.core(includeFood = true) + writes)
    }
}
