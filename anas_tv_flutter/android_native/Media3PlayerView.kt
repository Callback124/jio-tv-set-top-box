package com.anas.tv

import android.content.Context
import android.graphics.Color
import android.media.MediaDrm
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.View
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

@OptIn(UnstableApi::class)
class Media3PlayerView(
    private val appContext: Context,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
    viewId: Int
) : PlatformView {
    private val root = FrameLayout(appContext)
    private val playerView = PlayerView(appContext)
    private val channel = MethodChannel(messenger, "anas_tv/media3_player_$viewId")
    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        root.setBackgroundColor(Color.BLACK)
        root.isFocusable = false
        root.isFocusableInTouchMode = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            root.defaultFocusHighlightEnabled = false
            playerView.defaultFocusHighlightEnabled = false
        }

        playerView.useController = false
        playerView.setShutterBackgroundColor(Color.BLACK)
        playerView.resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FILL
        playerView.isFocusable = false
        playerView.isFocusableInTouchMode = false
        playerView.keepScreenOn = true

        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play" -> {
                    @Suppress("UNCHECKED_CAST")
                    val playParams = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val url = (playParams["streamUrl"] as? String).orEmpty().trim()
                    if (url.isBlank()) {
                        sendError("Stream URL missing in play parameters.")
                    } else {
                        startPlayer(appContext, url, playParams)
                    }
                    result.success(null)
                }
                "pause" -> {
                    player?.playWhenReady = false
                    result.success(null)
                }
                "resume" -> {
                    player?.playWhenReady = true
                    result.success(null)
                }
                "setResizeMode" -> {
                    val mode = (call.arguments as? String).orEmpty().lowercase(Locale.ROOT)
                    playerView.resizeMode = when (mode) {
                        "fit" -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                        "zoom" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        else -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                    }
                    result.success(null)
                }
                "getAudioTracks" -> {
                    result.success(collectAudioTracks())
                }
                "setAudioTrack" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val groupIdx = (args["groupIndex"] as? Number)?.toInt() ?: -1
                    val trackIdx = (args["trackIndex"] as? Number)?.toInt() ?: -1
                    applyAudioTrack(groupIdx, trackIdx)
                    result.success(null)
                }
                "getVideoQualities" -> {
                    result.success(collectVideoQualities())
                }
                "setVideoQuality" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val groupIdx = (args["groupIndex"] as? Number)?.toInt() ?: -1
                    val trackIdx = (args["trackIndex"] as? Number)?.toInt() ?: -1
                    applyVideoQuality(groupIdx, trackIdx)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun collectAudioTracks(): List<Map<String, Any?>> {
        val exo = player ?: return emptyList()
        val list = mutableListOf<Map<String, Any?>>()
        var audioGroupOrdinal = 0
        for (group in exo.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_AUDIO) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val fmt = group.getTrackFormat(i)
                val langCode = fmt.language.orEmpty().trim()
                val langDisplay = if (langCode.isNotEmpty() && langCode != "und") {
                    Locale.forLanguageTag(langCode).displayLanguage.replaceFirstChar {
                        if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString()
                    }.ifBlank { langCode.uppercase(Locale.ROOT) }
                } else {
                    "Audio ${list.size + 1}"
                }
                val label = listOfNotNull(
                    langDisplay,
                    fmt.label?.takeIf { it.isNotBlank() && !it.equals(langDisplay, ignoreCase = true) },
                    if (fmt.channelCount >= 6) "5.1" else null
                ).joinToString(" • ")

                list.add(
                    mapOf(
                        "groupIndex" to audioGroupOrdinal,
                        "trackIndex" to i,
                        "label" to label,
                        "selected" to group.isTrackSelected(i)
                    )
                )
            }
            audioGroupOrdinal++
        }
        return list
    }

    private fun applyAudioTrack(targetGroupOrdinal: Int, targetTrackIndex: Int) {
        val exo = player ?: return
        val builder = exo.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)

        if (targetGroupOrdinal >= 0 && targetTrackIndex >= 0) {
            val audioGroups = exo.currentTracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
            if (targetGroupOrdinal < audioGroups.size) {
                val group = audioGroups[targetGroupOrdinal]
                if (targetTrackIndex < group.length) {
                    builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, targetTrackIndex))
                }
            }
        }
        exo.trackSelectionParameters = builder.build()
    }

    private fun collectVideoQualities(): List<Map<String, Any?>> {
        val exo = player ?: return listOf(
            mapOf("groupIndex" to -1, "trackIndex" to -1, "label" to "Auto", "height" to 0, "selected" to true)
        )
        val hasExplicitOverride = exo.trackSelectionParameters.overrides.values.any {
            it.type == C.TRACK_TYPE_VIDEO
        }
        val entries = mutableListOf<Map<String, Any?>>()
        val seenLabels = HashSet<String>()
        var videoGroupOrdinal = 0

        for (group in exo.currentTracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (i in 0 until group.length) {
                if (!group.isTrackSupported(i)) continue
                val fmt = group.getTrackFormat(i)
                val height = fmt.height
                val bitrateKbps = if (fmt.bitrate > 0) fmt.bitrate / 1000 else 0
                val label = when {
                    height >= 2160 -> "4K (${height}p)"
                    height >= 1080 -> "1080p HD"
                    height > 0 -> "${height}p"
                    bitrateKbps > 0 -> "${bitrateKbps} kbps"
                    else -> "Stream ${i + 1}"
                }
                if (!seenLabels.add(label)) continue
                entries.add(
                    mapOf(
                        "groupIndex" to videoGroupOrdinal,
                        "trackIndex" to i,
                        "label" to label,
                        "height" to height,
                        "selected" to (hasExplicitOverride && group.isTrackSelected(i))
                    )
                )
            }
            videoGroupOrdinal++
        }

        val sorted = entries.sortedByDescending { (it["height"] as? Int) ?: 0 }
        return listOf(
            mapOf(
                "groupIndex" to -1,
                "trackIndex" to -1,
                "label" to "Auto (Best)",
                "height" to 99999,
                "selected" to !hasExplicitOverride
            )
        ) + sorted
    }

    private fun applyVideoQuality(targetGroupOrdinal: Int, targetTrackIndex: Int) {
        val exo = player ?: return
        val builder = exo.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)

        if (targetGroupOrdinal < 0 || targetTrackIndex < 0) {
            builder.setForceHighestSupportedBitrate(true)
        } else {
            builder.setForceHighestSupportedBitrate(false)
            val videoGroups = exo.currentTracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
            if (targetGroupOrdinal < videoGroups.size) {
                val group = videoGroups[targetGroupOrdinal]
                if (targetTrackIndex < group.length) {
                    builder.addOverride(TrackSelectionOverride(group.mediaTrackGroup, targetTrackIndex))
                }
            }
        }
        exo.trackSelectionParameters = builder.build()
    }

    private fun startPlayer(context: Context, streamUrl: String, params: Map<String, Any?>) {
        try {
            val prevPlayer = player
            player = null
            playerView.player = null
            prevPlayer?.playWhenReady = false
            if (prevPlayer != null) {
                mainHandler.post { prevPlayer.release() }
            }

            val rawHeaders = (params["headers"] as? Map<*, *>).orEmpty()
            val cleanHeaders = LinkedHashMap<String, String>()
            rawHeaders.forEach { (k, v) ->
                val key = k?.toString()?.trim().orEmpty()
                val value = v?.toString()?.trim().orEmpty()
                if (key.isNotEmpty() && value.isNotEmpty() && !key.equals("Connection", ignoreCase = true)) {
                    cleanHeaders[key] = value
                }
            }
            val userAgent = cleanHeaders["User-Agent"]
                ?: "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Mobile Safari/537.36"

            val httpFactory = DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(15_000)
                .setUserAgent(userAgent)
                .setDefaultRequestProperties(cleanHeaders)

            val mediaSourceFactory = DefaultMediaSourceFactory(context)
                .setDataSourceFactory(httpFactory)

            val clearKeyPairs = parseClearKeyMap(params["clearKeys"])
            if (clearKeyPairs.isNotEmpty() && isClearKeySupported()) {
                val clearKeyJson = buildClearKeyJsonBytes(clearKeyPairs)
                val drmCallback = LocalMediaDrmCallback(clearKeyJson)
                val drmSessionManager = DefaultDrmSessionManager.Builder()
                    .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                    .setMultiSession(true)
                    .build(drmCallback)
                mediaSourceFactory.setDrmSessionManagerProvider { drmSessionManager }
            }

            val renderersFactory = DefaultRenderersFactory(context)
                .setEnableDecoderFallback(true)

            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(10_000, 25_000, 1_200, 2_500)
                .build()

            val exoPlayer = ExoPlayer.Builder(context, renderersFactory)
                .setLoadControl(loadControl)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()
            player = exoPlayer
            playerView.player = exoPlayer

            val itemBuilder = MediaItem.Builder().setUri(streamUrl)
            val lowerUrl = streamUrl.lowercase()
            when {
                lowerUrl.contains(".mpd") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_MPD)
                lowerUrl.contains(".m3u8") -> itemBuilder.setMimeType(MimeTypes.APPLICATION_M3U8)
            }

            val licenseUrl = (params["drmLicenseUrl"] as? String).orEmpty().trim()
            if (clearKeyPairs.isEmpty() && (licenseUrl.startsWith("https://") || licenseUrl.startsWith("http://"))) {
                val drmHeaders = ((params["drmHeaders"] as? Map<*, *>).orEmpty())
                    .entries
                    .mapNotNull { (k, v) ->
                        val key = k?.toString()?.trim().orEmpty()
                        val value = v?.toString()?.trim().orEmpty()
                        if (key.isNotEmpty() && value.isNotEmpty()) key to value else null
                    }.toMap()

                itemBuilder.setDrmConfiguration(
                    MediaItem.DrmConfiguration.Builder(C.WIDEVINE_UUID)
                        .setLicenseUri(licenseUrl)
                        .setLicenseRequestHeaders(drmHeaders)
                        .setMultiSession(true)
                        .build()
                )
            }

            exoPlayer.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    val causes = generateSequence(error as Throwable?) { it.cause }
                        .take(6)
                        .map { "${it.javaClass.simpleName}: ${it.message ?: "(no message)"}" }
                        .joinToString("\n")
                    sendError("Playback failed (${error.errorCodeName}):\n$causes")
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    val state = when (playbackState) {
                        Player.STATE_BUFFERING -> "buffering"
                        Player.STATE_READY -> "ready"
                        Player.STATE_ENDED -> "ended"
                        else -> "idle"
                    }
                    sendState(state)
                }

                override fun onRenderedFirstFrame() {
                    sendState("ready")
                }
            })

            exoPlayer.setMediaItem(itemBuilder.build())
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
        } catch (error: Exception) {
            sendError("Player setup error: ${error.message ?: error.javaClass.simpleName}")
        }
    }

    private fun isClearKeySupported(): Boolean =
        runCatching { MediaDrm.isCryptoSchemeSupported(C.CLEARKEY_UUID) }.getOrDefault(false)

    private fun parseClearKeyMap(raw: Any?): Map<String, String> {
        val result = linkedMapOf<String, String>()
        when (raw) {
            is Map<*, *> -> raw.forEach { (k, v) ->
                val kid = k?.toString()?.trim().orEmpty()
                val key = v?.toString()?.trim().orEmpty()
                if (kid.isNotEmpty() && key.isNotEmpty()) result[kid] = key
            }
            is String -> raw.split(",", ";", "\n").forEach { entry ->
                val parts = entry.trim().split(":")
                if (parts.size == 2 && parts[0].isNotBlank() && parts[1].isNotBlank()) {
                    result[parts[0].trim()] = parts[1].trim()
                }
            }
        }
        return result
    }

    private fun buildClearKeyJsonBytes(clearKeyPairs: Map<String, String>): ByteArray {
        val keysArray = JSONArray()
        clearKeyPairs.forEach { (rawKid, rawKey) ->
            keysArray.put(
                JSONObject().apply {
                    put("kty", "oct")
                    put("kid", hexOrBase64ToBase64Url(rawKid))
                    put("k", hexOrBase64ToBase64Url(rawKey))
                }
            )
        }
        return JSONObject().apply {
            put("keys", keysArray)
            put("type", "temporary")
        }.toString().toByteArray(Charsets.UTF_8)
    }

    private fun hexOrBase64ToBase64Url(input: String): String {
        val clean = input.trim().replace("-", "")
        return if (clean.length == 32 && clean.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) {
            val bytes = ByteArray(16) { idx ->
                clean.substring(idx * 2, idx * 2 + 2).toInt(16).toByte()
            }
            Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        } else {
            clean.replace('+', '-').replace('/', '_').trimEnd('=')
        }
    }

    private fun sendError(message: String) {
        mainHandler.post { channel.invokeMethod("onError", message) }
    }

    private fun sendState(state: String) {
        mainHandler.post { channel.invokeMethod("onStateChanged", state) }
    }

    override fun getView(): View = root

    override fun dispose() {
        channel.setMethodCallHandler(null)
        val oldPlayer = player
        player = null
        playerView.player = null
        oldPlayer?.playWhenReady = false
        if (oldPlayer != null) {
            mainHandler.post { oldPlayer.release() }
        }
    }
}
