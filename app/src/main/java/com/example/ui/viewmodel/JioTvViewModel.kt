package com.example.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.example.data.local.PreferencesRepository
import com.example.data.local.UserPreferences
import com.example.data.model.ApiTraceEntry
import com.example.data.model.ChannelPlaybackInfo
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.data.model.WebDiscoveryResult
import com.example.data.repository.ApiLoadResult
import com.example.data.repository.JioTvRepository
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

sealed interface ChannelsUiState {
    data object Loading : ChannelsUiState
    data class Success(val channels: List<TvChannel>, val sourceLabel: String) : ChannelsUiState
    data class Error(
        val message: String,
        val httpCode: Int? = null,
        val isGeoBlocked: Boolean = false
    ) : ChannelsUiState
}

sealed interface PlaybackResolveState {
    data object Idle : PlaybackResolveState
    data object Loading : PlaybackResolveState
    data class Ready(val info: ChannelPlaybackInfo, val sourceUrl: String) : PlaybackResolveState
    data class Error(val message: String) : PlaybackResolveState
}

data class StbProgramSearchHit(
    val program: TvProgram,
    val channel: TvChannel?,
    val dayOffset: Int
)

sealed interface StbSearchUiState {
    data object Input : StbSearchUiState
    data class Searching(val query: String) : StbSearchUiState
    data class Results(
        val query: String,
        val programs: List<StbProgramSearchHit>,
        val channels: List<TvChannel>
    ) : StbSearchUiState
}

class JioTvViewModel(application: Application) : AndroidViewModel(application) {
    private val preferencesRepository = PreferencesRepository(application)
    private val repository = JioTvRepository(
        apiService = com.example.data.network.JioTvNetworkModule.createApiService(
            okHttpClient = com.example.data.network.JioTvNetworkModule.createOkHttpClient(application.cacheDir)
        )
    )

    private val epgSemaphore = Semaphore(12)

