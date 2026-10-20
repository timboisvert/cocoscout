package com.cocoscout.app.bridge

import kotlinx.serialization.Serializable

/**
 * The V1.1 menu the server sends generation-2 builds
 * (NativeAppHelper#native_nav). V1 builds never get it and keep drawing the
 * plain menu. Like ios/CocoScout/Menu/NavData.swift.
 */
@Serializable
data class NavData(
    val mode: String,
    val sections: List<NavSection> = emptyList(),
    val icons: NavIcons,
    val organization: NavOrganization? = null,
    val door: NavItem? = null,
    val modeSwitch: NavModeSwitch? = null,
    val profilePath: String,
    val settingsPath: String,
    val signOutPath: String
) {
    val isProduction: Boolean get() = mode == "production"
}

@Serializable
data class NavSection(val label: String? = null, val items: List<NavItem> = emptyList())

@Serializable
data class NavItem(
    val id: String,
    val title: String,
    val path: String,
    val icon: String,
    val badge: Int? = null,
    val subtitle: String? = null,
    val locked: Boolean? = null
)

@Serializable
data class NavIcon(val path: String, val count: Int = 0)

@Serializable
data class NavIcons(val messages: NavIcon, val notifications: NavIcon)

@Serializable
data class NavOrganization(val name: String, val initials: String, val sheetPath: String)

@Serializable
data class NavModeSwitch(val label: String, val subtitle: String = "", val path: String, val enter: Boolean)
