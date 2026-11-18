package com.example.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.DarkMode
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material.icons.rounded.LiveTv
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.TvOff
import androidx.compose.material.icons.rounded.ViewAgenda
import androidx.compose.material.icons.rounded.ViewTimeline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.data.local.UserPreferences
import com.example.data.model.JioTvDictionaries
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.ui.components.ApiErrorCard
import com.example.ui.components.ChannelGuideRowCard
import com.example.ui.components.DayOffsetStrip
import com.example.ui.components.FilterBarSection
import com.example.ui.components.GuideSearchField
import com.example.ui.components.StbBottomLegendBar
import com.example.ui.components.StbLegendAction
import com.example.ui.theme.HdEmerald
import com.example.ui.theme.JioCrimson
import com.example.ui.theme.LiveCyan
import com.example.ui.viewmodel.ChannelsUiState
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private val StbGuideHeaderBrush = Brush.verticalGradient(
    colors = listOf(Color(0xFF1A202D), Color(0xFF0C1018))
)
private val StbLiveSlotBrush = Brush.horizontalGradient(
    colors = listOf(Color(0xFF0099FF), Color(0xFF31C6FF), Color(0xFF0080DC))
)

@Composable
fun GuideScreen(
    channelsState: ChannelsUiState,
    filteredChannels: List<TvChannel>,
    epgByChannelAndDay: Map<Pair<Int, Int>, List<TvProgram>>,
    loadingEpgKeys: Set<Pair<Int, Int>>,
    epgErrors: Map<Pair<Int, Int>, String>,
    preferences: UserPreferences,
    searchQuery: String,
    selectedDayOffset: Int,
    currentTimeMs: Long,
    isExpandedWidth: Boolean,
    onSearchQueryChange: (String) -> Unit,
    onDayOffsetSelected: (Int) -> Unit,
    onCategorySelected: (Int) -> Unit,
    onLanguageSelected: (Int) -> Unit,
    onToggleHd: () -> Unit,
    onTogglePlayable: () -> Unit,
    onToggleFavorite: (Int) -> Unit,
    onToggleTheme: () -> Unit,
    onRefresh: () -> Unit,
    onEnsureEpgLoaded: (Int, Int, Boolean) -> Unit,
    onOpenChannelDetail: (Int) -> Unit,
    onPlayChannel: (Int) -> Unit,
    onOpenProgramSheet: (TvProgram) -> Unit,
    onOpenApiChain: () -> Unit,
    onOpenStbSearch: () -> Unit,
    modifier: Modifier = Modifier
) {
    var detailChannelId by remember { mutableStateOf<Int?>(null) }
    var useStbGridMode by remember { mutableStateOf(true) }
    var genresMenuExpanded by remember { mutableStateOf(false) }

    val activeCategoryName = remember(preferences.selectedCategoryId) {
        JioTvDictionaries.categories.firstOrNull { it.id == preferences.selectedCategoryId }?.name
            ?.let { if (it == "All") "All Channels" else it }
            ?: "All Channels"
    }

    val content: @Composable (Modifier) -> Unit = { listModifier ->
        Column(modifier = listModifier.fillMaxSize()) {
            GuideTopHeader(
                channelCount = (channelsState as? ChannelsUiState.Success)?.channels?.size ?: 0,
                activeCategoryName = activeCategoryName,
                currentTimeMs = currentTimeMs,
                useStbGridMode = useStbGridMode,
                darkTheme = preferences.darkTheme,
                onToggleGridMode = { useStbGridMode = !useStbGridMode },
                onToggleTheme = onToggleTheme,
                onRefresh = onRefresh
            )

            Spacer(Modifier.height(6.dp))

            if (!useStbGridMode) {
                GuideSearchField(
                    query = searchQuery,
                    onQueryChange = onSearchQueryChange,
                    modifier = Modifier.padding(horizontal = 16.dp)
                )
                Spacer(Modifier.height(8.dp))
            }

            DayOffsetStrip(
                selectedOffset = selectedDayOffset,
                onOffsetSelected = onDayOffsetSelected
            )

            Spacer(Modifier.height(8.dp))

            FilterBarSection(
                selectedCategoryId = preferences.selectedCategoryId,
                selectedLanguageId = preferences.selectedLanguageId,
                hdOnly = preferences.hdOnly,
                playableOnly = preferences.playableOnly,
                onCategorySelected = onCategorySelected,
                onLanguageSelected = onLanguageSelected,
                onToggleHd = onToggleHd,
                onTogglePlayable = onTogglePlayable
            )

            Spacer(Modifier.height(6.dp))

            when (channelsState) {
                is ChannelsUiState.Loading -> {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth()
                            .padding(32.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(14.dp)
                        ) {
                            CircularProgressIndicator(color = JioCrimson)
                            Text(
                                text = "Fetching JioTV Guide & Initiator Chain…",
                                style = MaterialTheme.typography.titleSmall
                            )
                        }
                    }
                }

                is ChannelsUiState.Error -> {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxWidth(),
                        contentAlignment = Alignment.TopCenter
                    ) {
                        ApiErrorCard(
                            message = channelsState.message,
                            httpCode = channelsState.httpCode,
                            isGeoBlocked = channelsState.isGeoBlocked,
                            onRetry = onRefresh,
                            onOpenApiChain = onOpenApiChain
                        )
                    }
                }

                is ChannelsUiState.Success -> {
                    if (filteredChannels.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.TvOff,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.size(44.dp)
                                )
                                Text(
                                    text = "No channels match your filters",
                                    style = MaterialTheme.typography.titleMedium
                                )
                            }
                        }
                    } else if (useStbGridMode) {
                        StbHorizontalEpgGrid(
                            channels = filteredChannels,
                            activeCategoryName = activeCategoryName,
                            epgByChannelAndDay = epgByChannelAndDay,
                            loadingEpgKeys = loadingEpgKeys,
                            selectedDayOffset = selectedDayOffset,
                            currentTimeMs = currentTimeMs,
                            onEnsureEpgLoaded = onEnsureEpgLoaded,
                            onPlayChannel = onPlayChannel,
                            onOpenChannelDetail = { chId ->
                                if (isExpandedWidth) detailChannelId = chId else onOpenChannelDetail(chId)
                            },
                            onProgramClick = onOpenProgramSheet,
                            modifier = Modifier.weight(1f)
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .testTag("guide_channel_list"),
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            items(filteredChannels, key = { it.id }) { channel ->
                                val key = channel.id to selectedDayOffset
                                LaunchedEffect(channel.id, selectedDayOffset) {
                                    onEnsureEpgLoaded(channel.id, selectedDayOffset, false)
                                }
                                ChannelGuideRowCard(
                                    channel = channel,
                                    programs = epgByChannelAndDay[key],
                                    isLoadingEpg = key in loadingEpgKeys,
                                    epgError = epgErrors[key],
                                    isFavorite = channel.id in preferences.favoriteChannelIds,
                                    currentTimeMs = currentTimeMs,
                                    selectedDayOffset = selectedDayOffset,
                                    onChannelClick = {
                                        if (isExpandedWidth) {
                                            detailChannelId = channel.id
                                        } else {
                                            onOpenChannelDetail(channel.id)
                                        }
                                    },
                                    onProgramClick = onOpenProgramSheet,
                                    onToggleFavorite = { onToggleFavorite(channel.id) },
                                    onRequestEpg = { onEnsureEpgLoaded(channel.id, selectedDayOffset, true) },
                                    onPlayChannel = { onPlayChannel(channel.id) }
                                )
                            }
                        }
                    }
                }
            }

            // Bottom STB Guide Legend Bar matching Screenshot 7: Genres • +24h • Press '0' to Search
            Box {
                StbBottomLegendBar(
                    items = listOf(
                        StbLegendAction(
                            dotColor = HdEmerald,
                            label = "Genres",
                            onClick = { genresMenuExpanded = true }
                        ),
                        StbLegendAction(
                            dotColor = Color(0xFF0099FF),
                            label = "+24h",
                            onClick = {
                                val next = if (selectedDayOffset >= 7) -7 else selectedDayOffset + 1
                                onDayOffsetSelected(next)
                            }
                        ),
                        StbLegendAction(
                            badgeText = "0",
                            label = "Press '0' to Search",
                            onClick = onOpenStbSearch
                        )
                    )
                )
                DropdownMenu(
                    expanded = genresMenuExpanded,
                    onDismissRequest = { genresMenuExpanded = false }
                ) {
                    JioTvDictionaries.categories.forEach { cat ->
                        DropdownMenuItem(
                            text = {
                                Text(
                                    text = cat.name,
                                    fontWeight = if (cat.id == preferences.selectedCategoryId) FontWeight.Bold else FontWeight.Normal
                                )
                            },
                            onClick = {
                                onCategorySelected(cat.id)
                                genresMenuExpanded = false
                            }
                        )
                    }
                }
            }
        }
    }

    if (isExpandedWidth && !useStbGridMode) {
        Row(modifier = modifier.fillMaxSize()) {
            content(Modifier.weight(1.1f))
            val selectedId = detailChannelId ?: filteredChannels.firstOrNull()?.id
            val selectedChannel = filteredChannels.firstOrNull { it.id == selectedId }
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(MaterialTheme.colorScheme.surface)
            ) {
                if (selectedChannel != null) {
                    ChannelDetailScreen(
                        channel = selectedChannel,
                        epgByChannelAndDay = epgByChannelAndDay,
                        loadingEpgKeys = loadingEpgKeys,
                        epgErrors = epgErrors,
                        selectedDayOffset = selectedDayOffset,
                        isFavorite = selectedChannel.id in preferences.favoriteChannelIds,
                        currentTimeMs = currentTimeMs,
                        showBackButton = false,
                        onBack = {},
                        onDayOffsetSelected = onDayOffsetSelected,
                        onEnsureEpgLoaded = onEnsureEpgLoaded,
                        onToggleFavorite = { onToggleFavorite(selectedChannel.id) },
                        onProgramClick = onOpenProgramSheet,
                        onPlayChannel = { onPlayChannel(selectedChannel.id) }
                    )
                }
            }
        }
    } else {
        content(modifier)
    }
}

