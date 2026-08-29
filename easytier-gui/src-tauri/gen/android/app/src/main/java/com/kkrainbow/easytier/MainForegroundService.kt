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
import androidx.core.app.NotificationCompat
import android.util.Log

class MainForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "easytier_channel"
        const val NOTIFICATION_ID = 1355
        // You can add more constants if needed
    }

    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        // Idle-state twin of the plugin's updateNotification (same channel/id
        // contract); the IO ticker replaces this once traffic starts flowing.
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EasyTier")
            .setContentText("网络空闲 · 隧道守护中")
            .setSmallIcon(R.drawable.ic_notification)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setShowWhen(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .addAction(NotificationCompat.Action(
                R.drawable.ic_notification, "打开", openAppIntent()))
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
        val launch = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
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
            val channel = NotificationChannel(
                CHANNEL_ID,
                "easytier notice",
                NotificationManager.IMPORTANCE_DEFAULT
            )
            channel.description = "显示 EasyTier 隧道在线状态与实时收发速率，可用于快速打开 App。"
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
            } catch (e: Exception) {
                Log.e("MainForegroundService", "Failed to create notification channel", e)
            }
        }
    }
}