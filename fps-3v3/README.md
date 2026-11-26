# FPS 3v3 Tactical (offline Android APK)
Push to branch `fps-3v3` (or run the workflow manually) -> Actions -> "Build FPS 3v3 APK" -> artifact `FPS3v3-debug-apk`.
The workflow downloads three.js r128 once at build time and bundles it into the APK assets, so the installed game never touches the network (no INTERNET permission).
Local build: `curl -o app/src/main/assets/three.min.js https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js && gradle wrapper --gradle-version 8.9 && ./gradlew assembleDebug`
