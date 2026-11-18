package com.example.ui.screens

import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.util.Base64
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AspectRatio
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Dialpad
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.HighQuality
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Tv
import androidx.compose.material.icons.rounded.VolumeOff
import androidx.compose.material.icons.rounded.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import android.media.MediaDrm
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import coil.compose.AsyncImage
import coil.compose.AsyncImagePainter
import com.example.data.model.ChannelPlaybackInfo
import com.example.data.model.TvChannel
import com.example.data.model.TvProgram
import com.example.data.network.JioTvNetworkModule
import com.example.ui.theme.HdEmerald
import com.example.ui.theme.JioCrimson
import com.example.ui.viewmodel.PlaybackResolveState
import kotlinx.coroutines.delay
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

private val StbActiveProgramBrush = Brush.horizontalGradient(
    colors = listOf(Color(0xFF0099FF), Color(0xFF28C3FF), Color(0xFF007EE0))
)
private val StbBannerBrush = Brush.verticalGradient(
    colors = listOf(Color(0xEB222732), Color(0xF0111622), Color(0xF50B0E16))
)

@OptIn(UnstableApi::class)
@Composable
fun PlayerScreen(
    channel: TvChannel,
    playbackState: PlaybackResolveState,
    todayPrograms: List<TvProgram>,
    currentTimeMs: Long,
    isSearchOverlayOpen: Boolean,
    onBack: () -> Unit,
    onResolvePlayback: (Boolean) -> Unit,
    onZapChannel: (Int) -> Unit,
    onDialChannelNumber: (Int) -> Boolean,
    onOpenSearch: () -> Unit,
    onOpenGuide: () -> Unit,
    onOpenChannelDetail: (Int) -> Unit,
    onEnsureTodayEpg: (Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val resolvedPlaybackInfo = (playbackState as? PlaybackResolveState.Ready)?.info
    var useNpointFallback by remember(channel.id) { mutableStateOf(false) }
    val playbackInfo = remember(resolvedPlaybackInfo, channel.playbackInfo, useNpointFallback) {
        if (useNpointFallback && channel.playbackInfo?.streamUrl?.isNotBlank() == true) {
            channel.playbackInfo
        } else {
            resolvedPlaybackInfo
        }
    }

    var isBuffering by remember(channel.id) { mutableStateOf(true) }
    var isMuted by remember { mutableStateOf(false) }
    var playerError by remember(channel.id) { mutableStateOf<String?>(null) }
    var retryCounter by remember(channel.id) { mutableIntStateOf(0) }
    // Default stretched mode (RESIZE_MODE_FILL) as requested
    var resizeMode by remember { mutableIntStateOf(AspectRatioFrameLayout.RESIZE_MODE_FILL) }

    var showStbBanner by remember { mutableStateOf(true) }
    var showKeypad by remember { mutableStateOf(false) }
    var showSettingsModal by remember { mutableStateOf(false) }
    var videoTracks by remember(channel.id) { mutableStateOf<List<PlayerVideoTrackOption>>(emptyList()) }
    var audioTracks by remember(channel.id) { mutableStateOf<List<PlayerAudioTrackOption>>(emptyList()) }
    var hasVideoOverride by remember(channel.id) { mutableStateOf(false) }
    var hasAudioOverride by remember(channel.id) { mutableStateOf(false) }
    var userChoseAutoQuality by remember(channel.id) { mutableStateOf(false) }
    var lastInteractionMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var dialBuffer by remember { mutableStateOf("") }
    var dialFeedback by remember { mutableStateOf<String?>(null) }

    val focusRequester = remember { FocusRequester() }

    val markInteracted: () -> Unit = {
        lastInteractionMs = System.currentTimeMillis()
        showStbBanner = true
    }

    val handleDigitInput: (Char) -> Unit = { digit ->
        lastInteractionMs = System.currentTimeMillis()
        val updated = (dialBuffer + digit).takeLast(4)
        if (updated == "0000") {
            dialBuffer = ""
            dialFeedback = null
            showKeypad = false
            onOpenSearch()
        } else {
            dialBuffer = updated
            dialFeedback = null
        }
    }

    val commitDialBuffer: () -> Unit = {
        val trimmed = dialBuffer.trim()
        if (trimmed.isNotEmpty() && !trimmed.all { it == '0' }) {
            val number = trimmed.toIntOrNull()
            if (number != null) {
                val matched = onDialChannelNumber(number)
                if (!matched) {
                    dialFeedback = "Channel #$number not found"
                }
            }
            dialBuffer = ""
        } else if (trimmed == "0000") {
            dialBuffer = ""
            onOpenSearch()
        }
    }

    LaunchedEffect(channel.id) {
        onResolvePlayback(true)
        onEnsureTodayEpg(channel.id)
        showStbBanner = true
        lastInteractionMs = System.currentTimeMillis()
    }

    // Auto-hide Set-Top Box bottom banner after 6.5s of idle playback
    LaunchedEffect(showStbBanner, lastInteractionMs, showKeypad, showSettingsModal, isSearchOverlayOpen, dialBuffer) {
        if (showStbBanner && !showKeypad && !showSettingsModal && !isSearchOverlayOpen && dialBuffer.isEmpty()) {
            delay(6_500L)
            if (System.currentTimeMillis() - lastInteractionMs >= 6_400L) {
                showStbBanner = false
            }
        }
    }

    // Auto-tune dial buffer after 1.3s when entering non-0000 channel numbers
    LaunchedEffect(dialBuffer) {
        if (dialBuffer.isNotEmpty()) {
            delay(1_300L)
            if (dialBuffer == "0000") {
                dialBuffer = ""
                onOpenSearch()
            } else if (!dialBuffer.all { it == '0' }) {
                commitDialBuffer()
            } else {
                // Keep waiting briefly for 4th '0' or clear after timeout
                delay(1_500L)
                if (dialBuffer.all { it == '0' }) {
                    dialBuffer = ""
                }
            }
        }
    }

    LaunchedEffect(dialFeedback) {
        if (dialFeedback != null) {
            delay(2_200L)
            dialFeedback = null
        }
    }

    LaunchedEffect(Unit) {
        runCatching { focusRequester.requestFocus() }
    }

    BackHandler {
        when {
            showSettingsModal -> showSettingsModal = false
            showKeypad -> showKeypad = false
            showStbBanner -> showStbBanner = false
            else -> onBack()
        }
    }

    // True edge-to-edge display cutout + immersive fullscreen landscape (full width including notch/punch-hole!)
    DisposableEffect(Unit) {
        val window = activity?.window
        if (window != null) {
            WindowCompat.setDecorFitsSystemWindows(window, false)
            window.addFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                window.attributes = window.attributes.apply {
                    layoutInDisplayCutoutMode =
                        WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
            }
            val controller = WindowCompat.getInsetsController(window, window.decorView)
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller.hide(WindowInsetsCompat.Type.systemBars())

            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        }
        onDispose {
            val disposeWindow = activity?.window
            if (disposeWindow != null) {
                disposeWindow.clearFlags(WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS)
                WindowCompat.getInsetsController(disposeWindow, disposeWindow.decorView)
                    .show(WindowInsetsCompat.Type.systemBars())
            }
            activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }
    }

    val okHttpClient = remember {
        OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(20, TimeUnit.SECONDS)
            .followRedirects(true)
            .build()
    }

    val exoPlayer = remember(
        channel.id,
        playbackInfo?.streamUrl,
        playbackInfo?.cookie,
        playbackInfo?.clearKeyPairs,
        retryCounter
    ) {
        if (playbackInfo == null || playbackInfo.streamUrl.isBlank()) {
            null
        } else {
            buildConfiguredExoPlayer(
                context = context,
                okHttpClient = okHttpClient,
                playbackInfo = playbackInfo
            )
        }
    }

    val refreshTracks: (ExoPlayer) -> Unit = remember {
        { player ->
            val snapshot = extractTracksSnapshot(player)
            if (!userChoseAutoQuality && !snapshot.hasVideoOverride && snapshot.videoOptions.isNotEmpty()) {
                val highest = snapshot.videoOptions.first()
                player.trackSelectionParameters = player.trackSelectionParameters
                    .buildUpon()
                    .setForceHighestSupportedBitrate(true)
                    .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
                    .setMaxVideoBitrate(Int.MAX_VALUE)
                    .setOverrideForType(TrackSelectionOverride(highest.trackGroup, highest.trackIndex))
                    .build()
                val updated = extractTracksSnapshot(player)
                videoTracks = updated.videoOptions
                audioTracks = updated.audioOptions
                hasVideoOverride = updated.hasVideoOverride
                hasAudioOverride = updated.hasAudioOverride
            } else {
                videoTracks = snapshot.videoOptions
                audioTracks = snapshot.audioOptions
                hasVideoOverride = snapshot.hasVideoOverride
                hasAudioOverride = snapshot.hasAudioOverride
            }
        }
    }

    if (exoPlayer != null) {
        DisposableEffect(exoPlayer) {
            refreshTracks(exoPlayer)
            val listener = object : Player.Listener {
                override fun onPlaybackStateChanged(playbackStateCode: Int) {
                    isBuffering = playbackStateCode == Player.STATE_BUFFERING
                    refreshTracks(exoPlayer)
                }

                override fun onTracksChanged(tracks: Tracks) {
                    refreshTracks(exoPlayer)
                }

                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    refreshTracks(exoPlayer)
                }

                override fun onRenderedFirstFrame() {
                    refreshTracks(exoPlayer)
                }

                override fun onPlayerError(error: PlaybackException) {
                    isBuffering = false
                    val httpCode = findHttpResponseCode(error)
                    val fallbackUrl = channel.playbackInfo?.streamUrl.orEmpty()
                    if (!useNpointFallback &&
                        (httpCode == 451 || httpCode == 403 || httpCode == 410) &&
                        fallbackUrl.isNotBlank() &&
                        fallbackUrl != playbackInfo?.streamUrl
                    ) {
                        useNpointFallback = true
                        playerError = null
                        isBuffering = true
                        return
                    }
                    playerError = when (httpCode) {
                        451 -> "HTTP 451: JioTV CDN geo-restricted this stream (Indian IP required) or rejected the token. Use an Indian network/VPN, or try Next CH / Retry."
                        403 -> "HTTP 403: Stream token expired or access denied. Tap Retry to refresh __hdnea__ cookie."
                        404 -> "HTTP 404: Stream manifest not found for #${channel.id}."
                        else -> error.cause?.localizedMessage ?: error.localizedMessage ?: "Stream playback error (${error.errorCodeName})"
                    }
                }
            }
            exoPlayer.addListener(listener)
            exoPlayer.volume = if (isMuted) 0f else 1f
            onDispose {
                exoPlayer.removeListener(listener)
                exoPlayer.release()
            }
        }

        LaunchedEffect(isMuted, exoPlayer) {
            exoPlayer.volume = if (isMuted) 0f else 1f
        }

        LifecycleEventEffect(Lifecycle.Event.ON_PAUSE) {
            exoPlayer.playWhenReady = false
        }
        LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
            exoPlayer.playWhenReady = true
        }
    }

    val liveProgram = remember(todayPrograms, currentTimeMs) {
        todayPrograms.firstOrNull { it.isLiveAt(currentTimeMs) } ?: todayPrograms.firstOrNull()
    }
    val nextProgram = remember(todayPrograms, liveProgram) {
        if (liveProgram != null) {
            val idx = todayPrograms.indexOf(liveProgram)
            todayPrograms.getOrNull(idx + 1)
        } else {
            null
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { keyEvent ->
                if (isSearchOverlayOpen) return@onPreviewKeyEvent false
                if (keyEvent.type == KeyEventType.KeyDown) {
                    when (keyEvent.key) {
                        Key.Zero, Key.NumPad0 -> { handleDigitInput('0'); return@onPreviewKeyEvent true }
                        Key.One, Key.NumPad1 -> { handleDigitInput('1'); return@onPreviewKeyEvent true }
                        Key.Two, Key.NumPad2 -> { handleDigitInput('2'); return@onPreviewKeyEvent true }
                        Key.Three, Key.NumPad3 -> { handleDigitInput('3'); return@onPreviewKeyEvent true }
                        Key.Four, Key.NumPad4 -> { handleDigitInput('4'); return@onPreviewKeyEvent true }
                        Key.Five, Key.NumPad5 -> { handleDigitInput('5'); return@onPreviewKeyEvent true }
                        Key.Six, Key.NumPad6 -> { handleDigitInput('6'); return@onPreviewKeyEvent true }
                        Key.Seven, Key.NumPad7 -> { handleDigitInput('7'); return@onPreviewKeyEvent true }
                        Key.Eight, Key.NumPad8 -> { handleDigitInput('8'); return@onPreviewKeyEvent true }
                        Key.Nine, Key.NumPad9 -> { handleDigitInput('9'); return@onPreviewKeyEvent true }
                        Key.DirectionLeft -> {
                            markInteracted()
                            onZapChannel(-1)
                            return@onPreviewKeyEvent true
                        }
                        Key.DirectionRight -> {
                            markInteracted()
                            onZapChannel(1)
                            return@onPreviewKeyEvent true
                        }
                        Key.ChannelUp -> {
                            markInteracted()
                            onZapChannel(1)
                            return@onPreviewKeyEvent true
                        }
                        Key.ChannelDown -> {
                            markInteracted()
                            onZapChannel(-1)
                            return@onPreviewKeyEvent true
                        }
                        Key.Enter, Key.NumPadEnter, Key.DirectionCenter -> {
                            if (dialBuffer.isNotEmpty()) {
                                commitDialBuffer()
                            } else {
                                showStbBanner = !showStbBanner
                                if (showStbBanner) lastInteractionMs = System.currentTimeMillis()
                            }
                            return@onPreviewKeyEvent true
                        }
                    }
                }
                false
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null
            ) {
                showStbBanner = !showStbBanner
                if (showStbBanner) lastInteractionMs = System.currentTimeMillis()
            }
    ) {
        // Full-bleed edge-to-edge ExoPlayer surface (renders across punch-holes & notches)
        if (exoPlayer != null) {
            AndroidView(
                factory = { ctx ->
                    PlayerView(ctx).apply {
                        layoutParams = FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT,
                            ViewGroup.LayoutParams.MATCH_PARENT
                        )
                        useController = false
                        setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
                        setShutterBackgroundColor(android.graphics.Color.BLACK)
                        this.resizeMode = resizeMode
                        player = exoPlayer
                    }
                },
                update = { view ->
                    if (view.player !== exoPlayer) {
                        view.player = exoPlayer
                    }
                    view.resizeMode = resizeMode
                },
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("exoplayer_surface")
            )
        } else if (playbackState is PlaybackResolveState.Loading || playbackState is PlaybackResolveState.Idle) {
            Column(
                modifier = Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                CircularProgressIndicator(color = Color(0xFF00B4FF))
                Text(
                    text = "Tuning #${channel.id} ${channel.name}…",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White
                )
            }
        } else if (playbackState is PlaybackResolveState.Error) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .background(Color.Black.copy(alpha = 0.85f), RoundedCornerShape(16.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                    .padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = playbackState.message,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = {
                            playerError = null
                            isBuffering = true
                            onResolvePlayback(true)
                        },
                        modifier = Modifier.testTag("player_retry_button")
                    ) {
                        Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Retry")
                    }
                    Button(onClick = { onZapChannel(1) }) {
                        Text("Next CH")
                    }
                }
            }
        }

        if (isBuffering && playerError == null && exoPlayer != null) {
            CircularProgressIndicator(
                modifier = Modifier.align(Alignment.Center),
                color = Color(0xFF00B4FF)
            )
        }

        if (playerError != null) {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .widthIn(max = 460.dp)
                    .padding(horizontal = 24.dp)
                    .background(Color.Black.copy(alpha = 0.88f), RoundedCornerShape(16.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.35f), RoundedCornerShape(16.dp))
                    .padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = playerError.orEmpty(),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White,
                    maxLines = 4,
                    overflow = TextOverflow.Ellipsis
                )
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(
                        onClick = {
                            useNpointFallback = false
                            playerError = null
                            isBuffering = true
                            retryCounter++
                            onResolvePlayback(true)
                        },
                        modifier = Modifier.testTag("player_retry_button")
                    ) {
                        Icon(Icons.Rounded.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Retry Stream")
                    }
                    Button(onClick = { onZapChannel(1) }) {
                        Text("Next CH")
                    }
                }
            }
        }

        // Top-right Channel Number Input OSD (full-width edge-to-edge including cutout side)
        if (dialBuffer.isNotEmpty() || dialFeedback != null) {
            Surface(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 14.dp, end = 16.dp)
                    .testTag("stb_channel_dial_osd"),
                shape = RoundedCornerShape(8.dp),
                color = Color(0xD9333842),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.5f)),
                shadowElevation = 8.dp
            ) {
                Text(
                    text = dialFeedback ?: "${dialBuffer}_",
                    color = Color.White,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp)
                )
            }
        }

        // Top-Right Quick Pill Controls
        AnimatedVisibility(
            visible = showStbBanner,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            Surface(
                shape = RoundedCornerShape(24.dp),
                color = Color(0x990D111A),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.3f))
            ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                        modifier = Modifier.padding(horizontal = 4.dp)
                    ) {
                        IconButton(
                            onClick = {
                                markInteracted()
                                showKeypad = !showKeypad
                            },
                            modifier = Modifier
                                .minimumInteractiveComponentSize()
                                .testTag("player_keypad_toggle")
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Dialpad,
                                contentDescription = "Channel Number Keypad",
                                tint = if (showKeypad) Color(0xFF4CC3FF) else Color.White
                            )
                        }
                        IconButton(
                            onClick = {
                                markInteracted()
                                isMuted = !isMuted
                            },
                            modifier = Modifier.minimumInteractiveComponentSize()
                        ) {
                            Icon(
                                imageVector = if (isMuted) Icons.Rounded.VolumeOff else Icons.Rounded.VolumeUp,
                                contentDescription = if (isMuted) "Unmute" else "Mute",
                                tint = Color.White
                            )
                        }
                        IconButton(
                            onClick = {
                                markInteracted()
                                resizeMode = when (resizeMode) {
                                    AspectRatioFrameLayout.RESIZE_MODE_FILL -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                                    AspectRatioFrameLayout.RESIZE_MODE_FIT -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                                    else -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                                }
                            },
                            modifier = Modifier
                                .minimumInteractiveComponentSize()
                                .testTag("player_aspect_button")
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.AspectRatio,
                                contentDescription = "Toggle Stretched / Fit / Zoom",
                                tint = Color.White
                            )
                        }
                        IconButton(
                            onClick = {
                                markInteracted()
                                if (exoPlayer != null) refreshTracks(exoPlayer)
                                showSettingsModal = true
                            },
                            modifier = Modifier
                                .minimumInteractiveComponentSize()
                                .testTag("player_settings_button")
                        ) {
                            Icon(
                                imageVector = Icons.Rounded.Settings,
                                contentDescription = "Player settings",
                                tint = if (showSettingsModal) Color(0xFF4CC3FF) else Color.White
                            )
                        }
                    }
                }
        }

        // Optional Touch Remote 0-9 Dialer Pad (for channel dialing + 0000 Search trigger)
        AnimatedVisibility(
            visible = showKeypad,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.CenterEnd)
                .padding(end = 12.dp)
        ) {
            StbRemoteKeypad(
                onDigit = handleDigitInput,
                onOk = commitDialBuffer,
                onBackspace = {
                    if (dialBuffer.isNotEmpty()) dialBuffer = dialBuffer.dropLast(1)
                },
                onZeroFourTimes = {
                    dialBuffer = ""
                    showKeypad = false
                    onOpenSearch()
                }
            )
        }

        // Bottom Set-Top Box Info Banner with clean horizontal & bottom margins
        AnimatedVisibility(
            visible = showStbBanner,
            enter = fadeIn() + slideInVertically { it / 2 },
            exit = fadeOut() + slideOutVertically { it / 2 },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp)
        ) {
            StbPlayerInfoBanner(
                channel = channel,
                liveProgram = liveProgram,
                nextProgram = nextProgram,
                currentTimeMs = currentTimeMs,
                onZapPrev = {
                    markInteracted()
                    onZapChannel(-1)
                },
                onZapNext = {
                    markInteracted()
                    onZapChannel(1)
                },
                onOpenSearch = {
                    markInteracted()
                    onOpenSearch()
                },
                onOpenGenres = {
                    markInteracted()
                    onOpenGuide()
                },
                onOpenCatchup = {
                    markInteracted()
                    onOpenChannelDetail(channel.id)
                },
                onOpenKeypad = {
                    markInteracted()
                    showKeypad = !showKeypad
                }
            )
        }

        // Centered Player Settings Modal (Quality & Audio tabs)
        if (showSettingsModal) {
            StbPlayerSettingsModal(
                videoTracks = videoTracks,
                audioTracks = audioTracks,
                hasVideoOverride = hasVideoOverride,
                hasAudioOverride = hasAudioOverride,
                userChoseAutoQuality = userChoseAutoQuality,
                isMuted = isMuted,
                onToggleMute = { isMuted = !isMuted },
                onSelectAutoQuality = {
                    userChoseAutoQuality = true
                    exoPlayer?.let { player ->
                        player.trackSelectionParameters = player.trackSelectionParameters
                            .buildUpon()
                            .setForceHighestSupportedBitrate(false)
                            .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
                            .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
                            .setMaxVideoBitrate(Int.MAX_VALUE)
                            .build()
                        refreshTracks(player)
                    }
                },
                onSelectVideoTrack = { option ->
                    userChoseAutoQuality = false
                    exoPlayer?.let { player ->
                        player.trackSelectionParameters = player.trackSelectionParameters
                            .buildUpon()
                            .setMaxVideoSize(Int.MAX_VALUE, Int.MAX_VALUE)
                            .setMaxVideoBitrate(Int.MAX_VALUE)
                            .setOverrideForType(TrackSelectionOverride(option.trackGroup, option.trackIndex))
                            .build()
                        refreshTracks(player)
                    }
                },
                onSelectAutoAudio = {
                    exoPlayer?.let { player ->
                        player.trackSelectionParameters = player.trackSelectionParameters
                            .buildUpon()
                            .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                            .build()
                        refreshTracks(player)
                    }
                },
                onSelectAudioTrack = { option ->
                    exoPlayer?.let { player ->
                        player.trackSelectionParameters = player.trackSelectionParameters
                            .buildUpon()
                            .setOverrideForType(TrackSelectionOverride(option.trackGroup, option.trackIndex))
                            .build()
                        refreshTracks(player)
                    }
                },
                onDismiss = { showSettingsModal = false }
            )
        }
    }
}

