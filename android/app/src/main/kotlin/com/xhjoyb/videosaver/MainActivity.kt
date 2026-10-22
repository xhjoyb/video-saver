package com.xhjoyb.videosaver

import android.content.ContentValues
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val channelName = "videosaver/media"

    companion object {
        /** 单个样本上限：1080P / 4K 关键帧远小于 8MB */
        private const val MAX_SAMPLE_SIZE = 8 * 1024 * 1024
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideo" -> handleSave(call, result, isImage = false)
                    "saveImage" -> handleSave(call, result, isImage = true)
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    "openMedia" -> handleOpen(call, result)
                    "muxAv" -> handleMux(call, result)
                    "startDownloadService" -> {
                        DownloadForegroundService.start(
                            this,
                            call.argument<Int>("running") ?: 0,
                            call.argument<Int>("queued") ?: 0,
                        )
                        result.success(true)
                    }
                    "updateDownloadService" -> {
                        DownloadForegroundService.update(
                            this,
                            call.argument<Int>("running") ?: 0,
                            call.argument<Int>("queued") ?: 0,
                            call.argument<Int>("progress") ?: -1,
                        )
                        result.success(true)
                    }
                    "stopDownloadService" -> {
                        DownloadForegroundService.stop(this)
                        result.success(true)
                    }
                    "getWebViewCookies" -> {
                        val url = call.argument<String>("url") ?: "https://www.bilibili.com"
                        val cookie = android.webkit.CookieManager.getInstance()
                            .getCookie(url) ?: ""
                        result.success(cookie)
                    }
                    else -> result.notImplemented()
                }
            }
        requestNotificationPermissionIfNeeded()
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) {
                requestPermissions(
                    arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                    2001,
                )
            }
        }
    }

    private fun handleSave(call: MethodCall, result: MethodChannel.Result, isImage: Boolean) {
        val path = call.argument<String>("path")
        val name = call.argument<String>("name") ?: if (isImage) "image.jpg" else "video.mp4"
        val mime = call.argument<String>("mime") ?: if (isImage) "image/jpeg" else "video/mp4"
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path is null", null)
            return
        }
        try {
            result.success(saveToGallery(File(path), name, mime, isImage))
        } catch (e: Exception) {
            result.error("save_failed", e.message, null)
        }
    }

    /**
     * 用系统查看器打开刚保存的 content:// 媒体，供「去相册看看」使用。
     * 找不到可用应用时返回 false，由 Flutter 侧提示。
     */
    private fun handleOpen(call: MethodCall, result: MethodChannel.Result) {
        val uriString = call.argument<String>("uri")
        if (uriString.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            val uri = Uri.parse(uriString)
            val mime = contentResolver.getType(uri) ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    /**
     * DASH 音视频合流：B 站 1080P 起只有分离的视频流与音轨。
     * 这里用 MediaExtractor + MediaMuxer 做纯转封装（不解码、不引入 ffmpeg 依赖）。
     */
    private fun handleMux(call: MethodCall, result: MethodChannel.Result) {
        val video = call.argument<String>("video")
        val audio = call.argument<String>("audio")
        val out = call.argument<String>("out")
        if (video.isNullOrBlank() || audio.isNullOrBlank() || out.isNullOrBlank()) {
            result.error("bad_args", "video/audio/out are required", null)
            return
        }
        Thread {
            try {
                muxAv(video, audio, out)
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error(
                        "mux_failed",
                        e.javaClass.simpleName + ": " + (e.message ?: ""),
                        null,
                    )
                }
            }
        }.apply { isDaemon = true }.start()
    }

    private fun muxAv(videoPath: String, audioPath: String, outPath: String) {
        val outFile = File(outPath)
        if (outFile.exists()) outFile.delete()
        outFile.parentFile?.mkdirs()

        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        try {
            val vEx = MediaExtractor().apply { setDataSource(videoPath) }
            val aEx = MediaExtractor().apply { setDataSource(audioPath) }
            videoExtractor = vEx
            audioExtractor = aEx

            val videoTrack = firstTrack(vEx, "video/")
            val audioTrack = firstTrack(aEx, "audio/")
            require(videoTrack >= 0) { "视频流缺失" }
            require(audioTrack >= 0) { "音频流缺失" }

            vEx.selectTrack(videoTrack)
            aEx.selectTrack(audioTrack)

            val out = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = out
            val outVideoTrack = out.addTrack(vEx.getTrackFormat(videoTrack))
            val outAudioTrack = out.addTrack(aEx.getTrackFormat(audioTrack))
            out.start()

            val buffer = ByteBuffer.allocateDirect(MAX_SAMPLE_SIZE)
            val info = MediaCodec.BufferInfo()
            // 两条流的起始时间不一定都是 0，统一按各自首个样本对齐
            val videoBase = vEx.sampleTime.coerceAtLeast(0L)
            val audioBase = aEx.sampleTime.coerceAtLeast(0L)

            var videoTime = vEx.sampleTime
            var audioTime = aEx.sampleTime
            while (videoTime >= 0 || audioTime >= 0) {
                // 按时间戳交错写入，避免输出文件整段视频在前、整段音频在后
                if (audioTime < 0 || (videoTime >= 0 && videoTime <= audioTime)) {
                    videoTime = writeSample(vEx, out, outVideoTrack, buffer, info, videoBase)
                } else {
                    audioTime = writeSample(aEx, out, outAudioTrack, buffer, info, audioBase)
                }
            }
        } finally {
            try { muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            try { videoExtractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
        }
    }

    /** 写入一个样本，返回下一样本的时间戳（无更多样本为 -1） */
    private fun writeSample(
        extractor: MediaExtractor,
        muxer: MediaMuxer,
        track: Int,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        baseTimeUs: Long,
    ): Long {
        val size = extractor.readSampleData(buffer, 0)
        if (size < 0) return -1
        info.offset = 0
        info.size = size
        info.presentationTimeUs = (extractor.sampleTime - baseTimeUs).coerceAtLeast(0L)
        info.flags = extractor.sampleFlags
        muxer.writeSampleData(track, buffer, info)
        extractor.advance()
        return extractor.sampleTime
    }

    private fun firstTrack(extractor: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(mimePrefix)) return i
        }
        return -1
    }

    /**
     * 写入系统相册：
     * 视频 -> Movies/VideoSaver
     * 图片 -> Pictures/VideoSaver
     */
    private fun saveToGallery(
        file: File,
        displayName: String,
        mime: String,
        isImage: Boolean,
    ): String {
        require(file.exists()) { "file not found: ${file.absolutePath}" }
        val q = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val relative = if (isImage) {
            "${Environment.DIRECTORY_PICTURES}/VideoSaver"
        } else {
            "${Environment.DIRECTORY_MOVIES}/VideoSaver"
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (q) {
                put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val collection: Uri = if (isImage) {
            if (q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
        } else {
            if (q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
        }

        val resolver = contentResolver
        val uri = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore insert failed")

        resolver.openOutputStream(uri)?.use { out ->
            file.inputStream().use { input -> input.copyTo(out) }
        } ?: throw IllegalStateException("openOutputStream failed")

        if (q) {
            val done = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, done, null, null)
        }
        return uri.toString()
    }
}