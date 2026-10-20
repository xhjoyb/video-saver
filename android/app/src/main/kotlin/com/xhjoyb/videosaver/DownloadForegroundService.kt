package com.xhjoyb.videosaver

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * 下载队列的前台服务：只负责「让进程在后台存活 + 通知栏进度」，
 * 真正的下载仍在 Flutter/Dart 侧执行。
 */
class DownloadForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "videosaver_download"
        private const val NOTIFICATION_ID = 2001

        private const val ACTION_START = "com.xhjoyb.videosaver.DOWNLOAD_START"
        private const val ACTION_UPDATE = "com.xhjoyb.videosaver.DOWNLOAD_UPDATE"

        private const val EXTRA_RUNNING = "running"
        private const val EXTRA_QUEUED = "queued"
        private const val EXTRA_PROGRESS = "progress"

        @Volatile
        private var isServiceRunning = false

        fun start(context: Context, running: Int, queued: Int) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_RUNNING, running)
                putExtra(EXTRA_QUEUED, queued)
            }
            isServiceRunning = true
            try {
                context.startForegroundService(intent)
            } catch (e: Exception) {
                // Android 12+ 后台启动前台服务受限时静默降级
            }
        }

        fun update(context: Context, running: Int, queued: Int, progress: Int) {
            val intent = Intent(context, DownloadForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_RUNNING, running)
                putExtra(EXTRA_QUEUED, queued)
                putExtra(EXTRA_PROGRESS, progress)
            }
            try {
                // 服务已在前台运行时用 startService 更新，避免再次触发前台服务启动限制
                if (isServiceRunning) {
                    context.startService(intent)
                } else {
                    isServiceRunning = true
                    context.startForegroundService(intent)
                }
            } catch (e: Exception) {
                // 后台受限时忽略，服务仍在运行
            }
        }

        fun stop(context: Context) {
            isServiceRunning = false
            try {
                context.stopService(Intent(context, DownloadForegroundService::class.java))
            } catch (_: Exception) {
            }
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "videosaver:download")
            .apply {
                setReferenceCounted(false)
                acquire(60 * 60 * 1000L)
            }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val running = intent?.getIntExtra(EXTRA_RUNNING, 0) ?: 0
        val queued = intent?.getIntExtra(EXTRA_QUEUED, 0) ?: 0
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1

        if (running <= 0 && queued <= 0) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        val notification = buildNotification(running, queued, progress)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isServiceRunning = false
        wakeLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        wakeLock = null
        super.onDestroy()
    }

    private fun createChannel() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "下载任务",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "显示视频下载队列的进度"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(running: Int, queued: Int, progress: Int): Notification {
        val text = when {
            queued > 0 -> "$running 个进行中，$queued 个等待"
            running > 0 -> "$running 个进行中"
            else -> "准备中"
        }
        val builder = Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("视频嗅探 · 正在下载")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (progress in 0..100) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }
}