private data class PlayerVideoTrackOption(
    val id: String,
    val label: String,
    val detail: String,
    val height: Int,
    val bitrate: Int,
    val trackGroup: TrackGroup,
    val trackIndex: Int,
    val isSelected: Boolean
)

private data class PlayerAudioTrackOption(
    val id: String,
    val label: String,
    val detail: String,
    val trackGroup: TrackGroup,
    val trackIndex: Int,
    val isSelected: Boolean
)

private data class TracksSnapshot(
    val videoOptions: List<PlayerVideoTrackOption>,
    val audioOptions: List<PlayerAudioTrackOption>,
    val hasVideoOverride: Boolean,
    val hasAudioOverride: Boolean
)

@OptIn(UnstableApi::class)
private fun extractTracksSnapshot(player: ExoPlayer): TracksSnapshot {
    val videoList = mutableListOf<PlayerVideoTrackOption>()
    val audioList = mutableListOf<PlayerAudioTrackOption>()

    player.currentTracks.groups.forEachIndexed { groupIdx, group ->
        when (group.type) {
            C.TRACK_TYPE_VIDEO -> {
                for (i in 0 until group.length) {
                    if (!group.isTrackSupported(i)) continue
                    val fmt = group.getTrackFormat(i)
                    val tier = when {
                        fmt.height >= 2160 -> "4K UHD"
                        fmt.height >= 1080 -> "Full HD"
                        fmt.height >= 720 -> "HD"
                        fmt.height > 0 -> "SD"
                        else -> "Adaptive"
                    }
                    val label = if (fmt.height > 0) {
                        "${fmt.height}p • $tier"
                    } else if (fmt.bitrate > 0) {
                        "${fmt.bitrate / 1000} kbps"
                    } else {
                        "Quality ${videoList.size + 1}"
                    }
                    val detailParts = buildList {
                        if (fmt.width > 0 && fmt.height > 0) add("${fmt.width}×${fmt.height}")
                        if (fmt.bitrate > 0) add("${fmt.bitrate / 1000} kbps")
                        if (fmt.frameRate > 0f) add("${fmt.frameRate.toInt()} fps")
                    }
                    videoList += PlayerVideoTrackOption(
                        id = "${groupIdx}_${i}_${fmt.height}_${fmt.bitrate}",
                        label = label,
                        detail = detailParts.joinToString(" • ").ifBlank { "Stream variant" },
                        height = fmt.height,
                        bitrate = fmt.bitrate,
                        trackGroup = group.mediaTrackGroup,
                        trackIndex = i,
                        isSelected = group.isTrackSelected(i)
                    )
                }
            }

            C.TRACK_TYPE_AUDIO -> {
                for (i in 0 until group.length) {
                    val support = group.getTrackSupport(i)
                    if (support == C.FORMAT_UNSUPPORTED_TYPE || support == C.FORMAT_UNSUPPORTED_SUBTYPE) {
                        continue
                    }
                    val fmt = group.getTrackFormat(i)
                    val langDisplay = fmt.language
                        ?.takeIf { it.isNotBlank() && !it.equals("und", ignoreCase = true) }
                        ?.let { code ->
                            Locale(code).displayLanguage.replaceFirstChar { ch -> ch.titlecase(Locale.getDefault()) }
                        }
                    val label = fmt.label?.takeIf { it.isNotBlank() }
                        ?: langDisplay
                        ?: "Audio Track ${audioList.size + 1}"
                    val channelsText = when (fmt.channelCount) {
                        1 -> "Mono"
                        2 -> "Stereo"
                        6 -> "5.1 Surround"
                        else -> if (fmt.channelCount > 0) "${fmt.channelCount} ch" else ""
                    }
                    val detailParts = buildList {
                        if (channelsText.isNotEmpty()) add(channelsText)
                        if (fmt.bitrate > 0) add("${fmt.bitrate / 1000} kbps")
                        if (!fmt.codecs.isNullOrBlank()) add(fmt.codecs.orEmpty())
                    }
                    audioList += PlayerAudioTrackOption(
                        id = "${groupIdx}_${i}_${fmt.id ?: label}",
                        label = label,
                        detail = detailParts.joinToString(" • ").ifBlank { "Default audio stream" },
                        trackGroup = group.mediaTrackGroup,
                        trackIndex = i,
                        isSelected = group.isTrackSelected(i)
                    )
                }
            }
        }
    }

    val sortedVideo = videoList
        .sortedWith(compareByDescending<PlayerVideoTrackOption> { it.height }.thenByDescending { it.bitrate })
        .distinctBy { if (it.height > 0 || it.bitrate > 0) "${it.height}_${it.bitrate}" else it.id }

    val overrides = player.trackSelectionParameters.overrides.values
    return TracksSnapshot(
        videoOptions = sortedVideo,
        audioOptions = audioList,
        hasVideoOverride = overrides.any { it.type == C.TRACK_TYPE_VIDEO },
        hasAudioOverride = overrides.any { it.type == C.TRACK_TYPE_AUDIO }
    )
}

