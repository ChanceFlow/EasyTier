package com.plugin.vpnservice

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.net.VpnService
import android.util.Log
import android.view.View
import androidx.activity.result.ActivityResult
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import app.tauri.annotation.Command
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import android.webkit.WebView

@InvokeArg
class PingArgs {
    var value: String? = null
}

@InvokeArg
class UpdateNotificationArgs {
    var rxRate: Double? = null
    var txRate: Double? = null
}

@InvokeArg
class UiChromeArgs {
    var dark: Boolean = false
}

@InvokeArg
class StartVpnArgs {
    var ipv4Addr: String? = null
    var routes: Array<String> = emptyArray()
    var dns: String? = null
    var disallowedApplications: Array<String> = emptyArray()
    var mtu: Int? = null
}

@TauriPlugin
class VpnServicePlugin(private val activity: Activity) : Plugin(activity) {
    private val implementation = Example()

    private val watchdogHandler = Handler(Looper.getMainLooper())
    private var lastRxRate: Double = 0.0
    private var lastTxRate: Double = 0.0
    private var lastTunnelActive: Boolean = false
    private val watchdogRunnable = Runnable { handleWatchdogTimeout() }

    // Cached icon identifier to avoid repeated getIdentifier() lookups on every rate tick.
    // Note: getIdentifier relies on resource entry name keeping; if shrinkResources is enabled,
    // ic_notification must be kept or resolved with fallback.
    private var cachedSmallIcon: Int = 0

    override fun load(webView: WebView) {
        println("load vpn service plugin")
        TauriVpnService.triggerCallback = { event, data ->
            println("vpn: triggerCallback $event $data")
            trigger(event, data)
        }
    }

    @Command
    fun ping(invoke: Invoke) {
        val args = invoke.parseArgs(PingArgs::class.java)

        val ret = JSObject()
        ret.put("value", implementation.pong(args.value ?: "default value :("))
        invoke.resolve(ret)
    }

    @Command
    fun prepareVpn(invoke: Invoke) {
        activity.runOnUiThread {
            println("prepare vpn in plugin")
            val it = VpnService.prepare(activity)
            if (it != null) {
                startActivityForResult(invoke, it, "onPrepareVpnResult")
                return@runOnUiThread
            }
            val ret = JSObject()
            ret.put("granted", true)
            invoke.resolve(ret)
        }
    }

    @ActivityCallback
    fun onPrepareVpnResult(invoke: Invoke, result: ActivityResult) {
        val ret = JSObject()
        ret.put("granted", result.resultCode == Activity.RESULT_OK)
        invoke.resolve(ret)
    }

    @Command
    fun startVpn(invoke: Invoke) {
        val args = invoke.parseArgs(StartVpnArgs::class.java)
        activity.runOnUiThread {
            println("start vpn in plugin, args: $args")

            TauriVpnService.self?.onRevoke()

            val it = VpnService.prepare(activity)
            val ret = JSObject()
            if (it != null) {
                ret.put("errorMsg", "need_prepare")
            } else {
                val intent = Intent(activity, TauriVpnService::class.java)
                intent.putExtra(TauriVpnService.IPV4_ADDR, args.ipv4Addr)
                intent.putExtra(TauriVpnService.ROUTES, args.routes)
                intent.putExtra(TauriVpnService.DNS, args.dns)
                intent.putExtra(TauriVpnService.DISALLOWED_APPLICATIONS, args.disallowedApplications)
                intent.putExtra(TauriVpnService.MTU, args.mtu)

                activity.startService(intent)
            }
            invoke.resolve(ret)
        }
    }

    @Command
    fun stopVpn(invoke: Invoke) {
        activity.runOnUiThread {
            println("stop vpn in plugin")
            watchdogHandler.removeCallbacks(watchdogRunnable)
            lastTunnelActive = false
            lastRxRate = 0.0
            lastTxRate = 0.0
            TauriVpnService.self?.onRevoke()
            activity.stopService(Intent(activity, TauriVpnService::class.java))
            println("stop vpn in plugin end")
            invoke.resolve(JSObject())
        }
    }

    @Command
    fun getVpnStatus(invoke: Invoke) {
        val ret = JSObject()
        ret.put("running", TauriVpnService.self != null)
        ret.put("ipv4Addr", TauriVpnService.ipv4Addr)
        ret.put("routes", TauriVpnService.routes)
        ret.put("dns", TauriVpnService.dns)
        invoke.resolve(ret)
    }

