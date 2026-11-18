package com.example.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
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
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.Backspace
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ui.theme.JioCrimson
import com.example.ui.viewmodel.StbSearchUiState

private val StbBlueHighlight = Brush.horizontalGradient(
    colors = listOf(Color(0xFF0099FF), Color(0xFF28C2FF), Color(0xFF0082E6))
)
private val StbPanelBg = Brush.verticalGradient(
    colors = listOf(
        Color(0xEB222733),
        Color(0xF0151923),
        Color(0xF20D1017)
    )
)
private val StbKeyBg = Color(0xFF232834)
private val StbKeyBorder = Color(0xFF59637A)

private val KeyboardRows = listOf(
    listOf("A", "B", "C", "D", "E", "F", "1", "2"),
    listOf("G", "H", "I", "J", "K", "L", "3", "4"),
    listOf("M", "N", "O", "P", "Q", "R", "5", "6"),
    listOf("S", "T", "U", "V", "W", "X", "7", "8"),
    listOf("Y", "Z", "SPACE", "DEL", "-", "&", "9", "0")
)

@Composable
fun StbSearchOverlay(
    searchState: StbSearchUiState,
    liveProgramTitles: List<String>,
    recentSearches: List<String>,
    onSearch: (String) -> Unit,
    onReturnToInput: () -> Unit,
    onClearHistory: () -> Unit,
    onClose: () -> Unit,
    onTuneChannel: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    var queryText by remember { mutableStateOf("") }

    BackHandler {
        if (searchState is StbSearchUiState.Results) {
            onReturnToInput()
        } else {
            onClose()
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .safeDrawingPadding()
            .onPreviewKeyEvent { keyEvent ->
                if (keyEvent.type == KeyEventType.KeyDown) {
                    when (keyEvent.key) {
                        Key.Zero, Key.NumPad0 -> {
                            if (searchState is StbSearchUiState.Results) {
                                onReturnToInput()
                                return@onPreviewKeyEvent true
                            }
                        }
                        Key.Back, Key.Escape -> {
                            if (searchState is StbSearchUiState.Results) {
                                onReturnToInput()
                            } else {
                                onClose()
                            }
                            return@onPreviewKeyEvent true
                        }
                        Key.Enter, Key.NumPadEnter, Key.DirectionCenter -> {
                            if (searchState is StbSearchUiState.Input && queryText.isNotBlank()) {
                                onSearch(queryText)
                                return@onPreviewKeyEvent true
                            }
                        }
                    }
                }
                false
            }
            .padding(horizontal = 12.dp, vertical = 10.dp)
    ) {
        when (searchState) {
            is StbSearchUiState.Input -> {
                StbSearchInputPanel(
                    query = queryText,
                    liveProgramTitles = liveProgramTitles,
                    recentSearches = recentSearches,
                    onQueryChange = { queryText = it },
                    onSubmitSearch = { target ->
                        val finalQuery = target.ifBlank { queryText }
                        if (finalQuery.isNotBlank()) {
                            queryText = finalQuery
                            onSearch(finalQuery)
                        }
                    },
                    onClearHistory = {
                        queryText = ""
                        onClearHistory()
                    },
                    onClose = onClose
                )
            }

            is StbSearchUiState.Searching -> {
                StbSearchInputPanel(
                    query = searchState.query,
                    liveProgramTitles = liveProgramTitles,
                    recentSearches = recentSearches,
                    onQueryChange = {},
                    onSubmitSearch = {},
                    onClearHistory = {},
                    onClose = onClose
                )
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black.copy(alpha = 0.45f)),
                    contentAlignment = Alignment.Center
                ) {
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = Color(0xFF0A0D12),
                        border = BorderStroke(1.5.dp, Color.White.copy(alpha = 0.8f)),
                        shadowElevation = 16.dp
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 36.dp, vertical = 28.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(16.dp)
                        ) {
                            CircularProgressIndicator(
                                color = Color(0xFF00B4FF),
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.5.dp
                            )
                            Text(
                                text = "Searching live shows…",
                                color = Color.White,
                                fontSize = 18.sp,
                                fontWeight = FontWeight.SemiBold
                            )
                        }
                    }
                }
            }

            is StbSearchUiState.Results -> {
                StbSearchResultsPanel(
                    results = searchState,
                    onPressZeroToSearch = onReturnToInput,
                    onBack = onReturnToInput,
                    onClose = onClose,
                    onTuneChannel = onTuneChannel
                )
            }
        }
    }
}

