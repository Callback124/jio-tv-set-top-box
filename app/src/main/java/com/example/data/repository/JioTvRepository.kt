package com.example.data.repository

import com.example.data.model.ChannelPlaybackInfo
import com.example.data.model.JioTvDictionaries
import com.example.data.model.RawJioChannel
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.data.model.WebDiscoveryResult
import com.example.data.network.InitiatorChainTracker
import com.example.data.network.JioTvApiService
import com.example.data.network.JioTvNetworkModule
import com.squareup.moshi.Moshi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap

sealed interface ApiLoadResult<out T> {
    data class Success<T>(val data: T, val sourceLabel: String) : ApiLoadResult<T>
    data class Error(
        val message: String,
        val httpCode: Int? = null,
        val isGeoBlocked: Boolean = false
    ) : ApiLoadResult<Nothing>
}

class JioTvRepository(
    private val apiService: JioTvApiService = JioTvNetworkModule.createApiService(),
    private val moshi: Moshi = JioTvNetworkModule.createMoshi(),
    val traceTracker: InitiatorChainTracker = InitiatorChainTracker()
) {
    private val epgCache = ConcurrentHashMap<Pair<Int, Int>, List<TvProgram>>()
    private val discoveryMutex = Mutex()
    private var cachedChannels: List<TvChannel> = emptyList()
    private var lastDiscovery: WebDiscoveryResult? = null

    private val timeFormatter = ThreadLocal.withInitial {
        SimpleDateFormat("hh:mm a", Locale.getDefault()).apply {
            timeZone = TimeZone.getDefault()
        }
    }

    /**
     * Executes the live JioTV TV-Guide Request Initiator Chain:
     * 1) https://www.jiotv.com/tv-guide (Web root document + __NEXT_DATA__ / script API discovery)
     * 2) Dictionary probe (apis/v1.3/dictionary/get)
     * 3) Channel directory (apis/v3.1/getMobileChannelList/get -> fallback v3.0 or embedded __NEXT_DATA__)
     */
    suspend fun executeChannelDiscoveryChain(
        customBaseUrl: String = "",
        forceRefresh: Boolean = false
    ): ApiLoadResult<List<TvChannel>> = withContext(Dispatchers.IO) {
        if (!forceRefresh && cachedChannels.isNotEmpty()) {
            return@withContext ApiLoadResult.Success(cachedChannels, "Memory Cache (from JioTV Initiator Chain)")
        }

        discoveryMutex.withLock {
            if (!forceRefresh && cachedChannels.isNotEmpty()) {
                return@withLock ApiLoadResult.Success(cachedChannels, "Memory Cache")
            }

            if (forceRefresh) {
                traceTracker.clear()
                epgCache.clear()
            }

            // Step 1: Fetch https://www.jiotv.com/tv-guide (Document Root Initiator)
            var embeddedChannels: List<TvChannel> = emptyList()
            var discoveredChannelUrl: String? = null
            val webStart = System.currentTimeMillis()
            try {
                val webResponse = apiService.fetchRawUrl(
                    url = JioTvNetworkModule.WEB_TV_GUIDE_URL,
                    headers = JioTvNetworkModule.webHeaders()
                )
                val duration = System.currentTimeMillis() - webStart
                val html = webResponse.body()?.string().orEmpty()
                val errBody = webResponse.errorBody()?.string().orEmpty()
                val rawPreview = if (html.isNotBlank()) html.take(900) else errBody.take(900)

                val discoveredUrls = extractDiscoveredApiUrls(html)
                discoveredChannelUrl = discoveredUrls.firstOrNull {
                    it.contains("getMobileChannelList", ignoreCase = true)
                }
                val nextBuildId = extractNextBuildId(html)
                embeddedChannels = extractEmbeddedChannelsFromNextData(html)

                lastDiscovery = WebDiscoveryResult(
                    webPageReached = webResponse.isSuccessful,
                    statusCode = webResponse.code(),
                    discoveredEndpoints = discoveredUrls,
                    nextBuildId = nextBuildId,
                    embeddedChannelsJsonAvailable = embeddedChannels.isNotEmpty()
                )

                traceTracker.record(
                    initiator = "User Navigation (Browser Document)",
                    endpointLabel = "Web Root: jiotv.com/tv-guide",
                    url = JioTvNetworkModule.WEB_TV_GUIDE_URL,
                    statusCode = webResponse.code(),
                    durationMs = duration,
                    contentType = webResponse.headers()["Content-Type"],
                    summary = buildString {
                        append(if (webResponse.isSuccessful) "Loaded web document" else "HTTP ${webResponse.code()}")
                        if (nextBuildId != null) append(" • Next.js build=$nextBuildId")
                        if (discoveredUrls.isNotEmpty()) append(" • Found ${discoveredUrls.size} API URLs")
                        if (embeddedChannels.isNotEmpty()) append(" • SSR channels=${embeddedChannels.size}")
                    },
                    rawSnippet = rawPreview.ifBlank { "No body returned (HTTP ${webResponse.code()})" },
                    isSuccess = webResponse.isSuccessful
                )

                // If Next.js buildId was discovered, also probe Next.js data JSON in initiator chain
                if (nextBuildId != null) {
                    val nextDataUrl = "https://www.jiotv.com/_next/data/$nextBuildId/tv-guide.json"
                    val nextStart = System.currentTimeMillis()
                    try {
                        val nextResp = apiService.fetchRawUrl(nextDataUrl, JioTvNetworkModule.webHeaders())
                        val nextBody = nextResp.body()?.string().orEmpty()
                        val nextDuration = System.currentTimeMillis() - nextStart
                        if (nextResp.isSuccessful && nextBody.isNotBlank() && embeddedChannels.isEmpty()) {
                            embeddedChannels = extractEmbeddedChannelsFromJson(nextBody)
                        }
                        traceTracker.record(
                            initiator = "https://www.jiotv.com/tv-guide",
                            endpointLabel = "Next.js Data Chunk",
                            url = nextDataUrl,
                            statusCode = nextResp.code(),
                            durationMs = nextDuration,
                            contentType = nextResp.headers()["Content-Type"],
                            summary = if (nextResp.isSuccessful) {
                                "Next.js tv-guide.json (${nextBody.length} bytes)"
                            } else {
                                "HTTP ${nextResp.code()}"
                            },
                            rawSnippet = nextBody.ifBlank { nextResp.errorBody()?.string().orEmpty() },
                            isSuccess = nextResp.isSuccessful
                        )
                    } catch (e: Exception) {
                        traceTracker.record(
                            initiator = "https://www.jiotv.com/tv-guide",
                            endpointLabel = "Next.js Data Chunk",
                            url = nextDataUrl,
                            statusCode = null,
                            durationMs = System.currentTimeMillis() - nextStart,
                            contentType = null,
                            summary = "Failed: ${e.localizedMessage ?: "Network error"}",
                            rawSnippet = e.stackTraceToString().take(800),
                            isSuccess = false
                        )
                    }
                }
            } catch (e: Exception) {
                traceTracker.record(
                    initiator = "User Navigation (Browser Document)",
                    endpointLabel = "Web Root: jiotv.com/tv-guide",
                    url = JioTvNetworkModule.WEB_TV_GUIDE_URL,
                    statusCode = null,
                    durationMs = System.currentTimeMillis() - webStart,
                    contentType = null,
                    summary = "Connection failed: ${e.localizedMessage ?: "Unknown error"}",
                    rawSnippet = e.stackTraceToString().take(800),
                    isSuccess = false
                )
            }

            // Step 2: Fetch Channel List from Custom Base -> Discovered URL -> v3.1 -> v3.0
            val candidateChannelUrls = buildList {
                if (customBaseUrl.isNotBlank()) {
                    add("$customBaseUrl/apis/v3.1/getMobileChannelList/get/")
                    add("$customBaseUrl/apis/v3.0/getMobileChannelList/get/")
                }
                if (!discoveredChannelUrl.isNullOrBlank()) {
                    add(discoveredChannelUrl)
                }
                add(JioTvNetworkModule.CHANNEL_LIST_V3_1)
                add(JioTvNetworkModule.CHANNEL_LIST_V3_0)
            }.distinct()

            var lastErrorCode: Int? = null
            var lastErrorMessage = "Unable to load channels from JioTV APIs."

            val extraChannels = fetchExtraPlayChannels()
            var jioChannels: List<TvChannel> = emptyList()
            var jioSourceLabel = ""

            for (channelUrl in candidateChannelUrls) {
                val callStart = System.currentTimeMillis()
                try {
                    val response = apiService.fetchChannelList(
                        url = channelUrl,
                        headers = JioTvNetworkModule.cdnApiHeaders()
                    )
                    val duration = System.currentTimeMillis() - callStart
                    val body = response.body()
                    val rawChannels = body?.result.orEmpty()

                    if (response.isSuccessful && rawChannels.isNotEmpty()) {
                        jioChannels = rawChannels.map { it.toDomain() }
                        jioSourceLabel = channelUrl
                        traceTracker.record(
                            initiator = "https://www.jiotv.com/tv-guide (Fetch API)",
                            endpointLabel = "getMobileChannelList",
                            url = channelUrl,
                            statusCode = response.code(),
                            durationMs = duration,
                            contentType = response.headers()["Content-Type"],
                            summary = "Fetched ${jioChannels.size} JioTV channels",
                            rawSnippet = serializeSampleChannel(rawChannels.first()),
                            isSuccess = true
                        )
                        break
                    } else {
                        lastErrorCode = response.code()
                        val errText = response.errorBody()?.string().orEmpty()
                        lastErrorMessage = buildErrorMessage(response.code(), errText)
                        traceTracker.record(
                            initiator = "https://www.jiotv.com/tv-guide (Fetch API)",
                            endpointLabel = "getMobileChannelList",
                            url = channelUrl,
                            statusCode = response.code(),
                            durationMs = duration,
                            contentType = response.headers()["Content-Type"],
                            summary = "HTTP ${response.code()} • ${if (rawChannels.isEmpty()) "Empty channel list" else "Failed"}",
                            rawSnippet = errText.ifBlank { body?.message ?: "Empty response" },
                            isSuccess = false
                        )
                    }
                } catch (e: Exception) {
                    lastErrorMessage = e.localizedMessage ?: "Network failure connecting to JioTV API"
                    traceTracker.record(
                        initiator = "https://www.jiotv.com/tv-guide (Fetch API)",
                        endpointLabel = "getMobileChannelList",
                        url = channelUrl,
                        statusCode = null,
                        durationMs = System.currentTimeMillis() - callStart,
                        contentType = null,
                        summary = "Error: $lastErrorMessage",
                        rawSnippet = e.stackTraceToString().take(800),
                        isSuccess = false
                    )
                }
            }

            if (jioChannels.isEmpty() && embeddedChannels.isNotEmpty()) {
                jioChannels = embeddedChannels
                jioSourceLabel = "SSR Payload (www.jiotv.com/tv-guide)"
            }

            if (jioChannels.isNotEmpty() || extraChannels.isNotEmpty()) {
                val merged = mergeAndDeduplicateChannels(jioChannels, extraChannels)
                cachedChannels = merged
                val sourceSummary = buildString {
                    if (jioSourceLabel.isNotBlank()) append(jioSourceLabel)
                    if (extraChannels.isNotEmpty()) {
                        if (isNotEmpty()) append(" + ")
                        append("npoint extra/play API")
                    }
                }
                return@withLock ApiLoadResult.Success(merged, sourceSummary)
            }

            val geoBlocked = lastErrorCode == 403 || lastErrorCode == 451
            ApiLoadResult.Error(
                message = lastErrorMessage,
                httpCode = lastErrorCode,
                isGeoBlocked = geoBlocked
            )
        }
    }

    /**
     * Step 4 in Initiator Chain: Fetches EPG schedule for a channel and day offset (-7 to +1).
     */
    suspend fun fetchChannelEpg(
        channelId: Int,
        offset: Int,
        customBaseUrl: String = "",
        forceRefresh: Boolean = false
    ): ApiLoadResult<List<TvProgram>> = withContext(Dispatchers.IO) {
        val cacheKey = channelId to offset
        if (!forceRefresh) {
            epgCache[cacheKey]?.let { cached ->
                return@withContext ApiLoadResult.Success(cached, "EPG Memory Cache")
            }
        }

        val epgUrl = if (customBaseUrl.isNotBlank()) {
            "$customBaseUrl/apis/v1.3/getepg/get"
        } else {
            JioTvNetworkModule.EPG_V1_3
        }

        val start = System.currentTimeMillis()
        try {
            val response = apiService.fetchEpg(
                url = epgUrl,
                offset = offset,
                channelId = channelId,
                langId = 6,
                headers = JioTvNetworkModule.cdnApiHeaders()
            )
            val duration = System.currentTimeMillis() - start
            if (response.isSuccessful) {
                val rawBody = response.body()?.string().orEmpty()
                val programs = parseEpgJson(rawBody, channelId, offset)
                    .sortedBy { it.startEpochMs }
                epgCache[cacheKey] = programs
                traceTracker.record(
                    initiator = "getMobileChannelList -> Channel $channelId",
                    endpointLabel = "getepg (offset=$offset)",
                    url = "$epgUrl?offset=$offset&channel_id=$channelId&langId=6",
                    statusCode = response.code(),
                    durationMs = duration,
                    contentType = response.headers()["Content-Type"],
                    summary = "Loaded ${programs.size} programs for channel #$channelId (day $offset)",
                    rawSnippet = formatEpgSnippet(rawBody),
                    isSuccess = true
                )
                ApiLoadResult.Success(programs, epgUrl)
            } else {
                val errBody = response.errorBody()?.string().orEmpty()
                traceTracker.record(
                    initiator = "getMobileChannelList -> Channel $channelId",
                    endpointLabel = "getepg (offset=$offset)",
                    url = "$epgUrl?offset=$offset&channel_id=$channelId&langId=6",
                    statusCode = response.code(),
                    durationMs = duration,
                    contentType = response.headers()["Content-Type"],
                    summary = "HTTP ${response.code()} fetching EPG for #$channelId",
                    rawSnippet = errBody.ifBlank { "HTTP ${response.code()}" },
                    isSuccess = false
                )
                ApiLoadResult.Error(
                    message = buildErrorMessage(response.code(), errBody),
                    httpCode = response.code(),
                    isGeoBlocked = response.code() == 403 || response.code() == 451
                )
            }
        } catch (e: Exception) {
            val msg = e.localizedMessage ?: "Network error loading EPG"
            traceTracker.record(
                initiator = "getMobileChannelList -> Channel $channelId",
                endpointLabel = "getepg (offset=$offset)",
                url = "$epgUrl?offset=$offset&channel_id=$channelId&langId=6",
                statusCode = null,
                durationMs = System.currentTimeMillis() - start,
                contentType = null,
                summary = "Error: $msg",
                rawSnippet = e.stackTraceToString().take(700),
                isSuccess = false
            )
            ApiLoadResult.Error(message = msg)
        }
    }

    fun getCachedEpg(channelId: Int, offset: Int): List<TvProgram>? = epgCache[channelId to offset]

    fun getLastDiscovery(): WebDiscoveryResult? = lastDiscovery

    private fun RawJioChannel.toDomain(): TvChannel {
        val rawLogo = logoUrl.orEmpty().trimStart('/')
        val primaryLogo = when {
            rawLogo.startsWith("http") -> rawLogo
            rawLogo.startsWith("dare_images/") -> "https://jiotvimages.cdn.jio.com/$rawLogo"
            rawLogo.isNotBlank() -> JioTvDictionaries.CHANNEL_LOGO_PRIMARY_BASE + rawLogo
            else -> ""
        }
        val fallbackLogo = when {
            rawLogo.startsWith("http") -> rawLogo
            rawLogo.startsWith("dare_images/") -> "https://jiotv.catchup.cdn.jio.com/$rawLogo"
            rawLogo.isNotBlank() -> JioTvDictionaries.CHANNEL_LOGO_FALLBACK_BASE + rawLogo
            else -> ""
        }
        return TvChannel(
            id = channelId,
            name = channelName.ifBlank { "Channel $channelId" },
            logoUrl = primaryLogo,
            fallbackLogoUrl = fallbackLogo,
            categoryId = channelCategoryId ?: 0,
            categoryName = JioTvDictionaries.categoryName(channelCategoryId),
            languageId = channelLanguageId ?: 0,
            languageName = JioTvDictionaries.languageName(channelLanguageId),
            isHd = isHd == true,
            isCatchupAvailable = isCatchupAvailable != false,
            channelOrder = channelOrder?.toIntOrNull() ?: Int.MAX_VALUE
        )
    }

    private fun parseEpgJson(rawBody: String, fallbackChannelId: Int, offset: Int): List<TvProgram> {
        if (rawBody.isBlank()) return emptyList()
        val root = JSONObject(rawBody)
        val epgArray = root.optJSONArray("epg") ?: return emptyList()
        val formatter = timeFormatter.get()!!

        val result = ArrayList<TvProgram>(epgArray.length())
        for (i in 0 until epgArray.length()) {
            val item = epgArray.optJSONObject(i) ?: continue
            val startMs = item.optEpochMs("startEpoch")
                ?: item.optTimeAsEpochMs("showtime", offset)
                ?: continue
            val endMs = item.optEpochMs("endEpoch")
                ?: item.optTimeAsEpochMs("endtime", offset)
                ?: (startMs + 3_600_000L)

            val resolvedChannelId = item.optFlexibleString("channel_id").toIntOrNull() ?: fallbackChannelId
            val resolvedTitle = item.optFlexibleString("showname").ifBlank {
                item.optFlexibleString("showtitle").ifBlank { "Program" }
            }
            val categoryText = item.optFlexibleString("showCategory").ifBlank {
                item.optFlexibleString("showGenre").ifBlank { "TV Show" }
            }
            val srno = item.optFlexibleString("srno")

            result.add(
                TvProgram(
                    id = srno.ifBlank { "${resolvedChannelId}_$startMs" },
                    channelId = resolvedChannelId,
                    channelName = item.optFlexibleString("channel_name"),
                    title = resolvedTitle,
                    description = item.optFlexibleString("description").ifBlank {
                        "No episode synopsis available."
                    },
                    startEpochMs = startMs,
                    endEpochMs = endMs,
                    startTimeFormatted = formatter.format(Date(startMs)),
                    endTimeFormatted = formatter.format(Date(endMs)),
                    posterUrl = resolveShowImage(item.optFlexibleString("episodePoster")),
                    thumbnailUrl = resolveShowImage(item.optFlexibleString("episodeThumbnail")),
                    category = categoryText,
                    starCast = item.optFlexibleString("starCast"),
                    director = item.optFlexibleString("director"),
                    isCatchupAvailable = endMs <= System.currentTimeMillis()
                )
            )
        }
        return result
    }

    private fun resolveShowImage(path: String): String {
        val trimmed = path.trim()
        return when {
            trimmed.isEmpty() -> ""
            trimmed.startsWith("http") -> trimmed
            trimmed.startsWith("dare_images/") -> "https://jiotv.catchup.cdn.jio.com/$trimmed"
            else -> JioTvDictionaries.SHOW_IMAGE_BASE + trimmed.trimStart('/')
        }
    }

    private fun JSONObject.optFlexibleString(key: String): String {
        val value = opt(key) ?: return ""
        if (value == JSONObject.NULL) return ""
        return when (value) {
            is JSONArray -> {
                val items = mutableListOf<String>()
                for (i in 0 until value.length()) {
                    val elem = value.opt(i)
                    if (elem != null && elem != JSONObject.NULL) {
                        val s = elem.toString().trim()
                        if (s.isNotEmpty() && s != "null") items.add(s)
                    }
                }
                items.joinToString(", ")
            }
            else -> value.toString().trim().let { if (it == "null") "" else it }
        }
    }

    private fun JSONObject.optEpochMs(key: String): Long? {
        val value = opt(key) ?: return null
        if (value == JSONObject.NULL) return null
        val numeric = when (value) {
            is Number -> value.toLong()
            is String -> value.trim().toLongOrNull()
            else -> null
        } ?: return null
        if (numeric <= 0L) return null
        return if (numeric < 10_000_000_000L) numeric * 1000L else numeric
    }

    private fun JSONObject.optTimeAsEpochMs(key: String, offset: Int): Long? {
        val raw = optFlexibleString(key)
        if (raw.isBlank()) return null
        val parts = raw.split(":")
        val hour = parts.getOrNull(0)?.toIntOrNull() ?: return null
        val minute = parts.getOrNull(1)?.toIntOrNull() ?: return null
        val second = parts.getOrNull(2)?.toIntOrNull() ?: 0
        val cal = java.util.Calendar.getInstance(TimeZone.getTimeZone("Asia/Kolkata")).apply {
            add(java.util.Calendar.DAY_OF_YEAR, offset)
            set(java.util.Calendar.HOUR_OF_DAY, hour)
            set(java.util.Calendar.MINUTE, minute)
            set(java.util.Calendar.SECOND, second)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }

    private fun formatEpgSnippet(rawBody: String): String {
        return try {
            val obj = JSONObject(rawBody)
            val arr = obj.optJSONArray("epg")
            if (arr != null && arr.length() > 0) {
                arr.optJSONObject(0)?.toString(2)?.take(1400) ?: rawBody.take(1400)
            } else {
                rawBody.take(1400)
            }
        } catch (_: Exception) {
            rawBody.take(1400)
        }
    }

    private fun extractDiscoveredApiUrls(html: String): List<String> {
        if (html.isBlank()) return emptyList()
        val regex = Regex("""https://[a-zA-Z0-9.-]*jio\.com/[a-zA-Z0-9_./?=&%-]+""")
        return regex.findAll(html)
            .map { it.value }
            .filter {
                it.contains("apis/", ignoreCase = true) ||
                    it.contains("getepg", ignoreCase = true) ||
                    it.contains("getMobileChannelList", ignoreCase = true) ||
                    it.contains("dictionary", ignoreCase = true)
            }
            .distinct()
            .take(20)
            .toList()
    }

    private fun extractNextBuildId(html: String): String? {
        val marker = """"buildId":""""
        val idx = html.indexOf(marker)
        if (idx == -1) return null
        val start = idx + marker.length
        val end = html.indexOf('"', start)
        if (end == -1 || end - start > 64) return null
        return html.substring(start, end)
    }

    private fun extractEmbeddedChannelsFromNextData(html: String): List<TvChannel> {
        val startTag = """<script id="__NEXT_DATA__" type="application/json">"""
        val startIdx = html.indexOf(startTag)
        if (startIdx == -1) return emptyList()
        val jsonStart = startIdx + startTag.length
        val endIdx = html.indexOf("</script>", jsonStart)
        if (endIdx == -1) return emptyList()
        val jsonStr = html.substring(jsonStart, endIdx)
        return extractEmbeddedChannelsFromJson(jsonStr)
    }

    private fun extractEmbeddedChannelsFromJson(jsonStr: String): List<TvChannel> {
        return try {
            val root = JSONObject(jsonStr)
            val foundArray = findChannelArray(root) ?: return emptyList()
            val adapter = moshi.adapter(RawJioChannel::class.java)
            buildList {
                for (i in 0 until foundArray.length()) {
                    val itemObj = foundArray.optJSONObject(i) ?: continue
                    val parsed = adapter.fromJson(itemObj.toString())
                    if (parsed != null && parsed.channelId > 0) {
                        add(parsed.toDomain())
                    }
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun findChannelArray(obj: JSONObject): JSONArray? {
        val keys = obj.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            val value = obj.opt(key)
            if (value is JSONArray && value.length() > 0) {
                val first = value.optJSONObject(0)
                if (first != null && first.has("channel_id") && first.has("channel_name")) {
                    return value
                }
            } else if (value is JSONObject) {
                val nested = findChannelArray(value)
                if (nested != null) return nested
            }
        }
        return null
    }

    private suspend fun fetchExtraPlayChannels(): List<TvChannel> {
        val url = JioTvNetworkModule.EXTRA_PLAY_CHANNELS_URL
        val start = System.currentTimeMillis()
        return try {
            val response = apiService.fetchRawUrl(
                url = url,
                headers = mapOf("Accept" to "application/json")
            )
            val duration = System.currentTimeMillis() - start
            val rawBody = response.body()?.string().orEmpty()
            if (response.isSuccessful && rawBody.isNotBlank()) {
                val parsed = parseExtraChannelsJson(rawBody)
                traceTracker.record(
                    initiator = "Channel & Playback Feed",
                    endpointLabel = "Extra Playable Channels (npoint)",
                    url = url,
                    statusCode = response.code(),
                    durationMs = duration,
                    contentType = response.headers()["Content-Type"],
                    summary = "Loaded ${parsed.size} channels with ExoPlayer stream data",
                    rawSnippet = rawBody.take(1400),
                    isSuccess = true
                )
                parsed
            } else {
                traceTracker.record(
                    initiator = "Channel & Playback Feed",
                    endpointLabel = "Extra Playable Channels (npoint)",
                    url = url,
                    statusCode = response.code(),
                    durationMs = duration,
                    contentType = response.headers()["Content-Type"],
                    summary = "HTTP ${response.code()} loading extra channels",
                    rawSnippet = response.errorBody()?.string().orEmpty().take(900),
                    isSuccess = false
                )
                emptyList()
            }
        } catch (e: Exception) {
            traceTracker.record(
                initiator = "Channel & Playback Feed",
                endpointLabel = "Extra Playable Channels (npoint)",
                url = url,
                statusCode = null,
                durationMs = System.currentTimeMillis() - start,
                contentType = null,
                summary = "Error: ${e.localizedMessage ?: "Failed"}",
                rawSnippet = e.stackTraceToString().take(800),
                isSuccess = false
            )
            emptyList()
        }
    }

    private fun mergeAndDeduplicateChannels(
        jioChannels: List<TvChannel>,
        extraChannels: List<TvChannel>
    ): List<TvChannel> {
        val mergedMap = LinkedHashMap<Int, TvChannel>(jioChannels.size + extraChannels.size)

        jioChannels.forEach { channel ->
            mergedMap.putIfAbsent(channel.id, channel)
        }

        extraChannels.forEach { extra ->
            val existing = mergedMap[extra.id]
            if (existing != null) {
                mergedMap[extra.id] = existing.copy(
                    name = existing.name.ifBlank { extra.name },
                    logoUrl = existing.logoUrl.ifBlank { extra.logoUrl },
                    fallbackLogoUrl = existing.fallbackLogoUrl.ifBlank { extra.fallbackLogoUrl },
                    categoryId = if (existing.categoryId != 0) existing.categoryId else extra.categoryId,
                    categoryName = if (existing.categoryId != 0 && existing.categoryName != "General") {
                        existing.categoryName
                    } else {
                        extra.categoryName
                    },
                    languageId = if (existing.languageId != 0) existing.languageId else extra.languageId,
                    languageName = if (existing.languageId != 0 && existing.languageName != "Regional") {
                        existing.languageName
                    } else {
                        extra.languageName
                    },
                    isHd = existing.isHd || extra.isHd,
                    playbackInfo = extra.playbackInfo ?: existing.playbackInfo,
                    isPlayable = existing.isPlayable || extra.isPlayable
                )
            } else {
                mergedMap[extra.id] = extra.copy(
                    isExtraChannel = true,
                    isPlayable = true
                )
            }
        }

        return mergedMap.values.sortedWith(
            compareBy<TvChannel> { it.channelOrder }.thenBy { it.name }
        )
    }

    /**
     * Resolves fresh live playback MPD/HLS URL, __hdnea__ cookie, and ClearKey all_keys
     * from https://eliteapiyash.streamxlive.workers.dev?id=<channel_id>
     */
    suspend fun resolveStreamPlayback(channel: TvChannel): ApiLoadResult<ChannelPlaybackInfo> =
        withContext(Dispatchers.IO) {
            val workerUrl = "${JioTvNetworkModule.STREAM_PLAY_WORKER_URL}?id=${channel.id}"
            val start = System.currentTimeMillis()
            var workerInfo: ChannelPlaybackInfo? = null

            // Synthetic IDs (>= 1_000_000) come from non-JioTV extra feeds (e.g., Dangal / SonyLIV / SunNXT)
            // and already carry direct playback URLs in channel.playbackInfo.
            if (channel.id < 1_000_000) {
                try {
                val response = apiService.fetchRawUrl(
                    url = workerUrl,
                    headers = JioTvNetworkModule.streamWorkerHeaders()
                )
                val duration = System.currentTimeMillis() - start
                val rawBody = response.body()?.string().orEmpty()

                if (response.isSuccessful && rawBody.isNotBlank()) {
                    val parsedInfo = parseWorkerPlaybackResponse(rawBody)
                    if (parsedInfo != null) {
                        workerInfo = parsedInfo
                        traceTracker.record(
                            initiator = "ExoPlayer -> Channel #${channel.id}",
                            endpointLabel = "Stream Play Worker",
                            url = workerUrl,
                            statusCode = response.code(),
                            durationMs = duration,
                            contentType = response.headers()["Content-Type"],
                            summary = buildString {
                                append("Resolved live stream for ${channel.name}")
                                if (parsedInfo.clearKeyPairs.isNotEmpty()) {
                                    append(" • ${parsedInfo.clearKeyPairs.size} ClearKey(s)")
                                }
                                if (parsedInfo.cookie.isNotBlank()) {
                                    append(" • Cookie ready")
                                }
                            },
                            rawSnippet = rawBody.take(1400),
                            isSuccess = true
                        )
                    } else {
                        traceTracker.record(
                            initiator = "ExoPlayer -> Channel #${channel.id}",
                            endpointLabel = "Stream Play Worker",
                            url = workerUrl,
                            statusCode = response.code(),
                            durationMs = duration,
                            contentType = response.headers()["Content-Type"],
                            summary = "Worker returned JSON without playable URL",
                            rawSnippet = rawBody.take(1000),
                            isSuccess = false
                        )
                    }
                } else {
                    val errText = response.errorBody()?.string().orEmpty()
                    traceTracker.record(
                        initiator = "ExoPlayer -> Channel #${channel.id}",
                        endpointLabel = "Stream Play Worker",
                        url = workerUrl,
                        statusCode = response.code(),
                        durationMs = duration,
                        contentType = response.headers()["Content-Type"],
                        summary = "HTTP ${response.code()} resolving stream for #${channel.id}",
                        rawSnippet = errText.ifBlank { rawBody }.take(900),
                        isSuccess = false
                    )
                }
            } catch (e: Exception) {
                traceTracker.record(
                    initiator = "ExoPlayer -> Channel #${channel.id}",
                    endpointLabel = "Stream Play Worker",
                    url = workerUrl,
                    statusCode = null,
                    durationMs = System.currentTimeMillis() - start,
                    contentType = null,
                    summary = "Error: ${e.localizedMessage ?: "Worker request failed"}",
                    rawSnippet = e.stackTraceToString().take(800),
                    isSuccess = false
                )
            }
            }

            val candidates = listOfNotNull(
                workerInfo?.let { it to workerUrl },
                channel.playbackInfo?.takeIf { it.streamUrl.isNotBlank() }?.let { it to "npoint playback feed" }
            ).distinctBy { it.first.streamUrl }

            if (candidates.isEmpty()) {
                return@withContext ApiLoadResult.Error(
                    "Unable to resolve live stream URL for ${channel.name} (#${channel.id})."
                )
            }

            var lastHttpCode: Int? = null
            var lastErrorMsg: String? = null

            for ((candidate, sourceLabel) in candidates) {
                val probeHeaders = LinkedHashMap<String, String>()
                candidate.headers.forEach { (k, v) ->
                    if (!k.equals("user-agent", true) && !k.equals("cookie", true)) {
                        probeHeaders[k] = v
                    }
                }
                probeHeaders["User-Agent"] = candidate.userAgent.ifBlank {
                    JioTvNetworkModule.MOBILE_CHROME_USER_AGENT
                }
                if (candidate.cookie.isNotBlank()) {
                    probeHeaders["Cookie"] = candidate.cookie
                }

                val probeStart = System.currentTimeMillis()
                try {
                    val probeResp = apiService.probeStream(
                        url = candidate.streamUrl,
                        headers = probeHeaders
                    )
                    val probeCode = probeResp.code()
                    val probeDuration = System.currentTimeMillis() - probeStart
                    val contentType = probeResp.headers()["Content-Type"]
                    probeResp.body()?.close()
                    probeResp.errorBody()?.close()

                    if (probeResp.isSuccessful) {
                        return@withContext ApiLoadResult.Success(candidate, sourceLabel)
                    } else {
                        lastHttpCode = probeCode
                        lastErrorMsg = when (probeCode) {
                            451 -> "HTTP 451: JioTV CDN geo-restricted this stream (Indian IP required) or rejected the __hdnea__ token."
                            403 -> "HTTP 403: Stream token expired or access denied for ${channel.name}."
                            404 -> "HTTP 404: Stream manifest not found for ${channel.name} (#${channel.id})."
                            else -> "Stream CDN returned HTTP $probeCode for ${channel.name}."
                        }
                        traceTracker.record(
                            initiator = "Stream Probe -> Channel #${channel.id}",
                            endpointLabel = "Manifest Check",
                            url = candidate.streamUrl,
                            statusCode = probeCode,
                            durationMs = probeDuration,
                            contentType = contentType,
                            summary = lastErrorMsg,
                            rawSnippet = "Source: $sourceLabel\nHTTP $probeCode",
                            isSuccess = false
                        )
                    }
                } catch (_: Exception) {
                    // Network probe hiccup (e.g., transient socket timeout) — allow ExoPlayer to attempt playback directly
                    return@withContext ApiLoadResult.Success(candidate, sourceLabel)
                }
            }

            ApiLoadResult.Error(
                message = lastErrorMsg ?: "Unable to open stream for ${channel.name}.",
                httpCode = lastHttpCode,
                isGeoBlocked = lastHttpCode == 451 || lastHttpCode == 403
            )
        }

    private fun parseExtraChannelsJson(rawJson: String): List<TvChannel> {
        val trimmed = rawJson.trim()
        if (trimmed.isEmpty()) return emptyList()
        val items = mutableListOf<Pair<String?, JSONObject>>()

        if (trimmed.startsWith("[")) {
            val arr = JSONArray(trimmed)
            for (i in 0 until arr.length()) {
                arr.optJSONObject(i)?.let { items.add(null to it) }
            }
        } else if (trimmed.startsWith("{")) {
            val root = JSONObject(trimmed)
            val listKeys = listOf("channels", "result", "data", "list", "items", "tv", "streams")
            var foundArray: JSONArray? = null
            for (key in listKeys) {
                val arr = root.optJSONArray(key)
                if (arr != null) {
                    foundArray = arr
                    break
                }
            }
            if (foundArray == null) {
                val keys = root.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    val v = root.opt(key)
                    if (v is JSONArray) {
                        foundArray = v
                        break
                    }
                }
            }
            if (foundArray != null) {
                for (i in 0 until foundArray.length()) {
                    foundArray.optJSONObject(i)?.let { items.add(null to it) }
                }
            } else {
                val keys = root.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    root.optJSONObject(key)?.let { items.add(key to it) }
                }
            }
        }

        return items.mapIndexedNotNull { index, (mapKey, obj) ->
            parseExtraChannelObject(obj, mapKey, index)
        }
    }

    private fun parseExtraChannelObject(
        obj: JSONObject,
        mapKey: String?,
        index: Int
    ): TvChannel? {
        val playObj = obj.optJSONObject("play_data")
            ?: obj.optJSONObject("playData")
            ?: obj.optJSONObject("playback")
            ?: obj.optJSONObject("stream")
            ?: obj.optJSONObject("source")
            ?: obj.optJSONObject("mpd_data")

        val rawStreamLink = firstNonBlank(
            obj.optFlexibleString("channel_url"),
            obj.optFlexibleString("stream_url"),
            obj.optFlexibleString("streamUrl"),
            obj.optFlexibleString("play_url"),
            obj.optFlexibleString("playUrl"),
            obj.optFlexibleString("mpd_url"),
            obj.optFlexibleString("mpdUrl"),
            obj.optFlexibleString("mpd"),
            obj.optFlexibleString("m3u8_url"),
            obj.optFlexibleString("m3u8Url"),
            obj.optFlexibleString("m3u8"),
            obj.optFlexibleString("hls_url"),
            obj.optFlexibleString("hls"),
            obj.optFlexibleString("dash_url"),
            obj.optFlexibleString("dash"),
            obj.optFlexibleString("manifest_url"),
            obj.optFlexibleString("manifest"),
            obj.optFlexibleString("url"),
            obj.optFlexibleString("link"),
            obj.optFlexibleString("src"),
            obj.optFlexibleString("ready_to_use_link"),
            obj.optFlexibleString("readyToUseLink"),
            playObj?.optFlexibleString("channel_url").orEmpty(),
            playObj?.optFlexibleString("stream_url").orEmpty(),
            playObj?.optFlexibleString("streamUrl").orEmpty(),
            playObj?.optFlexibleString("mpd_url").orEmpty(),
            playObj?.optFlexibleString("url").orEmpty(),
            playObj?.optFlexibleString("mpd").orEmpty(),
            playObj?.optFlexibleString("hls").orEmpty(),
            playObj?.optFlexibleString("m3u8").orEmpty(),
            playObj?.optFlexibleString("play_url").orEmpty(),
            playObj?.optFlexibleString("ready_to_use_link").orEmpty()
        )
        val (streamUrl, pipeParams) = splitPipeStreamLink(rawStreamLink)

        val name = firstNonBlank(
            obj.optFlexibleString("channel_name"),
            obj.optFlexibleString("channelName"),
            obj.optFlexibleString("name"),
            obj.optFlexibleString("title"),
            obj.optFlexibleString("tvg_name"),
            obj.optFlexibleString("ChannelName")
        )
        if (name.isBlank() && streamUrl.isBlank()) return null

        val rawId = firstNonBlank(
            obj.optFlexibleString("channel_id"),
            obj.optFlexibleString("channelId"),
            obj.optFlexibleString("id"),
            obj.optFlexibleString("chid"),
            obj.optFlexibleString("ChannelID"),
            obj.optFlexibleString("channelNo"),
            mapKey.orEmpty()
        ).toIntOrNull()

        val channelId = if (rawId != null && rawId > 0) {
            rawId
        } else {
            val hash = (name + "|" + streamUrl + "|" + index).hashCode()
            1_000_000 + kotlin.math.abs(hash % 8_000_000)
        }

        val rawLogo = firstNonBlank(
            obj.optFlexibleString("channel_logo"),
            obj.optFlexibleString("logoUrl"),
            obj.optFlexibleString("logo"),
            obj.optFlexibleString("tvg_logo"),
            obj.optFlexibleString("icon"),
            obj.optFlexibleString("image"),
            obj.optFlexibleString("img"),
            obj.optFlexibleString("thumbnail")
        ).trimStart('/')

        val primaryLogo = when {
            rawLogo.startsWith("http") -> rawLogo
            rawLogo.startsWith("dare_images/") -> "https://jiotvimages.cdn.jio.com/$rawLogo"
            rawLogo.isNotBlank() -> JioTvDictionaries.CHANNEL_LOGO_PRIMARY_BASE + rawLogo
            else -> ""
        }
        val fallbackLogo = when {
            rawLogo.startsWith("http") -> rawLogo
            rawLogo.startsWith("dare_images/") -> "https://jiotv.catchup.cdn.jio.com/$rawLogo"
            rawLogo.isNotBlank() -> JioTvDictionaries.CHANNEL_LOGO_FALLBACK_BASE + rawLogo
            else -> ""
        }

        val rawCatText = firstNonBlank(
            obj.optFlexibleString("channel_genre"),
            obj.optFlexibleString("cat"),
            obj.optFlexibleString("categoryName"),
            obj.optFlexibleString("category"),
            obj.optFlexibleString("genre"),
            obj.optFlexibleString("group_title"),
            obj.optFlexibleString("group")
        )
        val catId = firstNonBlank(
            obj.optFlexibleString("channelCategoryId"),
            obj.optFlexibleString("category_id"),
            obj.optFlexibleString("categoryId")
        ).toIntOrNull() ?: inferCategoryId(rawCatText, name)
        val catName = rawCatText
            .takeUnless { it.equals("Unknown", ignoreCase = true) }
            .orEmpty()
            .ifBlank { JioTvDictionaries.categoryName(catId) }

        val rawLangText = firstNonBlank(
            obj.optFlexibleString("languageName"),
            obj.optFlexibleString("language"),
            obj.optFlexibleString("lang")
        )
        val langId = firstNonBlank(
            obj.optFlexibleString("channelLanguageId"),
            obj.optFlexibleString("language_id"),
            obj.optFlexibleString("languageId")
        ).toIntOrNull() ?: inferLanguageId(rawLangText.ifBlank { rawCatText })
        val langName = rawLangText
            .let { if (it.equals("Malyalam", ignoreCase = true)) "Malayalam" else it }
            .takeIf { it.isNotBlank() }
            ?.lowercase()
            ?.replaceFirstChar { ch -> ch.titlecase(Locale.getDefault()) }
            ?: JioTvDictionaries.languageName(langId)

        val isHd = obj.optBoolean("isHD", false) ||
            obj.optBoolean("isHd", false) ||
            obj.optBoolean("hd", false) ||
            name.contains("HD", ignoreCase = true)

        val headers = linkedMapOf<String, String>()
        listOf(
            obj.optJSONObject("headers"),
            obj.optJSONObject("httpHeaders"),
            obj.optJSONObject("request_headers"),
            playObj?.optJSONObject("headers"),
            playObj?.optJSONObject("httpHeaders")
        ).forEach { hdrObj ->
            if (hdrObj != null) {
                val hKeys = hdrObj.keys()
                while (hKeys.hasNext()) {
                    val hk = hKeys.next()
                    val hv = hdrObj.optFlexibleString(hk)
                    if (hv.isNotBlank()) headers[hk] = hv
                }
            }
        }

        val userAgent = firstNonBlank(
            obj.optFlexibleString("userAgent"),
            obj.optFlexibleString("user_agent"),
            obj.optFlexibleString("User-Agent"),
            obj.optFlexibleString("ua"),
            playObj?.optFlexibleString("userAgent").orEmpty(),
            playObj?.optFlexibleString("user_agent").orEmpty(),
            headers["User-Agent"].orEmpty(),
            headers["user-agent"].orEmpty()
        )
        val cookie = firstNonBlank(
            obj.optFlexibleString("cookie"),
            obj.optFlexibleString("Cookie"),
            obj.optFlexibleString("cookies"),
            playObj?.optFlexibleString("cookie").orEmpty(),
            playObj?.optFlexibleString("Cookie").orEmpty(),
            headers["Cookie"].orEmpty(),
            headers["cookie"].orEmpty(),
            pipeParams["cookie"].orEmpty()
        )
        val referer = firstNonBlank(
            obj.optFlexibleString("referer"),
            obj.optFlexibleString("Referer"),
            obj.optFlexibleString("referrer"),
            playObj?.optFlexibleString("referer").orEmpty()
        )
        val origin = firstNonBlank(
            obj.optFlexibleString("origin"),
            obj.optFlexibleString("Origin"),
            playObj?.optFlexibleString("origin").orEmpty()
        )
        val effectiveUserAgent = userAgent.ifBlank { JioTvNetworkModule.MOBILE_CHROME_USER_AGENT }
        headers.putIfAbsent("User-Agent", effectiveUserAgent)
        if (cookie.isNotBlank()) headers.putIfAbsent("Cookie", cookie)
        if (referer.isNotBlank()) headers.putIfAbsent("Referer", referer)
        if (origin.isNotBlank()) headers.putIfAbsent("Origin", origin)

        val drmObj = obj.optJSONObject("drm")
            ?: obj.optJSONObject("drmConfig")
            ?: obj.optJSONObject("drm_info")
            ?: playObj?.optJSONObject("drm")
            ?: playObj?.optJSONObject("drmConfig")

        val drmScheme = firstNonBlank(
            obj.optFlexibleString("drm_scheme"),
            obj.optFlexibleString("drmScheme"),
            obj.optFlexibleString("drm_type"),
            obj.optFlexibleString("drmType"),
            if (obj.opt("drm") is String) obj.optFlexibleString("drm") else "",
            drmObj?.optFlexibleString("scheme").orEmpty(),
            drmObj?.optFlexibleString("type").orEmpty(),
            playObj?.optFlexibleString("drm_scheme").orEmpty(),
            playObj?.optFlexibleString("drmType").orEmpty(),
            pipeParams["drmScheme"].orEmpty()
        ).lowercase()

        val licenseUrl = firstNonBlank(
            obj.optFlexibleString("license_url"),
            obj.optFlexibleString("licenseUrl"),
            obj.optFlexibleString("drm_license_url"),
            obj.optFlexibleString("la_url"),
            obj.optFlexibleString("widevine_url"),
            drmObj?.optFlexibleString("license_url").orEmpty(),
            drmObj?.optFlexibleString("licenseUrl").orEmpty(),
            playObj?.optFlexibleString("license_url").orEmpty(),
            playObj?.optFlexibleString("licenseUrl").orEmpty(),
            if (pipeParams["drmLicense"].orEmpty().startsWith("http", ignoreCase = true)) {
                pipeParams["drmLicense"].orEmpty()
            } else {
                ""
            }
        )

        val clearKeyPairs = parseClearKeyPairs(obj, playObj, drmObj, pipeParams["drmLicense"])
        val effectiveDrmScheme = when {
            drmScheme.isNotBlank() -> drmScheme
            clearKeyPairs.isNotEmpty() -> "clearkey"
            licenseUrl.isNotBlank() -> "widevine"
            else -> ""
        }

        val mimeHint = firstNonBlank(
            obj.optFlexibleString("mime_type"),
            obj.optFlexibleString("mimeType"),
            obj.optFlexibleString("stream_type"),
            obj.optFlexibleString("type"),
            playObj?.optFlexibleString("mime_type").orEmpty(),
            playObj?.optFlexibleString("type").orEmpty()
        )

        val playback = if (streamUrl.isNotBlank()) {
            ChannelPlaybackInfo(
                streamUrl = streamUrl,
                drmScheme = effectiveDrmScheme,
                licenseUrl = licenseUrl,
                clearKeyPairs = clearKeyPairs,
                headers = headers,
                userAgent = effectiveUserAgent,
                cookie = cookie,
                mimeTypeHint = mimeHint
            )
        } else {
            null
        }

        val order = firstNonBlank(
            obj.optFlexibleString("channel_order"),
            obj.optFlexibleString("order")
        ).toIntOrNull() ?: (10_000 + index)

        return TvChannel(
            id = channelId,
            name = name.ifBlank { "Channel $channelId" },
            logoUrl = primaryLogo,
            fallbackLogoUrl = fallbackLogo,
            categoryId = catId,
            categoryName = catName,
            languageId = langId,
            languageName = langName,
            isHd = isHd,
            isCatchupAvailable = obj.optBoolean("isCatchupAvailable", true),
            channelOrder = order,
            playbackInfo = playback,
            isExtraChannel = true,
            isPlayable = true
        )
    }

    private fun parseWorkerPlaybackResponse(rawBody: String): ChannelPlaybackInfo? {
        val trimmed = rawBody.trim()
        if (trimmed.isEmpty()) return null

        val obj: JSONObject? = when {
            trimmed.startsWith("[") -> JSONArray(trimmed).optJSONObject(0)
            trimmed.startsWith("{") -> {
                val root = JSONObject(trimmed)
                root.optJSONArray("data")?.optJSONObject(0)
                    ?: root.optJSONArray("result")?.optJSONObject(0)
                    ?: root.optJSONObject("data")
                    ?: root.optJSONObject("result")
                    ?: root
            }
            else -> null
        }
        if (obj == null) return null

        val status = obj.optFlexibleString("status").lowercase()
        val rawLink = firstNonBlank(
            obj.optFlexibleString("mpd_url"),
            obj.optFlexibleString("mpdUrl"),
            obj.optFlexibleString("stream_url"),
            obj.optFlexibleString("streamUrl"),
            obj.optFlexibleString("m3u8_url"),
            obj.optFlexibleString("m3u8Url"),
            obj.optFlexibleString("play_url"),
            obj.optFlexibleString("url"),
            obj.optFlexibleString("ready_to_use_link"),
            obj.optFlexibleString("readyToUseLink")
        )
        val (baseUrlFromPrimary, primaryPipeParams) = splitPipeStreamLink(rawLink)
        val readyToUseRaw = firstNonBlank(
            obj.optFlexibleString("ready_to_use_link"),
            obj.optFlexibleString("readyToUseLink")
        )
        val (readyUrl, readyPipeParams) = splitPipeStreamLink(readyToUseRaw)

        val finalUrl = baseUrlFromPrimary.ifBlank { readyUrl }
        if (finalUrl.isBlank() || status == "error" || status == "failed") return null

        val mergedPipeParams = readyPipeParams + primaryPipeParams

        val headers = linkedMapOf<String, String>()
        obj.optJSONObject("headers")?.let { hdrObj ->
            val keys = hdrObj.keys()
            while (keys.hasNext()) {
                val hk = keys.next()
                val hv = hdrObj.optFlexibleString(hk)
                if (hv.isNotBlank()) headers[hk] = hv
            }
        }

        val userAgent = firstNonBlank(
            obj.optFlexibleString("userAgent"),
            obj.optFlexibleString("user_agent"),
            obj.optFlexibleString("User-Agent"),
            headers["User-Agent"].orEmpty(),
            JioTvNetworkModule.MOBILE_CHROME_USER_AGENT
        )
        val cookie = firstNonBlank(
            obj.optFlexibleString("cookie"),
            obj.optFlexibleString("Cookie"),
            mergedPipeParams["cookie"].orEmpty(),
            headers["Cookie"].orEmpty()
        )
        headers["User-Agent"] = userAgent
        if (cookie.isNotBlank()) headers["Cookie"] = cookie

        val clearKeyPairs = parseClearKeyPairs(
            obj = obj,
            playObj = null,
            drmObj = obj.optJSONObject("drm"),
            extraClearKeyString = mergedPipeParams["drmLicense"]
        )
        val licenseUrl = firstNonBlank(
            obj.optFlexibleString("license_url"),
            obj.optFlexibleString("licenseUrl"),
            if (mergedPipeParams["drmLicense"].orEmpty().startsWith("http", ignoreCase = true)) {
                mergedPipeParams["drmLicense"].orEmpty()
            } else {
                ""
            }
        )
        val rawScheme = firstNonBlank(
            obj.optFlexibleString("drm_scheme"),
            obj.optFlexibleString("drmScheme"),
            mergedPipeParams["drmScheme"].orEmpty()
        ).lowercase()

        val drmScheme = when {
            rawScheme.isNotBlank() -> rawScheme
            clearKeyPairs.isNotEmpty() -> "clearkey"
            licenseUrl.isNotBlank() -> "widevine"
            else -> ""
        }

        return ChannelPlaybackInfo(
            streamUrl = finalUrl,
            drmScheme = drmScheme,
            licenseUrl = licenseUrl,
            clearKeyPairs = clearKeyPairs,
            headers = headers,
            userAgent = userAgent,
            cookie = cookie,
            mimeTypeHint = obj.optFlexibleString("mime_type")
        )
    }

    private fun splitPipeStreamLink(raw: String): Pair<String, Map<String, String>> {
        val trimmed = raw.trim()
        if (trimmed.isBlank()) return "" to emptyMap()
        val pipeIdx = trimmed.indexOf('|')
        if (pipeIdx == -1) return trimmed to emptyMap()

        val baseUrl = trimmed.substring(0, pipeIdx).trim()
        val paramPart = trimmed.substring(pipeIdx + 1).trim()
        val params = linkedMapOf<String, String>()
        paramPart.split("&").forEach { entry ->
            val eqIdx = entry.indexOf('=')
            if (eqIdx > 0) {
                val key = entry.substring(0, eqIdx).trim()
                val value = entry.substring(eqIdx + 1).trim()
                if (key.isNotBlank() && value.isNotBlank()) {
                    params[key] = value
                }
            }
        }
        return baseUrl to params
    }

    private fun parseClearKeyPairs(
        obj: JSONObject,
        playObj: JSONObject?,
        drmObj: JSONObject?,
        extraClearKeyString: String? = null
    ): Map<String, String> {
        val pairs = linkedMapOf<String, String>()

        fun parseKeyValueString(raw: String) {
            if (raw.isBlank() || raw.startsWith("http", ignoreCase = true)) return
            raw.split(",", ";", "\n").forEach { segment ->
                val parts = segment.trim().split(":")
                if (parts.size == 2 && parts[0].isNotBlank() && parts[1].isNotBlank()) {
                    pairs[parts[0].trim()] = parts[1].trim()
                }
            }
        }

        fun inspectObject(target: JSONObject?) {
            if (target == null) return
            val clearKeyKeys = listOf(
                "all_keys",
                "allKeys",
                "drmLicense",
                "drm_license",
                "clearkey",
                "clearKey",
                "clear_key",
                "drm_key",
                "drmKey",
                "keys"
            )
            for (k in clearKeyKeys) {
                when (val v = target.opt(k)) {
                    is JSONObject -> {
                        val kid = v.optFlexibleString("kid").ifBlank { v.optFlexibleString("key_id") }
                        val keyVal = v.optFlexibleString("key").ifBlank { v.optFlexibleString("k") }
                        if (kid.isNotBlank() && keyVal.isNotBlank()) {
                            pairs[kid] = keyVal
                        } else {
                            val keys = v.keys()
                            while (keys.hasNext()) {
                                val mk = keys.next()
                                val mv = v.optFlexibleString(mk)
                                if (mk.isNotBlank() && mv.isNotBlank()) pairs[mk] = mv
                            }
                        }
                    }
                    is JSONArray -> {
                        for (i in 0 until v.length()) {
                            val item = v.optJSONObject(i) ?: continue
                            val kid = item.optFlexibleString("kid").ifBlank { item.optFlexibleString("key_id") }
                            val keyVal = item.optFlexibleString("k").ifBlank { item.optFlexibleString("key") }
                            if (kid.isNotBlank() && keyVal.isNotBlank()) pairs[kid] = keyVal
                        }
                    }
                    is String -> parseKeyValueString(v)
                }
            }
            val directKid = firstNonBlank(
                target.optFlexibleString("kid"),
                target.optFlexibleString("key_id"),
                target.optFlexibleString("keyId")
            )
            val directKey = firstNonBlank(
                target.optFlexibleString("key"),
                target.optFlexibleString("key_value")
            )
            if (directKid.contains(":")) {
                parseKeyValueString(directKid)
            } else if (directKid.isNotBlank() && directKey.isNotBlank()) {
                pairs.putIfAbsent(directKid, directKey)
            }
        }

        inspectObject(obj)
        inspectObject(playObj)
        inspectObject(drmObj)
        if (!extraClearKeyString.isNullOrBlank()) {
            parseKeyValueString(extraClearKeyString)
        }
        return pairs
    }

    private fun inferCategoryId(categoryName: String, channelName: String = ""): Int {
        val trimmed = categoryName.trim()
        val directMatch = if (trimmed.isNotBlank()) {
            JioTvDictionaries.categories.firstOrNull {
                it.id != 0 && (
                    it.name.equals(trimmed, ignoreCase = true) ||
                        trimmed.contains(it.name, ignoreCase = true)
                    )
            }?.id
        } else {
            null
        }
        if (directMatch != null) return directMatch

        val combined = "$trimmed $channelName".lowercase()
        return when {
            "movie" in combined || "cinema" in combined -> 6
            "sport" in combined || "cricket" in combined || "ten " in combined -> 8
            "news" in combined || "aaj tak" in combined || "samachar" in combined -> 12
            "kid" in combined || "cartoon" in combined || "pogo" in combined || "nick" in combined -> 7
            "music" in combined || "9xm" in combined || "mtv" in combined -> 13
            "infotainment" in combined || "discovery" in combined || "history" in combined || "nat geo" in combined -> 10
            "lifestyle" in combined || "tlc" in combined || "food" in combined -> 9
            "devotional" in combined || "bhakti" in combined || "sanskar" in combined || "aastha" in combined -> 15
            "business" in combined || "cnbc" in combined || "et now" in combined -> 16
            "edu" in combined || "gyan" in combined -> 17
            "shop" in combined -> 18
            trimmed.isNotBlank() && !trimmed.equals("Unknown", ignoreCase = true) -> 5
            else -> 0
        }
    }

    private fun inferLanguageId(languageName: String): Int {
        if (languageName.isBlank()) return 0
        val normalized = if (languageName.contains("malyalam", ignoreCase = true)) {
            "Malayalam"
        } else {
            languageName.trim()
        }
        return JioTvDictionaries.languages.firstOrNull {
            it.id != 0 && (
                it.name.equals(normalized, ignoreCase = true) ||
                    normalized.contains(it.name, ignoreCase = true)
                )
        }?.id ?: 0
    }

    private fun firstNonBlank(vararg values: String): String {
        return values.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
    }

    private fun buildErrorMessage(code: Int, body: String): String {
        return when (code) {
            403, 451 -> "JioTV CDN returned HTTP $code (Access Restricted / Indian IP Geo-Block). You can inspect the initiator chain log or configure a custom JioTV API base/proxy URL in API Chain settings."
            404 -> "Endpoint returned HTTP 404 (Not Found)."
            in 500..599 -> "JioTV server error (HTTP $code). Please retry shortly."
            else -> "JioTV API returned HTTP $code${if (body.isNotBlank()) ": ${body.take(120)}" else ""}"
        }
    }

    private fun serializeSampleChannel(raw: RawJioChannel): String {
        return moshi.adapter(RawJioChannel::class.java).indent("  ").toJson(raw)
    }
}
