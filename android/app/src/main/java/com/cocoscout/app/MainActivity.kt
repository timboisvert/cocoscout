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
import androidx.lifecycle.lifecycleScope
import com.cocoscout.app.door.TapToPayOverlay
import com.cocoscout.app.door.TapToPaySetup
import com.cocoscout.app.menu.MenuOverlay
import com.cocoscout.app.signin.SignInFlow
import com.cocoscout.app.signin.PasskeyOfferOverlay
import com.cocoscout.app.signin.SignInBackdrop
import com.cocoscout.app.signin.SignInOverlay
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * The app's frame around the web pages: one screen, no tab bar, and Coco in
 * each page's toolbar opening the menu (menu/ToolbarIcons). Like the iOS app.
 */
class MainActivity : HotwireActivity() {

    private var notificationAnswer: CompletableDeferred<Boolean>? = null
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        notificationAnswer?.complete(granted)
        notificationAnswer = null
    }

    private var locationAnswer: CompletableDeferred<Boolean>? = null
    private val locationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        locationAnswer?.complete(granted)
        locationAnswer = null
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

        findViewById<ComposeView>(R.id.overlays).setContent {
            SignInBackdrop()
            MenuOverlay()
            TapToPayOverlay()
            SignInOverlay()
            PasskeyOfferOverlay()
        }

        AppShell.attach(this)
        openLinkFrom(intent)

        // The window opens pink (the theme) and stays pink while nobody's
        // signed in, under the sign-in backdrop (SignInBackdrop), so nothing
        // white shows before the sign-in screens draw (1.4.1). Signed in,
        // white behind the pages.
        lifecycleScope.launch {
            combine(AppShell.state, AppShell.signInHandedOff) { shell, handedOff -> shell.signedIn || handedOff }
                .distinctUntilChanged()
                .collect { signedIn -> window.setBackgroundDrawableResource(if (signedIn) R.color.white else R.color.pink) }
        }
    }

    /** Back in front: Tap to Pay warms up again, so a sale's tap screen opens at once. */
    override fun onStart() {
        super.onStart()
        TapToPaySetup.warmUp()
    }

    override fun onDestroy() {
        AppShell.detach(this)
        super.onDestroy()
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = AppConfig.url("/start"),
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

    /** Android's location question, for Tap to Pay (TapToPayLocation.ask). Approximate is enough. */
    suspend fun askForLocationPermission(): Boolean {
        locationAnswer?.let { return it.await() }
        val answer = CompletableDeferred<Boolean>().also { locationAnswer = it }
        locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
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
        if (uri.scheme == "cocoscout" && uri.host == "auth") {
            // Back from Continue with Apple's Custom Tab (SignInFlow.continueWithApple).
            SignInFlow.returnFromTab(this, uri)
        } else if (uri.scheme == "cocoscout" && uri.host == "open") {
            val path = uri.getQueryParameter("path")?.takeIf { it.startsWith("/") } ?: "/my"
            AppShell.open(path)
        } else if (uri.scheme == "https" && uri.host in setOf("cocoscout.com", "www.cocoscout.com")) {
            val path = (uri.encodedPath?.takeIf { it.startsWith("/") } ?: "/my") +
                (uri.encodedQuery?.let { "?$it" } ?: "")
            AppShell.open(path)
        }
    }
}