    @Command
    fun updateNotification(invoke: Invoke) {
        val args = invoke.parseArgs(UpdateNotificationArgs::class.java)
        val ctx = activity?.applicationContext ?: activity
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        ensureNotificationChannel(ctx)

        val rx = (args.rxRate ?: 0.0).coerceAtLeast(0.0)
        val tx = (args.txRate ?: 0.0).coerceAtLeast(0.0)
        val active = rx > 0.0 || tx > 0.0

        lastRxRate = rx
        lastTxRate = tx
        lastTunnelActive = active

        // Reset watchdog on fresh JS tick
        watchdogHandler.removeCallbacks(watchdogRunnable)
        watchdogHandler.postDelayed(watchdogRunnable, WATCHDOG_TIMEOUT_MS)

        val title = if (active) {
            resolveString(ctx, "notification_title_connected", "EasyTier · 已连接")
        } else {
            resolveString(ctx, "app_name", "EasyTier")
        }

        val text = if (active) {
            "↑ %s · ↓ %s".format(formatRate(tx), formatRate(rx))
        } else {
            resolveString(ctx, "notification_text_idle", "网络空闲 · 隧道守护中")
        }

        val actionText = resolveString(ctx, "notification_action_open", "打开")

        val notification = NotificationCompat.Builder(ctx, NOTIFY_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(resolveSmallIcon(ctx))
            .setContentIntent(openAppIntent(ctx))
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(
                NotificationCompat.Action(
                    resolveSmallIcon(ctx),
                    actionText,
                    openAppIntent(ctx)
                )
            )
            .build()

        nm.notify(NOTIFY_ID, notification)
        invoke.resolve(JSObject())
    }

    /**
     * 需真机验证冻结时机:
     * When the app goes to background or the screen turns off, Android may throttle/freeze
     * WebView timers, causing rate updates from JS to stop.
     * If no new rate update arrives within WATCHDOG_TIMEOUT_MS, we re-issue the notification
     * with a static background status so the notification does not look permanently frozen on old rates.
     */
    private fun handleWatchdogTimeout() {
        try {
            val ctx = activity?.applicationContext ?: activity
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ensureNotificationChannel(ctx)

            val title = if (lastTunnelActive) {
                resolveString(ctx, "notification_title_connected", "EasyTier · 已连接")
            } else {
                resolveString(ctx, "app_name", "EasyTier")
            }

            val text = if (lastTunnelActive) {
                resolveString(ctx, "notification_text_background", "后台运行中 · 隧道保持")
            } else {
                resolveString(ctx, "notification_text_idle", "网络空闲 · 隧道守护中")
            }

            val actionText = resolveString(ctx, "notification_action_open", "打开")

            val notification = NotificationCompat.Builder(ctx, NOTIFY_CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(resolveSmallIcon(ctx))
                .setContentIntent(openAppIntent(ctx))
                .setCategory(Notification.CATEGORY_SERVICE)
                .setShowWhen(false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .addAction(
                    NotificationCompat.Action(
                        resolveSmallIcon(ctx),
                        actionText,
                        openAppIntent(ctx)
                    )
                )
                .build()

            nm.notify(NOTIFY_ID, notification)
        } catch (e: Exception) {
            Log.e("VpnServicePlugin", "Watchdog notification update failed", e)
        }
    }

    private fun resolveString(ctx: Context, name: String, fallback: String): String {
        val id = ctx.resources.getIdentifier(name, "string", ctx.packageName)
        return if (id != 0) {
            try {
                ctx.getString(id)
            } catch (_: Exception) {
                fallback
            }
        } else {
            fallback
        }
    }

    private fun ensureNotificationChannel(ctx: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                try {
                    nm.deleteNotificationChannel(OLD_NOTIFY_CHANNEL_ID)
                } catch (_: Exception) {}
                if (nm.getNotificationChannel(NOTIFY_CHANNEL_ID) == null) {
                    val name = resolveString(ctx, "notification_channel_name", "EasyTier Notice")
                    val desc = resolveString(ctx, "notification_channel_desc", "Shows EasyTier tunnel status and real-time network traffic rate.")
                    val channel = NotificationChannel(NOTIFY_CHANNEL_ID, name, NotificationManager.IMPORTANCE_LOW).apply {
                        description = desc
                        setShowBadge(false)
                    }
                    nm.createNotificationChannel(channel)
                }
            } catch (e: Exception) {
                Log.e("VpnServicePlugin", "Failed to ensure notification channel", e)
            }
        }
    }

    /**
     * The app module owns res/drawable/ic_notification.xml; the library module
     * cannot reference app resources at compile time, but everything is merged
     * into one APK at build time — resolve the id at runtime and fall back to
     * the stock wrench icon if the lookup fails.
     */
    private fun resolveSmallIcon(ctx: Context): Int {
        if (cachedSmallIcon != 0) {
            return cachedSmallIcon
        }
        val id = ctx.resources.getIdentifier("ic_notification", "drawable", ctx.packageName)
        cachedSmallIcon = if (id != 0) id else android.R.drawable.ic_menu_manage
        return cachedSmallIcon
    }

    /** PendingIntent that brings the EasyTier MainActivity to the front. */
    private fun openAppIntent(ctx: Context): PendingIntent {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent().apply {
                setClassName(ctx.packageName, "${ctx.packageName}.MainActivity")
            }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(ctx, 0, launch, piFlags)
    }

    /**
     * Drive the system-bar appearance from the web theme:
     * dark=false (light theme) -> dark status/navigation bar icons;
     * dark=true (dark theme)   -> light icons.
     */
    @Command
    fun setUiChrome(invoke: Invoke) {
        val args = invoke.parseArgs(UiChromeArgs::class.java)
        val lightBars = !args.dark
        activity.runOnUiThread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val controller = WindowCompat.getInsetsController(
                        activity.window, activity.window.decorView)
                    controller.isAppearanceLightStatusBars = lightBars
                    controller.isAppearanceLightNavigationBars = lightBars
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    // Pre-R fallback: the same systemUiVisibility flags WindowCompat
                    // would toggle internally (LIGHT_NAVIGATION_BAR is a no-op below 26).
                    val decorView = activity.window.decorView
                    var vis = decorView.systemUiVisibility
                    vis = if (lightBars) {
                        vis or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                    } else {
                        vis and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv() and
                            View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR.inv()
                    }
                    decorView.systemUiVisibility = vis
                }
                // Below API 23 light system-bar icons are unsupported: no-op.
            } catch (e: Exception) {
                Log.e("VpnServicePlugin", "set ui chrome failed", e)
            }
            invoke.resolve(JSObject())
        }
    }

    @Command
    fun notificationStatus(invoke: Invoke) {
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        val enabled = NotificationManagerCompat.from(activity).areNotificationsEnabled()
        val ret = JSObject()
        ret.put("granted", granted)
        ret.put("enabled", enabled)
        invoke.resolve(ret)
    }

    @Command
    fun openNotificationSettings(invoke: Invoke) {
        activity.runOnUiThread {
            try {
                activity.startActivity(
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (e: Exception) {
                try {
                    // some SDK levels lag on the Intent.* constant alias; the
                    // action string and fromParts() work on every API level
                    val details = Intent()
                    details.action = "android.settings.APPLICATION_DETAILS_SETTINGS"
                    details.data = Uri.fromParts("package", activity.packageName, null)
                    details.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(details)
                } catch (e2: Exception) {
                    Log.w("VpnServicePlugin", "open notification settings failed", e2)
                }
            }
            invoke.resolve(JSObject())
        }
    }

    private fun formatRate(bytesPerSec: Double): String {
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s")
        var v = bytesPerSec
        var i = 0
        while (v >= 1024.0 && i < units.size - 1) {
            v /= 1024.0
            i++
        }
        return if (i == 0) "%d %s".format(v.toLong(), units[i]) else "%.1f %s".format(v, units[i])
    }

    companion object {
        // Contract: must match MainForegroundService.CHANNEL_ID / NOTIFICATION_ID across modules
        private const val NOTIFY_CHANNEL_ID = "easytier_channel_v2"
        private const val OLD_NOTIFY_CHANNEL_ID = "easytier_channel"
        private const val NOTIFY_ID = 1355
        private const val WATCHDOG_TIMEOUT_MS = 15000L
    }
}
