package com.plugin.vpnservice

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.Bundle
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import java.net.InetAddress
import java.util.Arrays

import app.tauri.plugin.JSObject

class TauriVpnService : VpnService() {
    companion object {
        @JvmField var triggerCallback: (String, JSObject) -> Unit = { _, _ -> }
        @JvmField var self: TauriVpnService? = null
        @JvmField var ipv4Addr: String? = null
        @JvmField var routes: Array<String> = emptyArray()
        @JvmField var dns: String? = null

        const val IPV4_ADDR = "IPV4_ADDR"
        const val ROUTES = "ROUTES"
        const val DNS = "DNS"
        const val DISALLOWED_APPLICATIONS = "DISALLOWED_APPLICATIONS"
        const val MTU = "MTU"

        /** Action for the notification "Disconnect" button. */
        const val ACTION_STOP_VPN = "com.kkrainbow.easytier.action.STOP_VPN"

        /**
         * Why the tunnel went down, forwarded to JS in the `vpn_service_stop`
         * payload. Android hands the caller no reason, so the only place that
         * knows the difference is the callback we came in through:
         * `user` = notification "Disconnect" / in-app stop,
         * `revoked` = the system took the VPN slot away (normally because
         * another VPN app connected),
         * `destroy` = the service is being torn down.
         *
         * JS needs the distinction to tell "we asked for this" from "it was
         * taken from us": on revoke the EasyTier instance keeps running, so
         * nothing else would ever clear the in-app "connected" state.
         */
        const val REASON_USER = "user"
        const val REASON_REVOKED = "revoked"
        const val REASON_DESTROY = "destroy"

        /**
         * Contract C2: the whole app keeps exactly ONE ongoing notification.
         * Both values must match VpnServicePlugin.NOTIFY_CHANNEL_ID / NOTIFY_ID
         * and the app module's MainForegroundService.CHANNEL_ID /
         * NOTIFICATION_ID, so updateNotification() updates this very
         * notification in place instead of stacking a second one.
         */
        private const val NOTIFICATION_CHANNEL_ID = "easytier_channel_v2"
        private const val NOTIFICATION_ID = 1355
    }

    private lateinit var vpnInterface: ParcelFileDescriptor

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        println("vpn on start command ${intent?.getExtras()} $intent")

        // Notification "Disconnect" action: tear the tunnel down without
        // bringing the app forward. Mirrors onRevoke() so `self` is cleared
        // before onDestroy and the JS stop callback fires exactly once.
        if (intent?.action == ACTION_STOP_VPN) {
            disconnect(REASON_USER)
            stopForeground(STOP_FOREGROUND_REMOVE)
            self = null
            stopSelf()
            return START_NOT_STICKY
        }

        startVpnForegroundService()
        var args = intent?.getExtras()
        ipv4Addr = args?.getString(IPV4_ADDR)
        routes = args?.getStringArray(ROUTES) ?: emptyArray()
        dns = args?.getString(DNS)

        vpnInterface = createVpnInterface(args)
        println("vpn created ${vpnInterface.fd}")

        var event_data = JSObject()
        event_data.put("fd", vpnInterface.fd)
        triggerCallback("vpn_service_start", event_data)
        EasyTierVpnTileService.requestStateUpdate(this)

