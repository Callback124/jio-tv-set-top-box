package com.example

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.ViewTimeline
import androidx.compose.material.icons.rounded.AccountTree
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.GridView
import androidx.compose.material.icons.rounded.ViewTimeline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.example.ui.components.ProgramDetailBottomSheet
import com.example.ui.components.StbSearchOverlay
import com.example.ui.screens.ApiChainScreen
import com.example.ui.screens.ChannelDetailScreen
import com.example.ui.screens.ChannelsScreen
import com.example.ui.screens.FavoritesScreen
import com.example.ui.screens.GuideScreen
import com.example.ui.screens.PlayerScreen
import com.example.ui.theme.JioTvGuideTheme
import com.example.ui.viewmodel.JioTvViewModel
import com.example.ui.viewmodel.PlaybackResolveState

object NavRoutes {
    const val ROUTE_GUIDE = "guide"
    const val ROUTE_CHANNELS = "channels"
    const val ROUTE_FAVORITES = "favorites"
    const val ROUTE_API_CHAIN = "api_chain"
    const val ROUTE_CHANNEL_DETAIL = "channel_detail/{channelId}"
    const val ROUTE_PLAYER = "player/{channelId}"

    fun channelDetail(channelId: Int): String = "channel_detail/$channelId"
    fun player(channelId: Int): String = "player/$channelId"
}

private data class TopLevelDestination(
    val route: String,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val testTag: String
)

private val TopDestinations = listOf(
    TopLevelDestination(
        route = NavRoutes.ROUTE_GUIDE,
        label = "TV Guide",
        selectedIcon = Icons.Rounded.ViewTimeline,
        unselectedIcon = Icons.Outlined.ViewTimeline,
        testTag = "nav_tab_guide"
    ),
    TopLevelDestination(
        route = NavRoutes.ROUTE_CHANNELS,
        label = "Channels",
        selectedIcon = Icons.Rounded.GridView,
        unselectedIcon = Icons.Outlined.GridView,
        testTag = "nav_tab_channels"
    ),
    TopLevelDestination(
        route = NavRoutes.ROUTE_FAVORITES,
        label = "Favorites",
        selectedIcon = Icons.Rounded.Favorite,
        unselectedIcon = Icons.Outlined.FavoriteBorder,
        testTag = "nav_tab_favorites"
    ),
    TopLevelDestination(
        route = NavRoutes.ROUTE_API_CHAIN,
        label = "API Chain",
        selectedIcon = Icons.Rounded.AccountTree,
        unselectedIcon = Icons.Outlined.AccountTree,
        testTag = "nav_tab_api_chain"
    )
)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        setContent {
            val viewModel: JioTvViewModel = viewModel()
            val preferences by viewModel.preferences.collectAsStateWithLifecycle()

            JioTvGuideTheme(darkTheme = preferences.darkTheme) {
                JioTvGuideApp(viewModel = viewModel)
            }
        }
    }
}

