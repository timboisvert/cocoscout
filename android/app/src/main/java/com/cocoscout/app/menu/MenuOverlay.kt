package com.cocoscout.app.menu

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.cocoscout.app.AppShell
import com.cocoscout.app.R

/**
 * The menu sheet, over whatever page is showing. Coco in each page's toolbar
 * opens it (MenuButton, in ToolbarIcons). Nothing while signed out.
 */
@Composable
fun MenuOverlay() {
    val state by AppShell.state.collectAsState()
    val nav by AppShell.nav.collectAsState()
    val showMenu by AppShell.menuOpen.collectAsState()

    if (!state.signedIn) return

    // Always the V1.1 sheet: without a nav yet (only the first launch after
    // upgrading from V1, before the first page's message) the tap waits and
    // the sheet draws when one lands, instead of flashing the V1 MenuSheet
    // (kept for V1 installs, which never get a nav).
    val currentNav = nav
    if (showMenu && currentNav != null) {
        NavMenuSheet(
            nav = currentNav,
            person = state.person,
            onDismiss = { AppShell.showMenu(false) },
            onOpen = { path ->
                AppShell.showMenu(false)
                AppShell.openFromMenu(path)
            },
            onSignOut = {
                AppShell.showMenu(false)
                AppShell.signOut()
            }
        )
    }
}

/**
 * The menu button: Coco's face in a white circle with a pink ring, at the
 * right end of every page's toolbar, after Messages and Notifications and
 * the size of each of them (ToolbarIcons). It used to float over the page's
 * bottom right corner and was always over something (Tim, 2026-11-09).
 * Nothing while signed out. Like MenuButton.swift.
 */
@Composable
fun MenuButton() {
    val state by AppShell.state.collectAsState()
    if (!state.signedIn) return

    // 44dp to tap, as the icons beside it; a 36dp circle to look at.
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .clickable { AppShell.showMenu() }
            .semantics { contentDescription = "Menu" }
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .clip(CircleShape)
                .background(Color.White)
                .border(2.dp, Pink, CircleShape),
            contentAlignment = Alignment.TopCenter
        ) {
            // A little wider than the circle and nudged down, so the face fills it.
            Image(
                painter = painterResource(R.drawable.coco),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .padding(top = 3.dp)
                    .requiredWidth(40.dp)
                    .aspectRatio(721f / 768f)
            )
        }
    }
}
