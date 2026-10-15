package com.cocoscout.app.menu

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
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cocoscout.app.AppShell
import com.cocoscout.app.R

/** The floating Coco button, and the menu it opens. Hidden while signed out. */
@Composable
fun MenuOverlay() {
    val state by AppShell.state.collectAsState()
    var showMenu by remember { mutableStateOf(false) }

    if (!state.signedIn) return

    MenuButton(badge = AppShell.badgeText(state.badgeTotal)) { showMenu = true }

    if (showMenu) {
        MenuSheet(
            state = state,
            onDismiss = { showMenu = false },
            onOpen = { item ->
                showMenu = false
                AppShell.replaceScreen(item.path)
            },
            onSignOut = {
                showMenu = false
                AppShell.signOut()
            }
        )
    }
}

/**
 * Coco's face in a white circle with a pink ring, at the bottom right, with
 * the total of every badge. Like MenuButton.swift.
 */
@Composable
fun MenuButton(badge: String?, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .navigationBarsPadding()
            .padding(end = 20.dp, bottom = 16.dp, top = 8.dp, start = 8.dp)
            .semantics { contentDescription = "Menu" }
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .shadow(8.dp, CircleShape)
                .clip(CircleShape)
                .background(Color.White)
                .border(3.dp, Pink, CircleShape)
                .clickable(onClick = onClick),
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
                    .background(Color(0xFFE7000B))
                    .padding(horizontal = 6.dp, vertical = 1.dp)
            )
        }
    }
}