@Composable
private fun StbSearchInputPanel(
    query: String,
    liveProgramTitles: List<String>,
    recentSearches: List<String>,
    onQueryChange: (String) -> Unit,
    onSubmitSearch: (String) -> Unit,
    onClearHistory: () -> Unit,
    onClose: () -> Unit
) {
    val suggestions = remember(query, liveProgramTitles, recentSearches) {
        if (query.isBlank()) {
            (liveProgramTitles.take(5) + recentSearches).distinct().take(8)
        } else {
            val liveMatches = liveProgramTitles
                .filter { it.contains(query, ignoreCase = true) }
                .take(8)
                .map { it.uppercase() }
            (liveMatches + recentSearches.filter { it.contains(query, ignoreCase = true) })
                .distinct()
                .take(8)
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Folder tab header matching Screenshot 3
        Surface(
            shape = RoundedCornerShape(topStart = 12.dp, topEnd = 16.dp),
            color = Color(0xFF6B707B).copy(alpha = 0.85f),
            border = BorderStroke(1.dp, Color.White.copy(alpha = 0.35f))
        ) {
            Text(
                text = "Search",
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 7.dp)
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topEnd = 10.dp, bottomStart = 10.dp, bottomEnd = 10.dp))
                .background(StbPanelBg)
                .border(
                    width = 1.dp,
                    color = Color.White.copy(alpha = 0.35f),
                    shape = RoundedCornerShape(topEnd = 10.dp, bottomStart = 10.dp, bottomEnd = 10.dp)
                )
                .padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = "Search LIVE Programs • Tap keys or press 0-9 / A-Z to type.",
                color = Color.White.copy(alpha = 0.92f),
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium
            )

            BoxWithConstraints(modifier = Modifier.weight(1f)) {
                val isWide = maxWidth >= 600.dp
                if (isWide) {
                    Row(
                        modifier = Modifier.fillMaxSize(),
                        horizontalArrangement = Arrangement.spacedBy(18.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        StbSearchSuggestionColumn(
                            query = query,
                            suggestions = suggestions,
                            onQueryChange = onQueryChange,
                            onSubmitSearch = onSubmitSearch,
                            modifier = Modifier
                                .weight(0.9f)
                                .fillMaxHeight()
                        )
                        StbOnScreenKeyboard(
                            onKeyTap = { key ->
                                when (key) {
                                    "SPACE" -> onQueryChange("$query ")
                                    "DEL" -> if (query.isNotEmpty()) onQueryChange(query.dropLast(1))
                                    else -> onQueryChange(query + key)
                                }
                            },
                            onSearchClick = { onSubmitSearch(query) },
                            modifier = Modifier.weight(1.25f)
                        )
                    }
                } else {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        StbSearchSuggestionColumn(
                            query = query,
                            suggestions = suggestions,
                            onQueryChange = onQueryChange,
                            onSubmitSearch = onSubmitSearch,
                            modifier = Modifier
                                .weight(0.75f)
                                .fillMaxWidth()
                        )
                        StbOnScreenKeyboard(
                            onKeyTap = { key ->
                                when (key) {
                                    "SPACE" -> onQueryChange("$query ")
                                    "DEL" -> if (query.isNotEmpty()) onQueryChange(query.dropLast(1))
                                    else -> onQueryChange(query + key)
                                }
                            },
                            onSearchClick = { onSubmitSearch(query) },
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }
        }

        // Bottom legend bar matching Screenshot 3
        StbBottomLegendBar(
            items = listOf(
                StbLegendAction(badgeText = "SELECT", label = "Search", onClick = { onSubmitSearch(query) }),
                StbLegendAction(dotColor = JioCrimson, label = "Clear History", onClick = onClearHistory),
                StbLegendAction(badgeText = "BACK", label = "Previous Screen", onClick = onClose)
            )
        )
    }
}

@Composable
private fun StbSearchSuggestionColumn(
    query: String,
    suggestions: List<String>,
    onQueryChange: (String) -> Unit,
    onSubmitSearch: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(StbBlueHighlight)
                .border(1.dp, Color(0xFF9DE3FF), RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Icon(
                imageVector = Icons.Rounded.Search,
                contentDescription = "Search",
                tint = Color.White,
                modifier = Modifier.size(20.dp)
            )
            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                if (query.isEmpty()) {
                    Text(
                        text = "_",
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    singleLine = true,
                    textStyle = TextStyle(
                        color = Color.White,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold
                    ),
                    cursorBrush = SolidColor(Color.White),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSubmitSearch(query) }),
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("stb_search_input")
                )
            }
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.spacedBy(2.dp)
        ) {
            itemsIndexed(suggestions) { idx, suggestion ->
                Text(
                    text = suggestion,
                    color = Color.White.copy(alpha = 0.92f),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(6.dp))
                        .clickable { onSubmitSearch(suggestion) }
                        .padding(horizontal = 10.dp, vertical = 7.dp)
                        .testTag("stb_suggestion_$idx")
                )
            }
        }
    }
}

