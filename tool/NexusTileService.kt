package __PACKAGE__

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Base64
import android.widget.RemoteViews
import android.widget.Toast
import androidx.annotation.RequiresApi
import dev.amirzr.flutter_v2ray_client.v2ray.V2rayController
import dev.amirzr.flutter_v2ray_client.v2ray.utils.AppConfigs
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Общее для плитки, виджета и напоминаний: состояние VPN, последний
 * конфиг (зашифрован ключом Android Keystore) и одноразовые ключи нажатий —
 * другое приложение не сможет переключить VPN от имени Nexus.
 */
object NexusTile {
    private const val PREFS = "nexus_tile"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun random(): String {
        val b = ByteArray(24)
        SecureRandom().nextBytes(b)
        return b.joinToString("") { "%02x".format(it) }
    }

    // ── одноразовый ключ плитки (для открытия приложения) ──

    fun token(ctx: Context): String {
        val p = prefs(ctx)
        p.getString("token", null)?.let { return it }
        val t = random()
        p.edit().putString("token", t).commit()
        return t
    }

    /** Проверяет ключ и сразу его сжигает: повторно то же нажатие не сработает. */
    fun consume(ctx: Context, t: String?): Boolean {
        val p = prefs(ctx)
        val own = p.getString("token", null) ?: return false
        if (t == null || t != own) return false
        p.edit().remove("token").commit()
        return true
    }

    /** Постоянный ключ кнопки виджета. */
    fun widgetKey(ctx: Context): String {
        val p = prefs(ctx)
        p.getString("wkey", null)?.let { return it }
        val t = random()
        p.edit().putString("wkey", t).commit()
        return t
    }

    // ── состояние ──

    fun save(ctx: Context, on: Boolean, vpn: Boolean) {
        prefs(ctx).edit().putBoolean("on", on).putBoolean("vpn", vpn).apply()
        refreshViews(ctx)
    }

    /** Подписи «Подключено/Отключено» на языке интерфейса Nexus. */
    fun saveLabels(ctx: Context, onLabel: String?, offLabel: String?) {
        if (onLabel == null || offLabel == null) return
        prefs(ctx).edit().putString("onLabel", onLabel).putString("offLabel", offLabel).apply()
    }

    fun label(ctx: Context, on: Boolean): String =
        prefs(ctx).getString(if (on) "onLabel" else "offLabel", null)
            ?: if (on) "Подключено" else "Отключено"