/**
 * Classic Set-Top Box Horizontal Time-Slot EPG Matrix (Screenshot 7)
 */
@Composable
private fun StbHorizontalEpgGrid(
    channels: List<TvChannel>,
    activeCategoryName: String,
    epgByChannelAndDay: Map<Pair<Int, Int>, List<TvProgram>>,
    loadingEpgKeys: Set<Pair<Int, Int>>,
    selectedDayOffset: Int,
    currentTimeMs: Long,
    onEnsureEpgLoaded: (Int, Int, Boolean) -> Unit,
    onPlayChannel: (Int) -> Unit,
    onOpenChannelDetail: (Int) -> Unit,
    onProgramClick: (TvProgram) -> Unit,
    modifier: Modifier = Modifier
) {
    val slotMinutes = 30
    val totalSlots = 48 // 24 hours in 30-min intervals
    val slotWidthDp = 136.dp
    val channelColWidthDp = 152.dp
    val density = LocalDensity.current

    val dayStartCal = remember(selectedDayOffset) {
        Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, selectedDayOffset)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
    }
    val dayStartMs = dayStartCal.timeInMillis
    val dayEndMs = dayStartMs + 24L * 3_600_000L

    val nowMinutesIntoDay = remember(currentTimeMs, selectedDayOffset) {
        if (selectedDayOffset == 0) {
            ((currentTimeMs - dayStartMs) / 60_000L).toInt().coerceIn(0, 1410)
        } else {
            9 * 60 // default 9:00 AM on non-today view
        }
    }
    val initialScrollPx = remember(selectedDayOffset, density) {
        val slotsOffset = (nowMinutesIntoDay / slotMinutes - 1).coerceAtLeast(0)
        with(density) { (slotsOffset * slotWidthDp.toPx()).toInt() }
    }
    val horizontalScrollState = rememberScrollState(initial = initialScrollPx)

    LaunchedEffect(selectedDayOffset) {
        horizontalScrollState.animateScrollTo(initialScrollPx)
    }

    val dayHeaderText = remember(selectedDayOffset, dayStartMs) {
        val fmt = SimpleDateFormat("dd MMM", Locale.getDefault())
        val prefix = when (selectedDayOffset) {
            0 -> "Today"
            1 -> "Tom"
            -1 -> "Yest"
            else -> SimpleDateFormat("EEE", Locale.getDefault()).format(Date(dayStartMs))
        }
        "$prefix ${fmt.format(Date(dayStartMs))}"
    }
    val slotTimeFormatter = remember { SimpleDateFormat("hh:mm a", Locale.getDefault()) }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(Color(0xFF0E121B))
            .border(1.dp, Color(0xFF3E4A61), RoundedCornerShape(10.dp))
    ) {
        // EPG Matrix Top Title + Synchronized Time Slot Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(StbGuideHeaderBrush)
                .border(0.5.dp, Color(0xFF2D374B))
        ) {
            Column(
                modifier = Modifier
                    .width(channelColWidthDp)
                    .padding(horizontal = 10.dp, vertical = 7.dp)
            ) {
                Text(
                    text = activeCategoryName,
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = dayHeaderText,
                    color = Color(0xFF4CC3FF),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            Row(
                modifier = Modifier
                    .weight(1f)
                    .horizontalScroll(horizontalScrollState)
            ) {
                for (slot in 0 until totalSlots) {
                    val slotTimeMs = dayStartMs + slot * slotMinutes * 60_000L
                    val isCurrentSlot = selectedDayOffset == 0 &&
                        currentTimeMs in slotTimeMs until (slotTimeMs + slotMinutes * 60_000L)
                    Box(
                        modifier = Modifier
                            .width(slotWidthDp)
                            .height(48.dp)
                            .border(0.5.dp, Color(0xFF2B3548))
                            .background(
                                if (isCurrentSlot) Color(0xFF005B99).copy(alpha = 0.55f)
                                else Color.Transparent
                            )
                            .padding(horizontal = 8.dp),
                        contentAlignment = Alignment.CenterStart
                    ) {
                        Text(
                            text = slotTimeFormatter.format(Date(slotTimeMs)).lowercase(),
                            color = if (isCurrentSlot) Color(0xFF7BE0FF) else Color.White,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }

        // Channel Rows
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .testTag("stb_epg_matrix")
        ) {
            items(channels, key = { "grid_${it.id}" }) { channel ->
                val key = channel.id to selectedDayOffset
                LaunchedEffect(channel.id, selectedDayOffset) {
                    onEnsureEpgLoaded(channel.id, selectedDayOffset, false)
                }
                val programs = epgByChannelAndDay[key].orEmpty()
                val isLoading = key in loadingEpgKeys

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(50.dp)
                        .border(0.5.dp, Color(0xFF283142)),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    // Left Channel Column (#id Name) - tap to Watch Live, or tap EPG tag for 15-day view
                    Row(
                        modifier = Modifier
                            .width(channelColWidthDp)
                            .fillMaxHeight()
                            .background(Color(0xFF131824))
                            .clickable { onPlayChannel(channel.id) }
                            .border(0.5.dp, Color(0xFF283142))
                            .padding(horizontal = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp)
                    ) {
                        Text(
                            text = "${channel.id}",
                            color = Color(0xFF4CC3FF),
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                        Text(
                            text = channel.name,
                            color = Color.White,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f)
                        )
                        Icon(
                            imageVector = Icons.Rounded.PlayArrow,
                            contentDescription = "Watch ${channel.name}",
                            tint = if (channel.hasPlayback) Color(0xFF4CC3FF) else Color.White.copy(alpha = 0.45f),
                            modifier = Modifier
                                .size(15.dp)
                                .clickable { onOpenChannelDetail(channel.id) }
                        )
                    }

                    // Horizontal EPG timeline blocks synchronized with header scroll
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .horizontalScroll(horizontalScrollState)
                    ) {
                        val totalTimelineWidth = slotWidthDp * totalSlots
                        Box(
                            modifier = Modifier
                                .width(totalTimelineWidth)
                                .fillMaxHeight()
                        ) {
                            if (programs.isNotEmpty()) {
                                val pxPerMinute = with(density) { (slotWidthDp / slotMinutes).toPx() }
                                programs.forEach { prog ->
                                    val clippedStart = prog.startEpochMs.coerceIn(dayStartMs, dayEndMs)
                                    val clippedEnd = prog.endEpochMs.coerceIn(dayStartMs, dayEndMs)
                                    val durationMin = ((clippedEnd - clippedStart) / 60_000L).toInt()
                                    if (durationMin > 0) {
                                        val startMin = ((clippedStart - dayStartMs) / 60_000L).toInt()
                                        val offsetDp = with(density) { (startMin * pxPerMinute).toDp() }
                                        val widthDp = with(density) { (durationMin * pxPerMinute).toDp() }
                                            .coerceAtLeast(48.dp)
                                        val isLive = selectedDayOffset == 0 && prog.isLiveAt(currentTimeMs)

                                        Box(
                                            modifier = Modifier
                                                .padding(start = offsetDp)
                                                .width(widthDp)
                                                .fillMaxHeight()
                                                .then(
                                                    if (isLive) Modifier.background(StbLiveSlotBrush)
                                                    else Modifier.background(Color(0xFF151C2B))
                                                )
                                                .border(0.5.dp, Color(0xFF39465E))
                                                .clickable { onProgramClick(prog) }
                                                .padding(horizontal = 8.dp),
                                            contentAlignment = Alignment.CenterStart
                                        ) {
                                            Text(
                                                text = prog.title,
                                                color = if (isLive) Color.Black else Color.White,
                                                fontSize = 13.sp,
                                                fontWeight = if (isLive) FontWeight.Bold else FontWeight.Medium,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis
                                            )
                                        }
                                    }
                                }
                            } else {
                                Box(
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .clickable { onOpenChannelDetail(channel.id) }
                                        .padding(start = with(density) { initialScrollPx.toDp() } + 12.dp),
                                    contentAlignment = Alignment.CenterStart
                                ) {
                                    Text(
                                        text = if (isLoading) "Loading EPG…" else "Tap channel to view 15-day EPG",
                                        color = Color.White.copy(alpha = 0.55f),
                                        fontSize = 12.sp
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun GuideTopHeader(
    channelCount: Int,
    activeCategoryName: String,
    currentTimeMs: Long,
    useStbGridMode: Boolean,
    darkTheme: Boolean,
    onToggleGridMode: () -> Unit,
    onToggleTheme: () -> Unit,
    onRefresh: () -> Unit
) {
    val headerDate = remember(currentTimeMs / 60_000L) {
        SimpleDateFormat("EEE dd MMM hh:mm a", Locale.getDefault()).format(Date(currentTimeMs))
    }

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                Brush.horizontalGradient(
                    colors = listOf(
                        MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.45f),
                        MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.30f),
                        MaterialTheme.colorScheme.background
                    )
                )
            )
            .padding(horizontal = 14.dp, vertical = 10.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.weight(1f)
            ) {
                Surface(
                    shape = RoundedCornerShape(10.dp),
                    color = JioCrimson
                ) {
                    Icon(
                        imageVector = Icons.Rounded.LiveTv,
                        contentDescription = "JioTV Guide",
                        tint = Color.White,
                        modifier = Modifier
                            .padding(7.dp)
                            .size(20.dp)
                    )
                }
                Column {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = "TV Guide • $activeCategoryName",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        if (channelCount > 0) {
                            Surface(
                                shape = RoundedCornerShape(6.dp),
                                color = MaterialTheme.colorScheme.secondaryContainer
                            ) {
                                Text(
                                    text = "$channelCount CH",
                                    style = MaterialTheme.typography.labelSmall,
                                    color = LiveCyan,
                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                )
                            }
                        }
                    }
                    Text(
                        text = "$headerDate • 15-Day Catch-Up",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(
                    onClick = onToggleGridMode,
                    modifier = Modifier
                        .minimumInteractiveComponentSize()
                        .testTag("toggle_guide_mode_button")
                ) {
                    Icon(
                        imageVector = if (useStbGridMode) Icons.Rounded.ViewAgenda else Icons.Rounded.ViewTimeline,
                        contentDescription = if (useStbGridMode) "Switch to list view" else "Switch to TV Guide Grid"
                    )
                }
                IconButton(
                    onClick = onToggleTheme,
                    modifier = Modifier
                        .minimumInteractiveComponentSize()
                        .testTag("theme_toggle_button")
                ) {
                    Icon(
                        imageVector = if (darkTheme) Icons.Rounded.LightMode else Icons.Rounded.DarkMode,
                        contentDescription = "Toggle theme"
                    )
                }
                IconButton(
                    onClick = onRefresh,
                    modifier = Modifier
                        .minimumInteractiveComponentSize()
                        .testTag("refresh_guide_button")
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Refresh,
                        contentDescription = "Refresh JioTV Guide"
                    )
                }
            }
        }
    }
}
