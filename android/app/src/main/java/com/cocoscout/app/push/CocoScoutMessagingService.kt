package com.cocoscout.app.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * Firebase hands the app each notification here, open or not: the server
 * sends data only (FcmClient), so the app always builds the notification
 * itself and every one looks the same.
 */
class CocoScoutMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        Notifications.show(this, message.data)
    }

    override fun onNewToken(token: String) {
        PushRegistrar.tokenChanged(this, token)
    }
}
