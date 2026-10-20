package com.cocoscout.app.menu

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.cocoscout.app.AppConfig
import com.cocoscout.app.AppShell
import com.cocoscout.app.bridge.MenuPerson
import com.cocoscout.app.bridge.NavData
import com.cocoscout.app.bridge.NavItem
import com.cocoscout.app.bridge.NavModeSwitch
import com.cocoscout.app.bridge.NavOrganization

private val Pink50 = Color(0xFFFDF2F8)
private val Pink200 = Color(0xFFFCCEE8)
private val Pink600 = Color(0xFFE60076)
private val Pink700 = Color(0xFFC4005F)
private val Gray200 = Color(0xFFE5E7EB)
private val Gray500 = Color(0xFF6A7282)
private val Gray700 = Color(0xFF364153)
private val Gray900 = Color(0xFF101828)
private val SheetBackground = Color(0xFFF2F2F7)

/**
 * The V1.1 menu (navigation canvas, app row), for generation-2 builds: a
 * plain outlined card for you on top (close in its corner; Profile,
 * Settings, Sign out under it), the organization on soft pink in production
 * mode, the tiles, then Work the door (black) and the mode switch
 * (CocoScout pink) pinned to the bottom (Tim, 2026-10-20). Messages and
 * Notifications are toolbar icons, not tiles. Like NavMenuViewController.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NavMenuSheet(
    nav: NavData,
    person: MenuPerson?,
    onDismiss: () -> Unit,
    onOpen: (String) -> Unit,
    onSignOut: () -> Unit
) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = SheetBackground,
        dragHandle = null,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxHeight().padding(start = 16.dp, end = 16.dp, top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            PersonCard(person, nav, onDismiss, onOpen, onSignOut)
            nav.organization?.let { OrganizationRow(it) { onOpen(it.sheetPath) } }
            Column(
                modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                val perRow = if (nav.isProduction) 4 else 3
                nav.sections.forEach { section ->
                    section.label?.let {
                        Text(it.uppercase(), color = Gray500, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp,
                             modifier = Modifier.padding(top = 4.dp))
                    }
                    section.items.chunked(perRow).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { item -> Box(Modifier.weight(1f)) { Tile(item, nav.isProduction) { onOpen(item.path) } } }
                            repeat(perRow - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
            nav.door?.let { door ->
                Bar(MenuIcons.forName("qrcode.viewfinder"), door.title, door.subtitle, Gray900) { onOpen(door.path) }
            }
            nav.modeSwitch?.let { switch -> ModeSwitchBar(switch) { onOpen(switch.path) } }
            Spacer(Modifier.navigationBarsPadding().height(12.dp))
        }
    }
}

@Composable
private fun PersonCard(person: MenuPerson?, nav: NavData, onDismiss: () -> Unit, onOpen: (String) -> Unit, onSignOut: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Column(Modifier.fillMaxWidth().clip(shape).background(Color.White).border(1.dp, Gray200, shape)) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(14.dp)) {
            if (person != null) Avatar(person)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(person?.name ?: "CocoScout", color = Gray900, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                person?.email?.let { Text(it, color = Gray500, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
            Box(
                modifier = Modifier.size(40.dp).clip(CircleShape).background(Color(0xFFF2F2F7)).clickable(onClick = onDismiss),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.Close, contentDescription = "Close", tint = Gray700, modifier = Modifier.size(18.dp))
            }
        }
        HorizontalDivider(color = Color(0xFFF3F4F6))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.heightIn(min = 46.dp)) {
            CardLink("Profile", "person.crop.circle", Modifier.weight(1f)) { onOpen(nav.profilePath) }
            VerticalDivider(Modifier.height(28.dp), color = Color(0xFFF3F4F6))
            CardLink("Settings", "gearshape", Modifier.weight(1f)) { onOpen(nav.settingsPath) }
            VerticalDivider(Modifier.height(28.dp), color = Color(0xFFF3F4F6))
            CardLink("Sign out", "rectangle.portrait.and.arrow.right", Modifier.weight(1f), onSignOut)
        }
    }
}

@Composable
private fun CardLink(text: String, icon: String, modifier: Modifier, onClick: () -> Unit) {
    Row(
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.heightIn(min = 46.dp).clickable(onClick = onClick)
    ) {
        Icon(MenuIcons.forName(icon), contentDescription = null, tint = Gray700, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(text, color = Gray900, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

@Composable
private fun Avatar(person: MenuPerson) {
    val shape = RoundedCornerShape(10.dp)
    Box(Modifier.size(48.dp).clip(shape).background(Pink50), contentAlignment = Alignment.Center) {
        Text(person.initials, color = Pink700, fontSize = 17.sp, fontWeight = FontWeight.Bold)
        person.headshotPath?.let { path ->
            AsyncImage(model = AppConfig.url(path), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(48.dp).clip(shape))
        }
    }
}

@Composable
private fun OrganizationRow(organization: NavOrganization, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(shape).background(Pink50).border(1.dp, Pink200, shape)
            .clickable(onClick = onClick).padding(horizontal = 14.dp)
    ) {
        Box(Modifier.size(28.dp).clip(RoundedCornerShape(7.dp)).background(Pink600), contentAlignment = Alignment.Center) {
            Text(organization.initials, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.width(10.dp))
        Text(organization.name, color = Gray900, fontSize = 15.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
             modifier = Modifier.weight(1f, fill = false))
        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = Pink700, modifier = Modifier.size(18.dp))
        Spacer(Modifier.weight(1f))
        Text("PRODUCTION MODE", color = Pink700, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.8.sp)
    }
}

@Composable
private fun Tile(item: NavItem, compact: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    val locked = item.locked == true
    Box {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
            modifier = Modifier.fillMaxWidth().heightIn(min = if (compact) 66.dp else 80.dp).clip(shape).background(Color.White)
                .border(1.dp, Gray200, shape).clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 3.dp)
        ) {
            Icon(MenuIcons.forName(item.icon), contentDescription = null, tint = if (locked) Gray500 else Pink, modifier = Modifier.size(if (compact) 22.dp else 26.dp))
            Spacer(Modifier.height(6.dp))
            Text(item.title, color = Gray900, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 2, lineHeight = 15.sp)
        }
        if (locked) {
            Icon(Icons.Filled.Lock, contentDescription = "Pro", tint = Gray500, modifier = Modifier.align(Alignment.TopEnd).padding(7.dp).size(11.dp))
        } else {
            AppShell.badgeText(item.badge ?: 0)?.let { badge ->
                Text(badge, color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                     modifier = Modifier.align(Alignment.TopEnd).padding(5.dp).clip(RoundedCornerShape(9.dp)).background(Pink600)
                         .padding(horizontal = 6.dp, vertical = 1.dp))
            }
        }
    }
}

/** Enter or Exit production mode: CocoScout pink with white words, never dark pink (Tim, 2026-10-20). */
@Composable
private fun ModeSwitchBar(switch: NavModeSwitch, onClick: () -> Unit) {
    val icon = if (switch.enter) MenuIcons.forName("building.2") else MenuIcons.forName("rectangle.portrait.and.arrow.right")
    Bar(icon, switch.label, switch.subtitle, Pink, onClick)
}

@Composable
private fun Bar(icon: ImageVector, title: String, subtitle: String?, fill: Color, onClick: () -> Unit) {
    val shape = RoundedCornerShape(14.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().heightIn(min = 58.dp).clip(shape).background(fill).clickable(onClick = onClick).padding(horizontal = 14.dp)
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = Color.White, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            if (!subtitle.isNullOrEmpty()) Text(subtitle, color = Color.White.copy(alpha = 0.85f), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = Color.White.copy(alpha = 0.85f))
    }
}
