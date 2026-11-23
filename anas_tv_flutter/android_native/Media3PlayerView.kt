package com.anas.tv

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.media.MediaDrm
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.FocusFinder
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageButton
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
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
    private val appContext: Context,
    params: Map<String, Any?>,
    messenger: BinaryMessenger,
    viewId: Int
) : PlatformView {
    private val root = object : FrameLayout(appContext) {
        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            if (isHandledTvKey(event.keyCode)) {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    return dispatchTvKey(event.keyCode)
                }
                if (event.action == KeyEvent.ACTION_UP) {
                    return true
                }
            }
            return super.dispatchKeyEvent(event)
        }
    }
    private val playerView = PlayerView(appContext)
    private val channel = MethodChannel(messenger, "anas_tv/media3_player_$viewId")
    private var player: ExoPlayer? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isControllerShown = false
    private var focusedControl: View? = null

    init {
        root.setBackgroundColor(Color.BLACK)
        root.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            root.defaultFocusHighlightEnabled = false
            playerView.defaultFocusHighlightEnabled = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            root.foreground = null
            playerView.foreground = null
        }

        playerView.useController = true
        playerView.isFocusable = true
        playerView.isFocusableInTouchMode = true
        playerView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        playerView.keepScreenOn = true
        @OptIn(UnstableApi::class)
        playerView.setControllerAnimationEnabled(false)
        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                isControllerShown = (visibility == View.VISIBLE)
                if (!isControllerShown) {
                    clearFocusedControl()
                } else {
                    mainHandler.post { applyControlFocusStyles(playerView) }
                }
            }
        )

        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        mainHandler.post { applyControlFocusStyles(playerView) }

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
                "dispatchKey" -> {
                    val keyCode = (call.arguments as? Number)?.toInt() ?: 0
                    result.success(dispatchTvKey(keyCode))
                }
                "isControllerVisible" -> {
                    result.success(isControllerVisible())
                }
                "hideController" -> {
                    hideNativeController()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isHandledTvKey(keyCode: Int): Boolean = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_CENTER,
        KeyEvent.KEYCODE_ENTER,
        KeyEvent.KEYCODE_NUMPAD_ENTER,
        KeyEvent.KEYCODE_DPAD_LEFT,
        KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_DPAD_UP,
        KeyEvent.KEYCODE_DPAD_DOWN,
        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
        KeyEvent.KEYCODE_MEDIA_REWIND -> true
        else -> false
    }

    @OptIn(UnstableApi::class)
    private fun isControllerVisible(): Boolean = isControllerShown || playerView.isControllerFullyVisible

    @OptIn(UnstableApi::class)
    private fun hideNativeController() {
        isControllerShown = false
        clearFocusedControl()
        playerView.hideController()
    }

    private fun buildGreyFocusBackground(context: Context, isSubtle: Boolean = false): StateListDrawable {
        val density = context.resources.displayMetrics.density
        val focusedDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = 999f * density
            setColor(if (isSubtle) 0x33FFFFFF else 0x55FFFFFF)
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_selected), focusedDrawable)
            addState(intArrayOf(android.R.attr.state_focused), focusedDrawable)
            addState(intArrayOf(android.R.attr.state_hovered), focusedDrawable)
            addState(intArrayOf(), ColorDrawable(Color.TRANSPARENT))
        }
    }

    private fun applyControlFocusStyles(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            view.defaultFocusHighlightEnabled = false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && view !== root && view !== playerView) {
            view.foreground = null
        }

        if (view !== root && view !== playerView) {
            val isAlreadyStyled = view.tag == "anas_tv_styled"
            if (!isAlreadyStyled) {
                if (view is ImageButton || (view.isFocusable && view.isClickable && view !is ViewGroup)) {
                    view.backgroundTintList = null
                    view.background = buildGreyFocusBackground(view.context, isSubtle = false)
                    view.tag = "anas_tv_styled"
                } else if (view.isFocusable && view !is ViewGroup) {
                    view.backgroundTintList = null
                    view.background = buildGreyFocusBackground(view.context, isSubtle = true)
                    view.tag = "anas_tv_styled"
                }
            }
        }

        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                applyControlFocusStyles(view.getChildAt(i))
            }
        }
    }

    private fun clearFocusedControl() {
        focusedControl?.isSelected = false
        focusedControl = null
    }

    private fun selectControl(target: View?) {
        if (target == null) return
        applyControlFocusStyles(target)
        if (focusedControl !== target) {
            focusedControl?.isSelected = false
        }
        focusedControl = target
        target.isSelected = true
        target.requestFocus()
    }

    private fun collectFocusableControls(view: View, out: MutableList<View>) {
        if (view !== root && view !== playerView) {
            if (view.visibility != View.VISIBLE) return
            if (view.isShown && view.isEnabled && view.isFocusable && view !is ViewGroup) {
                if (view is ImageButton || view.isClickable || view.id == exoProgressId()) {
                    out.add(view)
                    return
                }
            }
        }
        if (view is ViewGroup && view.visibility == View.VISIBLE) {
            for (i in 0 until view.childCount) {
                collectFocusableControls(view.getChildAt(i), out)
            }
        }
    }

    private fun exoProgressId(): Int =
        appContext.resources.getIdentifier("exo_progress", "id", appContext.packageName)

    private fun focusInitialControl() {
        val playPauseId = appContext.resources.getIdentifier("exo_play_pause", "id", appContext.packageName)
        val playPauseView = if (playPauseId != 0) playerView.findViewById<View>(playPauseId) else null
        if (playPauseView != null && playPauseView.visibility == View.VISIBLE && playPauseView.isFocusable) {
            selectControl(playPauseView)
            return
        }
        val controls = mutableListOf<View>()
        collectFocusableControls(playerView, controls)
        selectControl(controls.firstOrNull())
    }

    private fun findNextControl(current: View, direction: Int): View? {
        val controls = mutableListOf<View>()
        collectFocusableControls(playerView, controls)
        if (controls.isEmpty()) return null

        val systemNext = FocusFinder.getInstance().findNextFocus(playerView, current, direction)
        if (systemNext != null && controls.contains(systemNext) && systemNext !== current) {
            return systemNext
        }

        val curPos = IntArray(2)
        current.getLocationOnScreen(curPos)
        val curCx = curPos[0] + current.width / 2f
        val curCy = curPos[1] + current.height / 2f

        var best: View? = null
        var bestScore = Float.MAX_VALUE
        val candPos = IntArray(2)

        for (candidate in controls) {
            if (candidate === current) continue
            candidate.getLocationOnScreen(candPos)
            val candCx = candPos[0] + candidate.width / 2f
            val candCy = candPos[1] + candidate.height / 2f
            val dx = candCx - curCx
            val dy = candCy - curCy

            val valid = when (direction) {
                View.FOCUS_LEFT -> dx < -4f
                View.FOCUS_RIGHT -> dx > 4f
                View.FOCUS_UP -> dy < -4f
                View.FOCUS_DOWN -> dy > 4f
                else -> false
            }
            if (!valid) continue

            val score = when (direction) {
                View.FOCUS_LEFT, View.FOCUS_RIGHT -> kotlin.math.abs(dx) + kotlin.math.abs(dy) * 2.5f
                else -> kotlin.math.abs(dy) + kotlin.math.abs(dx) * 1.4f
            }
            if (score < bestScore) {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    @OptIn(UnstableApi::class)
    private fun dispatchTvKey(keyCode: Int): Boolean {
        if (keyCode <= 0) return false
        if (keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) {
            player?.let { it.playWhenReady = !it.playWhenReady }
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_MEDIA_FAST_FORWARD) {
            player?.seekForward()
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_MEDIA_REWIND) {
            player?.seekBack()
            return true
        }

        if (!isControllerVisible()) {
            isControllerShown = true
            playerView.showController()
            mainHandler.post {
                applyControlFocusStyles(playerView)
                focusInitialControl()
            }
            return true
        }

        applyControlFocusStyles(playerView)
        playerView.showController()

        val active = focusedControl?.takeIf { it.isShown && it.visibility == View.VISIBLE }
            ?: playerView.findFocus()?.takeIf { it !== playerView && it !== root && it.isShown }

        if (keyCode == KeyEvent.KEYCODE_DPAD_CENTER ||
            keyCode == KeyEvent.KEYCODE_ENTER ||
            keyCode == KeyEvent.KEYCODE_NUMPAD_ENTER
        ) {
            if (active != null && active.isClickable) {
                active.performClick()
            } else {
                player?.let { it.playWhenReady = !it.playWhenReady }
            }
            return true
        }

        if (active != null && active.id == exoProgressId() && player?.isCurrentMediaItemSeekable == true) {
            if (keyCode == KeyEvent.KEYCODE_DPAD_LEFT) {
                player?.seekBack()
                return true
            }
            if (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT) {
                player?.seekForward()
                return true
            }
        }

        val direction = when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> View.FOCUS_LEFT
            KeyEvent.KEYCODE_DPAD_RIGHT -> View.FOCUS_RIGHT
            KeyEvent.KEYCODE_DPAD_UP -> View.FOCUS_UP
            KeyEvent.KEYCODE_DPAD_DOWN -> View.FOCUS_DOWN
            else -> null
        }

        if (direction != null) {
            if (active == null) {
                focusInitialControl()
                return true
            }
            val next = findNextControl(active, direction)
            if (next != null) {
                selectControl(next)
            }
            return true
        }

        val down = KeyEvent(KeyEvent.ACTION_DOWN, keyCode)
        val up = KeyEvent(KeyEvent.ACTION_UP, keyCode)
        return playerView.dispatchKeyEvent(down) || playerView.dispatchKeyEvent(up)
    }

    @OptIn(UnstableApi::class)
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

                override fun onRenderedFirstFrame() {
                    sendState("ready")
                }
            })

            exoPlayer.setMediaItem(itemBuilder.build())
            exoPlayer.prepare()
            exoPlayer.playWhenReady = true
            mainHandler.post { applyControlFocusStyles(playerView) }
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