@Composable
private fun StbPlayerSettingsModal(
    videoTracks: List<PlayerVideoTrackOption>,
    audioTracks: List<PlayerAudioTrackOption>,
    hasVideoOverride: Boolean,
    hasAudioOverride: Boolean,
    userChoseAutoQuality: Boolean,
    isMuted: Boolean,
    onToggleMute: () -> Unit,
    onSelectAutoQuality: () -> Unit,
    onSelectVideoTrack: (PlayerVideoTrackOption) -> Unit,
    onSelectAutoAudio: () -> Unit,
    onSelectAudioTrack: (PlayerAudioTrackOption) -> Unit,
    onDismiss: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.6f))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onDismiss
            )
            .testTag("player_settings_modal"),
        contentAlignment = Alignment.Center
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.9f)
                .widthIn(max = 440.dp)
                .heightIn(max = 330.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = {}
                ),
            shape = RoundedCornerShape(14.dp),
            color = Color(0xF5111622),
            border = BorderStroke(1.5.dp, Color.White.copy(alpha = 0.5f)),
            shadowElevation = 18.dp
        ) {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Top 2 Tabs: Quality & Audio + Close
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color(0xFF1A202E))
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    SettingsModalTab(
                        label = "Quality",
                        icon = Icons.Rounded.HighQuality,
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("player_settings_tab_quality")
                    )
                    SettingsModalTab(
                        label = "Audio",
                        icon = Icons.Rounded.GraphicEq,
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        modifier = Modifier
                            .weight(1f)
                            .testTag("player_settings_tab_audio")
                    )
                    IconButton(
                        onClick = onDismiss,
                        modifier = Modifier
                            .minimumInteractiveComponentSize()
                            .testTag("player_settings_close")
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.Close,
                            contentDescription = "Close settings",
                            tint = Color.White
                        )
                    }
                }

                HorizontalDivider(color = Color.White.copy(alpha = 0.16f))

                // Tab content below
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .verticalScroll(rememberScrollState())
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    if (selectedTab == 0) {
                        if (videoTracks.isEmpty()) {
                            SettingsTrackRow(
                                title = "Highest Quality (Default)",
                                subtitle = "Automatically locks to maximum supported bitrate",
                                selected = !userChoseAutoQuality,
                                badge = "DEFAULT",
                                onClick = {
                                    videoTracks.firstOrNull()?.let(onSelectVideoTrack)
                                },
                                modifier = Modifier.testTag("player_quality_highest_placeholder")
                            )
                        } else {
                            videoTracks.forEachIndexed { index, track ->
                                SettingsTrackRow(
                                    title = track.label,
                                    subtitle = track.detail,
                                    selected = hasVideoOverride && track.isSelected,
                                    badge = when {
                                        index == 0 -> "HIGHEST"
                                        track.isSelected && !hasVideoOverride -> "ACTIVE"
                                        else -> null
                                    },
                                    onClick = { onSelectVideoTrack(track) },
                                    modifier = Modifier.testTag("player_quality_track_$index")
                                )
                            }
                        }
                        SettingsTrackRow(
                            title = "Auto (Adaptive)",
                            subtitle = "Adjusts quality dynamically based on network speed",
                            selected = userChoseAutoQuality && !hasVideoOverride,
                            onClick = onSelectAutoQuality,
                            modifier = Modifier.testTag("player_quality_auto")
                        )
                    } else {
                        SettingsTrackRow(
                            title = if (isMuted) "Sound Muted (Tap to Unmute)" else "Sound On (Tap to Mute)",
                            subtitle = if (isMuted) "Player audio output is muted" else "Audio output at full volume",
                            selected = isMuted,
                            badge = if (isMuted) "MUTED" else "ON",
                            onClick = onToggleMute,
                            modifier = Modifier.testTag("player_audio_mute_toggle")
                        )
                        SettingsTrackRow(
                            title = "Auto (Default Audio)",
                            subtitle = "Uses channel default language audio track",
                            selected = !hasAudioOverride,
                            onClick = onSelectAutoAudio,
                            modifier = Modifier.testTag("player_audio_auto")
                        )
                        if (audioTracks.isEmpty()) {
                            Text(
                                text = "Default audio stream active.",
                                color = Color.White.copy(alpha = 0.72f),
                                fontSize = 12.sp,
                                modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp)
                            )
                        } else {
                            audioTracks.forEachIndexed { index, track ->
                                SettingsTrackRow(
                                    title = track.label,
                                    subtitle = track.detail,
                                    selected = hasAudioOverride && track.isSelected,
                                    badge = if (track.isSelected && !hasAudioOverride) "ACTIVE" else null,
                                    onClick = { onSelectAudioTrack(track) },
                                    modifier = Modifier.testTag("player_audio_track_$index")
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SettingsModalTab(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .height(44.dp)
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(10.dp),
        color = if (selected) Color(0xFF0099FF) else Color(0xFF252D3F),
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) Color(0xFF9DE3FF) else Color.White.copy(alpha = 0.25f)
        )
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = if (selected) Color.Black else Color.White,
                modifier = Modifier.size(18.dp)
            )
            Spacer(Modifier.width(6.dp))
            Text(
                text = label,
                color = if (selected) Color.Black else Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@Composable
private fun SettingsTrackRow(
    title: String,
    subtitle: String,
    selected: Boolean,
    badge: String? = null,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(10.dp),
        color = if (selected) Color(0x330099FF) else Color(0xFF1A202D),
        border = BorderStroke(
            width = 1.dp,
            color = if (selected) Color(0xFF4CC3FF) else Color.White.copy(alpha = 0.16f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Icon(
                imageVector = if (selected) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked,
                contentDescription = if (selected) "Selected" else "Not selected",
                tint = if (selected) Color(0xFF4CC3FF) else Color.White.copy(alpha = 0.5f),
                modifier = Modifier.size(20.dp)
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    color = Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (subtitle.isNotBlank()) {
                    Text(
                        text = subtitle,
                        color = Color.White.copy(alpha = 0.72f),
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (!badge.isNullOrBlank()) {
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = Color(0xFF0088E8)
                ) {
                    Text(
                        text = badge,
                        color = Color.White,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun StbPlayerInfoBanner(
    channel: TvChannel,
    liveProgram: TvProgram?,
    nextProgram: TvProgram?,
    currentTimeMs: Long,
    onZapPrev: () -> Unit,
    onZapNext: () -> Unit,
    onOpenSearch: () -> Unit,
    onOpenGenres: () -> Unit,
    onOpenCatchup: () -> Unit,
    onOpenKeypad: () -> Unit
) {
    val dateTimeText = remember(currentTimeMs / 30_000L) {
        SimpleDateFormat("EEE dd MMM hh:mm a", Locale.getDefault()).format(Date(currentTimeMs))
    }
    val progress = liveProgram?.progressAt(currentTimeMs) ?: 0.35f
    val programImageUrl = remember(liveProgram, channel) {
        liveProgram?.thumbnailUrl?.takeIf { it.isNotBlank() }
            ?: liveProgram?.posterUrl?.takeIf { it.isNotBlank() }
            ?: channel.logoUrl
    }

    var primaryArtFailed by remember(programImageUrl) { mutableStateOf(false) }
    var fallbackArtFailed by remember(channel.logoUrl) { mutableStateOf(false) }

    // Full-width bottom container inside normal horizontal & bottom gaps
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(StbBannerBrush)
            .border(
                width = 1.dp,
                color = Color.White.copy(alpha = 0.5f),
                shape = RoundedCornerShape(10.dp)
            ),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Left Program Artwork inside the same bottom container — stretched so full image is visible
        Box(
            modifier = Modifier
                .padding(start = 6.dp, top = 6.dp, bottom = 6.dp, end = 6.dp)
                .width(148.dp)
                .height(106.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Color(0xFF161D2B))
                .clickable(onClick = onOpenCatchup)
                .testTag("stb_banner_program_image"),
            contentAlignment = Alignment.Center
        ) {
            if (!primaryArtFailed && programImageUrl.isNotBlank()) {
                AsyncImage(
                    model = programImageUrl,
                    contentDescription = liveProgram?.title ?: "${channel.name} program art",
                    contentScale = ContentScale.FillBounds,
                    modifier = Modifier.fillMaxSize(),
                    onState = { state ->
                        if (state is AsyncImagePainter.State.Error) {
                            primaryArtFailed = true
                        }
                    }
                )
            } else if (!fallbackArtFailed && channel.logoUrl.isNotBlank()) {
                AsyncImage(
                    model = channel.logoUrl,
                    contentDescription = channel.name,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(10.dp),
                    onState = { state ->
                        if (state is AsyncImagePainter.State.Error) {
                            fallbackArtFailed = true
                        }
                    }
                )
            } else {
                Icon(
                    imageVector = Icons.Rounded.Tv,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.55f),
                    modifier = Modifier.size(30.dp)
                )
            }
        }

        // Right Program Details & Controls inside the exact same bottom container
        Column(modifier = Modifier.weight(1f)) {
            // Channel Header Row: < 165  Channel Name >   |   Mon 18 Nov 11:42 am
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF1A1F2B))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.weight(1f)
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowLeft,
                        contentDescription = "Previous channel",
                        tint = Color.White,
                        modifier = Modifier
                            .size(22.dp)
                            .clip(CircleShape)
                            .clickable(onClick = onZapPrev)
                            .testTag("stb_prev_channel")
                    )
                    Text(
                        text = "${channel.id}   ${channel.name}",
                        color = Color.White,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.ExtraBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false)
                    )
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.KeyboardArrowRight,
                        contentDescription = "Next channel",
                        tint = Color.White,
                        modifier = Modifier
                            .size(22.dp)
                            .clip(CircleShape)
                            .clickable(onClick = onZapNext)
                            .testTag("stb_next_channel")
                    )
                }

                Text(
                    text = dateTimeText,
                    color = Color.White.copy(alpha = 0.92f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold
                )
            }

            // Row 1: Current Live Show (Glowing Blue Highlight)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(StbActiveProgramBrush)
                    .clickable(onClick = onOpenCatchup)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = liveProgram?.title ?: "${channel.name} Live Stream",
                    color = Color.Black,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                Spacer(Modifier.width(10.dp))
                Text(
                    text = if (liveProgram != null) {
                        "${liveProgram.startTimeFormatted} - ${liveProgram.endTimeFormatted}"
                    } else {
                        "LIVE NOW"
                    },
                    color = Color.Black,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold
                )
            }

            // Row 2: Next Show
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF141923))
                    .clickable(onClick = onOpenCatchup)
                    .padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = nextProgram?.title ?: "Tap for 15-Day EPG & Catch-Up Schedule",
                    color = Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f)
                )
                if (nextProgram != null) {
                    Spacer(Modifier.width(10.dp))
                    Text(
                        text = "${nextProgram.startTimeFormatted} - ${nextProgram.endTimeFormatted}",
                        color = Color.White.copy(alpha = 0.9f),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
            }

            // Row 3: Progress Bar + Color Action Hotkeys (0 Search | Genres | Catch-Up | Language)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF0D1119))
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                // Classic green progress bar
                Box(
                    modifier = Modifier
                        .width(96.dp)
                        .height(9.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .background(Color(0xFF283040))
                        .border(1.dp, Color.White.copy(alpha = 0.55f), RoundedCornerShape(5.dp))
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth(progress.coerceIn(0.05f, 1f))
                            .height(9.dp)
                            .background(Color(0xFF39D353))
                    )
                }

                Row(
                    modifier = Modifier.weight(1f),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StbBannerActionChip(
                        dotColor = JioCrimson,
                        label = "Search",
                        onClick = onOpenSearch,
                        modifier = Modifier.testTag("stb_banner_search")
                    )
                    StbBannerActionChip(
                        dotColor = HdEmerald,
                        label = "Genres",
                        onClick = onOpenGenres,
                        modifier = Modifier.testTag("stb_banner_genres")
                    )
                    StbBannerActionChip(
                        dotColor = Color(0xFFFFC107),
                        label = "Catch-Up",
                        onClick = onOpenCatchup,
                        modifier = Modifier.testTag("stb_banner_catchup")
                    )
                    StbBannerActionChip(
                        dotColor = Color(0xFF0099FF),
                        label = channel.languageName,
                        onClick = onOpenKeypad,
                        modifier = Modifier.testTag("stb_banner_language")
                    )
                }
            }
        }
    }
}

