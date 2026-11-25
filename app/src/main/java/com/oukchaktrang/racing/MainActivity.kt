package com.oukchaktrang.racing

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import android.webkit.JavascriptInterface
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity(), SensorEventListener {

    private lateinit var webView: WebView
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null
    private lateinit var prefs: SharedPreferences

    // Tilt values forwarded to JS
    private var tiltX = 0f
    private var tiltY = 0f

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Keep screen on during gameplay
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Full-screen immersive
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
        }

        setContentView(R.layout.activity_main)
        webView = findViewById(R.id.webView)
        prefs = getSharedPreferences("racing_prefs", Context.MODE_PRIVATE)

        configureWebView()

        // Load game from assets (zero network required)
        webView.loadUrl("file:///android_asset/game/index.html")

        // Accelerometer setup
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        with(webView.settings) {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            mediaPlaybackRequiresUserGesture = false
            // Hardware-accelerated rendering
            setRenderPriority(WebSettings.RenderPriority.HIGH)
            // Disable text size adjustment
            textZoom = 100
            // Disable unnecessary features
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            loadWithOverviewMode = true
            useWideViewPort = true
        }
        // Enable hardware acceleration on the WebView layer
        webView.setLayerType(android.view.View.LAYER_TYPE_HARDWARE, null)
        // Attach JavaScript bridge
        webView.addJavascriptInterface(GameBridge(), "AndroidBridge")
    }

    override fun onResume() {
        super.onResume()
        accelerometer?.also { sensor ->
            sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        }
        webView.onResume()
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
        webView.onPause()
    }

    override fun onDestroy() {
        webView.destroy()
        super.onDestroy()
    }

    // ── Accelerometer ──────────────────────────────────────────────────────
    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
            tiltX = event.values[0]  // left/right tilt
            tiltY = event.values[1]  // forward/back tilt
            webView.post {
                webView.evaluateJavascript(
                    "window.onTilt && window.onTilt($tiltX, $tiltY);",
                    null
                )
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) { /* unused */ }

    // ── JavaScript ↔ Kotlin Bridge ─────────────────────────────────────────
    inner class GameBridge {

        @JavascriptInterface
        fun saveHighScore(score: Int) {
            val current = prefs.getInt("high_score", 0)
            if (score > current) {
                prefs.edit().putInt("high_score", score).apply()
            }
        }

        @JavascriptInterface
        fun getHighScore(): Int = prefs.getInt("high_score", 0)

        @JavascriptInterface
        fun saveSettings(quality: String, control: String) {
            prefs.edit()
                .putString("quality", quality)
                .putString("control", control)
                .apply()
        }

        @JavascriptInterface
        fun getSettings(): String {
            val q = prefs.getString("quality", "medium") ?: "medium"
            val c = prefs.getString("control", "buttons") ?: "buttons"
            return """{"quality":"$q","control":"$c"}"""
        }

        @JavascriptInterface
        fun vibrate(ms: Long) {
            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(ms)
            }
        }

        @JavascriptInterface
        fun getDeviceInfo(): String {
            val mem = Runtime.getRuntime().maxMemory() / (1024 * 1024)
            return """{"model":"${Build.MODEL}","maxMemMB":$mem}"""
        }
    }
}
