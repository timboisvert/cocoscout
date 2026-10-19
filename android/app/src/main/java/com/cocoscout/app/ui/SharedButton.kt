package com.cocoscout.app.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * The app's own buttons, drawn exactly like the website's shared/button
 * partial (app/views/shared/_button.html.erb), which can't render in a native
 * screen. Like SharedButtonStyle.swift in the iOS app. Every labeled button
 * the app draws itself uses this; add a variant here rather than styling one
 * inline.
 */
@Composable
fun SharedButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: ButtonVariant = ButtonVariant.Primary,
    size: ButtonSize = ButtonSize.Medium,
    fullWidth: Boolean = false
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val primary = variant == ButtonVariant.Primary
    Button(
        onClick = onClick,
        modifier = if (fullWidth) modifier.fillMaxWidth() else modifier,
        shape = RoundedCornerShape(4.dp),
        border = if (primary) null else BorderStroke(1.dp, Tailwind.Gray300),
        contentPadding = PaddingValues(horizontal = size.horizontal, vertical = size.vertical),
        interactionSource = interaction,
        colors = ButtonDefaults.buttonColors(
            containerColor = when {
                primary -> if (pressed) Tailwind.Pink600 else Tailwind.Pink500
                else -> if (pressed) Tailwind.Gray50 else Color.White
            },
            contentColor = if (primary) Color.White else Tailwind.Gray700
        )
    ) {
        Text(text, fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, maxLines = 1)
    }
}

/** shared/button's variants the app uses so far: "primary" (pink) and "secondary" (white, gray border). */
enum class ButtonVariant { Primary, Secondary }

/** shared/button's sizes: small is px-3 py-1.5; medium px-5 py-2.5; large px-8 py-3. */
enum class ButtonSize(val horizontal: androidx.compose.ui.unit.Dp, val vertical: androidx.compose.ui.unit.Dp) {
    Small(12.dp, 6.dp),
    Medium(20.dp, 10.dp),
    Large(32.dp, 12.dp)
}

/** The Tailwind v4 colors the website compiles to, so native pieces match the pages around them. */
object Tailwind {
    val Pink500 = Color(0xFFF6339A)
    val Pink600 = Color(0xFFE60076)
    val Gray50 = Color(0xFFF9FAFB)
    val Gray300 = Color(0xFFD1D5DC)
    val Gray700 = Color(0xFF364153)
    val Gray900 = Color(0xFF101828)
}
