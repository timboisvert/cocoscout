package com.cocoscout.app

/**
 * Where the app points. Debug builds talk to the Rails server on this Mac
 * (the emulator reaches it at localhost through `adb reverse tcp:3000 tcp:3000`);
 * release builds talk to cocoscout.com.
 */
object AppConfig {
    val baseUrl: String = BuildConfig.BASE_URL

    /**
     * Which navigation this build draws: V1 builds are 1 and read the original
     * page rules; V1.1 builds (production mode, the universal Messages and
     * Notifications icons) are 2. The server reads it from the user agent
     * (NativeAppVersion) and only sends generation-2 menus and pages to builds
     * that say so, so V1 installs never see them.
     */
    const val NAV_GENERATION = 2

    /** Each generation's page rules, shared with the iOS app (public/hotwire-native). */
    val pathConfigurationUrl = "$baseUrl/hotwire-native/nav-$NAV_GENERATION/path-configuration.json"
    const val PATH_CONFIGURATION_ASSET = "nav-$NAV_GENERATION/path-configuration.json"

    /** "CocoScout/1.2 (3; nav 2)", ahead of Hotwire Native's own user agent. */
    val userAgentPrefix = "CocoScout/${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}; nav $NAV_GENERATION)"

    fun url(path: String): String = if (path.startsWith("http")) path else baseUrl + path
}
