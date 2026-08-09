package com.fakegem.historylens

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.fakegem.historylens/orientation",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "defaultDisplayRotation" -> {
                    @Suppress("DEPRECATION")
                    val rotation = windowManager.defaultDisplay.rotation
                    result.success(rotation)
                }
                else -> result.notImplemented()
            }
        }
    }
}