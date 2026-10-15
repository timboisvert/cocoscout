package com.cocoscout.app.routing

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import androidx.browser.customtabs.CustomTabColorSchemeParams
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

// Links the page rules (public/hotwire-native/path-configuration.json, shared
// with the iOS app) mark with "open_in".

/**
 * "open_in": "safari" — pages the app doesn't carry, like /manage and the
 * marketing site, open in the phone's browser (a Custom Tab, so the person
 * stays signed in there and comes straight back).
 */
class OpenInBrowserRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "open-in-browser"

    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration) =
        proposal.properties["open_in"] == "safari"

    override fun handle(proposal: VisitProposal, configuration: NavigatorConfiguration, activity: HotwireActivity): Router.Decision {
        BrowserTab.open(activity, proposal.location)
        return Router.Decision.CANCEL
    }
}

/**
 * "open_in": "document" — PDFs (W-9 copy, 1099s, invoices, signed contracts)
 * and calendar files, downloaded signed in and handed to the phone's viewer.
 */
class OpenAsDocumentRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "open-as-document"

    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration) =
        proposal.properties["open_in"] == "document"

    override fun handle(proposal: VisitProposal, configuration: NavigatorConfiguration, activity: HotwireActivity): Router.Decision {
        DocumentOpener.open(activity, proposal.location)
        return Router.Decision.CANCEL
    }
}

object BrowserTab {
    fun open(activity: HotwireActivity, url: String) {
        val colors = CustomTabColorSchemeParams.Builder()
            .setToolbarColor(Color.WHITE)
            .setNavigationBarColor(Color.WHITE)
            .build()
        try {
            CustomTabsIntent.Builder()
                .setShowTitle(true)
                .setDefaultColorSchemeParams(colors)
                .build()
                .launchUrl(activity, url.toUri())
        } catch (e: ActivityNotFoundException) {
            runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, url.toUri())) }
        }
    }
}
