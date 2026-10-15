package com.cocoscout.app.menu

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.cocoscout.app.AppConfig
import com.cocoscout.app.AppShell
import com.cocoscout.app.R
import com.cocoscout.app.bridge.MenuItem
import com.cocoscout.app.bridge.MenuPerson

val Pink = Color(0xFFF6339A)
private val Pink600 = Color(0xFFE60076)
private val Gray900 = Color(0xFF101828)
private val SheetBackground = Color(0xFFF2F2F7)
private val HeaderGradient = Brush.horizontalGradient(listOf(Pink, Pink600))
private val Coustard = FontFamily(Font(R.font.coustard_regular))

/** About you rather than everyday work: buttons in the pink card, not tiles. */
private val accountIds = setOf("profile", "groups", "settings")

/**
 * The menu the Coco button opens: a pink card on top (CocoScout, who's
 * signed in, Sign out, Profile and Settings), every My item as a tile with
 * its badge, and the Door bar at the bottom while a show is on. The items
 * come from the server, so who sees what matches the website. Like
 * MenuViewController.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MenuSheet(
    state: AppShell.State,
    onDismiss: () -> Unit,
    onOpen: (MenuItem) -> Unit,
    onSignOut: () -> Unit
) {
    val accountItems = state.menu.filter { it.id in accountIds }
    val everydayItems = state.menu.filter { it.id !in accountIds && it.id != "door" }
    val doorItem = state.menu.firstOrNull { it.id == "door" }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = SheetBackground,
        dragHandle = null,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(Modifier.fillMaxHeight()) {
            Header(state.person, accountItems, onDismiss, onOpen, onSignOut)
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f)
            ) {
                items(everydayItems, key = { it.id }) { item -> Tile(item) { onOpen(item) } }
            }
            if (doorItem != null) {
                DoorBar(doorItem) { onOpen(doorItem) }
            }
            Spacer(Modifier.navigationBarsPadding())
        }
    }
}

@Composable
private fun Header(
    person: MenuPerson?,
    accountItems: List<MenuItem>,
    onDismiss: () -> Unit,
    onOpen: (MenuItem) -> Unit,
    onSignOut: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(HeaderGradient)
            .padding(start = 16.dp, end = 16.dp, top = 20.dp, bottom = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(
                painter = painterResource(R.drawable.coco),
                contentDescription = null,
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.White)
                    .padding(3.dp)
            )
            Spacer(Modifier.width(10.dp))
            Text("CocoScout", color = Color.White, fontFamily = Coustard, fontSize = 26.sp)
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.2f))
                    .clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = Color.White, modifier = Modifier.size(18.dp))
            }
        }

        if (person != null) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(Color.White.copy(alpha = 0.15f))
                    .padding(12.dp)
            ) {
                Avatar(person)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text("Signed in as", color = Color.White.copy(alpha = 0.8f), fontSize = 12.sp)
                    Text(person.name, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(person.email, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Spacer(Modifier.width(8.dp))
                SecondaryButton("Sign out", onClick = onSignOut)
            }
        }

        if (accountItems.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                accountItems.forEach { item ->
                    SecondaryButton(item.title, icon = item.icon, modifier = Modifier.weight(1f)) { onOpen(item) }
                }
            }
        }
    }
}

/** shared/button's secondary look: white, gray border, dark text. */
@Composable
private fun SecondaryButton(text: String, modifier: Modifier = Modifier, icon: String? = null, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        modifier = modifier.heightIn(min = 36.dp),
        shape = RoundedCornerShape(6.dp),
        border = BorderStroke(1.dp, Color(0xFFD1D5DC)),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        colors = androidx.compose.material3.ButtonDefaults.outlinedButtonColors(containerColor = Color.White, contentColor = Gray900)
    ) {
        if (icon != null) {
            Icon(MenuIcons.forName(icon), contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

@Composable
private fun Avatar(person: MenuPerson) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier = Modifier
            .size(48.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.25f)),
        contentAlignment = Alignment.Center
    ) {
        Text(person.initials, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        person.headshotPath?.let { path ->
            AsyncImage(
                model = AppConfig.url(path),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(48.dp).clip(shape)
            )
        }
    }
}

@Composable
private fun Tile(item: MenuItem, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Box {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 92.dp)
                .clip(shape)
                .background(Color.White)
                .border(1.dp, Color(0x99C6C6C8), shape)
                .clickable(onClick = onClick)
                .padding(vertical = 12.dp, horizontal = 4.dp)
        ) {
            Icon(MenuIcons.forName(item.icon), contentDescription = null, tint = Pink, modifier = Modifier.size(30.dp))
            Spacer(Modifier.height(8.dp))
            Text(
                item.title,
                color = Gray900,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 2,
                lineHeight = 16.sp
            )
        }
        AppShell.badgeText(item.badge ?: 0)?.let { badge ->
            Text(
                badge,
                color = Color.White,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color(0xFFE7000B))
                    .padding(horizontal = 6.dp, vertical = 2.dp)
            )
        }
    }
}

/** Full width along the bottom, pink: tonight's show and when, a tap from the door. */
@Composable
private fun DoorBar(item: MenuItem, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp)
            .fillMaxWidth()
            .clip(shape)
            .background(HeaderGradient)
            .clickable(onClick = onClick)
            .padding(14.dp)
    ) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(Color.White.copy(alpha = 0.2f)),
            contentAlignment = Alignment.Center
        ) {
            Icon(MenuIcons.forName(item.icon), contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text(item.title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            item.subtitle?.let {
                Text(it, color = Color.White.copy(alpha = 0.9f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color.White.copy(alpha = 0.9f))
    }
}
