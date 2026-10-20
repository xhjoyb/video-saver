package com.xhjoyb.videosaver

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "videosaver/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveVideo" -> handleSave(call, result, isImage = false)
                    "saveImage" -> handleSave(call, result, isImage = true)
                    "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    else -> result.notImplemented()
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