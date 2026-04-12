package com.polri.bodyworn.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF0A2740),
    onPrimary = Color.White,
    secondary = Color(0xFFC1121F),
    onSecondary = Color.White,
    tertiary = Color(0xFF2E6F95),
    background = Color(0xFFF3F6F8),
    surface = Color.White
)

@Composable
fun BodyWornTheme(
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = LightColors,
        typography = Typography,
        content = content
    )
}
