package com.oukchaktrang.ouk_chaktrang

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ouk/native")
            .setMethodCallHandler { call, result ->
                if (call.method == "nativeLibDir") {
                    result.success(applicationInfo.nativeLibraryDir)
                } else {
                    result.notImplemented()
                }
            }
    }
}
