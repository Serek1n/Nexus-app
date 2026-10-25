package __PACKAGE__

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Системные функции Nexus: уведомления, работа в фоне, настройки VPN
 * (постоянный VPN и блокировка соединений без VPN), защита экрана.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
                        }
                        result.success(null)
                    }

                    "isIgnoringBattery" -> {
                        if (Build.VERSION.SDK_INT >= 23) {
                            val pm = getSystemService(POWER_SERVICE) as PowerManager
                            result.success(pm.isIgnoringBatteryOptimizations(packageName))
                        } else {
                            result.success(true)
                        }
                    }

                    "requestIgnoreBattery" -> {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "listApps" -> {
                        // Приложения с иконкой в лаунчере: [пакет, название].
                        Thread {
                            val apps = try {
                                val intent = Intent(Intent.ACTION_MAIN)
                                    .addCategory(Intent.CATEGORY_LAUNCHER)
                                packageManager.queryIntentActivities(intent, 0)
                                    .map { listOf(it.activityInfo.packageName, it.loadLabel(packageManager).toString()) }
                                    .filter { it[0] != packageName }
                                    .distinctBy { it[0] }
                                    .sortedBy { it[1].lowercase() }
                            } catch (e: Exception) {
                                emptyList()
                            }
                            runOnUiThread { result.success(apps) }
                        }.start()
                    }

                    "appInfo" -> {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
                        else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success(
                            mapOf(
                                "versionCode" to code,
                                "versionName" to (info.versionName ?: ""),
                                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                                "cacheDir" to cacheDir.absolutePath,
                            )
                        )
                    }

                    "canInstallApk" -> {
                        result.success(
                            Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()
                        )
                    }

                    "openInstallSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= 26) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "installApk" -> {
                        // Устанавливаем только файл из своей папки кэша обновлений.
                        val path = call.arguments as? String
                        val updates = File(cacheDir, "updates").canonicalPath
                        val file = path?.let { File(it) }
                        if (file == null || !file.exists() ||
                            !file.canonicalPath.startsWith(updates + File.separator)
                        ) {
                            result.success(false)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.nexus.files", file
                                )
                                startActivity(
                                    Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(uri, "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }
                    }

                    "openVpnSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }

                    "setSecureScreen" -> {
                        val on = call.arguments as? Boolean ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
