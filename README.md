# BigEvil Launcher

BigEvil Launcher is a local game and app library with an adaptive interface in Brazilian Portuguese, English, and Spanish. The home screen has two horizontal galleries and navigation by category. Search finds items by name or target. In the item editor, you can import a local PNG, JPEG, or WebP cover.

Use the language picker in the top bar to switch between Brazilian Portuguese, English, and Spanish without restarting. The launcher saves your choice on this device. **System language** follows your system settings and uses Brazilian Portuguese when your language is outside the supported list. Library entries and website content are displayed in their original language.

Select an item's cover to open its details page. The editor lets you set the cover image, background image, description, developer, repository URL, download URL, and URL of the online version. The local target is optional. **Download** opens the URL in your default browser. **Play online** opens the web version inside the launcher.

The built-in browser uses Android System WebView, Microsoft Edge WebView2 on Windows, and WebKitGTK 4.1 on Linux. The launcher starts a browser session when you open an online item and closes it when you return to the library. Use HTTPS on Android. The compatibility button checks WebAssembly, WebGL, WebGL 2, Canvas 2D, Web Audio, and optional features on the current page. Availability depends on the browser engine version, the device's graphics support, and the page's policies.

| Platform | Supported targets | Distribution |
| --- | --- | --- |
| Windows x64 | Executables, `.lnk` shortcuts, and HTTP(S) links | Per-user Inno Setup installer |
| Linux x64 | Executables, `.desktop` entries via GIO, and HTTP(S) links | Debian/Ubuntu package |
| Android | Installed apps with a launcher activity and HTTP(S) links | Signed universal APK |

## Build and test

Use Flutter 3.50.1 and Python 3. On Windows, install the Desktop development with C++ workload. On Linux, use Clang, CMake, Ninja, pkg-config, and the GTK 3 headers. On Android, use the Android SDK and JDK 21. The setup commands generate the native Flutter runners and apply the integrations in `packaging/`. Run setup for each target on the machine that will build it.

```sh
python packaging/prepare.py windows
flutter pub get
flutter run -d windows
flutter build windows --release
```

On Windows, run `./packaging/windows.ps1 -Portable` to create the ZIP, or run `./packaging/windows.ps1` with Inno Setup 6 installed to create the installer. The script bundles the Visual C++ redistributable DLLs alongside the executable.

On Linux, also install `libwebkit2gtk-4.1-dev`, generate the runner with `python3 packaging/prepare.py linux`, build with `flutter build linux --release`, and run `bash packaging/linux.sh 1.3.0` to create the DEB. On Windows, the built-in browser requires the WebView2 Evergreen Runtime. For Android, run `python packaging/prepare.py android` and `flutter build apk --release` with Android SDK API level 36. If no production signing key is configured, the Android build uses a debug signature for local testing.

```sh
flutter gen-l10n
flutter analyze lib test integration_test
flutter test
dart run test/filter_benchmark.dart
```

To test the built-in browser engine on Windows, run `flutter test -d windows integration_test/browser_test.dart`. The test opens a local page and checks the WebAssembly diagnostic result.

The microbenchmark compares normalizing text on each search with normalizing each item in advance. It uses 10,000 entries and five query strings, warms up before measuring, and reports the median of 11 samples of 90 searches each. It measures the in-memory filter.

When testing version 1.0.0 on Windows x64, the microbenchmark compiled with `dart compile exe` went from 122.49 ms to 53.19 ms per 90 queries, a reduction of about 57%. Across five runs from the portable ZIP, the median time for the window's input queue to become idle was 323 ms, and the median resident memory use after 1.5 seconds was 74.8 MiB. The installer for that version was 10.7 MB.

## GitHub Releases

1. Host the code in a public GitHub repository. Configure the `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, and `ANDROID_KEY_ALIAS` secrets. Use the same Android signing key across releases.
2. Update `version` in `pubspec.yaml`. Increase the number after `+` for each Android release. Push a tag that matches the version without its build number, such as `v1.1.0` for `1.1.0+2`.
3. The workflow builds all three platforms and publishes the release after all jobs pass. It embeds the repository and version in the binary. Local builds use `bigevilmods/BigEvil-Launcher` by default. Set `--dart-define=BIGEVIL_VERSION=1.3.0` to match the version being built. To use a different repository, set `--dart-define=BIGEVIL_REPOSITORY=owner/repository` when building or enter it in the launcher's update settings. Clearing the field restores the build's default repository.

The launcher checks the repository for a stable release at startup and every six hours while it is open. When it finds a newer version, it automatically downloads the package for your platform and verifies its size and the SHA-256 checksum provided by GitHub. **Install** opens the system installer. On Android, the system may ask you to allow installation from this source. On Linux, open the DEB in your distribution's package manager. If no graphical package manager is associated with DEB files, the launcher displays the package path so you can run `sudo apt install /path/to/BigEvil-Launcher-linux-x64.deb`.

Updates preserve the library in the user data directory. The launcher stores your data locally and contacts GitHub to check for updates.
