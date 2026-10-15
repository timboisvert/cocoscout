package com.cocoscout.app

import android.os.Bundle
import android.view.View
import androidx.core.net.toUri
import androidx.core.view.isVisible
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
    }

    /**
     * Sign-in and sign-up stand on their own: no title bar above them (the
     * page has its own heading, and there's nowhere to go back to). The status
     * bar's space stays.
     */
    private fun updateToolbar(location: String) {
        toolbarForNavigation()?.isVisible = location.toUri().path !in barlessPaths
    }

    companion object {
        private val barlessPaths = setOf("/signin", "/signup")
    }
}
