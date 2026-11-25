# Keep WebView JavaScript interface
-keepclassmembers class com.oukchaktrang.racing.** {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.oukchaktrang.racing.GameBridge { *; }
