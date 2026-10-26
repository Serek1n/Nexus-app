package __PACKAGE__

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import androidx.core.content.FileProvider
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Системные функции Nexus: уведомления, работа в фоне, настройки VPN
 * (постоянный VPN и блокировка соединений без VPN), защита экрана.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    // Ключ AES-256 в Android Keystore: не покидает устройство и не извлекается.
    private fun secretKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey("nexus_data", null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                "nexus_data",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, secretKey())
        val out = c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    private fun decrypt(data: String): String {
        val raw = Base64.decode(data, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, raw, 0, 12))
        return String(c.doFinal(raw, 12, raw.size - 12), Charsets.UTF_8)
    }
    private var pendingLink: String? = null

    private fun linkOf(intent: Intent?): String? {
        val data = intent?.data ?: return null
        return if (intent.action == Intent.ACTION_VIEW && data.scheme == "nexus") data.toString() else null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        linkOf(intent)?.let { channel?.invokeMethod("link", it) }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingLink = linkOf(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexus/system")
        channel!!
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "protect" -> {
                        try {
                            result.success(encrypt(call.arguments as String))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }

                    "unprotect" -> {
                        try {
                            result.success(decrypt(call.arguments as String))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }

                    "initialLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }

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

                    "scanQr" -> {
                        // Окно сканера рисуют сервисы Google; приложению камера не нужна.
                        try {
                            val options = GmsBarcodeScannerOptions.Builder()
                                .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                                .enableAutoZoom()
                                .build()
                            GmsBarcodeScanning.getClient(this, options).startScan()
                                .addOnSuccessListener { result.success(it.rawValue ?: "") }
                                .addOnCanceledListener { result.success(null) }
                                .addOnFailureListener {
                                    result.error("scan", it.message ?: "Сканер недоступен", null)
                                }
                        } catch (e: Exception) {
                            result.error("scan", e.message ?: "Сканер недоступен", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
