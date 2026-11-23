package com.anas.tv

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
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

        MethodChannel(messenger, "anas_tv/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> {
                    val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
                    val isTelevision = uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
                    val hasLeanback = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                    result.success(isTelevision || hasLeanback)
                }
                else -> result.notImplemented()
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
