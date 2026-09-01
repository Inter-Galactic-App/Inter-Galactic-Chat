package chat.intergalactic.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundForCall(intent)
        return START_NOT_STICKY
    }

    private fun startForegroundForCall(intent: Intent?) {
        val roomName = intent?.getStringExtra(EXTRA_ROOM_NAME)?.takeIf { it.isNotBlank() }
        val usesMicrophone = intent?.getBooleanExtra(EXTRA_USES_MICROPHONE, false) == true
        val usesCamera = intent?.getBooleanExtra(EXTRA_USES_CAMERA, false) == true

        ensureNotificationChannel()

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            pendingIntentFlags,
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ig_notification_icon)
            .setContentTitle("Inter Galactic call")
            .setContentText(roomName ?: "Call in progress")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                foregroundServiceType(usesMicrophone, usesCamera),
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Calls",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps active Inter Galactic calls connected in the background."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun foregroundServiceType(
        usesMicrophone: Boolean,
        usesCamera: Boolean,
    ): Int {
        var serviceType = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (usesMicrophone) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            if (usesCamera) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
        }

        return serviceType
    }

    companion object {
        private const val ACTION_START = "chat.intergalactic.app.call.START"
        private const val EXTRA_ROOM_NAME = "room_name"
        private const val EXTRA_USES_MICROPHONE = "uses_microphone"
        private const val EXTRA_USES_CAMERA = "uses_camera"
        private const val CHANNEL_ID = "intergalactic_calls"
        private const val NOTIFICATION_ID = 9101

        fun start(
            context: Context,
            roomName: String?,
            usesMicrophone: Boolean,
            usesCamera: Boolean,
        ) {
            val intent = Intent(context, CallForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_ROOM_NAME, roomName)
                putExtra(EXTRA_USES_MICROPHONE, usesMicrophone)
                putExtra(EXTRA_USES_CAMERA, usesCamera)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallForegroundService::class.java))
        }
    }
}
