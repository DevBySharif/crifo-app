package com.crifo.crifo

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var drmPlayerPlugin: DrmPlayerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        drmPlayerPlugin = DrmPlayerPlugin(
            flutterEngine.dartExecutor,
            flutterEngine.renderer,
            applicationContext
        )
        drmPlayerPlugin?.start()
    }

    override fun onDestroy() {
        drmPlayerPlugin?.destroy()
        super.onDestroy()
    }
}