@Composable
private fun StbBannerActionChip(
    badgeText: String? = null,
    dotColor: Color? = null,
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 5.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        if (dotColor != null) {
            Box(
                modifier = Modifier
                    .size(11.dp)
                    .clip(CircleShape)
                    .background(dotColor)
                    .border(1.dp, Color.White.copy(alpha = 0.8f), CircleShape)
            )
        } else if (badgeText != null) {
            Surface(
                shape = CircleShape,
                color = Color(0xFF232B3A),
                border = BorderStroke(1.dp, Color.White.copy(alpha = 0.8f))
            ) {
                Text(
                    text = badgeText,
                    color = Color.White,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp)
                )
            }
        }
        Text(
            text = label,
            color = Color.White,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
private fun StbRemoteKeypad(
    onDigit: (Char) -> Unit,
    onOk: () -> Unit,
    onBackspace: () -> Unit,
    onZeroFourTimes: () -> Unit
) {
    val rows = listOf(
        listOf('1', '2', '3'),
        listOf('4', '5', '6'),
        listOf('7', '8', '9')
    )
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = Color(0xE6141925),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.45f)),
        shadowElevation = 12.dp
    ) {
        Column(
            modifier = Modifier
                .width(172.dp)
                .padding(10.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Channel # / 0000 Search",
                color = Color(0xFF4CC3FF),
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold
            )
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp)
                ) {
                    row.forEach { digit ->
                        StbKeypadButton(
                            label = digit.toString(),
                            onClick = { onDigit(digit) },
                            modifier = Modifier.weight(1f)
                        )
                    }
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                StbKeypadButton(
                    label = "⌫",
                    onClick = onBackspace,
                    modifier = Modifier.weight(1f)
                )
                StbKeypadButton(
                    label = "0",
                    onClick = { onDigit('0') },
                    modifier = Modifier
                        .weight(1f)
                        .testTag("stb_keypad_zero")
                )
                StbKeypadButton(
                    label = "OK",
                    onClick = onOk,
                    highlight = true,
                    modifier = Modifier.weight(1f)
                )
            }
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClick = onZeroFourTimes)
                    .testTag("stb_keypad_0000"),
                shape = RoundedCornerShape(8.dp),
                color = Color(0xFF007ACC)
            ) {
                Text(
                    text = "0000 Search",
                    color = Color.White,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(vertical = 6.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun StbKeypadButton(
    label: String,
    onClick: () -> Unit,
    highlight: Boolean = false,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier
            .height(34.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(6.dp),
        color = if (highlight) Color(0xFF0099FF) else Color(0xFF262E3F),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.35f))
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(
                text = label,
                color = if (highlight) Color.Black else Color.White,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}

@OptIn(UnstableApi::class)
private fun buildConfiguredExoPlayer(
    context: android.content.Context,
    okHttpClient: OkHttpClient,
    playbackInfo: ChannelPlaybackInfo
): ExoPlayer {
    val requestHeaders = LinkedHashMap<String, String>()
    playbackInfo.headers.forEach { (k, v) ->
        if (!k.equals("user-agent", ignoreCase = true) && !k.equals("cookie", ignoreCase = true)) {
            requestHeaders[k] = v
        }
    }
    val userAgent = playbackInfo.userAgent.ifBlank {
        playbackInfo.headers["User-Agent"]
            ?: playbackInfo.headers["user-agent"]
            ?: JioTvNetworkModule.MOBILE_CHROME_USER_AGENT
    }
    val cookie = playbackInfo.cookie.ifBlank {
        playbackInfo.headers["Cookie"]
            ?: playbackInfo.headers["cookie"]
            ?: ""
    }

    val playerOkHttpClient = okHttpClient.newBuilder()
        .addInterceptor { chain ->
            val reqBuilder = chain.request().newBuilder()
                .header("User-Agent", userAgent)
            if (cookie.isNotBlank()) {
                reqBuilder.header("Cookie", cookie)
            }
            requestHeaders.forEach { (k, v) ->
                reqBuilder.header(k, v)
            }
            chain.proceed(reqBuilder.build())
        }
        .build()

    val httpDataSourceFactory = OkHttpDataSource.Factory(playerOkHttpClient)
        .setUserAgent(userAgent)
        .apply {
            val props = LinkedHashMap<String, String>(requestHeaders)
            if (cookie.isNotBlank()) props["Cookie"] = cookie
            if (props.isNotEmpty()) {
                setDefaultRequestProperties(props)
            }
        }

    val mediaSourceFactory = DefaultMediaSourceFactory(httpDataSourceFactory)

    if (playbackInfo.drmScheme.contains("clearkey", ignoreCase = true) &&
        playbackInfo.clearKeyPairs.isNotEmpty() &&
        runCatching { MediaDrm.isCryptoSchemeSupported(C.CLEARKEY_UUID) }.getOrDefault(false)
    ) {
        runCatching {
            val clearKeyJson = buildClearKeyJsonBytes(playbackInfo.clearKeyPairs)
            val drmCallback = LocalMediaDrmCallback(clearKeyJson)
            val drmSessionManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.CLEARKEY_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .setMultiSession(true)
                .build(drmCallback)
            mediaSourceFactory.setDrmSessionManagerProvider { drmSessionManager }
        }
    } else if (playbackInfo.licenseUrl.isNotBlank() &&
        playbackInfo.drmScheme.contains("widevine", ignoreCase = true) &&
        runCatching { MediaDrm.isCryptoSchemeSupported(C.WIDEVINE_UUID) }.getOrDefault(false)
    ) {
        runCatching {
            val drmCallback = HttpMediaDrmCallback(playbackInfo.licenseUrl, httpDataSourceFactory).apply {
                if (cookie.isNotBlank()) setKeyRequestProperty("Cookie", cookie)
                requestHeaders.forEach { (k, v) -> setKeyRequestProperty(k, v) }
            }
            val drmSessionManager = DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(C.WIDEVINE_UUID, FrameworkMediaDrm.DEFAULT_PROVIDER)
                .setMultiSession(true)
                .build(drmCallback)
            mediaSourceFactory.setDrmSessionManagerProvider { drmSessionManager }
        }
    }

    val mimeType = when {
        playbackInfo.mimeTypeHint.contains("mpd", ignoreCase = true) ||
            playbackInfo.mimeTypeHint.contains("dash", ignoreCase = true) ||
            playbackInfo.streamUrl.contains(".mpd", ignoreCase = true) -> MimeTypes.APPLICATION_MPD
        playbackInfo.mimeTypeHint.contains("m3u8", ignoreCase = true) ||
            playbackInfo.mimeTypeHint.contains("hls", ignoreCase = true) ||
            playbackInfo.streamUrl.contains(".m3u8", ignoreCase = true) -> MimeTypes.APPLICATION_M3U8
        else -> null
    }

    val mediaItemBuilder = MediaItem.Builder()
        .setUri(playbackInfo.streamUrl)
        .apply {
            if (mimeType != null) setMimeType(mimeType)
            if (playbackInfo.licenseUrl.isNotBlank() &&
                !playbackInfo.drmScheme.contains("clearkey", ignoreCase = true)
            ) {
                val drmUuid = when {
                    playbackInfo.drmScheme.contains("playready", ignoreCase = true) -> C.PLAYREADY_UUID
                    else -> C.WIDEVINE_UUID
                }
                setDrmConfiguration(
                    MediaItem.DrmConfiguration.Builder(drmUuid)
                        .setLicenseUri(playbackInfo.licenseUrl)
                        .setLicenseRequestHeaders(requestHeaders)
                        .setMultiSession(true)
                        .build()
                )
            }
        }

    return ExoPlayer.Builder(context)
        .setMediaSourceFactory(mediaSourceFactory)
        .build()
        .apply {
            trackSelectionParameters = trackSelectionParameters
                .buildUpon()
                .setForceHighestSupportedBitrate(true)
                .build()
            setMediaItem(mediaItemBuilder.build())
            playWhenReady = true
            prepare()
        }
}

private fun buildClearKeyJsonBytes(clearKeyPairs: Map<String, String>): ByteArray {
    val keysArray = JSONArray()
    clearKeyPairs.forEach { (rawKid, rawKey) ->
        val kidB64 = hexOrBase64ToBase64Url(rawKid)
        val keyB64 = hexOrBase64ToBase64Url(rawKey)
        keysArray.put(
            JSONObject().apply {
                put("kty", "oct")
                put("kid", kidB64)
                put("k", keyB64)
            }
        )
    }
    val payload = JSONObject().apply {
        put("keys", keysArray)
        put("type", "temporary")
    }
    return payload.toString().toByteArray(Charsets.UTF_8)
}

private fun findHttpResponseCode(error: Throwable?): Int? {
    var current: Throwable? = error
    var depth = 0
    while (current != null && depth < 10) {
        if (current is HttpDataSource.InvalidResponseCodeException) {
            return current.responseCode
        }
        current = current.cause
        depth++
    }
    return null
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
