package com.cocoscout.app

/**
 * Where the app points. Debug builds talk to the Rails server on this Mac
 * (the emulator reaches it at localhost through `adb reverse tcp:3000 tcp:3000`);
 * release builds talk to cocoscout.com.
 */
object AppConfig {
    val baseUrl: String = BuildConfig.BASE_URL

    /** The page rules the iOS app and this one share (public/hotwire-native). */
    val pathConfigurationUrl = "$baseUrl/hotwire-native/path-configuration.json"

    fun url(path: String): String = if (path.startsWith("http")) path else baseUrl + path
}
