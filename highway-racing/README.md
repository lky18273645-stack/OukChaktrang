# Highway Rush - 3D offline highway racing (Android, landscape)

Raw WebGL engine inside a hardware-accelerated WebView. No external assets, no libraries, APK well under 5 MB.
Build: GitHub Actions workflow `.github/workflows/build-racing-apk.yml` (Java 17, Gradle 8.7, AGP 8.5.2).

Add to the repo (run in Termux, inside your OukChaktrang clone):

    unzip -o ~/storage/downloads/highway-racing-addon.zip
    git add .github/workflows/build-racing-apk.yml highway-racing
    git commit -m "Add 3D Highway Racing APK project"
    git push

Then open GitHub > Actions > "Build Highway Racing APK" > latest run > Artifacts.
The workflow only runs when files in `highway-racing/` (or its own workflow file) change, so your existing workflows are untouched.
