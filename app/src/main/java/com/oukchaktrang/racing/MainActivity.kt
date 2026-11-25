name: Build Highway Racer APK

on:
  push:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Gradle 8.4
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.4'

      - name: Prepare assets (Three.js, fix minus signs, icons)
        run: |
          mkdir -p app/src/main/assets/game
          curl -fsSL "https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js" \
            -o app/src/main/assets/game/three.min.js
          sed -i 's/−/-/g' app/src/main/assets/game/index.html
          python3 - <<'EOF'
          import struct, zlib, os
          def make_png(w, h, r, g, b):
              def chunk(t, d):
                  return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
              ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
              raw = b''.join(b'\x00' + bytes([r, g, b] * w) for _ in range(h))
              return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
          sizes = {'mipmap-mdpi': 48, 'mipmap-hdpi': 72, 'mipmap-xhdpi': 96, 'mipmap-xxhdpi': 144, 'mipmap-xxxhdpi': 192}
          for folder, sz in sizes.items():
              path = 'app/src/main/res/' + folder
              os.makedirs(path, exist_ok=True)
              png = make_png(sz, sz, 0, 136, 255)
              for name in ['ic_launcher.png', 'ic_launcher_round.png']:
                  with open(path + '/' + name, 'wb') as f:
                      f.write(png)
          print("Icons generated")
          EOF

      - name: Build Debug APK
        run: gradle assembleDebug --no-daemon --stacktrace

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: HighwayRacer-Debug-APK
          path: app/build/outputs/apk/debug/*.apk
          retention-days: 30