@Composable
private fun StbOnScreenKeyboard(
    onKeyTap: (String) -> Unit,
    onSearchClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(5.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        KeyboardRows.forEach { row ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                row.forEach { keyLabel ->
                    Surface(
                        modifier = Modifier
                            .weight(1f)
                            .height(38.dp)
                            .clickable { onKeyTap(keyLabel) }
                            .testTag("stb_key_$keyLabel"),
                        shape = RoundedCornerShape(5.dp),
                        color = StbKeyBg,
                        border = BorderStroke(1.dp, StbKeyBorder)
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            when (keyLabel) {
                                "SPACE" -> Text(
                                    text = "␣",
                                    color = Color.White,
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                "DEL" -> Icon(
                                    imageVector = Icons.AutoMirrored.Rounded.Backspace,
                                    contentDescription = "Delete",
                                    tint = Color.White,
                                    modifier = Modifier.size(16.dp)
                                )
                                else -> Text(
                                    text = keyLabel,
                                    color = Color.White,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                        }
                    }
                }
            }
        }

        Surface(
            modifier = Modifier
                .width(140.dp)
                .height(38.dp)
                .clickable(onClick = onSearchClick)
                .testTag("stb_keyboard_search_button"),
            shape = RoundedCornerShape(6.dp),
            color = Color(0xFF1E2B3D),
            border = BorderStroke(1.2.dp, Color(0xFF4CC3FF))
        ) {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = "SEARCH",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }
        }
    }
}

