package com.cocoscout.app

import android.os.Bundle
import android.view.View
import androidx.core.net.toUri
import android.view.ViewGroup
import androidx.core.view.updateLayoutParams
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebFragment

/**
 * Every page: Hotwire's web screen with the page's title in the toolbar
 * (Coustard, on the left, via the theme). Like WebViewController.swift.
 */
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
open class WebFragment : HotwireWebFragment() {

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        navigator.location?.let { updateToolbar(it) }
    }

    override fun onVisitRendered(location: String) {
        super.onVisitRendered(location)
        // A page can turn out to be sign-in after a redirect (/my, signed out).
        updateToolbar(location)
        AppShell.pageRendered()
    }

    /**
     * The welcome screen, sign-in and sign-up stand on their own: no title bar
     * above them (each has its own heading; sign-in and sign-up have a Back
     * link to the welcome screen). The status bar's space stays.
     */
    private fun updateToolbar(location: String) {
        val toolbar = toolbarForNavigation() ?: return
        // Zero height rather than hidden: the app bar above it only keeps the
        // status bar's space while it has a visible child.
        toolbar.updateLayoutParams {
            height = if (location.toUri().path in barlessPaths) 0 else ViewGroup.LayoutParams.WRAP_CONTENT
        }
    }

    companion object {
        private val barlessPaths = setOf("/welcome", "/signin", "/signup")
    }
}
