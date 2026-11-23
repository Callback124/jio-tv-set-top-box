package com.anas.tv

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    private var texturePlayer: TextureMedia3Player? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        texturePlayer?.dispose()
        texturePlayer = TextureMedia3Player(
            applicationContext,
            this,
            flutterEngine.renderer,
            messenger
        )

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "anas_tv/media3_player",
            Media3PlayerFactory(messenger)
        )

        enableHighestRefreshRate()

        MethodChannel(messenger, "anas_tv/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> {
                    val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
                    val isTelevision = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    val hasLeanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    result.success(isTelevision || hasLeanback)
                }
                "setDisplayCutoutMode" -> {
                    val expandIntoCutout = call.arguments == true
                    runOnUiThread {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            val lp = window.attributes
                            lp.layoutInDisplayCutoutMode = if (expandIntoCutout) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
                                } else {
                                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                                }
                            } else {
                                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_DEFAULT
                            }
                            window.attributes = lp
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        enableHighestRefreshRate()
    }

    private fun enableHighestRefreshRate() {
        runOnUiThread {
            val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                @Suppress("DEPRECATION")
                windowManager.defaultDisplay
            } ?: return@runOnUiThread

            val lp = window.attributes
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val activeMode = currentDisplay.mode
                val bestMode = currentDisplay.supportedModes
                    .filter {
                        it.physicalWidth == activeMode.physicalWidth &&
                            it.physicalHeight == activeMode.physicalHeight
                    }
                    .maxByOrNull { it.refreshRate }
                if (bestMode != null && (lp.preferredDisplayModeId != bestMode.modeId || lp.preferredRefreshRate != bestMode.refreshRate)) {
                    lp.preferredDisplayModeId = bestMode.modeId
                    lp.preferredRefreshRate = bestMode.refreshRate
                    window.attributes = lp
                }
            } else if (lp.preferredRefreshRate != currentDisplay.refreshRate) {
                lp.preferredRefreshRate = currentDisplay.refreshRate
                window.attributes = lp
            }
        }
    }

    override fun onDestroy() {
        texturePlayer?.dispose()
        texturePlayer = null
        super.onDestroy()
    }
}

class Media3PlayerFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?> ?: emptyMap()
        return Media3PlayerView(context, params, messenger, viewId)
    }
}
