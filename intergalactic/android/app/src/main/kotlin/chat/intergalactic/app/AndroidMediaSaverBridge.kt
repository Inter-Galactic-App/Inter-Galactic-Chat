package chat.intergalactic.app

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.OutputStream
import java.util.concurrent.Executors

private const val MEDIA_SAVER_CHANNEL = "chat.intergalactic.app/media_saver"
private const val MEDIA_SAVER_TAG = "IGMediaSaver"
private const val MEDIA_SAVER_ALBUM = "Inter Galactic"
private const val MEDIA_SAVER_COPY_BUFFER_BYTES = 8 * 1024

/// Saves image and video media into the device gallery so it shows up in
/// Photos/Gallery apps rather than only inside app-private storage.
///
/// This is the Android counterpart of the iOS `media_saver` channel in
/// AppDelegate.swift, and answers the same two method names so the Dart side
/// (`DownloadUtils`) does not have to branch per platform.
///
/// Storage model differs sharply across the supported range:
///  - API 29+ (scoped storage): insert into MediaStore with IS_PENDING, stream
///    the bytes through the ContentResolver, then clear IS_PENDING. No runtime
///    permission is required for an app writing its own media.
///  - API 24-28: MediaStore rows still point at real public files, so the write
///    needs WRITE_EXTERNAL_STORAGE. The permission is requested on demand and
///    the save is replayed once the user answers.
object AndroidMediaSaverBridge {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingRequest: PendingSave? = null

    private class PendingSave(
        val bytes: ByteArray?,
        val path: String?,
        val filename: String,
        val mimeType: String?,
        val result: MethodChannel.Result,
    )

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MEDIA_SAVER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Kept distinct so the channel contract matches iOS, where the
                // image-only entry point predates the media one.
                "saveImageToPhotos" -> saveMedia(activity, call, result, imagesOnly = true)
                "saveMediaToPhotos" -> saveMedia(activity, call, result, imagesOnly = false)
                else -> result.notImplemented()
            }
        }
    }

    /// Replays a save that was parked waiting for WRITE_EXTERNAL_STORAGE.
    /// Returns true when the request code belonged to this bridge.
    fun onRequestPermissionsResult(
        activity: Activity,
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != MEDIA_SAVER_PERMISSION_REQUEST) {
            return false
        }

        val pending = pendingRequest
        pendingRequest = null
        if (pending == null) {
            return true
        }

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            performSave(activity, pending)
        } else {
            pending.result.error(
                "photo_permission_denied",
                "Storage access is needed to save media to the gallery.",
                null,
            )
        }

        return true
    }

    private fun saveMedia(
        activity: Activity,
        call: MethodCall,
        result: MethodChannel.Result,
        imagesOnly: Boolean,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val path = call.argument<String>("path")?.takeIf { it.isNotBlank() }
        val filename = call.argument<String>("filename")?.takeIf { it.isNotBlank() }
            ?: "intergalactic-media"
        val mimeType = call.argument<String>("mimeType")?.lowercase()

        if ((bytes == null || bytes.isEmpty()) && path == null) {
            result.error("invalid_arguments", "Media bytes or a file path are required.", null)
            return
        }

        if (imagesOnly && mimeType != null && mimeType.startsWith("video/")) {
            result.error("invalid_arguments", "Image media is required.", null)
            return
        }

        val request = PendingSave(bytes, path, filename, mimeType, result)

        if (!requiresLegacyStoragePermission()) {
            performSave(activity, request)
            return
        }

        if (
            ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            performSave(activity, request)
            return
        }

        if (pendingRequest != null) {
            result.error("media_saver_busy", "Another gallery save is awaiting permission.", null)
            return
        }

        pendingRequest = request
        activity.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            MEDIA_SAVER_PERMISSION_REQUEST,
        )
    }

    private fun requiresLegacyStoragePermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.Q
    }

    private fun performSave(activity: Activity, request: PendingSave) {
        val context = activity.applicationContext
        ioExecutor.execute {
            try {
                val uri = writeToMediaStore(context, request)
                mainHandler.post {
                    if (uri != null) {
                        request.result.success(true)
                    } else {
                        request.result.error(
                            "media_save_failed",
                            "The media could not be saved to the gallery.",
                            null,
                        )
                    }
                }
            } catch (exception: Exception) {
                Log.w(MEDIA_SAVER_TAG, "Failed to save media to the gallery", exception)
                mainHandler.post {
                    request.result.error(
                        "media_save_failed",
                        exception.message ?: "The media could not be saved to the gallery.",
                        null,
                    )
                }
            }
        }
    }

    private fun writeToMediaStore(context: Context, request: PendingSave): Uri? {
        val effectiveMimeType = request.mimeType ?: "image/*"
        val isVideo = effectiveMimeType.startsWith("video/")
        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, request.filename)
            put(MediaStore.MediaColumns.MIME_TYPE, effectiveMimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val base = if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$base/$MEDIA_SAVER_ALBUM")
                // Hide the row until the bytes are fully written, so gallery
                // apps never index a half-copied file.
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val resolver = context.contentResolver
        val uri = resolver.insert(collection, values) ?: return null

        try {
            resolver.openOutputStream(uri).use { stream ->
                if (stream == null) {
                    throw IllegalStateException("Gallery destination could not be opened for writing.")
                }
                writeSource(request, stream)
            }
        } catch (exception: Exception) {
            // Leave no pending placeholder row behind on failure.
            runCatching { resolver.delete(uri, null, null) }
            throw exception
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val published = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, published, null, null)
        }

        return uri
    }

    private fun writeSource(request: PendingSave, destination: OutputStream) {
        val path = request.path
        if (path != null) {
            val source = File(path)
            if (source.exists() && source.length() > 0) {
                FileInputStream(source).use { input ->
                    input.copyTo(destination, MEDIA_SAVER_COPY_BUFFER_BYTES)
                }
                return
            }
        }

        val bytes = request.bytes
        if (bytes == null || bytes.isEmpty()) {
            throw IllegalStateException("The media to save could not be read.")
        }

        destination.write(bytes)
    }
}
