package com.cocoscout.app.menu

import android.content.Context
import android.view.ViewTreeObserver
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.cocoscout.app.AppShell
import com.cocoscout.app.R

/**
 * The floating Coco button, and the menu it opens. Hidden while signed out.
 * The button gets itself out of the page's way (Tim, 2026-11-06): the page
 * says what is pinned at its bottom (MenuButtonComponent) and the button sits
 * above it, or goes away while the reader scrolls down, a sheet is over the
 * page, or the keyboard is up.
 */
@Composable
fun MenuOverlay() {
    val state by AppShell.state.collectAsState()
    val nav by AppShell.nav.collectAsState()
    val place by AppShell.buttonPlace.collectAsState()
    var showMenu by remember { mutableStateOf(false) }

    if (!state.signedIn) return

    // With TalkBack the button never leaves for a scroll: it has to stay findable.
    val context = LocalContext.current
    val touchExploration = remember(place) {
        (context.getSystemService(Context.ACCESSIBILITY_SERVICE) as? AccessibilityManager)?.isTouchExplorationEnabled == true
    }
    val away = keyboardShowing() || (place.away && !touchExploration)
    // 16dp off the bottom at rest; 10dp of air above a pinned bar.
    val bottom = if (place.rise > 0) maxOf(16, place.rise + 10).dp else 16.dp

    // V1.1: no badge on Coco; the toolbar's Messages and Notifications carry the counts.
    MenuButton(badge = if (nav != null) null else AppShell.badgeText(state.badgeTotal), bottom = bottom, away = away) { showMenu = true }

    // Always the V1.1 sheet: without a nav yet (only the first launch after
    // upgrading from V1, before the first page's message) the tap waits and
    // the sheet draws when one lands, instead of flashing the V1 MenuSheet
    // (kept for V1 installs, which never get a nav).
    val currentNav = nav
    if (showMenu && currentNav != null) {
        NavMenuSheet(
            nav = currentNav,
            person = state.person,
            onDismiss = { showMenu = false },
            onOpen = { path ->
                showMenu = false
                AppShell.openFromMenu(path)
            },
            onSignOut = {
                showMenu = false
                AppShell.signOut()
            }
        )
    }
}

/**
 * The keyboard is up. Read from the window itself: the activity's root takes
 * the keyboard's inset for its own padding, so it may never reach this view.
 * The button used to ride up with the page, over the form being typed in.
 */
@Composable
private fun keyboardShowing(): Boolean {
    val view = LocalView.current
    var showing by remember { mutableStateOf(false) }
    DisposableEffect(view) {
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            showing = ViewCompat.getRootWindowInsets(view)?.isVisible(WindowInsetsCompat.Type.ime()) == true
        }
        view.viewTreeObserver.addOnGlobalLayoutListener(listener)
        onDispose { view.viewTreeObserver.removeOnGlobalLayoutListener(listener) }
    }
    return showing
}

/**
 * Coco's face in a white circle with a pink ring, at the bottom right, with
 * the total of every badge. Like MenuButton.swift.
 *
 * bottom: how far off the bottom it sits (higher above a pinned bar).
 * away: shrunk and faded out of the page's way, and not there to tap.
 */
@Composable
fun MenuButton(badge: String?, bottom: Dp = 16.dp, away: Boolean = false, onClick: () -> Unit) {
    val lift by animateDpAsState(bottom, spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow), label = "lift")
    val shown by animateFloatAsState(if (away) 0f else 1f, tween(200), label = "shown")
    if (shown < 0.01f) return

    Box(
        modifier = Modifier
            .navigationBarsPadding()
            .padding(end = 20.dp, bottom = lift, top = 8.dp, start = 8.dp)
            .graphicsLayer {
                alpha = shown
                scaleX = 0.5f + shown / 2
                scaleY = 0.5f + shown / 2
                // Shrinks into its own middle (20dp in from the right, 8dp
                // down), not the middle of the room under it.
                if (size.width > 0f && size.height > 0f) {
                    transformOrigin = TransformOrigin(1f - 50.dp.toPx() / size.width, 38.dp.toPx() / size.height)
                }
            }
            .semantics { contentDescription = "Menu" }
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .shadow(8.dp, CircleShape)
                .clip(CircleShape)
                .background(Color.White)
                .border(3.dp, Pink, CircleShape)
                .clickable(enabled = !away, onClick = onClick),
            contentAlignment = Alignment.TopCenter
        ) {
            // A little wider than the circle and nudged down, so the face fills it.
            Image(
                painter = painterResource(R.drawable.coco),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .padding(top = 5.dp)
                    .requiredWidth(66.dp)
                    .aspectRatio(721f / 768f)
            )
        }
        if (badge != null) {
            Text(
                text = badge,
                color = Color.White,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 4.dp, y = (-4).dp)
                    .defaultMinSize(minWidth = 20.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color(0xFFE60076))
                    .border(2.dp, Color.White, RoundedCornerShape(10.dp))
                    .padding(horizontal = 6.dp, vertical = 1.dp)
            )
        }
    }
}
