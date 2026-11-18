package com.example.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.NotificationsActive
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.data.local.UserPreferences
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.ui.components.ChannelGuideRowCard
import com.example.ui.theme.LiveCyan
import com.example.ui.viewmodel.ChannelsUiState

@Composable
fun FavoritesScreen(
    channelsState: ChannelsUiState,
    epgByChannelAndDay: Map<Pair<Int, Int>, List<TvProgram>>,
    loadingEpgKeys: Set<Pair<Int, Int>>,
    epgErrors: Map<Pair<Int, Int>, String>,
    preferences: UserPreferences,
    currentTimeMs: Long,
    onToggleFavorite: (Int) -> Unit,
    onEnsureEpgLoaded: (Int, Int, Boolean) -> Unit,
    onOpenChannelDetail: (Int) -> Unit,
    onPlayChannel: (Int) -> Unit,
    onOpenProgramSheet: (TvProgram) -> Unit,
    onRemoveReminder: (TvProgram) -> Unit,
    modifier: Modifier = Modifier
) {
    val allChannels = (channelsState as? ChannelsUiState.Success)?.channels.orEmpty()
    val favoriteChannels = remember(allChannels, preferences.favoriteChannelIds) {
        allChannels.filter { it.id in preferences.favoriteChannelIds }
    }

    val savedPrograms = remember(epgByChannelAndDay, preferences.reminderKeys) {
        epgByChannelAndDay.values
            .flatten()
            .filter { it.reminderKey() in preferences.reminderKeys }
            .distinctBy { it.reminderKey() }
            .sortedBy { it.startEpochMs }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp)
        ) {
            Text(
                text = "Favorites & Reminders",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "${favoriteChannels.size} pinned channels • ${preferences.reminderKeys.size} saved reminders",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        if (favoriteChannels.isEmpty() && savedPrograms.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                contentAlignment = Alignment.Center
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Outlined.FavoriteBorder,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(48.dp)
                    )
                    Text(
                        text = "No favorites pinned yet",
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "Tap the heart icon on any TV channel or save a show reminder from its EPG details.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("favorites_list"),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                if (savedPrograms.isNotEmpty()) {
                    item(key = "reminders_header") {
                        Text(
                            text = "Saved Show Reminders",
                            style = MaterialTheme.typography.titleMedium,
                            color = LiveCyan
                        )
                    }
                    items(savedPrograms, key = { "rem_${it.reminderKey()}" }) { program ->
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainer
                            ),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.NotificationsActive,
                                    contentDescription = null,
                                    tint = LiveCyan
                                )
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(
                                        text = program.title,
                                        style = MaterialTheme.typography.titleSmall
                                    )
                                    Text(
                                        text = "${program.startTimeFormatted} – ${program.endTimeFormatted} • ${program.channelName.ifBlank { "Channel #${program.channelId}" }}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                IconButton(
                                    onClick = { onRemoveReminder(program) },
                                    modifier = Modifier.minimumInteractiveComponentSize()
                                ) {
                                    Icon(
                                        imageVector = Icons.Rounded.DeleteOutline,
                                        contentDescription = "Remove reminder"
                                    )
                                }
                            }
                        }
                    }
                    item(key = "reminders_spacer") {
                        Spacer(Modifier.height(6.dp))
                    }
                }

                if (favoriteChannels.isNotEmpty()) {
                    item(key = "fav_channels_header") {
                        Text(
                            text = "Pinned Channels",
                            style = MaterialTheme.typography.titleMedium
                        )
                    }
                    items(favoriteChannels, key = { "fav_${it.id}" }) { channel ->
                        val key = channel.id to 0
                        LaunchedEffect(channel.id) {
                            onEnsureEpgLoaded(channel.id, 0, false)
                        }
                        ChannelGuideRowCard(
                            channel = channel,
                            programs = epgByChannelAndDay[key],
                            isLoadingEpg = key in loadingEpgKeys,
                            epgError = epgErrors[key],
                            isFavorite = true,
                            currentTimeMs = currentTimeMs,
                            selectedDayOffset = 0,
                            onChannelClick = { onOpenChannelDetail(channel.id) },
                            onProgramClick = onOpenProgramSheet,
                            onToggleFavorite = { onToggleFavorite(channel.id) },
                            onRequestEpg = { onEnsureEpgLoaded(channel.id, 0, true) },
                            onPlayChannel = if (channel.hasPlayback) {
                                { onPlayChannel(channel.id) }
                            } else {
                                null
                            }
                        )
                    }
                }
            }
        }
    }
}
