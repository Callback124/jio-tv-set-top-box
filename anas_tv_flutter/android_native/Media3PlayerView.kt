package com.anas.tv

import android.content.Context
import android.graphics.Color
import android.media.MediaDrm
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
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject

class Media3PlayerView(
    context: Context,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
    viewId: Int
) : PlatformView {
    private val root = FrameLayout(context)
    private val playerView = PlayerView(context)
    private val channel = MethodChannel(messenger, "anas_tv/media3_player_$viewId")
    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        root.setBackgroundColor(Color.BLACK)
        root.isFocusable = false
        root.isFocusableInTouchMode = false

        // Flutter owns TV D-Pad & Mobile touch controls so navigation never gets trapped.
        playerView.useController = false
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
                        startPlayer(context, url, playParams)
                    }
                    result.success(null)
                }
                "pause" -> {
                    player?.playWhenReady = false
                    result.success(false)
                }
                "resume" -> {
                    player?.playWhenReady = true
                    result.success(true)
                }
                "togglePlayPause" -> {
                    val p = player
                    if (p != null) {
                        val next = !p.playWhenReady
                        p.playWhenReady = next
                        result.success(next)
                    } else {
                        result.success(false)
                    }
                }
                "setMuted" -> {
                    val muted = (call.arguments as? Boolean) ?: false
                    player?.volume = if (muted) 0f else 1f
                    result.success(muted)
                }
                "getVideoTracks" -> {
                    result.success(extractVideoTracks())
                }
                "selectVideoTrack" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val groupIndex = (args["groupIndex"] as? Number)?.toInt() ?: -1
                    val trackIndex = (args["trackIndex"] as? Number)?.toInt() ?: -1
                    selectVideoTrack(groupIndex, trackIndex)
                    result.success(null)
                }
                "stop" -> {
                    playerView.player = null
                    player?.release()
                    player = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun startPlayer(context: Context, streamUrl: String, params: Map<String, Any?>) {
        try {
            playerView.player = null
            player?.release()
            player = null

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

            val exoPlayer = ExoPlayer.Builder(context)
                .setMediaSourceFactory(mediaSourceFactory)
                .build()
            player = exoPlayer
            playerView.player = exoPlayer

            exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
                .buildUpon()
                .setForceHighestSupportedBitrate(true)
                .build()

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

                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    mainHandler.post { channel.invokeMethod("onIsPlayingChanged", isPlaying) }
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

    @OptIn(UnstableApi::class)
    private fun extractVideoTracks(): List<Map<String, Any>> {
        val exoPlayer = player ?: return emptyList()
        val list = ArrayList<Map<String, Any>>()
        val groups = exoPlayer.currentTracks.groups
        for (gIdx in 0 until groups.size) {
            val group = groups[gIdx]
            if (group.type != C.TRACK_TYPE_VIDEO || !group.isSupported) continue
            for (tIdx in 0 until group.length) {
                if (!group.isTrackSupported(tIdx)) continue
                val fmt = group.getTrackFormat(tIdx)
                val height = fmt.height
                val bitrate = fmt.bitrate
                val label = when {
                    height > 0 && bitrate > 0 -> "${height}p (${bitrate / 1000} kbps)"
                    height > 0 -> "${height}p"
                    bitrate > 0 -> "${bitrate / 1000} kbps"
                    else -> "Track ${tIdx + 1}"
                }
                list.add(
                    mapOf(
                        "groupIndex" to gIdx,
                        "trackIndex" to tIdx,
                        "height" to height,
                        "bitrate" to bitrate,
                        "label" to label,
                        "selected" to group.isTrackSelected(tIdx),
                    )
                )
            }
        }
        return list.sortedByDescending { (it["height"] as? Int) ?: 0 }
    }

    @OptIn(UnstableApi::class)
    private fun selectVideoTrack(groupIndex: Int, trackIndex: Int) {
        val exoPlayer = player ?: return
        if (groupIndex < 0 || trackIndex < 0) {
            exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                .setForceHighestSupportedBitrate(true)
                .build()
            return
        }
        val groups = exoPlayer.currentTracks.groups
        if (groupIndex >= groups.size) return
        val group = groups[groupIndex]
        if (trackIndex >= group.length) return
        exoPlayer.trackSelectionParameters = exoPlayer.trackSelectionParameters
            .buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, trackIndex))
            .build()
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
        playerView.player = null
        player?.release()
        player = null
    }
}