    val preferences: StateFlow<UserPreferences> = preferencesRepository.preferencesFlow
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = UserPreferences()
        )

    private val _channelsState = MutableStateFlow<ChannelsUiState>(ChannelsUiState.Loading)
    val channelsState: StateFlow<ChannelsUiState> = _channelsState.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _selectedDayOffset = MutableStateFlow(0)
    val selectedDayOffset: StateFlow<Int> = _selectedDayOffset.asStateFlow()

    private val _epgByChannelAndDay = MutableStateFlow<Map<Pair<Int, Int>, List<TvProgram>>>(emptyMap())
    val epgByChannelAndDay: StateFlow<Map<Pair<Int, Int>, List<TvProgram>>> = _epgByChannelAndDay.asStateFlow()

    private val _loadingEpgKeys = MutableStateFlow<Set<Pair<Int, Int>>>(emptySet())
    val loadingEpgKeys: StateFlow<Set<Pair<Int, Int>>> = _loadingEpgKeys.asStateFlow()

    private val _epgErrors = MutableStateFlow<Map<Pair<Int, Int>, String>>(emptyMap())
    val epgErrors: StateFlow<Map<Pair<Int, Int>, String>> = _epgErrors.asStateFlow()

    private val _selectedProgram = MutableStateFlow<TvProgram?>(null)
    val selectedProgram: StateFlow<TvProgram?> = _selectedProgram.asStateFlow()

    private val _currentTimeMs = MutableStateFlow(System.currentTimeMillis())
    val currentTimeMs: StateFlow<Long> = _currentTimeMs.asStateFlow()

    private val _lastDiscovery = MutableStateFlow<WebDiscoveryResult?>(null)
    val lastDiscovery: StateFlow<WebDiscoveryResult?> = _lastDiscovery.asStateFlow()

    private val _playbackStates = MutableStateFlow<Map<Int, PlaybackResolveState>>(emptyMap())
    val playbackStates: StateFlow<Map<Int, PlaybackResolveState>> = _playbackStates.asStateFlow()

    private val _isSearchPanelOpen = MutableStateFlow(false)
    val isSearchPanelOpen: StateFlow<Boolean> = _isSearchPanelOpen.asStateFlow()

    private val _stbSearchState = MutableStateFlow<StbSearchUiState>(StbSearchUiState.Input)
    val stbSearchState: StateFlow<StbSearchUiState> = _stbSearchState.asStateFlow()

    private val _recentSearches = MutableStateFlow(listOf("ZEE CINEMA", "MOVIES", "SPORTS", "NEWS"))
    val recentSearches: StateFlow<List<String>> = _recentSearches.asStateFlow()

    val traceEntries: StateFlow<List<ApiTraceEntry>> = repository.traceTracker.traces

    val filteredChannels: StateFlow<List<TvChannel>> = combine(
        _channelsState,
        preferences,
        _searchQuery
    ) { state, prefs, query ->
        val all = (state as? ChannelsUiState.Success)?.channels.orEmpty()
        val trimmed = query.trim()
        all.filter { channel ->
            val matchCategory = prefs.selectedCategoryId == 0 || channel.categoryId == prefs.selectedCategoryId
            val matchLang = prefs.selectedLanguageId == 0 || channel.languageId == prefs.selectedLanguageId
            val matchHd = !prefs.hdOnly || channel.isHd
            val matchPlayable = !prefs.playableOnly || channel.hasPlayback
            val matchQuery = trimmed.isEmpty() ||
                channel.name.contains(trimmed, ignoreCase = true) ||
                channel.categoryName.contains(trimmed, ignoreCase = true) ||
                channel.languageName.contains(trimmed, ignoreCase = true) ||
                channel.id.toString() == trimmed
            matchCategory && matchLang && matchHd && matchPlayable && matchQuery
        }
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = emptyList()
    )

    init {
        viewModelScope.launch {
            while (true) {
                delay(30_000L)
                _currentTimeMs.value = System.currentTimeMillis()
            }
        }
        viewModelScope.launch {
            val initialPrefs = preferencesRepository.preferencesFlow.first()
            loadChannelDirectory(customBaseUrl = initialPrefs.customApiBaseUrl, forceRefresh = false)
        }
    }

    fun loadChannelDirectory(
        customBaseUrl: String = preferences.value.customApiBaseUrl,
        forceRefresh: Boolean = true
    ) {
        viewModelScope.launch {
            _channelsState.value = ChannelsUiState.Loading
            when (val result = repository.executeChannelDiscoveryChain(customBaseUrl, forceRefresh)) {
                is ApiLoadResult.Success -> {
                    _lastDiscovery.value = repository.getLastDiscovery()
                    _channelsState.value = ChannelsUiState.Success(result.data, result.sourceLabel)
                    prefetchEpgForTopChannels(result.data.take(18), _selectedDayOffset.value)
                }
                is ApiLoadResult.Error -> {
                    _lastDiscovery.value = repository.getLastDiscovery()
                    _channelsState.value = ChannelsUiState.Error(
                        message = result.message,
                        httpCode = result.httpCode,
                        isGeoBlocked = result.isGeoBlocked
                    )
                }
            }
        }
    }

    fun ensureEpgLoaded(channelId: Int, offset: Int = _selectedDayOffset.value, forceRefresh: Boolean = false) {
        val key = channelId to offset
        if (!forceRefresh && (_epgByChannelAndDay.value.containsKey(key) || key in _loadingEpgKeys.value)) {
            return
        }
        viewModelScope.launch {
            _loadingEpgKeys.update { it + key }
            _epgErrors.update { it - key }
            epgSemaphore.withPermit {
                when (
                    val result = repository.fetchChannelEpg(
                        channelId = channelId,
                        offset = offset,
                        customBaseUrl = preferences.value.customApiBaseUrl,
                        forceRefresh = forceRefresh
                    )
                ) {
                    is ApiLoadResult.Success -> {
                        _epgByChannelAndDay.update { it + (key to result.data) }
                    }
                    is ApiLoadResult.Error -> {
                        _epgErrors.update { it + (key to result.message) }
                    }
                }
            }
            _loadingEpgKeys.update { it - key }
        }
    }

    fun prefetchChannelAllDays(channelId: Int, priorityOffset: Int = _selectedDayOffset.value) {
        val orderedOffsets = (-7..7).sortedBy { kotlin.math.abs(it - priorityOffset) }
        orderedOffsets.forEach { dayOffset ->
            ensureEpgLoaded(channelId, dayOffset, false)
        }
    }

    private fun prefetchEpgForTopChannels(channels: List<TvChannel>, offset: Int) {
        channels.forEach { channel ->
            ensureEpgLoaded(channel.id, offset)
        }
    }

    fun onSearchQueryChanged(query: String) {
        _searchQuery.value = query
    }

    fun onDayOffsetSelected(offset: Int) {
        _selectedDayOffset.value = offset.coerceIn(-7, 7)
        val top = filteredChannels.value.take(16)
        prefetchEpgForTopChannels(top, _selectedDayOffset.value)
    }

    fun selectCategory(categoryId: Int) {
        viewModelScope.launch { preferencesRepository.setCategory(categoryId) }
    }

    fun selectLanguage(languageId: Int) {
        viewModelScope.launch { preferencesRepository.setLanguage(languageId) }
    }

    fun toggleHdOnly() {
        viewModelScope.launch { preferencesRepository.setHdOnly(!preferences.value.hdOnly) }
    }

    fun togglePlayableOnly() {
        viewModelScope.launch { preferencesRepository.setPlayableOnly(!preferences.value.playableOnly) }
    }

    fun toggleFavorite(channelId: Int) {
        viewModelScope.launch { preferencesRepository.toggleFavorite(channelId) }
    }

    fun toggleReminder(program: TvProgram) {
        viewModelScope.launch { preferencesRepository.toggleReminder(program.reminderKey()) }
    }

    fun toggleDarkTheme() {
        viewModelScope.launch { preferencesRepository.setDarkTheme(!preferences.value.darkTheme) }
    }

    fun saveCustomBaseUrlAndReload(url: String) {
        viewModelScope.launch {
            preferencesRepository.setCustomApiBaseUrl(url)
            loadChannelDirectory(customBaseUrl = url.trim().trimEnd('/'), forceRefresh = true)
        }
    }

    fun openProgramSheet(program: TvProgram) {
        _selectedProgram.value = program
    }

    fun closeProgramSheet() {
        _selectedProgram.value = null
    }

    fun resolvePlayback(channel: TvChannel, forceRefresh: Boolean = true) {
        val current = _playbackStates.value[channel.id]
        if (!forceRefresh && (current is PlaybackResolveState.Loading || current is PlaybackResolveState.Ready)) {
            return
        }
        viewModelScope.launch {
            _playbackStates.update { it + (channel.id to PlaybackResolveState.Loading) }
            when (val result = repository.resolveStreamPlayback(channel)) {
                is ApiLoadResult.Success -> {
                    _playbackStates.update {
                        it + (channel.id to PlaybackResolveState.Ready(result.data, result.sourceLabel))
                    }
                }
                is ApiLoadResult.Error -> {
                    _playbackStates.update {
                        it + (channel.id to PlaybackResolveState.Error(result.message))
                    }
                }
            }
        }
    }

    fun openSearchPanel() {
        _stbSearchState.value = StbSearchUiState.Input
        _isSearchPanelOpen.value = true
    }

    fun closeSearchPanel() {
        _isSearchPanelOpen.value = false
    }

    fun returnToSearchInput() {
        _stbSearchState.value = StbSearchUiState.Input
    }

    fun clearSearchHistory() {
        _recentSearches.value = emptyList()
    }

    fun executeStbSearch(rawQuery: String) {
        val query = rawQuery.trim()
        if (query.isBlank()) return

        _recentSearches.update { existing ->
            (listOf(query.uppercase()) + existing.filterNot { it.equals(query, ignoreCase = true) }).take(8)
        }

        viewModelScope.launch {
            _stbSearchState.value = StbSearchUiState.Searching(query)

            val allChannels = (_channelsState.value as? ChannelsUiState.Success)?.channels.orEmpty()
            val matchingChannels = allChannels.filter { ch ->
                ch.name.contains(query, ignoreCase = true) ||
                    ch.categoryName.contains(query, ignoreCase = true) ||
                    ch.languageName.contains(query, ignoreCase = true) ||
                    ch.id.toString() == query
            }.sortedWith(compareByDescending<TvChannel> { it.hasPlayback }.thenBy { it.channelOrder })

            // Ensure today's (offset = 0) EPG is loaded across matching + playable + top channels for live search
            val channelsToProbe = (
                matchingChannels.take(16) +
                    allChannels.filter { it.hasPlayback }.take(20) +
                    allChannels.take(16)
                )
                .distinctBy { it.id }
                .filter { !_epgByChannelAndDay.value.containsKey(it.id to 0) }
                .take(36)

            if (channelsToProbe.isNotEmpty()) {
                channelsToProbe.map { ch ->
                    async {
                        val key = ch.id to 0
                        epgSemaphore.withPermit {
                            val res = repository.fetchChannelEpg(
                                channelId = ch.id,
                                offset = 0,
                                customBaseUrl = preferences.value.customApiBaseUrl,
                                forceRefresh = false
                            )
                            if (res is ApiLoadResult.Success) {
                                _epgByChannelAndDay.update { it + (key to res.data) }
                            }
                        }
                    }
                }.awaitAll()
            }

            val nowMs = System.currentTimeMillis()
            val channelById = allChannels.associateBy { it.id }
            val liveHits = _epgByChannelAndDay.value.entries
                .asSequence()
                .filter { (key, _) -> key.second == 0 }
                .flatMap { (_, programs) -> programs.asSequence() }
                .filter { prog -> prog.isLiveAt(nowMs) }
                .filter { prog ->
                    val ch = channelById[prog.channelId]
                    prog.title.contains(query, ignoreCase = true) ||
                        prog.description.contains(query, ignoreCase = true) ||
                        prog.category.contains(query, ignoreCase = true) ||
                        prog.starCast.contains(query, ignoreCase = true) ||
                        (ch?.name?.contains(query, ignoreCase = true) == true)
                }
                .map { prog ->
                    StbProgramSearchHit(
                        program = prog,
                        channel = channelById[prog.channelId],
                        dayOffset = 0
                    )
                }
                .distinctBy { "${it.program.channelId}_${it.program.startEpochMs}" }
                .sortedWith(
                    compareByDescending<StbProgramSearchHit> { it.channel?.hasPlayback == true }
                        .thenBy { it.channel?.channelOrder ?: Int.MAX_VALUE }
                        .thenBy { it.program.title }
                )
                .toList()

            _stbSearchState.value = StbSearchUiState.Results(
                query = query,
                programs = liveHits,
                channels = emptyList()
            )
        }
    }

    fun findChannelById(channelId: Int): TvChannel? {
        return (_channelsState.value as? ChannelsUiState.Success)
            ?.channels
            ?.firstOrNull { it.id == channelId }
    }

    fun findChannelByDialNumber(dialNumber: Int): TvChannel? {
        val all = (_channelsState.value as? ChannelsUiState.Success)?.channels.orEmpty()
        return all.firstOrNull { it.id == dialNumber }
            ?: all.firstOrNull { it.id.toString().startsWith(dialNumber.toString()) && it.hasPlayback }
    }

    fun adjacentChannel(currentId: Int, delta: Int): TvChannel? {
        val all = (_channelsState.value as? ChannelsUiState.Success)?.channels.orEmpty()
        val playable = all.filter { it.hasPlayback }.ifEmpty { all }
        if (playable.isEmpty()) return null
        val currentIdx = playable.indexOfFirst { it.id == currentId }
        val nextIdx = if (currentIdx == -1) {
            0
        } else {
            (currentIdx + delta + playable.size) % playable.size
        }
        return playable[nextIdx]
    }
}
