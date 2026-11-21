package com.bigevil.bigevil_launcher

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bigevil/android")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "apps" -> result.success(installedApps())
                    "launch" -> {
                        val target = call.arguments as String
                        val launch = packageManager.getLaunchIntentForPackage(target)
                            ?: throw ActivityNotFoundException("Aplicativo indisponível")
                        startActivity(launch)
                        result.success(null)
                    }
                    "install" -> {
                        install(File(call.arguments as String))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
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

    private fun install(candidate: File) {
        val directory = File(cacheDir, "updates").canonicalFile
        val file = candidate.canonicalFile
        require(file.path.startsWith(directory.path + File.separator) && file.isFile)
        if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
            throw IllegalStateException("Autorize esta fonte no Android e toque em Instalar novamente.")
        }
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }
}
