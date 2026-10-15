package com.cocoscout.app

import android.Manifest
import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.ui.platform.ComposeView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import com.cocoscout.app.menu.MenuOverlay
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import kotlinx.coroutines.CompletableDeferred

/**
 * The app's frame around the web pages: one screen, no tab bar, and the
 * floating Coco button that opens the menu (AppShell, menu/). Like the iOS app.
 */
class MainActivity : HotwireActivity() {

    private var notificationAnswer: CompletableDeferred<Boolean>? = null
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notificationAnswer?.complete(granted)
        notificationAnswer = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val root = findViewById<View>(R.id.root)
        root.applyDefaultImeWindowInsets()
        // Pages end above the gesture bar; each page's toolbar handles the top.
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main_navigator_host)) { view, insets ->
            view.updatePadding(bottom = insets.getInsets(WindowInsetsCompat.Type.navigationBars()).bottom)
            insets
        }

        findViewById<ComposeView>(R.id.menu_button).setContent { MenuOverlay() }

        AppShell.attach(this)
        openLinkFrom(intent)
    }

    override fun onDestroy() {
        AppShell.detach(this)
        super.onDestroy()
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = AppConfig.url("/my"),
            navigatorHostId = R.id.main_navigator_host
        )
    )

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openLinkFrom(intent)
    }

    /** Android 13's "Allow notifications?" (PushRegistrar.request). */
    suspend fun askForNotificationPermission(): Boolean {
        val answer = CompletableDeferred<Boolean>().also { notificationAnswer = it }
        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        return answer.await()
    }

    val currentNavigator: Navigator?
        get() = delegate.currentNavigator

    /**
     * cocoscout://open?path=/my/... from Stripe's return page
     * (AppReturnsController) or a tapped notification (push/Notifications),
     * and https://cocoscout.com/... links the app claims (AndroidManifest).
     */
    private fun openLinkFrom(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "cocoscout" && uri.host == "open") {
            val path = uri.getQueryParameter("path")?.takeIf { it.startsWith("/") } ?: "/my"
            AppShell.open(path)
        } else if (uri.scheme == "https" && uri.host in setOf("cocoscout.com", "www.cocoscout.com")) {
            val path = (uri.encodedPath?.takeIf { it.startsWith("/") } ?: "/my") +
                (uri.encodedQuery?.let { "?$it" } ?: "")
            AppShell.open(path)
        }
    }
}
