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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import coil.request.ImageRequest
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.ui.components.ChannelLogoBadge
import com.example.ui.components.DayOffsetStrip
import com.example.ui.components.LivePulseBadge
import com.example.ui.theme.CatchupGold
import com.example.ui.theme.CatchupGoldContainer
import com.example.ui.theme.HdEmerald
import com.example.ui.theme.HdEmeraldContainer
import com.example.ui.theme.JioCrimson
import com.example.ui.theme.LiveCyan

@Composable
fun ChannelDetailScreen(
    channel: TvChannel,
    epgByChannelAndDay: Map<Pair<Int, Int>, List<TvProgram>>,
    loadingEpgKeys: Set<Pair<Int, Int>>,
    epgErrors: Map<Pair<Int, Int>, String>,
    selectedDayOffset: Int,
    isFavorite: Boolean,
    currentTimeMs: Long,
    showBackButton: Boolean = true,
    onBack: () -> Unit,
    onDayOffsetSelected: (Int) -> Unit,
    onEnsureEpgLoaded: (Int, Int, Boolean) -> Unit,
    onToggleFavorite: () -> Unit,
    onProgramClick: (TvProgram) -> Unit,
    onPlayChannel: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val key = channel.id to selectedDayOffset
    val programs = epgByChannelAndDay[key]
    val isLoading = key in loadingEpgKeys
    val errorMsg = epgErrors[key]

    LaunchedEffect(channel.id, selectedDayOffset) {
        onEnsureEpgLoaded(channel.id, selectedDayOffset, false)
    }

    LaunchedEffect(channel.id) {
        (-7..7)
            .sortedBy { kotlin.math.abs(it - selectedDayOffset) }
            .forEach { dayOffset ->
                onEnsureEpgLoaded(channel.id, dayOffset, false)
            }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (showBackButton) {
                IconButton(
                    onClick = onBack,
                    modifier = Modifier
                        .minimumInteractiveComponentSize()
                        .testTag("detail_back_button")
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "Back to guide"
                    )
                }
            }
            ChannelLogoBadge(channel = channel, size = 46.dp)
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    Text(
                        text = channel.name,
                        style = MaterialTheme.typography.titleLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
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
                }
                Text(
                    text = "#${channel.id} • ${channel.categoryName} • ${channel.languageName}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            IconButton(
                onClick = onToggleFavorite,
                modifier = Modifier
                    .minimumInteractiveComponentSize()
                    .testTag("detail_favorite_button")
            ) {
                Icon(
                    imageVector = if (isFavorite) Icons.Rounded.Favorite else Icons.Outlined.FavoriteBorder,
                    contentDescription = if (isFavorite) "Remove favorite" else "Add favorite",
                    tint = if (isFavorite) JioCrimson else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        if (channel.hasPlayback && onPlayChannel != null) {
            Button(
                onClick = onPlayChannel,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 10.dp)
                    .height(48.dp)
                    .testTag("detail_watch_live_button")
            ) {
                Icon(
                    imageVector = Icons.Rounded.PlayArrow,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(Modifier.size(8.dp))
                Text("Watch Live in ExoPlayer")
            }
        }

        DayOffsetStrip(
            selectedOffset = selectedDayOffset,
            onOffsetSelected = onDayOffsetSelected
        )

        Spacer(Modifier.height(10.dp))

        when {
            isLoading -> {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        CircularProgressIndicator(color = JioCrimson)
                        Text(
                            text = "Loading getepg schedule…",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            errorMsg != null -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            text = errorMsg,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.error
                        )
                        Button(onClick = { onEnsureEpgLoaded(channel.id, selectedDayOffset, true) }) {
                            Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            Text("Retry Schedule")
                        }
                    }
                }
            }

            programs.isNullOrEmpty() -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(32.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Schedule,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(40.dp)
                        )
                        Text(
                            text = "No programs listed for this day",
                            style = MaterialTheme.typography.titleMedium
                        )
                    }
                }
            }

            else -> {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("channel_schedule_list"),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    items(programs, key = { it.id }) { program ->
                        val isLive = selectedDayOffset == 0 && program.isLiveAt(currentTimeMs)
                        val isPast = program.isPastAt(currentTimeMs)
                        ProgramTimelineCard(
                            program = program,
                            isLive = isLive,
                            isPast = isPast,
                            currentTimeMs = currentTimeMs,
                            onClick = { onProgramClick(program) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun ProgramTimelineCard(
    program: TvProgram,
    isLive: Boolean,
    isPast: Boolean,
    currentTimeMs: Long,
    onClick: () -> Unit
) {
    val context = LocalContext.current
    val thumb = program.thumbnailUrl.ifBlank { program.posterUrl }

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .testTag("program_card_${program.id}"),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (isLive) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
            } else {
                MaterialTheme.colorScheme.surfaceContainer
            }
        ),
        border = BorderStroke(
            width = if (isLive) 1.5.dp else 1.dp,
            color = if (isLive) JioCrimson else MaterialTheme.colorScheme.outlineVariant
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (thumb.isNotBlank()) {
                SubcomposeAsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(thumb)
                        .crossfade(true)
                        .build(),
                    contentDescription = program.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(width = 96.dp, height = 64.dp)
                        .clip(RoundedCornerShape(10.dp))
                )
            }

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (isLive) {
                        LivePulseBadge()
                    } else if (isPast) {
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = CatchupGoldContainer
                        ) {
                            Text(
                                text = "CATCH-UP",
                                style = MaterialTheme.typography.labelSmall,
                                color = CatchupGold,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 2.dp)
                            )
                        }
                    }
                    Text(
                        text = "${program.startTimeFormatted} – ${program.endTimeFormatted}",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (isLive) LiveCyan else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Text(
                    text = program.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )

                Text(
                    text = program.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis
                )

                if (isLive) {
                    LinearProgressIndicator(
                        progress = { program.progressAt(currentTimeMs) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 4.dp)
                            .height(4.dp)
                            .clip(CircleShape),
                        color = LiveCyan
                    )
                }
            }
        }
    }
}