@Composable
private fun StbSearchResultsPanel(
    results: StbSearchUiState.Results,
    onPressZeroToSearch: () -> Unit,
    onBack: () -> Unit,
    onClose: () -> Unit,
    onTuneChannel: (Int) -> Unit
) {
    var selectedRowIndex by remember(results.query) { mutableIntStateOf(0) }
    val activeCount = results.programs.size
    val displayIndex = if (activeCount == 0) 0 else (selectedRowIndex + 1).coerceAtMost(activeCount)

    Column(modifier = Modifier.fillMaxSize()) {
        // Folder tab header — Live Programs ONLY
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            StbFolderTab(
                label = "Live Programs (${results.programs.size})",
                selected = true,
                onClick = {},
                modifier = Modifier.testTag("stb_results_programs_tab")
            )

            Text(
                text = "$displayIndex/$activeCount",
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(end = 10.dp, bottom = 6.dp)
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topEnd = 10.dp, bottomStart = 10.dp, bottomEnd = 10.dp))
                .background(Color(0xE80A0F1A))
                .border(
                    width = 1.dp,
                    color = Color.White.copy(alpha = 0.35f),
                    shape = RoundedCornerShape(topEnd = 10.dp, bottomStart = 10.dp, bottomEnd = 10.dp)
                )
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF141B29))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text("Live Program", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(1.7f))
                Text("Status", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(0.65f))
                Text("Time", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(0.85f))
                Text("Channel", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(1.4f))
            }
            if (results.programs.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = "No LIVE programs currently airing matching \"${results.query}\".",
                        color = Color.White.copy(alpha = 0.85f),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(24.dp)
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(vertical = 4.dp)
                ) {
                    itemsIndexed(results.programs) { index, hit ->
                        val isSelected = index == selectedRowIndex
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .then(
                                    if (isSelected) Modifier.background(StbBlueHighlight)
                                    else Modifier.background(Color.Transparent)
                                )
                                .clickable {
                                    selectedRowIndex = index
                                    onClose()
                                    onTuneChannel(hit.program.channelId)
                                }
                                .padding(horizontal = 14.dp, vertical = 9.dp)
                                .testTag("stb_live_result_$index"),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            val textColor = if (isSelected) Color.Black else Color.White
                            Text(
                                text = hit.program.title,
                                color = textColor,
                                fontWeight = FontWeight.SemiBold,
                                fontSize = 14.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(1.7f)
                            )
                            Box(modifier = Modifier.weight(0.65f)) {
                                Surface(
                                    shape = RoundedCornerShape(4.dp),
                                    color = JioCrimson
                                ) {
                                    Text(
                                        text = "LIVE",
                                        color = Color.White,
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.ExtraBold,
                                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                    )
                                }
                            }
                            Text(
                                text = "${hit.program.startTimeFormatted} - ${hit.program.endTimeFormatted}",
                                color = textColor,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier.weight(0.85f)
                            )
                            Row(
                                modifier = Modifier.weight(1.4f),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(4.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Rounded.PlayArrow,
                                    contentDescription = "Watch Live",
                                    tint = if (isSelected) Color.Black else Color(0xFF4CC3FF),
                                    modifier = Modifier.size(16.dp)
                                )
                                Text(
                                    text = "${hit.program.channelId}  ${hit.channel?.name ?: hit.program.channelName}",
                                    color = textColor,
                                    fontWeight = FontWeight.Medium,
                                    fontSize = 13.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis
                                )
                            }
                        }
                    }
                }
            }
        }

        StbBottomLegendBar(
            items = listOf(
                StbLegendAction(badgeText = "0", label = "Press '0' to Search", onClick = onPressZeroToSearch),
                StbLegendAction(badgeText = "BACK", label = "Search Keys", onClick = onBack),
                StbLegendAction(dotColor = JioCrimson, label = "Close", onClick = onClose)
            )
        )
    }
}

@Composable
private fun StbFolderTab(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = RoundedCornerShape(topStart = 10.dp, topEnd = 16.dp),
        color = if (selected) Color(0xFF4CC3FF) else Color(0xFF232C44),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.4f))
    ) {
        Text(
            text = label,
            color = if (selected) Color.Black else Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 20.dp, vertical = 7.dp)
        )
    }
}

data class StbLegendAction(
    val badgeText: String? = null,
    val dotColor: Color? = null,
    val label: String,
    val onClick: () -> Unit
)

@Composable
fun StbBottomLegendBar(
    items: List<StbLegendAction>,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xE00A0D14))
            .padding(horizontal = 14.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically
    ) {
        items.forEach { item ->
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = item.onClick)
                    .minimumInteractiveComponentSize()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                if (item.dotColor != null) {
                    Box(
                        modifier = Modifier
                            .size(12.dp)
                            .clip(CircleShape)
                            .background(item.dotColor)
                            .border(1.dp, Color.White.copy(alpha = 0.7f), CircleShape)
                    )
                } else if (item.badgeText != null) {
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = Color(0xFF1F2736),
                        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.75f))
                    ) {
                        Text(
                            text = item.badgeText,
                            color = Color.White,
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 7.dp, vertical = 2.dp)
                        )
                    }
                }
                Text(
                    text = item.label,
                    color = Color.White,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
