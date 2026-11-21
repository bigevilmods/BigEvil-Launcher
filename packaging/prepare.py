"""Generate the pinned Flutter runners without replacing application sources."""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "packaging" / "android"


def prepare(platform):
    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("Flutter deve estar no PATH.")
    with tempfile.TemporaryDirectory(dir=ROOT) as temp:
        destination = Path(temp) / "bigevil_launcher"
        command = [
            flutter, "create", "--no-pub", "--platforms", platform,
            "--project-name", "bigevil_launcher", "--org", "com.bigevil",
            str(destination),
        ]
        if sys.platform == "win32" and flutter.lower().endswith(".bat"):
            command = ["cmd.exe", "/d", "/c", *command]
        subprocess.run(command, check=True)
        runner = ROOT / platform
        shutil.copytree(destination / platform, runner, dirs_exist_ok=True)

    if platform == "android":
        android = runner / "app" / "src" / "main"
        for filename, target in {
            "MainActivity.kt": "kotlin/com/bigevil/bigevil_launcher/MainActivity.kt",
            "AndroidManifest.xml": "AndroidManifest.xml",
            "update_paths.xml": "res/xml/update_paths.xml",
            "ic_bigevil.xml": "res/drawable/ic_bigevil.xml",
        }.items():
            path = android / target
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ASSETS / filename, path)
        gradle = runner / "app" / "build.gradle.kts"
        source = gradle.read_text(encoding="utf-8")
        signing = """
    signingConfigs {
        create("production") {
            val keyPath = System.getenv("BIGEVIL_KEYSTORE")
            if (!keyPath.isNullOrEmpty()) {
                storeFile = file(keyPath)
                storePassword = System.getenv("BIGEVIL_STORE_PASSWORD")
                keyAlias = System.getenv("BIGEVIL_KEY_ALIAS")
                keyPassword = System.getenv("BIGEVIL_KEY_PASSWORD")
            }
        }
    }
"""
        source = source.replace("    buildTypes {", signing + "\n    buildTypes {", 1)
        debug = 'signingConfig = signingConfigs.getByName("debug")'
        if debug not in source:
            raise RuntimeError("O template Flutter de assinatura mudou.")
        source = source.replace(debug,
            'signingConfig = signingConfigs.getByName(if (System.getenv("BIGEVIL_KEYSTORE").isNullOrEmpty()) "debug" else "production")')
        gradle.write_text(source + '\ndependencies { implementation("androidx.core:core:1.15.0") }\n', encoding="utf-8")
        if sys.platform == "win32":
            # Flutter plugins can reside on a different Windows drive from the project.
            properties = runner / "gradle.properties"
            with properties.open("a", encoding="utf-8") as config:
                config.write("\nkotlin.incremental=false\n")
    elif platform == "windows":
        cmake = runner / "CMakeLists.txt"
        with cmake.open("a", encoding="utf-8") as config:
            config.write("""
# The WebView plugin links the SDK loader dynamically.
target_compile_features(webview_all_windows_plugin PRIVATE cxx_std_20)
string(TOLOWER "${CMAKE_VS_PLATFORM_NAME}" BIGEVIL_WEBVIEW_ARCH)
set(BIGEVIL_WEBVIEW_LOADER
  "${CMAKE_BINARY_DIR}/packages/Microsoft.Web.WebView2/build/native/${BIGEVIL_WEBVIEW_ARCH}/WebView2Loader.dll")
install(FILES "${BIGEVIL_WEBVIEW_LOADER}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
""")
        shutil.copyfile(ROOT / "packaging" / "assets" / "bigevil.ico",
                        runner / "runner" / "resources" / "app_icon.ico")
        for relative in ("runner/main.cpp", "runner/Runner.rc"):
            path = runner / relative
            path.write_text(path.read_text(encoding="utf-8").replace(
                '"bigevil_launcher"', '"BigEvil Launcher"'), encoding="utf-8")
    elif platform == "linux":
        path = runner / "runner" / "my_application.cc"
        path.write_text(path.read_text(encoding="utf-8").replace(
            '"bigevil_launcher"', '"BigEvil Launcher"'), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("android", "windows", "linux"), nargs="+")
    for platform in parser.parse_args().platform:
        prepare(platform)