        return START_STICKY
    }

    override fun onCreate() {
        super.onCreate()
        self = this
        println("vpn on create")
    }

    override fun onDestroy() {
        println("vpn on destroy")
        disconnect(REASON_DESTROY)
        setMainForegroundServiceEnabled(true)
        stopForeground(STOP_FOREGROUND_REMOVE)
        self = null
        EasyTierVpnTileService.requestStateUpdate(this)
        super.onDestroy()
    }

    override fun onRevoke() {
        println("vpn on revoke")
        disconnect(REASON_REVOKED)
        setMainForegroundServiceEnabled(true)
        stopForeground(STOP_FOREGROUND_REMOVE)
        self = null
        EasyTierVpnTileService.requestStateUpdate(this)
        super.onRevoke()
    }

    private fun disconnect(reason: String) {
        if (self == this && this::vpnInterface.isInitialized) {
            val event_data = JSObject()
            event_data.put("reason", reason)
            triggerCallback("vpn_service_stop", event_data)
            vpnInterface.close()
        }
        clearStatus()
    }

    private fun clearStatus() {
        ipv4Addr = null
        routes = emptyArray()
        dns = null
    }

    private fun startVpnForegroundService() {
        // Tear the no-TUN keepalive service down BEFORE claiming the shared
        // notification id: bringing it down makes the system cancel whatever
        // notification currently occupies id 1355, which would otherwise wipe
        // the notification posted a few lines below under the same id.
        setMainForegroundServiceEnabled(false)

        createNotificationChannel()

        val smallIcon = resolveSmallIcon()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        val stopIntent = PendingIntent.getService(
            this,
            1,
            Intent(this, TauriVpnService::class.java).setAction(ACTION_STOP_VPN),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Localized at runtime: this is a library module, so app_* strings come
        // from the merged app resources (same helper contract as
        // VpnServicePlugin.resolveString). No hard-coded user-visible copy.
        val title = resolveString("app_name", "EasyTier")
        val text = resolveString("notification_text_idle", "Network idle · Tunnel active")
        val openText = resolveString("notification_action_open", "Open")
        val disconnectText = resolveString("notification_action_disconnect", "Disconnect")

        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(smallIcon)
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

        contentIntent?.let {
            builder.setContentIntent(it)
            builder.addAction(NotificationCompat.Action(smallIcon, openText, it))
        }
        builder.addAction(NotificationCompat.Action(smallIcon, disconnectText, stopIntent))

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun setMainForegroundServiceEnabled(enabled: Boolean) {
        val intent = Intent().setClassName(packageName, "$packageName.MainForegroundService")
        if (!enabled) {
            stopService(intent)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = resolveString("notification_channel_name", "EasyTier Notice")
            val desc = resolveString(
                "notification_channel_desc",
                "Shows EasyTier tunnel status and real-time network traffic rate.",
            )
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                name,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = desc
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    /**
     * The app module owns res/drawable/ic_notification.xml; this library module
     * cannot reference it at compile time, so resolve it at runtime and fall
     * back to the stock wrench icon (same rule as VpnServicePlugin).
     */
    private fun resolveSmallIcon(): Int {
        val id = resources.getIdentifier("ic_notification", "drawable", packageName)
        return if (id != 0) id else android.R.drawable.ic_menu_manage
    }

    private fun resolveString(name: String, fallback: String): String {
        val id = resources.getIdentifier(name, "string", packageName)
        if (id == 0) {
            return fallback
        }
        return try {
            getString(id)
        } catch (_: Exception) {
            fallback
        }
    }

    private fun createVpnInterface(args: Bundle?): ParcelFileDescriptor {
        var builder = Builder()
                .setSession("TauriVpnService")
                .setBlocking(false)
        
        var mtu = args?.getInt(MTU) ?: 1500
        var ipv4Addr = args?.getString(IPV4_ADDR) ?: "10.126.126.1/24"
        var dns: String? = args?.getString(DNS)
        var routes = args?.getStringArray(ROUTES) ?: emptyArray()
        var disallowedApplications = args?.getStringArray(DISALLOWED_APPLICATIONS) ?: emptyArray()

        println("vpn create vpn interface. mtu: $mtu, ipv4Addr: $ipv4Addr, dns:" +
            "$dns, routes: ${java.util.Arrays.toString(routes)}," +
            "disallowedApplications:  ${java.util.Arrays.toString(disallowedApplications)}")

        val ipParts = ipv4Addr.split("/")
        if (ipParts.size != 2) throw IllegalArgumentException("Invalid IP addr string")
        builder.addAddress(ipParts[0], ipParts[1].toInt())
        builder.addAddress("fd00::1", 128)

        builder.setMtu(mtu)
        dns?.let { builder.addDnsServer(it) }

        for (route in routes) {
            val ipParts = route.split("/")
            if (ipParts.size != 2) throw IllegalArgumentException("Invalid route cidr string")
            builder.addRoute(ipParts[0], ipParts[1].toInt())
        }
        
        for (app in disallowedApplications) {
            builder.addDisallowedApplication(app)
        }

        return builder.also {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                it.setMetered(false)
            }
        }
        .establish()
        ?: throw IllegalStateException("Failed to init VpnService")
    }
}
