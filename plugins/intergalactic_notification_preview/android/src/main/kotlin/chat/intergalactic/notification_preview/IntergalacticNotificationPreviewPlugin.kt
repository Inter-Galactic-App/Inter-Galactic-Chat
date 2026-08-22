package chat.intergalactic.notification_preview

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class IntergalacticNotificationPreviewPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != CONTENT_URI_METHOD && call.method != REVOKE_URI_METHOD) {
            result.notImplemented()
            return
        }

        val applicationContext = context
        if (applicationContext == null) {
            result.error(ERROR_UNAVAILABLE, ERROR_MESSAGE, null)
            return
        }

        if (call.method == REVOKE_URI_METHOD) {
            revokePreviewGrants(applicationContext, call, result)
            return
        }

        val rawPath = call.argument<String>("path")
        if (rawPath.isNullOrBlank()) {
            result.error(ERROR_INVALID_PREVIEW, ERROR_MESSAGE, null)
            return
        }

        try {
            val previewRoot = File(
                applicationContext.cacheDir,
                PREVIEW_DIRECTORY,
            ).canonicalFile
            val preview = File(rawPath).canonicalFile
            if (!preview.path.startsWith(previewRoot.path + File.separator) || !preview.isFile) {
                result.error(ERROR_INVALID_PREVIEW, ERROR_MESSAGE, null)
                return
            }

            val previewUri = FileProvider.getUriForFile(
                applicationContext,
                "${applicationContext.packageName}.fileprovider",
                preview,
            )
            applicationContext.grantUriPermission(
                SYSTEM_UI_PACKAGE,
                previewUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            Log.i(TAG, "android_notification_preview result=uri_granted target=system_ui")
            result.success(previewUri.toString())
        } catch (_: Exception) {
            Log.w(TAG, "android_notification_preview result=uri_failed reason=native_exception")
            result.error(ERROR_STAGING, ERROR_MESSAGE, null)
        }
    }

    /// Releases the read grants for previews the Dart-side sweep has deleted.
    ///
    /// `grantUriPermission` had no matching revoke, so every staged preview left
    /// a grant behind for the life of the process while its file was removed
    /// after two days. Each entry then pointed at a path that no longer
    /// existed. The sweep knows which files it deleted, so it names them here
    /// and this rebuilds the same content URI to revoke.
    ///
    /// Paths are re-validated against the preview root exactly as the staging
    /// path does: this method takes caller-supplied paths, and revoking is a
    /// write to our own permission table, so it must not be reachable for an
    /// arbitrary file.
    private fun revokePreviewGrants(
        applicationContext: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val paths = call.argument<List<String>>("paths").orEmpty()
        var revoked = 0
        val previewRoot = File(applicationContext.cacheDir, PREVIEW_DIRECTORY).canonicalFile
        for (rawPath in paths) {
            if (rawPath.isBlank()) {
                continue
            }
            try {
                val preview = File(rawPath).canonicalFile
                if (!preview.path.startsWith(previewRoot.path + File.separator)) {
                    continue
                }
                val previewUri = FileProvider.getUriForFile(
                    applicationContext,
                    "${applicationContext.packageName}.fileprovider",
                    preview,
                )
                applicationContext.revokeUriPermission(
                    previewUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
                revoked += 1
            } catch (_: Exception) {
                // A path the provider will not map is one we never granted.
                // Nothing to release, and nothing worth failing the sweep for.
            }
        }
        Log.i(TAG, "android_notification_preview result=grants_revoked count=$revoked")
        result.success(revoked)
    }

    private companion object {
        const val TAG = "NotificationPreview"
        const val CHANNEL = "chat.intergalactic.app/notification_preview"
        const val CONTENT_URI_METHOD = "contentUriForNotificationPreview"
        const val REVOKE_URI_METHOD = "revokeNotificationPreviewGrants"
        const val PREVIEW_DIRECTORY = "shared_media/notification-previews"
        const val SYSTEM_UI_PACKAGE = "com.android.systemui"
        const val ERROR_UNAVAILABLE = "notification_preview_unavailable"
        const val ERROR_INVALID_PREVIEW = "invalid_preview"
        const val ERROR_STAGING = "notification_preview_error"
        const val ERROR_MESSAGE = "Notification preview could not be staged."
    }
}
