package com.cocoscout.app.menu

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Apartment
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Contactless
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Draw
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Payments
import androidx.compose.material.icons.outlined.QrCodeScanner
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.TheaterComedy
import androidx.compose.ui.graphics.vector.ImageVector

/**
 * The server names each menu item's icon by its SF Symbol (for the iOS app);
 * these are the Material icons that say the same thing.
 */
object MenuIcons {
    private val icons: Map<String, ImageVector> = mapOf(
        "house" to Icons.Outlined.Home,
        "envelope" to Icons.Outlined.Email,
        "checklist" to Icons.Outlined.Checklist,
        "calendar" to Icons.Outlined.CalendarMonth,
        "clock" to Icons.Outlined.Schedule,
        "book" to Icons.AutoMirrored.Outlined.MenuBook,
        "theatermasks" to Icons.Outlined.TheaterComedy,
        "doc.text" to Icons.Outlined.Description,
        "signature" to Icons.Outlined.Draw,
        "dollarsign.circle" to Icons.Outlined.Payments,
        "building.2" to Icons.Outlined.Apartment,
        "chart.bar" to Icons.Outlined.BarChart,
        "person.crop.circle" to Icons.Outlined.AccountCircle,
        "person.3" to Icons.Outlined.Groups,
        "gearshape" to Icons.Outlined.Settings,
        "qrcode.viewfinder" to Icons.Outlined.QrCodeScanner,
        "wave.3.right.circle" to Icons.Outlined.Contactless
    )

    fun forName(name: String): ImageVector = icons[name] ?: Icons.Outlined.Circle
}
