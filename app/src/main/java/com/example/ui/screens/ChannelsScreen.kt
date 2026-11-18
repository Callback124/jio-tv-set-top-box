package com.example.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.example.data.local.UserPreferences
import com.example.data.model.TvChannel
import com.example.ui.components.ApiErrorCard
import com.example.ui.components.ChannelLogoBadge
import com.example.ui.components.FilterBarSection
import com.example.ui.components.GuideSearchField
import com.example.ui.theme.CatchupGold
import com.example.ui.theme.HdEmerald
import com.example.ui.theme.HdEmeraldContainer
import com.example.ui.theme.JioCrimson
import com.example.ui.viewmodel.ChannelsUiState

@Composable
fun ChannelsScreen(
    channelsState: ChannelsUiState,
    filteredChannels: List<TvChannel>,
    preferences: UserPreferences,
    searchQuery: String,
    onSearchQueryChange: (String) -> Unit,
    onCategorySelected: (Int) -> Unit,
    onLanguageSelected: (Int) -> Unit,
    onToggleHd: () -> Unit,
    onTogglePlayable: () -> Unit,
    onToggleFavorite: (Int) -> Unit,
    onOpenChannelDetail: (Int) -> Unit,
    onPlayChannel: (Int) -> Unit,
    onRefresh: () -> Unit,
    onOpenApiChain: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp)
        ) {
            Text(
                text = "Channel Directory",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "${filteredChannels.size} channels available across categories & languages",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        GuideSearchField(
            query = searchQuery,
            onQueryChange = onSearchQueryChange,
            modifier = Modifier.padding(horizontal = 16.dp)
        )

        Spacer(Modifier.height(10.dp))

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

        Spacer(Modifier.height(8.dp))

        when (channelsState) {
            is ChannelsUiState.Loading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator(color = JioCrimson)
                }
            }

            is ChannelsUiState.Error -> {
                ApiErrorCard(
                    message = channelsState.message,
                    httpCode = channelsState.httpCode,
                    isGeoBlocked = channelsState.isGeoBlocked,
                    onRetry = onRefresh,
                    onOpenApiChain = onOpenApiChain
                )
            }

            is ChannelsUiState.Success -> {
                LazyVerticalGrid(
                    columns = GridCells.Adaptive(minSize = 165.dp),
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("channels_grid"),
                    contentPadding = PaddingValues(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    items(filteredChannels, key = { it.id }) { channel ->
                        val isFav = channel.id in preferences.favoriteChannelIds
                        Card(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { onOpenChannelDetail(channel.id) }
                                .testTag("channel_grid_card_${channel.id}"),
                            shape = RoundedCornerShape(18.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainer
                            ),
                            border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                        ) {
                            Column(
                                modifier = Modifier.padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(10.dp)
                            ) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.Top
                                ) {
                                    ChannelLogoBadge(channel = channel, size = 52.dp)
                                    IconButton(
                                        onClick = { onToggleFavorite(channel.id) },
                                        modifier = Modifier.minimumInteractiveComponentSize()
                                    ) {
                                        Icon(
                                            imageVector = if (isFav) Icons.Rounded.Favorite else Icons.Outlined.FavoriteBorder,
                                            contentDescription = if (isFav) "Remove favorite" else "Favorite",
                                            tint = if (isFav) JioCrimson else MaterialTheme.colorScheme.onSurfaceVariant
                                        )
                                    }
                                }

                                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                    Text(
                                        text = channel.name,
                                        style = MaterialTheme.typography.titleSmall,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                    Text(
                                        text = "${channel.categoryName} • ${channel.languageName}",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }

                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                                ) {
                                    Surface(
                                        shape = RoundedCornerShape(4.dp),
                                        color = MaterialTheme.colorScheme.surfaceContainerHigh
                                    ) {
                                        Text(
                                            text = "#${channel.id}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp)
                                        )
                                    }
                                    if (channel.isHd) {
                                        Surface(
                                            shape = RoundedCornerShape(4.dp),
                                            color = HdEmeraldContainer
                                        ) {
                                            Text(
                                                text = "HD",
                                                style = MaterialTheme.typography.labelSmall,
                                                color = HdEmerald,
                                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp)
                                            )
                                        }
                                    }
                                    if (channel.isCatchupAvailable) {
                                        Icon(
                                            imageVector = Icons.Rounded.History,
                                            contentDescription = "Catch-up available",
                                            tint = CatchupGold,
                                            modifier = Modifier.size(14.dp)
                                        )
                                    }
                                    if (channel.hasPlayback) {
                                        Surface(
                                            modifier = Modifier
                                                .clickable { onPlayChannel(channel.id) }
                                                .testTag("grid_play_channel_${channel.id}"),
                                            shape = RoundedCornerShape(6.dp),
                                            color = JioCrimson
                                        ) {
                                            Row(
                                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                                verticalAlignment = Alignment.CenterVertically,
                                                horizontalArrangement = Arrangement.spacedBy(2.dp)
                                            ) {
                                                Icon(
                                                    imageVector = Icons.Rounded.PlayArrow,
                                                    contentDescription = "Watch live",
                                                    tint = androidx.compose.ui.graphics.Color.White,
                                                    modifier = Modifier.size(12.dp)
                                                )
                                                Text(
                                                    text = "PLAY",
                                                    style = MaterialTheme.typography.labelSmall,
                                                    color = androidx.compose.ui.graphics.Color.White
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
        }
    }
}
