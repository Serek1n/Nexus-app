package __PACKAGE__

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import java.security.SecureRandom

/**
 * Общие данные плитки: состояние VPN и одноразовый ключ нажатия.
 * Ключ лежит в личных настройках Nexus — другое приложение не сможет
 * прислать MainActivity команду «переключить VPN» от имени плитки.
 */
object NexusTile {
    private const val PREFS = "nexus_tile"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun token(ctx: Context): String {
        val p = prefs(ctx)
        p.getString("token", null)?.let { return it }
        val b = ByteArray(24)
        SecureRandom().nextBytes(b)
        val t = b.joinToString("") { "%02x".format(it) }
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

    fun save(ctx: Context, on: Boolean, vpn: Boolean) {
        prefs(ctx).edit().putBoolean("on", on).putBoolean("vpn", vpn).apply()
        if (Build.VERSION.SDK_INT >= 24) {
            try {
                TileService.requestListeningState(
                    ctx, ComponentName(ctx, NexusTileService::class.java)
                )
            } catch (e: Exception) {
            }
        }
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
            t.subtitle = if (on) "Подключено" else "Отключено"
        }
        t.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val open = Runnable {
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
        if (isLocked) unlockAndRun(open) else open.run()
    }
}
