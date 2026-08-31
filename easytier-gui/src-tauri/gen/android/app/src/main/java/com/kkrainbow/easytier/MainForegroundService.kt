package com.kkrainbow.easytier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class MainForegroundService : Service() {
    companion object {
        // Contract: must match VpnServicePlugin.NOTIFY_CHANNEL_ID across modules
        const val CHANNEL_ID = "easytier_channel_v2"
        const val OLD_CHANNEL_ID = "easytier_channel"
        const val NOTIFICATION_ID = 1355
    }

    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        // Idle-state twin of the plugin's updateNotification (same channel/id
        // contract); the IO ticker replaces this once traffic starts flowing.
        val title = getString(R.string.app_name)
        val text = getString(R.string.notification_text_idle)
        val openText = getString(R.string.notification_action_open)

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(openAppIntent())
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(
                NotificationCompat.Action(
                    R.drawable.ic_notification,
                    openText,
                    openAppIntent()
                )
            )
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    /** Tapping the notification opens MainActivity; immutable on API 23+. */
    private fun openAppIntent(): PendingIntent {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java).apply {
                setClassName(packageName, "$packageName.MainActivity")
            }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or (
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(this, 0, launch, piFlags)
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val manager = getSystemService(NotificationManager::class.java)
                // Delete legacy IMPORTANCE_DEFAULT channel to fix notification sound/badge
                manager?.deleteNotificationChannel(OLD_CHANNEL_ID)
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = getString(R.string.notification_channel_desc)
                    setShowBadge(false)
                }
                manager?.createNotificationChannel(channel)
            } catch (e: Exception) {
                Log.e("MainForegroundService", "Failed to create notification channel", e)
            }
        }
    }
}
