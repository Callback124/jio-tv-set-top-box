package com.example.data.model

import com.squareup.moshi.Json
import com.squareup.moshi.JsonClass

@JsonClass(generateAdapter = true)
data class ChannelListResponse(
    val code: Int? = null,
    val message: String? = null,
    val result: List<RawJioChannel>? = null
)

@JsonClass(generateAdapter = true)
data class RawJioChannel(
    @Json(name = "channel_id") val channelId: Int = 0,
    @Json(name = "channel_name") val channelName: String = "",
    @Json(name = "logoUrl") val logoUrl: String? = null,
    @Json(name = "channelCategoryId") val channelCategoryId: Int? = null,
    @Json(name = "channelLanguageId") val channelLanguageId: Int? = null,
    @Json(name = "isHD") val isHd: Boolean? = null,
    @Json(name = "channel_order") val channelOrder: String? = null,
    @Json(name = "isCatchupAvailable") val isCatchupAvailable: Boolean? = null,
    @Json(name = "stb_channel_id") val stbChannelId: Int? = null
)

@JsonClass(generateAdapter = true)
data class EpgResponse(
    val epg: List<RawEpgProgram>? = null,
    val serverDate: String? = null
)

@JsonClass(generateAdapter = true)
data class RawEpgProgram(
    val srno: String? = null,
    val showname: String? = null,
    val showtitle: String? = null,
    val description: String? = null,
    val startEpoch: Long? = null,
    val endEpoch: Long? = null,
    val showtime: String? = null,
    val endtime: String? = null,
    val episodePoster: String? = null,
    val episodeThumbnail: String? = null,
    val showCategory: String? = null,
    val showGenre: List<String>? = null,
    val starCast: String? = null,
    val director: String? = null,
    @Json(name = "channel_id") val channelId: Int? = null,
    @Json(name = "channel_name") val channelName: String? = null,
    val keywords: List<String>? = null
)

data class ChannelPlaybackInfo(
    val streamUrl: String,
    val drmScheme: String = "",
    val licenseUrl: String = "",
    val clearKeyPairs: Map<String, String> = emptyMap(),
    val headers: Map<String, String> = emptyMap(),
    val userAgent: String = "",
    val cookie: String = "",
    val mimeTypeHint: String = ""
)

data class TvChannel(
    val id: Int,
    val name: String,
    val logoUrl: String,
    val fallbackLogoUrl: String,
    val categoryId: Int,
    val categoryName: String,
    val languageId: Int,
    val languageName: String,
    val isHd: Boolean,
    val isCatchupAvailable: Boolean,
    val channelOrder: Int,
    val playbackInfo: ChannelPlaybackInfo? = null,
    val isExtraChannel: Boolean = false,
    val isPlayable: Boolean = false
) {
    val hasPlayback: Boolean
        get() = isPlayable || playbackInfo?.streamUrl?.isNotBlank() == true
}

data class TvProgram(
    val id: String,
    val channelId: Int,
    val channelName: String,
    val title: String,
    val description: String,
    val startEpochMs: Long,
    val endEpochMs: Long,
    val startTimeFormatted: String,
    val endTimeFormatted: String,
    val posterUrl: String,
    val thumbnailUrl: String,
    val category: String,
    val starCast: String,
    val director: String,
    val isCatchupAvailable: Boolean
) {
    fun isLiveAt(nowMs: Long): Boolean = nowMs in startEpochMs until endEpochMs

    fun isPastAt(nowMs: Long): Boolean = endEpochMs <= nowMs

    fun progressAt(nowMs: Long): Float {
        if (endEpochMs <= startEpochMs) return 0f
        return ((nowMs - startEpochMs).toFloat() / (endEpochMs - startEpochMs).toFloat())
            .coerceIn(0f, 1f)
    }

    fun reminderKey(): String = "${channelId}_${startEpochMs}"
}

data class JioFilterOption(
    val id: Int,
    val name: String
)

object JioTvDictionaries {
    const val BASE_WEB_URL = "https://www.jiotv.com/"
    const val BASE_CDN_API_URL = "https://jiotv.data.cdn.jio.com/"
    const val CHANNEL_LOGO_PRIMARY_BASE = "https://jiotvimages.cdn.jio.com/dare_images/images/"
    const val CHANNEL_LOGO_FALLBACK_BASE = "https://jiotv.catchup.cdn.jio.com/dare_images/images/"
    const val SHOW_IMAGE_BASE = "https://jiotv.catchup.cdn.jio.com/dare_images/shows/"

    val categories = listOf(
        JioFilterOption(0, "All"),
        JioFilterOption(5, "Entertainment"),
        JioFilterOption(6, "Movies"),
        JioFilterOption(8, "Sports"),
        JioFilterOption(12, "News"),
        JioFilterOption(7, "Kids"),
        JioFilterOption(13, "Music"),
        JioFilterOption(10, "Infotainment"),
        JioFilterOption(9, "Lifestyle"),
        JioFilterOption(15, "Devotional"),
        JioFilterOption(16, "Business"),
        JioFilterOption(17, "Educational"),
        JioFilterOption(18, "Shopping")
    )

    val languages = listOf(
        JioFilterOption(0, "All Languages"),
        JioFilterOption(1, "Hindi"),
        JioFilterOption(6, "English"),
        JioFilterOption(8, "Tamil"),
        JioFilterOption(11, "Telugu"),
        JioFilterOption(2, "Marathi"),
        JioFilterOption(5, "Bengali"),
        JioFilterOption(9, "Gujarati"),
        JioFilterOption(13, "Kannada"),
        JioFilterOption(7, "Malayalam"),
        JioFilterOption(3, "Punjabi"),
        JioFilterOption(10, "Odia"),
        JioFilterOption(12, "Bhojpuri"),
        JioFilterOption(4, "Urdu"),
        JioFilterOption(14, "Assamese"),
        JioFilterOption(15, "Nepali")
    )

    private val categoryMap = categories.associate { it.id to it.name }
    private val languageMap = languages.associate { it.id to it.name }

    fun categoryName(id: Int?): String = categoryMap[id] ?: "General"
    fun languageName(id: Int?): String = languageMap[id] ?: "Regional"
}

data class ApiTraceEntry(
    val id: String,
    val stepOrder: Int,
    val initiator: String,
    val endpointLabel: String,
    val url: String,
    val method: String,
    val statusCode: Int?,
    val durationMs: Long,
    val contentType: String?,
    val summary: String,
    val rawSnippet: String,
    val timestampMs: Long,
    val isSuccess: Boolean
)

data class WebDiscoveryResult(
    val webPageReached: Boolean,
    val statusCode: Int?,
    val discoveredEndpoints: List<String>,
    val nextBuildId: String?,
    val embeddedChannelsJsonAvailable: Boolean
)
