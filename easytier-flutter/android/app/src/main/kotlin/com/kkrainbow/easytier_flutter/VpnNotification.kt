package com.kkrainbow.easytier_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.util.Locale

/**
 * The single source of truth for EasyTier's ongoing notification.
 *
 * Contract (ported from the deprecated Tauri client, contract C2 there): the
 * whole app owns exactly ONE ongoing notification, posted under [CHANNEL_ID] /
 * [NOTIFICATION_ID]. Both the foreground VPN service (initial post) and
 * [MainActivity] (live rx/tx updates from Dart) go through this object, so the
 * ids cannot drift and updates land on the same notification in place instead
 * of stacking a second one.
 *
 * The Flutter client has a single foreground service (unlike the Tauri client,
 * which also had a no-TUN keepalive service), so keeping one notification per
 * app is a property of using these constants, not of coordination code.
 *
 * Channel id / notification id are intentionally identical to the Tauri
 * client's: on upgrade the user keeps the same channel (and its importance /
 * sound settings) and the old notification is replaced, not duplicated.
 */
internal object VpnNotification {
    private const val TAG = "VpnNotification"

    /** Ongoing-notification channel. Shared with the deprecated Tauri client. */
    const val CHANNEL_ID = "easytier_channel_v2"

    /** Pre-rename channel of the Tauri client; deleted so the shade has one. */
    private const val LEGACY_CHANNEL_ID = "easytier_channel"

    /** The one and only ongoing-notification slot of this app. */
    const val NOTIFICATION_ID = 1355

    /** Action sent to [EasyTierVpnService] by the "Disconnect" action button. */
    const val ACTION_DISCONNECT = "com.kkrainbow.easytier_flutter.action.VPN_DISCONNECT"

    /**
     * What the ongoing notification should say right now.
     *
     * @param connected whether the EasyTier core reports the network up. Kept
     *   separate from "the TUN exists" so an established-but-connecting tunnel
     *   reads as idle instead of pretending to be connected.
     * @param rxBps received bytes/second as sampled by the Dart side.
     * @param txBps transmitted bytes/second as sampled by the Dart side.
     * @param stale true when those samples stopped arriving (screen off /
     *   engine timers throttled); the copy switches to a static background
     *   sentence so the user never reads frozen numbers.
     */
    data class State(
        val connected: Boolean = false,
        val rxBps: Double = 0.0,
        val txBps: Double = 0.0,
        val stale: Boolean = false,
    )

    /** Creates the channel if needed and drops the legacy one. Idempotent. */
    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        } catch (_: Throwable) {
            // Nothing to delete on a fresh install.
        }
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.notification_channel_desc)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION") // setSound/setVibrate are no-ops on API 26+, the channel governs.
    fun build(context: Context, state: State): Notification {
        ensureChannel(context)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }

        val icon = R.drawable.ic_notification
        val openIntent = openAppIntent(context)

        builder
            .setSmallIcon(icon)
            .setContentTitle(
                context.getString(
                    if (state.connected) R.string.notification_title_connected else R.string.app_name,
                ),
            )
            .setContentText(contentText(context, state))
            .setContentIntent(openIntent)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)

        // Silent status surface, not an alert. API 26+ ignores these in favour
        // of the channel's IMPORTANCE_LOW; they keep API 24/25 quiet too.
        builder.setSound(null).setVibrate(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }

        builder.addAction(action(context, icon, R.string.notification_action_open, openIntent))
        builder.addAction(
            action(context, icon, R.string.notification_action_disconnect, disconnectIntent(context)),
        )

        return builder.build()
    }

    /**
     * Updates the already-posted ongoing notification in place (same id as the
     * foreground-service notification). No-op when the service is not running:
     * the notification then belongs to the system's FGS lifecycle.
     */
    fun notify(context: Context, state: State) {
        if (!EasyTierVpnService.isRunning()) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        try {
            manager.notify(NOTIFICATION_ID, build(context, state))
        } catch (t: Throwable) {
            Log.e(TAG, "failed to update the ongoing notification", t)
        }
    }

    private fun contentText(context: Context, state: State): String = when {
        !state.connected -> context.getString(R.string.notification_text_idle)
        state.stale -> context.getString(R.string.notification_text_background)
        // Plain text on purpose: platform notification text has a single
        // typeface, so the monospace data treatment used in-app cannot apply.
        else -> context.getString(
            R.string.notification_text_rates,
            formatRate(state.txBps),
            formatRate(state.rxBps),
        )
    }

    @Suppress("DEPRECATION")
    private fun action(
        context: Context,
        icon: Int,
        titleRes: Int,
        intent: PendingIntent,
    ): Notification.Action =
        Notification.Action.Builder(icon, context.getString(titleRes), intent).build()

    private fun openAppIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent().apply { setClassName(context.packageName, MainActivity::class.java.name) }
        launch.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Lets the user drop the tunnel straight from the shade, without the app. */
    private fun disconnectIntent(context: Context): PendingIntent {
        val intent = Intent(context, EasyTierVpnService::class.java)
            .setAction(ACTION_DISCONNECT)
        return PendingIntent.getService(
            context,
            1,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Decimal (1000) units, matching the in-app `formatRate` so the
     * notification and the UI never disagree about the same sample.
     */
    private fun formatRate(bytesPerSecond: Double): String {
        val units = arrayOf("B/s", "KB/s", "MB/s", "GB/s")
        if (!bytesPerSecond.isFinite() || bytesPerSecond <= 0.0) return "0 ${units[0]}"
        var value = bytesPerSecond
        var unit = 0
        while (value >= 1000.0 && unit < units.size - 1) {
            value /= 1000.0
            unit++
        }
        val number = if (value >= 100.0) {
            String.format(Locale.US, "%.0f", value)
        } else {
            String.format(Locale.US, "%.1f", value)
        }
        return "$number ${units[unit]}"
    }
}
