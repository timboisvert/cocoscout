package com.cocoscout.app

import android.content.Context
import android.webkit.CookieManager
import androidx.lifecycle.lifecycleScope
import dev.hotwire.core.config.Hotwire
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import com.cocoscout.app.bridge.MenuItem
import com.cocoscout.app.bridge.MenuPerson
import dev.hotwire.core.turbo.visit.VisitAction
import dev.hotwire.core.turbo.visit.VisitOptions
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * The menu and who's signed in, as the server last sent them (MenuComponent
 * on every page load), and the moves the menu makes. An empty menu means
 * signed out, and the floating button hides. Mirrors ios/CocoScout/AppShell.swift.
 */
object AppShell {
    @Serializable
    data class State(val menu: List<MenuItem> = emptyList(), val person: MenuPerson? = null) {
        val signedIn: Boolean get() = menu.isNotEmpty()
        val badgeTotal: Int get() = menu.sumOf { it.badge ?: 0 }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private const val PREFS = "app_shell"
    private const val STATE_KEY = "state"

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private val _nav = MutableStateFlow<com.cocoscout.app.bridge.NavData?>(null)
    /** The V1.1 menu (NativeAppHelper#native_nav), once a page has sent one. */
    val nav: StateFlow<com.cocoscout.app.bridge.NavData?> = _nav.asStateFlow()

    /** Every page sends it; the menu sheet and the toolbar's two icons follow it. */
    fun update(newNav: com.cocoscout.app.bridge.NavData?) {
        if (newNav != null) _nav.value = newNav
    }

    private var activity: MainActivity? = null
    /** Signed in or out, as the screen was last built for (from the cache at launch). */
    private var shownSignedIn: Boolean? = null
    private var pendingPath: String? = null
    private var pendingScreen: String? = null
    /** The first page has rendered: before that, the web view can't take a visit. */
    private var pageShown = false
    private lateinit var appContext: Context

    /** Starts with last time's menu, so the button is there right away for someone still signed in. */
    fun start(context: Context) {
        appContext = context.applicationContext
        val saved = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(STATE_KEY, null)
        saved?.let { runCatching { json.decodeFromString(State.serializer(), it) }.getOrNull() }?.let { _state.value = it }
        shownSignedIn = _state.value.signedIn
    }

    fun attach(activity: MainActivity) {
        this.activity = activity
        pageShown = false
    }

    fun detach(activity: MainActivity) {
        if (this.activity === activity) this.activity = null
    }

    /**
     * A page finished rendering (WebFragment). A link that opened the app
     * from closed (a tapped notification) waits for the first one, then
     * opens on top of it.
     */
    fun pageRendered() {
        pageShown = true
        pendingScreen?.let {
            pendingScreen = null
            replaceScreen(it)
        }
        pendingPath?.let {
            pendingPath = null
            open(it)
        }
    }

    /** page: the address of the page that sent the menu. */
    fun update(menu: List<MenuItem>, person: MenuPerson?, page: String? = null) {
        _state.value = State(menu, person)
        val signedIn = menu.isNotEmpty()
        val justSignedIn = signedIn && shownSignedIn == false
        shownSignedIn = signedIn
        // Just signed in: start afresh on the page the server sent them to
        // (an invitation's, from an email link) or My Calendar, with no back
        // to the sign-in page. Signing out lands on sign-in by itself.
        if (justSignedIn) startOver(pageAfterSignIn(page))
        // Without badges or the Door (it comes and goes with the shows).
        val cached = State(menu.filter { it.id != "door" }.map { it.copy(badge = null) }, person)
        appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(STATE_KEY, json.encodeToString(State.serializer(), cached))
            .apply()
    }

    /** A page on top of whatever's showing (a link back from Stripe, a tapped notification). */
    fun open(path: String) {
        val navigator = activity?.currentNavigator
        if (navigator == null || !navigator.isReady() || !pageShown) {
            pendingPath = path
            return
        }
        navigator.route(AppConfig.url(path))
    }

    /**
     * A pick from the menu becomes the whole screen, with no back to the page
     * before. With pages stacked up, they're cleared back to the first one,
     * which must finish showing before it's replaced: replacing it straight
     * away left the shared web view stuck on the screen being removed, and
     * every screen after it blank.
     */
    fun replaceScreen(path: String) {
        val navigator = activity?.currentNavigator ?: return
        if (navigator.isAtStartDestination()) {
            navigator.route(AppConfig.url(path), VisitOptions(action = VisitAction.REPLACE))
        } else {
            pendingScreen = path
            navigator.clearAll()
        }
    }

    /**
     * The screen built afresh on My Calendar (Hotwire's reset, like the iOS
     * app reloading its tab), then the given page on top. Posted, so the
     * page that sent the menu finishes first.
     */
    private fun startOver(path: String?) {
        val navigator = activity?.currentNavigator ?: return
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            navigator.reset {
                path?.let { navigator.route(AppConfig.url(it)) }
            }
        }
    }

    /**
     * Ends the session on the server (with the web view's cookies), then
     * starts the app afresh, which lands on the welcome screen like opening
     * the app signed out does.
     */
    fun signOut() {
        val activity = activity ?: return
        activity.lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                runCatching {
                    val url = AppConfig.url("/signout")
                    val cookies = CookieManager.getInstance()
                    val connection = URL(url).openConnection() as HttpURLConnection
                    cookies.getCookie(url)?.let { connection.setRequestProperty("Cookie", it) }
                    connection.setRequestProperty("User-Agent", Hotwire.config.userAgentWithWebViewDefault(activity))
                    connection.instanceFollowRedirects = false
                    connection.responseCode
                    connection.headerFields["Set-Cookie"]?.forEach { cookies.setCookie(url, it) }
                    cookies.flush()
                    connection.disconnect()
                }
            }
            update(emptyList(), null)
            startOver(null)
        }
    }

    /** The page sign-in landed on, when it's somewhere other than My Calendar or the sign-in pages. */
    private fun pageAfterSignIn(page: String?): String? {
        val uri = page?.let { runCatching { android.net.Uri.parse(it) }.getOrNull() } ?: return null
        if (uri.host != android.net.Uri.parse(AppConfig.baseUrl).host) return null
        val path = uri.path.orEmpty()
        val home = setOf("", "/", "/start", "/my", "/my/")
        val signingIn = listOf("/welcome", "/signin", "/signup", "/signout", "/password", "/reset")
        if (path in home || signingIn.any { path.startsWith(it) }) return null
        return uri.query?.let { "$path?$it" } ?: path
    }

    fun badgeText(count: Int): String? = when {
        count <= 0 -> null
        count > 99 -> "99+"
        else -> count.toString()
    }
}