    fun refreshViews(ctx: Context) {
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                TileService.requestListeningState(
                    ctx, ComponentName(ctx, NexusTileService::class.java)
                )
            } catch (e: Exception) {
            }
        }
        NexusWidget.updateAll(ctx)
    }

    /** Включено, если Nexus сообщил о подключении и системный VPN правда поднят. */
    fun isOn(ctx: Context): Boolean {
        val p = prefs(ctx)
        if (!p.getBoolean("on", false)) return false
        if (!p.getBoolean("vpn", true)) return true
        return try {
            val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            @Suppress("DEPRECATION")
            val nets = cm.allNetworks
            nets.any {
                cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true
            }
        } catch (e: Exception) {
            true
        }
    }

    // ── шифрование ──

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
        return Base64.encodeToString(c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
    }

    private fun decrypt(data: String): String {
        val raw = Base64.decode(data, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, raw, 0, 12))
        return String(c.doFinal(raw, 12, raw.size - 12), Charsets.UTF_8)
    }

    // ── последний конфиг: чтобы плитка и виджет подключали без приложения ──

    fun saveConfig(ctx: Context, remark: String, config: String, blocked: List<String>, vpn: Boolean) {
        try {
            val j = JSONObject()
                .put("remark", remark)
                .put("config", config)
                .put("blocked", JSONArray(blocked))
                .put("vpn", vpn)
            prefs(ctx).edit().putString("cfg", encrypt(j.toString())).apply()
        } catch (e: Exception) {
        }
    }

    fun clearConfig(ctx: Context) {
        prefs(ctx).edit().remove("cfg").apply()
    }

    /**
     * Переключает VPN без открытия окна. false — нужно приложение
     * (нет конфига, нет разрешения на VPN, система не дала запустить службу).
     */
    fun toggle(ctx: Context): Boolean {
        // Приложение открыто — переключает оно: там проверка канала и
        // автопереподключение.
        MainActivity.live?.let {
            try {
                it.invokeMethod("toggle", null)
                return true
            } catch (e: Exception) {
            }
        }
        val p = prefs(ctx)
        val vpnMode = p.getBoolean("vpn", true)
        AppConfigs.NOTIFICATION_DISCONNECT_BUTTON_NAME = "ОТКЛЮЧИТЬ"
        if (isOn(ctx)) {
            return try {
                V2rayController.changeConnectionMode(
                    if (vpnMode) AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN
                    else AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY
                )
                V2rayController.StopV2ray(ctx)
                save(ctx, false, vpnMode)
                true
            } catch (e: Exception) {
                false
            }
        }
        val enc = p.getString("cfg", null) ?: return false
        return try {
            val j = JSONObject(decrypt(enc))
            val vpn = j.optBoolean("vpn", true)
            if (vpn && VpnService.prepare(ctx) != null) return false
            val arr = j.optJSONArray("blocked") ?: JSONArray()
            val blocked = ArrayList<String>()
            for (i in 0 until arr.length()) blocked.add(arr.getString(i))
            AppConfigs.APPLICATION_ICON =
                ctx.resources.getIdentifier("ic_launcher", "mipmap", ctx.packageName)
            AppConfigs.APPLICATION_NAME = "Nexus"
            V2rayController.changeConnectionMode(
                if (vpn) AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN
                else AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY
            )
            V2rayController.StartV2ray(
                ctx, j.optString("remark", "Nexus"), j.getString("config"),
                if (vpn && blocked.isNotEmpty()) blocked else null, null
            )
            save(ctx, true, vpn)
            true
        } catch (e: Exception) {
            false
        }
    }

    // ── напоминания о конце подписки ──

    private const val CHANNEL = "nexus_expiry"

    /** [subs] — JSON-массив {id, title, expire (мс)}. */
    fun scheduleExpiry(ctx: Context, subs: String) {
        prefs(ctx).edit().putString("expiry", subs).apply()
        reschedule(ctx)
    }

    fun reschedule(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val p = prefs(ctx)
        // Отменяем прежние напоминания.
        val old = p.getInt("alarms", 0)
        for (code in 0 until old) {
            am.cancel(alarmIntent(ctx, code, "", 0, ""))
        }
        val arr = try {
            JSONArray(p.getString("expiry", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        val now = System.currentTimeMillis()
        val day = 24L * 3600 * 1000
        var code = 0
        for (i in 0 until minOf(arr.length(), 20)) {
            val o = arr.optJSONObject(i) ?: continue
            val title = o.optString("title", "Подписка")
            val expire = o.optLong("expire", 0)
            if (expire <= now) continue
            for (d in intArrayOf(3, 1)) {
                val at = expire - d * day
                if (at <= now) continue
                val msg = o.optString(if (d == 1) "m1" else "m3", "")
                am.set(AlarmManager.RTC, at, alarmIntent(ctx, code, title, d, msg))
                code++
            }
        }
        p.edit().putInt("alarms", code).apply()
    }

    private fun alarmIntent(ctx: Context, code: Int, title: String, days: Int, msg: String): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, 1000 + code,
            Intent(ctx, NexusAlarmReceiver::class.java)
                .putExtra("title", title)
                .putExtra("days", days)
                .putExtra("msg", msg),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    fun notifyExpiry(ctx: Context, title: String, days: Int, msg: String?) {
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Окончание подписки", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            ctx, 9,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val text = if (!msg.isNullOrEmpty()) msg
        else if (days <= 1) "Подписка «$title» закончится завтра — продлите её в боте"
        else "Подписка «$title» закончится через $days дня — продлите её в боте"
        @Suppress("DEPRECATION")
        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(ctx, CHANNEL)
        else android.app.Notification.Builder(ctx)
        val n = b.setSmallIcon(ctx.resources.getIdentifier("ic_nexus_tile", "drawable", ctx.packageName))
            .setContentTitle("Nexus")
            .setContentText(text)
            .setStyle(android.app.Notification.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(title.hashCode(), n)
        } catch (e: SecurityException) {
            // Уведомления запрещены пользователем.
        }
    }
}

/** Плитка «Nexus» в шторке уведомлений: подключить или отключить VPN. */
@RequiresApi(24)
class NexusTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    private fun refresh() {
        val t = qsTile ?: return
        val on = NexusTile.isOn(this)
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = "Nexus"
        if (Build.VERSION.SDK_INT >= 29) {
            t.subtitle = NexusTile.label(this, on)
        }
        t.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val run = Runnable {
            // Сначала — тихо, без окна. Не вышло — открываем Nexus.
            if (NexusTile.toggle(this)) {
                refresh()
                return@Runnable
            }
            val i = Intent(this, MainActivity::class.java)
                .setAction("$packageName.TOGGLE")
                .putExtra("token", NexusTile.token(this))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(
                    PendingIntent.getActivity(
                        this, 7, i,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(i)
            }
        }
        if (isLocked) unlockAndRun(run) else run.run()
    }
}

/** Виджет на рабочем столе: кнопка VPN и состояние. */
class NexusWidget : AppWidgetProvider() {
    companion object {
        fun updateAll(ctx: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(ctx) ?: return
                val ids = mgr.getAppWidgetIds(ComponentName(ctx, NexusWidget::class.java))
                if (ids.isNotEmpty()) mgr.updateAppWidget(ids, views(ctx))
            } catch (e: Exception) {
            }
        }

        private fun views(ctx: Context): RemoteViews {
            val pkg = ctx.packageName
            val res = ctx.resources
            fun id(name: String, type: String) = res.getIdentifier(name, type, pkg)
            val on = NexusTile.isOn(ctx)
            val v = RemoteViews(pkg, id("nexus_widget", "layout"))
            v.setTextViewText(id("nexus_widget_state", "id"), NexusTile.label(ctx, on))
            v.setInt(
                id("nexus_widget_icon", "id"), "setBackgroundResource",
                id(if (on) "nexus_widget_dot_on" else "nexus_widget_dot_off", "drawable")
            )
            val click = PendingIntent.getBroadcast(
                ctx, 8,
                Intent(ctx, NexusWidget::class.java)
                    .setAction("$pkg.WIDGET_TOGGLE")
                    .putExtra("key", NexusTile.widgetKey(ctx)),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            v.setOnClickPendingIntent(id("nexus_widget_root", "id"), click)
            return v
        }
    }

    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        mgr.updateAppWidget(ids, views(ctx))
    }

    override fun onReceive(ctx: Context, intent: Intent) {
        super.onReceive(ctx, intent)
        if (intent.action != "${ctx.packageName}.WIDGET_TOGGLE") return
        if (intent.getStringExtra("key") != NexusTile.widgetKey(ctx)) return
        if (!NexusTile.toggle(ctx)) {
            // Нужен Nexus (первое подключение или разрешение на VPN).
            Toast.makeText(ctx, "Откройте Nexus, чтобы подключиться", Toast.LENGTH_SHORT).show()
            try {
                ctx.startActivity(
                    Intent(ctx, MainActivity::class.java)
                        .setAction("${ctx.packageName}.TOGGLE")
                        .putExtra("token", NexusTile.token(ctx))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e: Exception) {
            }
        }
        updateAll(ctx)
    }
}

/** Напоминание о конце подписки (по будильнику AlarmManager). */
class NexusAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        NexusTile.notifyExpiry(
            ctx, intent.getStringExtra("title") ?: "Подписка", intent.getIntExtra("days", 1),
            intent.getStringExtra("msg")
        )
    }
}

/** После перезагрузки будильники пропадают — ставим заново. */
class NexusBootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) NexusTile.reschedule(ctx)
    }
}
