package com.cocoscout.app.door

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.cocoscout.app.MainActivity

/**
 * Card networks need to know where a payment is taken, so Tap to Pay needs
 * location access (approximate is enough; Stripe's own example asks for
 * just that). It's asked for when someone sets Tap to Pay up on its page,
 * and before a sale if it somehow still hasn't been, so a sale never stops
 * halfway for it. Like TapToPayLocation.swift.
 */
object TapToPayLocation {
    fun isGranted(context: Context): Boolean =
        listOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION).any {
            ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
        }

    /** Asks if it isn't allowed yet, and returns whether it is. */
    suspend fun ask(activity: MainActivity): Boolean =
        isGranted(activity) || activity.askForLocationPermission()
}
