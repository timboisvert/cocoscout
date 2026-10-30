package com.cocoscout.app.menu

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cocoscout.app.AppShell
import com.cocoscout.app.bridge.NavIcon

/**
 * V1.1: Messages and Notifications on the right of every toolbar, with pink
 * counts, the same in both modes. Nothing until a V1.1 menu arrives. Like
 * WebViewController.swift's bar items.
 */
@Composable
fun ToolbarIcons() {
    val nav by AppShell.nav.collectAsState()
    val icons = nav?.icons ?: return
    // A gap between the two and off the edge, so neither is cramped.
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(end = 8.dp)
    ) {
        ToolbarIcon(Icons.Outlined.Email, "Messages", icons.messages)
        ToolbarIcon(Icons.Outlined.Notifications, "Notifications", icons.notifications)
    }
}

@Composable
private fun ToolbarIcon(image: ImageVector, label: String, icon: NavIcon) {
    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(44.dp)
            .clip(RoundedCornerShape(22.dp))
            .clickable { AppShell.open(icon.path) }
            .semantics { contentDescription = if (icon.count > 0) "$label, ${icon.count} unread" else label }
    ) {
        Icon(image, contentDescription = null, tint = Pink, modifier = Modifier.size(24.dp))
        AppShell.badgeText(icon.count)?.let { badge ->
            Text(
                badge, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 5.dp, end = 3.dp)
                    .clip(RoundedCornerShape(8.dp)).background(Color(0xFFE60076))
                    .border(1.5.dp, Color.White, RoundedCornerShape(8.dp))
                    .padding(horizontal = 5.dp)
            )
        }
    }
}
