package com.pokergto.poker_gto_trainer

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/update").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "info" -> {
                        val pi = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) {
                            pi.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            pi.versionCode.toLong()
                        }
                        val dir = File(cacheDir, "updates")
                        dir.mkdirs()
                        result.success(
                            mapOf(
                                "versionName" to (pi.versionName ?: ""),
                                "versionCode" to code,
                                "downloadDir" to dir.absolutePath,
                            )
                        )
                    }
                    "canInstall" -> {
                        result.success(Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls())
                    }
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= 26) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")!!
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("update_error", e.message, null)
            }
        }
    }
}
