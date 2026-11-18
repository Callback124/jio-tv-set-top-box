package com.example.ui.theme

import android.app.Activity
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat

private val BroadcastDarkColorScheme = darkColorScheme(
    primary = JioCrimson,
    onPrimary = Color.White,
    primaryContainer = JioCrimsonContainer,
    onPrimaryContainer = JioCrimsonLight,
    secondary = LiveCyan,
    onSecondary = Color(0xFF001F29),
    secondaryContainer = LiveCyanContainer,
    onSecondaryContainer = LiveCyan,
    tertiary = CatchupGold,
    onTertiary = Color(0xFF261A00),
    tertiaryContainer = CatchupGoldContainer,
    onTertiaryContainer = CatchupGold,
    background = ObsidianBg,
    onBackground = TextPrimaryDark,
    surface = ObsidianSurface,
    onSurface = TextPrimaryDark,
    surfaceVariant = ObsidianSurfaceVariant,
    onSurfaceVariant = TextSecondaryDark,
    surfaceContainerLow = ObsidianSurface,
    surfaceContainer = ObsidianSurfaceVariant,
    surfaceContainerHigh = ObsidianCardElevated,
    outline = ObsidianOutline,
    outlineVariant = Color(0xFF23293E),
    error = Color(0xFFFF5C77),
    onError = Color(0xFF3E0010)
)

private val BroadcastLightColorScheme = lightColorScheme(
    primary = JioCrimson,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFD9DF),
    onPrimaryContainer = Color(0xFF400010),
    secondary = Color(0xFF006B82),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFC4F0FF),
    onSecondaryContainer = Color(0xFF002029),
    tertiary = Color(0xFF8C6200),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFFFE19E),
    onTertiaryContainer = Color(0xFF2B1C00),
    background = LightBg,
    onBackground = TextPrimaryLight,
    surface = LightSurface,
    onSurface = TextPrimaryLight,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = TextSecondaryLight,
    surfaceContainerLow = Color(0xFFFDFDFF),
    surfaceContainer = LightSurfaceVariant,
    surfaceContainerHigh = Color(0xFFE1E6F0),
    outline = LightOutline,
    outlineVariant = Color(0xFFE2E7F2)
)

val AppShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp)
)

@Composable
fun JioTvGuideTheme(
    darkTheme: Boolean = true,
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) BroadcastDarkColorScheme else BroadcastLightColorScheme
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window
            if (window != null) {
                WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = !darkTheme
                WindowCompat.getInsetsController(window, view).isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        shapes = AppShapes,
        content = content
    )
}
