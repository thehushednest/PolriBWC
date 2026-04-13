package id.co.senopati.polribwc

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class PolriPersistentService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Standby", ""))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                val status = intent.getStringExtra(EXTRA_STATUS) ?: "Standby"
                val channel = intent.getStringExtra(EXTRA_CHANNEL) ?: ""
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(status, channel))
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Polri BWC Background",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Menjaga Polri BWC tetap aktif di background"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(status: String, channelLabel: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT }
        val pendingLaunch = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val title = if (channelLabel.isNotBlank()) "PTT $status · $channelLabel" else "PTT $status"
        val body = if (status.equals("TRANSMITTING", ignoreCase = true))
            "Sedang transmisi — tekan Volume untuk melepas"
        else
            "Tombol Volume = PTT · App berjalan di background"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
        else
            @Suppress("DEPRECATION")
            Notification.Builder(this)

        return builder
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(pendingLaunch)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "polri_bwc_background"
        const val NOTIFICATION_ID = 10421

        const val ACTION_STOP = "id.co.senopati.polribwc.ACTION_STOP"
        const val ACTION_UPDATE = "id.co.senopati.polribwc.ACTION_UPDATE"
        const val EXTRA_STATUS = "status"
        const val EXTRA_CHANNEL = "channel"

        fun update(context: Context, status: String, channel: String) {
            val intent = Intent(context, PolriPersistentService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_STATUS, status)
                putExtra(EXTRA_CHANNEL, channel)
            }
            context.startService(intent)
        }
    }
}
