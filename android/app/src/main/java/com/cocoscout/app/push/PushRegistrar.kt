package com.cocoscout.app.push

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import com.cocoscout.app.MainActivity
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.Serializable
import kotlin.coroutines.resume

/**
 * This phone's push notifications: whether they're allowed, the token
 * Firebase gives the app to reach this phone, and asking. The web side files
 * the token under the signed-in person (PushComponent →
 * bridge/push_controller.js → /my/push-token). Like PushRegistrar.swift.
 *
 * Never asks on its own: Android's "Allow notifications?" appears only when
 * someone taps Turn on (the Home card, or Settings → Notifications).
 */
object PushRegistrar {
    /**
     * What the web side needs, in the iOS app's words: status is
     * "authorized", "denied" or "notDetermined". token: when allowed, the
     * current one; when not, the last one, so the server can forget it.
     */
    @Serializable
    data class State(
        val status: String,
        val token: String?,
        val environment: String = "production",
        val platform: String = "android"
    )

    private const val PREFS = "push"
    private const val TOKEN_KEY = "token"
    private const val ASKED_KEY = "asked"

    suspend fun state(activity: Activity): State {
        val status = status(activity)
        val token = if (status == "authorized") currentToken(activity) else savedToken(activity)
        return State(status, token)
    }

    /** Android's own question (Android 13 and later), then where that leaves things. */
    suspend fun request(activity: MainActivity): State {
        if (Build.VERSION.SDK_INT >= 33 && status(activity) == "notDetermined") {
            prefs(activity).edit { putBoolean(ASKED_KEY, true) }
            activity.askForNotificationPermission()
        }
        return state(activity)
    }

    /** CocoScout's notification settings, the only place they can be turned off. */
    fun openSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        context.startActivity(intent)
    }

    /** Firebase's new token for this phone; the next page the app opens files it. */
    fun tokenChanged(context: Context, token: String) {
        prefs(context).edit { putString(TOKEN_KEY, token) }
    }

    private fun status(activity: Activity): String {
        val enabled = NotificationManagerCompat.from(activity).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < 33) return if (enabled) "authorized" else "denied"

        val permission = Manifest.permission.POST_NOTIFICATIONS
        val granted = ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED
        return when {
            granted && enabled -> "authorized"
            granted -> "denied" // turned off in Settings
            !prefs(activity).getBoolean(ASKED_KEY, false) -> "notDetermined"
            // Said no once: Android lets the app ask one more time.
            activity.shouldShowRequestPermissionRationale(permission) -> "notDetermined"
            else -> "denied"
        }
    }

    private suspend fun currentToken(context: Context): String? {
        // Firebase usually answers at once; never leave the page waiting.
        val token = withTimeoutOrNull(10_000) {
            suspendCancellableCoroutine { continuation ->
                FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                    continuation.resume(if (task.isSuccessful) task.result else null)
                }
            }
        }
        if (token != null) tokenChanged(context, token)
        return token ?: savedToken(context)
    }

    private fun savedToken(context: Context) = prefs(context).getString(TOKEN_KEY, null)

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
