package com.cocoscout.app

import android.app.Application
import com.cocoscout.app.bridge.FormComponent
import com.cocoscout.app.bridge.MenuComponent
import com.cocoscout.app.routing.OpenAsDocumentRouteDecisionHandler
import com.cocoscout.app.routing.OpenInBrowserRouteDecisionHandler
import dev.hotwire.core.bridge.BridgeComponentFactory
import dev.hotwire.core.bridge.KotlinXJsonConverter
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.logging.HotwireLogLevel
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerBridgeComponents
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler
import dev.hotwire.navigation.routing.BrowserTabRouteDecisionHandler
import dev.hotwire.navigation.routing.SystemNavigationRouteDecisionHandler

class CocoScoutApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        Hotwire.defaultFragmentDestination = WebFragment::class
        Hotwire.registerFragmentDestinations(WebFragment::class)

        // The same bridge components as the iOS app, so the server's
        // native_bridge_component? reads this app the same way.
        Hotwire.registerBridgeComponents(
            BridgeComponentFactory("form", ::FormComponent),
            BridgeComponentFactory("menu", ::MenuComponent)
        )

        // The page rules' "open_in" first (the phone's browser, or a document
        // viewer), then Hotwire's own in its usual order.
        Hotwire.registerRouteDecisionHandlers(
            OpenInBrowserRouteDecisionHandler(),
            OpenAsDocumentRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            BrowserTabRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        )

        Hotwire.config.jsonConverter = KotlinXJsonConverter()
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG
        Hotwire.config.logger.logLevel = if (BuildConfig.DEBUG) HotwireLogLevel.DEBUG else HotwireLogLevel.NONE

        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "path-configuration.json",
                remoteFileUrl = AppConfig.pathConfigurationUrl
            )
        )

        AppShell.start(this)
    }
}