@Composable
fun JioTvGuideApp(viewModel: JioTvViewModel) {
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route

    val channelsState by viewModel.channelsState.collectAsStateWithLifecycle()
    val filteredChannels by viewModel.filteredChannels.collectAsStateWithLifecycle()
    val epgByChannelAndDay by viewModel.epgByChannelAndDay.collectAsStateWithLifecycle()
    val loadingEpgKeys by viewModel.loadingEpgKeys.collectAsStateWithLifecycle()
    val epgErrors by viewModel.epgErrors.collectAsStateWithLifecycle()
    val preferences by viewModel.preferences.collectAsStateWithLifecycle()
    val searchQuery by viewModel.searchQuery.collectAsStateWithLifecycle()
    val selectedDayOffset by viewModel.selectedDayOffset.collectAsStateWithLifecycle()
    val selectedProgram by viewModel.selectedProgram.collectAsStateWithLifecycle()
    val currentTimeMs by viewModel.currentTimeMs.collectAsStateWithLifecycle()
    val traceEntries by viewModel.traceEntries.collectAsStateWithLifecycle()
    val lastDiscovery by viewModel.lastDiscovery.collectAsStateWithLifecycle()
    val playbackStates by viewModel.playbackStates.collectAsStateWithLifecycle()
    val isSearchPanelOpen by viewModel.isSearchPanelOpen.collectAsStateWithLifecycle()
    val stbSearchState by viewModel.stbSearchState.collectAsStateWithLifecycle()
    val recentSearches by viewModel.recentSearches.collectAsStateWithLifecycle()

    val isPlayerRoute = currentRoute == NavRoutes.ROUTE_PLAYER
    val isTopLevelRoute = TopDestinations.any { it.route == currentRoute }

    var globalZeroStreak by remember { mutableIntStateOf(0) }

    val navigateToTopLevel: (String) -> Unit = { route ->
        navController.navigate(route) {
            popUpTo(navController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
            restoreState = true
        }
    }

    val tuneToPlayer: (Int) -> Unit = { targetId ->
        if (currentRoute == NavRoutes.ROUTE_PLAYER) {
            navController.navigate(NavRoutes.player(targetId)) {
                popUpTo(NavRoutes.ROUTE_PLAYER) { inclusive = true }
            }
        } else {
            navController.navigate(NavRoutes.player(targetId))
        }
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .onPreviewKeyEvent { keyEvent ->
                if (!isPlayerRoute && !isSearchPanelOpen && keyEvent.type == KeyEventType.KeyDown) {
                    if (keyEvent.key == Key.Zero || keyEvent.key == Key.NumPad0) {
                        globalZeroStreak++
                        if (globalZeroStreak >= 4) {
                            globalZeroStreak = 0
                            viewModel.openSearchPanel()
                            return@onPreviewKeyEvent true
                        }
                    } else {
                        globalZeroStreak = 0
                    }
                }
                false
            }
    ) {
        val useNavigationRail = maxWidth >= 600.dp
        val isExpandedWidth = maxWidth >= 840.dp

        Scaffold(
            modifier = Modifier.fillMaxSize(),
            containerColor = if (isPlayerRoute) Color.Black else MaterialTheme.colorScheme.background,
            contentWindowInsets = if (isPlayerRoute) WindowInsets(0, 0, 0, 0) else WindowInsets.safeDrawing,
            bottomBar = {
                if (!useNavigationRail && isTopLevelRoute) {
                    NavigationBar(
                        windowInsets = WindowInsets.navigationBars,
                        containerColor = MaterialTheme.colorScheme.surface
                    ) {
                        TopDestinations.forEach { dest ->
                            val selected = currentRoute == dest.route
                            NavigationBarItem(
                                selected = selected,
                                onClick = { navigateToTopLevel(dest.route) },
                                icon = {
                                    Icon(
                                        imageVector = if (selected) dest.selectedIcon else dest.unselectedIcon,
                                        contentDescription = dest.label
                                    )
                                },
                                label = { Text(dest.label) },
                                modifier = Modifier.testTag(dest.testTag)
                            )
                        }
                    }
                }
            }
        ) { innerPadding ->
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .then(
                        if (isPlayerRoute) Modifier else Modifier.padding(innerPadding)
                    )
            ) {
                if (useNavigationRail && isTopLevelRoute) {
                    NavigationRail(
                        modifier = Modifier
                            .fillMaxHeight()
                            .windowInsetsPadding(WindowInsets.navigationBars),
                        containerColor = MaterialTheme.colorScheme.surface
                    ) {
                        TopDestinations.forEach { dest ->
                            val selected = currentRoute == dest.route
                            NavigationRailItem(
                                selected = selected,
                                onClick = { navigateToTopLevel(dest.route) },
                                icon = {
                                    Icon(
                                        imageVector = if (selected) dest.selectedIcon else dest.unselectedIcon,
                                        contentDescription = dest.label
                                    )
                                },
                                label = { Text(dest.label) },
                                modifier = Modifier.testTag(dest.testTag)
                            )
                        }
                    }
                }

                Box(modifier = Modifier.weight(1f)) {
                    NavHost(
                        navController = navController,
                        startDestination = NavRoutes.ROUTE_GUIDE
                    ) {

                        composable(NavRoutes.ROUTE_GUIDE) {
                            GuideScreen(
                                channelsState = channelsState,
                                filteredChannels = filteredChannels,
                                epgByChannelAndDay = epgByChannelAndDay,
                                loadingEpgKeys = loadingEpgKeys,
                                epgErrors = epgErrors,
                                preferences = preferences,
                                searchQuery = searchQuery,
                                selectedDayOffset = selectedDayOffset,
                                currentTimeMs = currentTimeMs,
                                isExpandedWidth = isExpandedWidth,
                                onSearchQueryChange = viewModel::onSearchQueryChanged,
                                onDayOffsetSelected = viewModel::onDayOffsetSelected,
                                onCategorySelected = viewModel::selectCategory,
                                onLanguageSelected = viewModel::selectLanguage,
                                onToggleHd = viewModel::toggleHdOnly,
                                onTogglePlayable = viewModel::togglePlayableOnly,
                                onToggleFavorite = viewModel::toggleFavorite,
                                onToggleTheme = viewModel::toggleDarkTheme,
                                onRefresh = { viewModel.loadChannelDirectory(forceRefresh = true) },
                                onEnsureEpgLoaded = viewModel::ensureEpgLoaded,
                                onOpenChannelDetail = { channelId ->
                                    navController.navigate(NavRoutes.channelDetail(channelId))
                                },
                                onPlayChannel = { channelId ->
                                    navController.navigate(NavRoutes.player(channelId))
                                },
                                onOpenProgramSheet = viewModel::openProgramSheet,
                                onOpenApiChain = { navigateToTopLevel(NavRoutes.ROUTE_API_CHAIN) },
                                onOpenStbSearch = viewModel::openSearchPanel
                            )
                        }

                        composable(NavRoutes.ROUTE_CHANNELS) {
                            ChannelsScreen(
                                channelsState = channelsState,
                                filteredChannels = filteredChannels,
                                preferences = preferences,
                                searchQuery = searchQuery,
                                onSearchQueryChange = viewModel::onSearchQueryChanged,
                                onCategorySelected = viewModel::selectCategory,
                                onLanguageSelected = viewModel::selectLanguage,
                                onToggleHd = viewModel::toggleHdOnly,
                                onTogglePlayable = viewModel::togglePlayableOnly,
                                onToggleFavorite = viewModel::toggleFavorite,
                                onOpenChannelDetail = { channelId ->
                                    navController.navigate(NavRoutes.channelDetail(channelId))
                                },
                                onPlayChannel = { channelId ->
                                    navController.navigate(NavRoutes.player(channelId))
                                },
                                onRefresh = { viewModel.loadChannelDirectory(forceRefresh = true) },
                                onOpenApiChain = { navigateToTopLevel(NavRoutes.ROUTE_API_CHAIN) }
                            )
                        }

                        composable(NavRoutes.ROUTE_FAVORITES) {
                            FavoritesScreen(
                                channelsState = channelsState,
                                epgByChannelAndDay = epgByChannelAndDay,
                                loadingEpgKeys = loadingEpgKeys,
                                epgErrors = epgErrors,
                                preferences = preferences,
                                currentTimeMs = currentTimeMs,
                                onToggleFavorite = viewModel::toggleFavorite,
                                onEnsureEpgLoaded = viewModel::ensureEpgLoaded,
                                onOpenChannelDetail = { channelId ->
                                    navController.navigate(NavRoutes.channelDetail(channelId))
                                },
                                onPlayChannel = { channelId ->
                                    navController.navigate(NavRoutes.player(channelId))
                                },
                                onOpenProgramSheet = viewModel::openProgramSheet,
                                onRemoveReminder = viewModel::toggleReminder
                            )
                        }

                        composable(NavRoutes.ROUTE_API_CHAIN) {
                            ApiChainScreen(
                                traceEntries = traceEntries,
                                lastDiscovery = lastDiscovery,
                                preferences = preferences,
                                onRerunDiscoveryChain = { viewModel.loadChannelDirectory(forceRefresh = true) },
                                onSaveCustomBaseUrl = viewModel::saveCustomBaseUrlAndReload
                            )
                        }

                        composable(
                            route = NavRoutes.ROUTE_CHANNEL_DETAIL,
                            arguments = listOf(navArgument("channelId") { type = NavType.IntType })
                        ) { entry ->
                            val channelId = entry.arguments?.getInt("channelId") ?: 0
                            val channel = viewModel.findChannelById(channelId)
                            if (channel != null) {
                                ChannelDetailScreen(
                                    channel = channel,
                                    epgByChannelAndDay = epgByChannelAndDay,
                                    loadingEpgKeys = loadingEpgKeys,
                                    epgErrors = epgErrors,
                                    selectedDayOffset = selectedDayOffset,
                                    isFavorite = channel.id in preferences.favoriteChannelIds,
                                    currentTimeMs = currentTimeMs,
                                    showBackButton = true,
                                    onBack = { navController.popBackStack() },
                                    onDayOffsetSelected = viewModel::onDayOffsetSelected,
                                    onEnsureEpgLoaded = viewModel::ensureEpgLoaded,
                                    onToggleFavorite = { viewModel.toggleFavorite(channel.id) },
                                    onProgramClick = viewModel::openProgramSheet,
                                    onPlayChannel = { navController.navigate(NavRoutes.player(channel.id)) }
                                )
                            } else {
                                LaunchedEffect(channelId) {
                                    navController.popBackStack()
                                }
                            }
                        }

                        composable(
                            route = NavRoutes.ROUTE_PLAYER,
                            arguments = listOf(navArgument("channelId") { type = NavType.IntType })
                        ) { entry ->
                            val channelId = entry.arguments?.getInt("channelId") ?: 0
                            val channel = viewModel.findChannelById(channelId)
                            if (channel != null) {
                                PlayerScreen(
                                    channel = channel,
                                    playbackState = playbackStates[channel.id] ?: PlaybackResolveState.Idle,
                                    todayPrograms = epgByChannelAndDay[channel.id to 0].orEmpty(),
                                    currentTimeMs = currentTimeMs,
                                    isSearchOverlayOpen = isSearchPanelOpen,
                                    onBack = { navController.popBackStack() },
                                    onResolvePlayback = { force ->
                                        viewModel.resolvePlayback(channel, forceRefresh = force)
                                    },
                                    onZapChannel = { delta ->
                                        viewModel.adjacentChannel(channel.id, delta)?.let { target ->
                                            tuneToPlayer(target.id)
                                        }
                                    },
                                    onDialChannelNumber = { number ->
                                        val match = viewModel.findChannelByDialNumber(number)
                                        if (match != null) {
                                            tuneToPlayer(match.id)
                                            true
                                        } else {
                                            false
                                        }
                                    },
                                    onOpenSearch = viewModel::openSearchPanel,
                                    onOpenGuide = {
                                        navController.popBackStack()
                                        navigateToTopLevel(NavRoutes.ROUTE_GUIDE)
                                    },
                                    onOpenChannelDetail = { targetId ->
                                        navController.navigate(NavRoutes.channelDetail(targetId))
                                    },
                                    onEnsureTodayEpg = { targetId ->
                                        viewModel.ensureEpgLoaded(targetId, 0, false)
                                    }
                                )
                            } else {
                                LaunchedEffect(channelId) {
                                    navController.popBackStack()
                                }
                            }
                        }
                    }
                }
            }
        }

        if (isSearchPanelOpen) {
            val liveProgramTitles = remember(epgByChannelAndDay, currentTimeMs) {
                epgByChannelAndDay.entries
                    .asSequence()
                    .filter { (key, _) -> key.second == 0 }
                    .flatMap { (_, list) -> list.asSequence() }
                    .filter { it.isLiveAt(currentTimeMs) }
                    .map { it.title }
                    .filter { it.isNotBlank() }
                    .distinct()
                    .toList()
            }
            StbSearchOverlay(
                searchState = stbSearchState,
                liveProgramTitles = liveProgramTitles,
                recentSearches = recentSearches,
                onSearch = viewModel::executeStbSearch,
                onReturnToInput = viewModel::returnToSearchInput,
                onClearHistory = viewModel::clearSearchHistory,
                onClose = viewModel::closeSearchPanel,
                onTuneChannel = { targetId ->
                    viewModel.closeSearchPanel()
                    tuneToPlayer(targetId)
                }
            )
        }
    }

    selectedProgram?.let { program ->
        ProgramDetailBottomSheet(
            program = program,
            channel = viewModel.findChannelById(program.channelId),
            isReminderSet = program.reminderKey() in preferences.reminderKeys,
            currentTimeMs = currentTimeMs,
            onDismiss = viewModel::closeProgramSheet,
            onToggleReminder = { viewModel.toggleReminder(program) },
            onOpenChannelSchedule = { channelId ->
                navController.navigate(NavRoutes.channelDetail(channelId))
            }
        )
    }
}
