package com.bigevil.bigevil_launcher

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.zip.ZipFile

class MainActivity : FlutterActivity() {
    private var pendingItemInstall: File? = null

    override fun onResume() {
        super.onResume()
        val file = pendingItemInstall ?: return
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) return
        pendingItemInstall = null
        if (file.isFile) {
            runCatching { install(file) }
                .onFailure { android.util.Log.e("BigEvil Launcher", "Could not start APK installer", it) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bigevil/android")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "installedVersion" -> {
                        val packageName = call.arguments as String
                        val version = try {
                            packageManager.getPackageInfo(packageName, 0).versionName.orEmpty()
                        } catch (_: PackageManager.NameNotFoundException) {
                            null
                        }
                        result.success(version)
                    }
                    "bluetoothSettings" -> {
                        startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                        result.success(null)
                    }
                    "apps" -> result.success(installedApps())
                    "launch" -> {
                        val target = call.arguments as String
                        val launch = packageManager.getLaunchIntentForPackage(target)
                            ?: throw ActivityNotFoundException()
                        startActivity(launch)
                        result.success(null)
                    }
                    "install" -> {
                        install(File(call.arguments as String))
                        result.success(null)
                    }
                    "installItem" -> {
                        install(File(call.arguments as String), deferPermission = true)
                        result.success(null)
                    }
                    "extractItemApk" -> {
                        val archive = updateFile(File(call.argument<String>("archive")!!))
                        val preferred = call.argument<String>("executable").orEmpty()
                        Thread {
                            try {
                                val apk = extractItemApk(archive, preferred)
                                runOnUiThread { result.success(apk.path) }
                            } catch (error: Exception) {
                                runOnUiThread { result.error("archive", error.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            } catch (error: ActivityNotFoundException) {
                result.error(if (call.method == "launch") "app_unavailable" else "platform", error.message, null)
            } catch (error: InstallPermissionRequired) {
                result.error("install_permission", null, null)
            } catch (error: Exception) {
                result.error("platform", error.message, null)
            }
        }
    }

    private fun installedApps(): List<Map<String, String>> {
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return packageManager.queryIntentActivities(query, 0)
            .filter { it.activityInfo.packageName != packageName }
            .distinctBy { it.activityInfo.packageName }
            .map {
                mapOf("name" to it.loadLabel(packageManager).toString(),
                    "package" to it.activityInfo.packageName)
            }
            .sortedBy { it.getValue("name").lowercase() }
    }

    private fun updateFile(candidate: File): File {
        val directory = File(cacheDir, "updates").canonicalFile
        val file = candidate.canonicalFile
        require(file.path.startsWith(directory.path + File.separator) && file.isFile)
        return file
    }

    private fun extractItemApk(archive: File, preferred: String): File {
        val output = File(archive.parentFile, "payload.apk")
        val limit = 10L * 1024 * 1024 * 1024
        ZipFile(archive).use { zip ->
            val entry = zip.entries().asSequence().filter {
                !it.isDirectory && it.name.endsWith(".apk", ignoreCase = true) &&
                    (preferred.isEmpty() || it.name == preferred)
            }.singleOrNull() ?: error("ZIP must contain one selected APK")
            require(entry.size in 1..limit)
            zip.getInputStream(entry).use { input ->
                output.outputStream().use { target ->
                    val buffer = ByteArray(64 * 1024)
                    var received = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count == -1) break
                        received += count
                        require(received <= entry.size)
                        target.write(buffer, 0, count)
                    }
                    require(received == entry.size)
                }
            }
        }
        return output
    }

    private fun install(candidate: File, deferPermission: Boolean = false) {
        val file = updateFile(candidate)
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            if (deferPermission) {
                pendingItemInstall = file
                return
            }
            throw InstallPermissionRequired()
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    private class InstallPermissionRequired : Exception()
}
