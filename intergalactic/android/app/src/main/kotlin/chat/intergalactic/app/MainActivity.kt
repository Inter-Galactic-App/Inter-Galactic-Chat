package chat.intergalactic.app

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaRecorder
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Rational
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.webkit.MimeTypeMap
import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.io.File
import java.lang.ref.WeakReference
import java.nio.ByteBuffer
import java.util.concurrent.Executor
import kotlin.math.ceil
import kotlin.math.max


class MainActivity: FlutterFragmentActivity() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return provideEngine(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        registerMethods(flutterEngine, this);
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (AndroidCameraMediaPickerBridge.onRequestPermissionsResult(this, requestCode, grantResults)) {
            return
        }
        if (AndroidVoiceRecorderBridge.onRequestPermissionsResult(requestCode, grantResults)) {
            return
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (AndroidCameraMediaPickerBridge.onActivityResult(this, requestCode, resultCode, data)) {
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AndroidCallBackgroundBridge.handlePictureInPictureIntent(intent)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidCallBackgroundBridge.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }

    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        AndroidCallBackgroundBridge.onMultiWindowModeChanged(isInMultiWindowMode)
    }

    companion object {
        var engine: FlutterEngine? = null
        fun provideEngine(context: Context): FlutterEngine {
            val eng = engine ?: FlutterEngine(context, emptyArray(), true, false)
            engine = eng
            return eng
        }
    }
}

abstract class BaseActivity : FlutterFragmentActivity() {

    abstract var entryPoint: String

    override fun getDartEntrypointFunctionName() = entryPoint

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        registerMethods(flutterEngine, this);
        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (AndroidCameraMediaPickerBridge.onRequestPermissionsResult(this, requestCode, grantResults)) {
            return
        }
        if (AndroidVoiceRecorderBridge.onRequestPermissionsResult(requestCode, grantResults)) {
            return
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (AndroidCameraMediaPickerBridge.onActivityResult(this, requestCode, resultCode, data)) {
            return
        }

        super.onActivityResult(requestCode, resultCode, data)
    }
}

class BubbleActivity : BaseActivity() {
    override var entryPoint = "bubble"
}

private const val APP_ICON_CHANNEL = "chat.intergalactic.app/app_icon"
private const val BIOMETRIC_CHANNEL = "chat.intergalactic.app/biometrics"
private const val ANDROID_CAMERA_MEDIA_PICKER_CHANNEL = "chat.intergalactic.app/android_camera_media_picker"
private const val MEDIA_SHARE_CHANNEL = "chat.intergalactic.app/media_share"
private const val MOBILE_CALL_BACKGROUND_CHANNEL = "chat.intergalactic.app/mobile_call_background"
private const val NOTIFICATION_DIAGNOSTICS_CHANNEL = "chat.intergalactic.app/notification_diagnostics"
private const val STORY_VIDEO_EXPORT_CHANNEL = "chat.intergalactic.app/story_video_export"
private const val VOICE_RECORDER_CHANNEL = "chat.intergalactic.app/voice_recorder"
private const val VOICE_RECORDER_PERMISSION_REQUEST = 7301
private const val CAMERA_MEDIA_PICKER_REQUEST = 7302
private const val CAMERA_MEDIA_PICKER_PERMISSION_REQUEST = 7303
private const val CAMERA_MEDIA_KIND_PHOTO = "photo"
private const val CAMERA_MEDIA_KIND_VIDEO = "video"
private const val LAUNCHER_LIGHT_ALIAS = "chat.intergalactic.app.LauncherLightAlias"
private const val LAUNCHER_DARK_ALIAS = "chat.intergalactic.app.LauncherDarkAlias"
private const val LAUNCHER_SYSTEM_ALIAS = "chat.intergalactic.app.LauncherSystemAlias"
private const val MOBILE_CALL_PIP_CONTROL_ACTION = "chat.intergalactic.app.action.MOBILE_CALL_PIP_CONTROL"
private const val MOBILE_CALL_PIP_EXTRA_ACTION = "action"
private const val MOBILE_CALL_PIP_EXTRA_SESSION_ID = "sessionId"
private const val MOBILE_CALL_PIP_ACTION_RETURN = "returnToCall"
private const val MOBILE_CALL_PIP_ACTION_HANG_UP = "hangUp"
private const val MOBILE_CALL_PIP_ACTION_MUTE = "muteMicrophone"
private const val MOBILE_CALL_PIP_ACTION_CAMERA = "toggleCamera"

fun registerMethods(flutterEngine: FlutterEngine, activity: Activity) {
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chat.intergalactic.app/utils").apply {
        setMethodCallHandler { call, result ->
            if(call.method == "dismissKeyboard") {
                hideKeyboard(activity);
                result.success(null);
            }
            if(call.method == "isKeyboardOpen") {
                result.success(isKeyboardOpen(activity));
            }
        }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_ICON_CHANNEL).apply {
        setMethodCallHandler { call, result ->
            if (call.method != "setAppIcon") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val mode = call.argument<String>("mode") ?: "system"
            val brightness = call.argument<String>("brightness")

            try {
                setLauncherIconAlias(activity, mode, brightness)
                result.success(null)
            } catch (exception: Exception) {
                result.error("app_icon_error", exception.message, null)
            }
        }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BIOMETRIC_CHANNEL).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "getBiometricAvailability" -> {
                    result.success(getBiometricAvailability(activity))
                }
                "authenticate" -> {
                    authenticateWithBiometrics(
                        activity = activity,
                        reason = call.argument<String>("reason"),
                        result = result,
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_SHARE_CHANNEL).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> shareMediaFile(
                    activity,
                    call.argument<ByteArray>("bytes"),
                    call.argument<String>("filename"),
                    call.argument<String>("mimeType"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_DIAGNOSTICS_CHANNEL).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "getNotificationDiagnostics" -> {
                    try {
                        result.success(getNotificationDiagnostics(activity))
                    } catch (exception: Exception) {
                        result.error("notification_diagnostics_error", exception.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    SecureRecoveryKeyStore.register(flutterEngine, activity)
    AndroidCallBackgroundBridge.register(flutterEngine, activity)
    AndroidCameraMediaPickerBridge.register(flutterEngine, activity)
    AndroidImageCutoutBridge.register(flutterEngine)
    AndroidStoryVideoExportBridge.register(flutterEngine, activity)
    AndroidVoiceRecorderBridge.register(flutterEngine, activity)
}

object AndroidCallBackgroundBridge {
    private data class PictureInPictureControlsState(
        val isMicrophoneMuted: Boolean = false,
        val isCameraEnabled: Boolean = false,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var isInPictureInPictureMode = false
    private var isInMultiWindowMode = false
    private var activeSessionId: String? = null
    private var controlsState = PictureInPictureControlsState()
    private var receiverRegistered = false
    private val pictureInPictureActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            handlePictureInPictureIntent(intent)
        }
    }

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MOBILE_CALL_BACKGROUND_CHANNEL,
        )
        channel = methodChannel
        registerPictureInPictureActionReceiver(activity.applicationContext)
        syncPresentationState(activity)
        methodChannel.apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCallBackgroundActive" -> {
                        val active = call.argument<Boolean>("active") == true
                        if (active) {
                            CallForegroundService.start(
                                context = activity.applicationContext,
                                roomName = call.argument<String>("roomName"),
                                usesMicrophone = call.argument<Boolean>("usesMicrophone") == true,
                                usesCamera = call.argument<Boolean>("usesCamera") == true,
                            )
                        } else {
                            CallForegroundService.stop(activity.applicationContext)
                        }
                        result.success(null)
                    }
                    "enterPictureInPicture" -> {
                        result.success(enterPictureInPicture(activity, call.arguments))
                    }
                    "exitPictureInPicture" -> {
                        result.success(false)
                    }
                    "updatePictureInPictureControls" -> {
                        result.success(updatePictureInPictureControls(activity, call.arguments))
                    }
                    "isPictureInPictureSupported" -> {
                        result.success(isPictureInPictureSupported(activity))
                    }
                    "getPopoutPresentationState" -> {
                        result.success(popoutPresentationState())
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun isPictureInPictureSupported(activity: Activity): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun registerPictureInPictureActionReceiver(context: Context) {
        if (receiverRegistered) {
            return
        }

        val filter = IntentFilter(MOBILE_CALL_PIP_CONTROL_ACTION)
        val broadcastPermission = mobileCallPipBroadcastPermission(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                pictureInPictureActionReceiver,
                filter,
                broadcastPermission,
                null,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(
                pictureInPictureActionReceiver,
                filter,
                broadcastPermission,
                null,
            )
        }
        receiverRegistered = true
    }

    private fun mobileCallPipBroadcastPermission(context: Context): String {
        return "${context.packageName}.permission.MOBILE_CALL_PIP_CONTROL"
    }

    fun onPictureInPictureModeChanged(active: Boolean) {
        isInPictureInPictureMode = active
        if (!active && !isInMultiWindowMode) {
            activeSessionId = null
        }
        publishPresentationState()
    }

    fun onMultiWindowModeChanged(active: Boolean) {
        isInMultiWindowMode = active
        if (!active && !isInPictureInPictureMode) {
            activeSessionId = null
        }
        publishPresentationState()
    }

    private fun syncPresentationState(activity: Activity) {
        isInPictureInPictureMode =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity.isInPictureInPictureMode
        isInMultiWindowMode =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInMultiWindowMode
    }

    private fun publishPresentationState() {
        mainHandler.post {
            channel?.invokeMethod(
                "mobileCallPresentationChanged",
                popoutPresentationState(),
            )
        }
    }

    private fun popoutPresentationState(): Map<String, Any> {
        return mapOf(
            "pictureInPicture" to isInPictureInPictureMode,
            "resizedPopout" to (isInMultiWindowMode && !isInPictureInPictureMode),
            "sessionId" to (activeSessionId ?: ""),
        )
    }

    fun handlePictureInPictureIntent(intent: Intent?) {
        if (intent?.action != MOBILE_CALL_PIP_CONTROL_ACTION) {
            return
        }
        val action = intent.getStringExtra(MOBILE_CALL_PIP_EXTRA_ACTION)?.takeIf { it.isNotBlank() }
            ?: return
        val sessionId = intent.getStringExtra(MOBILE_CALL_PIP_EXTRA_SESSION_ID)?.takeIf {
            it.isNotBlank()
        } ?: return
        if (activeSessionId == null || sessionId != activeSessionId) {
            return
        }
        publishPictureInPictureAction(action, sessionId)
    }

    private fun publishPictureInPictureAction(action: String, sessionId: String?) {
        mainHandler.post {
            channel?.invokeMethod(
                "mobileCallPictureInPictureAction",
                mapOf(
                    "action" to action,
                    "sessionId" to (sessionId ?: activeSessionId ?: ""),
                ),
            )
        }
    }

    private fun updatePictureInPictureControls(activity: Activity, rawArguments: Any?): Boolean {
        val arguments = rawArguments as? Map<*, *>
        activeSessionId = (arguments?.get("sessionId") as? String)
            ?.takeIf { it.isNotBlank() }
            ?: activeSessionId
        controlsState = controlsStateFrom(arguments)
        if (!isPictureInPictureSupported(activity) || !isInPictureInPictureMode) {
            return false
        }

        return setPictureInPictureParams(activity)
    }

    private fun enterPictureInPicture(activity: Activity, rawArguments: Any?): Boolean {
        if (!isPictureInPictureSupported(activity)) {
            return false
        }

        val arguments = rawArguments as? Map<*, *>
        val numerator = (arguments?.get("aspectRatioNumerator") as? Number)?.toInt() ?: 16
        val denominator = (arguments?.get("aspectRatioDenominator") as? Number)?.toInt() ?: 9
        val sourceRect = sourceRectFrom(arguments)
        activeSessionId = (arguments?.get("sessionId") as? String)?.takeIf { it.isNotBlank() }
        controlsState = controlsStateFrom(arguments)
        val rawRatio = numerator.toDouble() / denominator.coerceAtLeast(1).toDouble()
        val safeRatio = rawRatio.coerceIn(1.0 / 2.39, 2.39)
        val safeDenominator = 100000
        val safeNumerator = ceil(safeRatio * safeDenominator).toInt()
            .coerceIn(1, (2.39 * safeDenominator).toInt())

        val entered = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val builder = pictureInPictureParamsBuilder(activity)
                    .setAspectRatio(Rational(safeNumerator, safeDenominator))
                if (sourceRect != null) {
                    builder.setSourceRectHint(sourceRect)
                }
                activity.enterPictureInPictureMode(builder.build())
            } catch (_: IllegalArgumentException) {
                false
            } catch (_: IllegalStateException) {
                false
            }
        } else {
            false
        }
        if (!entered) {
            activeSessionId = null
        }
        return entered
    }

    private fun setPictureInPictureParams(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return try {
            activity.setPictureInPictureParams(pictureInPictureParamsBuilder(activity).build())
            true
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun pictureInPictureParamsBuilder(activity: Activity): PictureInPictureParams.Builder {
        val builder = PictureInPictureParams.Builder()
            .setActions(pictureInPictureActions(activity))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setSeamlessResizeEnabled(false)
        }
        return builder
    }

    private fun pictureInPictureActions(activity: Activity): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return emptyList()
        }

        val microphoneTitle = if (controlsState.isMicrophoneMuted) "Unmute" else "Mute"
        val microphoneIcon = if (controlsState.isMicrophoneMuted) {
            R.drawable.pip_mic_on
        } else {
            R.drawable.pip_mic_off
        }
        val cameraTitle = if (controlsState.isCameraEnabled) "Turn camera off" else "Turn camera on"
        val cameraIcon = if (controlsState.isCameraEnabled) {
            R.drawable.pip_camera_off
        } else {
            R.drawable.pip_camera_on
        }

        return listOf(
            pictureInPictureRemoteAction(
                activity = activity,
                action = MOBILE_CALL_PIP_ACTION_RETURN,
                title = "Return to call",
                iconRes = R.drawable.pip_return_to_call,
                foreground = true,
                requestCode = 9010,
            ),
            pictureInPictureRemoteAction(
                activity = activity,
                action = MOBILE_CALL_PIP_ACTION_MUTE,
                title = microphoneTitle,
                iconRes = microphoneIcon,
                requestCode = 9011,
            ),
            pictureInPictureRemoteAction(
                activity = activity,
                action = MOBILE_CALL_PIP_ACTION_CAMERA,
                title = cameraTitle,
                iconRes = cameraIcon,
                requestCode = 9012,
            ),
            pictureInPictureRemoteAction(
                activity = activity,
                action = MOBILE_CALL_PIP_ACTION_HANG_UP,
                title = "Hang up",
                iconRes = R.drawable.pip_hang_up,
                requestCode = 9013,
            ),
        )
    }

    private fun pictureInPictureRemoteAction(
        activity: Activity,
        action: String,
        title: String,
        iconRes: Int,
        foreground: Boolean = false,
        requestCode: Int,
    ): RemoteAction {
        val pendingIntent = if (foreground) {
            PendingIntent.getActivity(
                activity,
                requestCode,
                pictureInPictureActionIntent(activity, action, foreground = true),
                pictureInPicturePendingIntentFlags(),
            )
        } else {
            PendingIntent.getBroadcast(
                activity,
                requestCode,
                pictureInPictureActionIntent(activity, action),
                pictureInPicturePendingIntentFlags(),
            )
        }
        return RemoteAction(
            Icon.createWithResource(activity, iconRes),
            title,
            title,
            pendingIntent,
        )
    }

    private fun pictureInPictureActionIntent(
        activity: Activity,
        action: String,
        foreground: Boolean = false,
    ): Intent {
        val intent = if (foreground) {
            Intent(activity, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
        } else {
            Intent(MOBILE_CALL_PIP_CONTROL_ACTION).setPackage(activity.packageName)
        }
        return intent
            .putExtra(MOBILE_CALL_PIP_EXTRA_ACTION, action)
            .putExtra(MOBILE_CALL_PIP_EXTRA_SESSION_ID, activeSessionId ?: "")
    }

    private fun pictureInPicturePendingIntentFlags(): Int {
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        return PendingIntent.FLAG_UPDATE_CURRENT or immutable
    }

    private fun controlsStateFrom(arguments: Map<*, *>?): PictureInPictureControlsState {
        return PictureInPictureControlsState(
            isMicrophoneMuted = arguments?.get("isMicrophoneMuted") as? Boolean ?: false,
            isCameraEnabled = arguments?.get("isCameraEnabled") as? Boolean ?: false,
        )
    }

    private fun sourceRectFrom(arguments: Map<*, *>?): Rect? {
        if (arguments == null) {
            return null
        }
        val left = (arguments["sourceRectLeft"] as? Number)?.toInt() ?: return null
        val top = (arguments["sourceRectTop"] as? Number)?.toInt() ?: return null
        val right = (arguments["sourceRectRight"] as? Number)?.toInt() ?: return null
        val bottom = (arguments["sourceRectBottom"] as? Number)?.toInt() ?: return null
        if (right <= left || bottom <= top) {
            return null
        }
        return Rect(left, top, right, bottom)
    }
}

object AndroidCameraMediaPickerBridge {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingOutputFile: File? = null
    private var pendingMediaKind: String? = null

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANDROID_CAMERA_MEDIA_PICKER_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickCameraMedia" -> pickCameraMedia(
                        activity,
                        call.argument<String>("kind"),
                        result,
                    )
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun onRequestPermissionsResult(
        activity: Activity,
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_MEDIA_PICKER_PERMISSION_REQUEST) {
            return false
        }

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            launchCamera(activity)
        } else {
            finishWithError(
                "camera_permission_denied",
                "Camera access is needed to capture media.",
            )
        }

        return true
    }

    fun onActivityResult(
        activity: Activity,
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != CAMERA_MEDIA_PICKER_REQUEST) {
            return false
        }

        if (pendingResult == null) {
            clearPending(deleteOutput = true)
            return true
        }

        if (resultCode != Activity.RESULT_OK) {
            pendingResult?.success(null)
            clearPending(deleteOutput = true)
            return true
        }

        try {
            val returnedUri = data?.data ?: data?.clipData?.getItemAt(0)?.uri
            if (returnedUri != null) {
                val file = copyReturnedCameraUri(activity, returnedUri)
                finishWithSuccess(
                    cameraMediaPayload(
                        file = file,
                        mimeType = cameraMimeType(activity, returnedUri, file),
                    ),
                    deleteOutput = true,
                )
                return true
            }

            val outputFile = pendingOutputFile
            val mediaKind = pendingMediaKind ?: CAMERA_MEDIA_KIND_PHOTO
            if (outputFile != null && outputFile.exists() && outputFile.length() > 0) {
                finishWithSuccess(
                    cameraMediaPayload(
                        file = outputFile,
                        mimeType = cameraMimeTypeFromFile(outputFile)
                            .takeIf { it != "application/octet-stream" }
                            ?: fallbackCameraMimeType(mediaKind),
                    ),
                    deleteOutput = false,
                )
                return true
            }

            finishWithError(
                "camera_media_missing",
                "The captured media could not be found.",
            )
        } catch (exception: Exception) {
            finishWithError(
                "camera_media_export_failed",
                exception.message ?: "The captured media could not be exported.",
            )
        }

        return true
    }

    private fun pickCameraMedia(activity: Activity, kind: String?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("camera_picker_active", "A camera picker is already active.", null)
            return
        }

        pendingResult = result
        pendingMediaKind = normalizeCameraMediaKind(kind)

        if (
            ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            activity.requestPermissions(
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_MEDIA_PICKER_PERMISSION_REQUEST,
            )
            return
        }

        launchCamera(activity)
    }

    private fun launchCamera(activity: Activity) {
        val result = pendingResult
        if (result == null) {
            clearPending(deleteOutput = true)
            return
        }

        try {
            val mediaKind = pendingMediaKind ?: CAMERA_MEDIA_KIND_PHOTO
            val outputFile = nextCameraOutputFile(
                activity,
                extension = cameraOutputExtension(mediaKind),
            )
            val outputUri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                outputFile,
            )
            pendingOutputFile = outputFile

            val intent = Intent(cameraCaptureAction(mediaKind)).apply {
                putExtra(MediaStore.EXTRA_OUTPUT, outputUri)
                if (mediaKind == CAMERA_MEDIA_KIND_VIDEO) {
                    putExtra(MediaStore.EXTRA_VIDEO_QUALITY, 1)
                }
                clipData = ClipData.newUri(activity.contentResolver, outputFile.name, outputUri)
                addFlags(
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }

            activity.startActivityForResult(intent, CAMERA_MEDIA_PICKER_REQUEST)
        } catch (_: ActivityNotFoundException) {
            finishWithError(
                "camera_unavailable",
                "Camera capture is not available on this device.",
            )
        } catch (exception: Exception) {
            finishWithError(
                "camera_launch_failed",
                exception.message ?: "Camera capture could not be started.",
            )
        }
    }

    private fun normalizeCameraMediaKind(kind: String?): String {
        return when (kind) {
            CAMERA_MEDIA_KIND_VIDEO -> CAMERA_MEDIA_KIND_VIDEO
            else -> CAMERA_MEDIA_KIND_PHOTO
        }
    }

    private fun cameraCaptureAction(kind: String): String {
        return if (kind == CAMERA_MEDIA_KIND_VIDEO) {
            MediaStore.ACTION_VIDEO_CAPTURE
        } else {
            MediaStore.ACTION_IMAGE_CAPTURE
        }
    }

    private fun cameraOutputExtension(kind: String): String {
        return if (kind == CAMERA_MEDIA_KIND_VIDEO) "mp4" else "jpg"
    }

    private fun fallbackCameraMimeType(kind: String): String {
        return if (kind == CAMERA_MEDIA_KIND_VIDEO) "video/mp4" else "image/jpeg"
    }

    private fun copyReturnedCameraUri(activity: Activity, uri: Uri): File {
        val mimeType = cameraMimeType(activity, uri, null)
        val outputFile = nextCameraOutputFile(
            activity,
            extension = cameraFileExtension(mimeType, uri),
        )
        val input = activity.contentResolver.openInputStream(uri)
            ?: throw IllegalStateException("The captured media could not be opened.")

        input.use { source ->
            outputFile.outputStream().use { destination ->
                source.copyTo(destination)
            }
        }

        return outputFile
    }

    private fun nextCameraOutputFile(activity: Activity, extension: String): File {
        val directory = File(activity.cacheDir, "shared_media/camera")
        if (!directory.exists()) {
            directory.mkdirs()
        }

        return File(
            directory,
            "camera-${System.currentTimeMillis()}.$extension",
        )
    }

    private fun cameraMimeType(activity: Activity, uri: Uri, file: File?): String {
        val resolverMimeType = activity.contentResolver.getType(uri)
        if (!resolverMimeType.isNullOrBlank()) {
            return resolverMimeType
        }

        return cameraMimeTypeFromFile(file)
    }

    private fun cameraMimeTypeFromFile(file: File?): String {
        val extension = file?.extension?.lowercase()
        return when (extension) {
            "mp4", "m4v" -> "video/mp4"
            "mov", "qt" -> "video/quicktime"
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "application/octet-stream"
        }
    }

    private fun cameraFileExtension(mimeType: String, uri: Uri): String {
        val mapped = MimeTypeMap.getSingleton()
            .getExtensionFromMimeType(mimeType)
            ?.takeIf { it.isNotBlank() }
        if (mapped != null) {
            return mapped
        }

        val uriExtension = MimeTypeMap.getFileExtensionFromUrl(uri.toString())
            ?.takeIf { it.isNotBlank() }
        if (uriExtension != null) {
            return uriExtension
        }

        return when {
            mimeType.startsWith("video/") -> "mp4"
            mimeType.startsWith("image/") -> "jpg"
            else -> "bin"
        }
    }

    private fun cameraMediaPayload(file: File, mimeType: String): Map<String, Any?> {
        return mapOf(
            "path" to file.absolutePath,
            "name" to file.name,
            "mimeType" to mimeType,
            "size" to file.length(),
        )
    }

    private fun finishWithSuccess(payload: Map<String, Any?>, deleteOutput: Boolean) {
        pendingResult?.success(payload)
        clearPending(deleteOutput = deleteOutput)
    }

    private fun finishWithError(code: String, message: String) {
        pendingResult?.error(code, message, null)
        clearPending(deleteOutput = true)
    }

    private fun clearPending(deleteOutput: Boolean) {
        if (deleteOutput) {
            pendingOutputFile?.delete()
        }
        pendingResult = null
        pendingOutputFile = null
        pendingMediaKind = null
    }
}

fun shareMediaFile(
    activity: Activity,
    bytes: ByteArray?,
    filename: String?,
    mimeType: String?,
    result: MethodChannel.Result,
) {
    if (bytes == null || bytes.isEmpty()) {
        result.error("invalid_arguments", "File bytes are required.", null)
        return
    }

    try {
        val shareDir = File(activity.cacheDir, "shared_media")
        if (!shareDir.exists()) {
            shareDir.mkdirs()
        }

        val safeName = sanitizeShareFileName(filename)
        val file = File(shareDir, safeName)
        file.writeBytes(bytes)

        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            file,
        )
        val type = mimeType?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        val intent = Intent(Intent.ACTION_SEND).apply {
            this.type = type
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(activity.contentResolver, safeName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(Intent.createChooser(intent, "Share"))
        result.success(true)
    } catch (exception: Exception) {
        result.error("share_failed", exception.message, null)
    }
}

fun sanitizeShareFileName(filename: String?): String {
    val trimmed = filename?.trim()?.takeIf { it.isNotEmpty() }
        ?: "intergalactic-media"
    return trimmed.replace(Regex("[^A-Za-z0-9._-]"), "_")
}

fun getNotificationDiagnostics(activity: Activity): Map<String, Any?> {
    val notificationManager =
        activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val notificationsEnabled =
        NotificationManagerCompat.from(activity).areNotificationsEnabled()
    val appBubblesAllowed =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            notificationManager.areBubblesAllowed()
        } else {
            null
        }
    val batteryOptimizationIgnored =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager =
                activity.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.isIgnoringBatteryOptimizations(activity.packageName)
        } else {
            null
        }
    val channels =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.notificationChannels.map { channel ->
                mapOf(
                    "id" to channel.id,
                    "importance" to channel.importance,
                    "canBubble" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        channel.canBubble()
                    } else {
                        null
                    },
                )
            }
        } else {
            emptyList<Map<String, Any?>>()
        }

    return mapOf(
        "sdkInt" to Build.VERSION.SDK_INT,
        "notificationsEnabled" to notificationsEnabled,
        "appBubblesAllowed" to appBubblesAllowed,
        "batteryOptimizationIgnored" to batteryOptimizationIgnored,
        "channels" to channels,
    )
}

object AndroidVoiceRecorderBridge {
    private var recorder: MediaRecorder? = null
    private var recordingFile: File? = null
    private var recordingStartedAtMs: Long = 0
    private var pendingStartActivityRef: WeakReference<Activity>? = null
    private var pendingStartResult: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOICE_RECORDER_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> startRecording(activity, result)
                    "stopRecording" -> stopRecording(result)
                    "cancelRecording" -> cancelRecording(result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != VOICE_RECORDER_PERMISSION_REQUEST) {
            return false
        }

        val result = pendingStartResult ?: return true
        val activity = pendingStartActivityRef?.get()
        pendingStartActivityRef = null
        pendingStartResult = null

        if (grantResults.firstOrNull() != PackageManager.PERMISSION_GRANTED || activity == null) {
            result.error(
                "microphone_permission_denied",
                "Microphone permission was denied.",
                null,
            )
            return true
        }

        startRecordingWithPermission(activity, result)
        return true
    }

    private fun startRecording(activity: Activity, result: MethodChannel.Result) {
        if (recorder != null) {
            result.error(
                "voice_recorder_active",
                "A voice recording is already active.",
                null,
            )
            return
        }

        if (pendingStartResult != null) {
            result.error(
                "voice_recorder_permission_pending",
                "A voice recording permission request is already pending.",
                null,
            )
            return
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            pendingStartActivityRef = WeakReference(activity)
            pendingStartResult = result
            activity.requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                VOICE_RECORDER_PERMISSION_REQUEST,
            )
            return
        }

        startRecordingWithPermission(activity, result)
    }

    private fun startRecordingWithPermission(activity: Activity, result: MethodChannel.Result) {
        val fileName = "voice-message-${System.currentTimeMillis()}.m4a"
        val outputFile = File(activity.cacheDir, fileName)
        val mediaRecorder = createMediaRecorder()

        try {
            mediaRecorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            mediaRecorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            mediaRecorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            mediaRecorder.setAudioChannels(1)
            mediaRecorder.setAudioSamplingRate(44100)
            mediaRecorder.setAudioEncodingBitRate(64000)
            mediaRecorder.setOutputFile(outputFile.absolutePath)
            mediaRecorder.prepare()
            mediaRecorder.start()

            recorder = mediaRecorder
            recordingFile = outputFile
            recordingStartedAtMs = SystemClock.elapsedRealtime()

            result.success(
                mapOf(
                    "path" to outputFile.absolutePath,
                    "name" to fileName,
                    "mime_type" to "audio/mp4",
                )
            )
        } catch (exception: Exception) {
            safelyRelease(mediaRecorder)
            outputFile.delete()
            result.error("voice_recorder_start_failed", exception.message, null)
        }
    }

    private fun stopRecording(result: MethodChannel.Result) {
        val mediaRecorder = recorder
        val outputFile = recordingFile
        if (mediaRecorder == null || outputFile == null) {
            result.error("voice_recorder_inactive", "No voice recording is active.", null)
            return
        }

        val durationMs = SystemClock.elapsedRealtime() - recordingStartedAtMs
        recorder = null
        recordingFile = null
        recordingStartedAtMs = 0

        try {
            mediaRecorder.stop()
            safelyRelease(mediaRecorder)

            if (!outputFile.exists() || outputFile.length() <= 0) {
                outputFile.delete()
                result.error("voice_recorder_empty", "Voice recording was empty.", null)
                return
            }

            result.success(
                mapOf(
                    "path" to outputFile.absolutePath,
                    "name" to outputFile.name,
                    "mime_type" to "audio/mp4",
                    "size" to outputFile.length().toInt(),
                    "duration_ms" to durationMs.coerceAtLeast(0L).toInt(),
                )
            )
        } catch (exception: RuntimeException) {
            safelyRelease(mediaRecorder)
            outputFile.delete()
            result.error("voice_recorder_stop_failed", exception.message, null)
        }
    }

    private fun cancelRecording(result: MethodChannel.Result) {
        pendingStartResult?.error(
            "voice_recorder_cancelled",
            "Voice recording was cancelled.",
            null,
        )
        pendingStartActivityRef = null
        pendingStartResult = null

        val mediaRecorder = recorder
        val outputFile = recordingFile
        recorder = null
        recordingFile = null
        recordingStartedAtMs = 0

        if (mediaRecorder != null) {
            try {
                mediaRecorder.stop()
            } catch (_: RuntimeException) {
                // Stopping a very short recording can throw; cancel should still clean up.
            } finally {
                safelyRelease(mediaRecorder)
            }
        }

        outputFile?.delete()
        result.success(null)
    }

    @Suppress("DEPRECATION")
    private fun createMediaRecorder(): MediaRecorder {
        return MediaRecorder()
    }

    private fun safelyRelease(mediaRecorder: MediaRecorder) {
        try {
            mediaRecorder.release()
        } catch (_: RuntimeException) {
        }
    }
}

object AndroidStoryVideoExportBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORY_VIDEO_EXPORT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportTrim" -> exportTrim(activity, call.arguments, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun exportTrim(
        activity: Activity,
        rawArguments: Any?,
        result: MethodChannel.Result,
    ) {
        val arguments = rawArguments as? Map<*, *>
        val sourcePath = arguments?.get("sourcePath") as? String
        val sourceName = arguments?.get("sourceName") as? String
        val trimStartMs = (arguments?.get("trimStartMs") as? Number)?.toLong()
        val trimEndMs = (arguments?.get("trimEndMs") as? Number)?.toLong()

        Thread {
            var outputFile: File? = null
            try {
                if (
                    sourcePath.isNullOrBlank() ||
                    trimStartMs == null ||
                    trimEndMs == null ||
                    trimStartMs < 0 ||
                    trimEndMs <= trimStartMs
                ) {
                    throw IllegalArgumentException("Invalid story video trim arguments.")
                }

                val sourceFile = File(sourcePath)
                if (!sourceFile.exists() || !sourceFile.isFile) {
                    throw IllegalArgumentException("Story video source file does not exist.")
                }

                val exportDirectory = File(activity.cacheDir, "intergalactic_story_video_exports")
                if (!exportDirectory.exists()) {
                    exportDirectory.mkdirs()
                }

                val outputName = trimmedVideoName(sourceName ?: sourceFile.name)
                outputFile = File(exportDirectory, outputName)
                copyTrimmedMedia(
                    sourcePath = sourceFile.absolutePath,
                    outputPath = outputFile.absolutePath,
                    trimStartUs = trimStartMs * 1000L,
                    trimEndUs = trimEndMs * 1000L,
                )

                if (!outputFile.exists() || outputFile.length() <= 0L) {
                    throw IllegalStateException("Story video trim export was empty.")
                }

                success(
                    result,
                    mapOf(
                        "path" to outputFile.absolutePath,
                        "name" to outputName,
                        "mime_type" to "video/mp4",
                        "size" to outputFile.length(),
                    ),
                )
            } catch (exception: IllegalArgumentException) {
                outputFile?.delete()
                error(result, "invalid_arguments", exception.message, null)
            } catch (exception: UnsupportedOperationException) {
                outputFile?.delete()
                error(result, "story_video_export_unsupported", exception.message, null)
            } catch (exception: Exception) {
                outputFile?.delete()
                error(result, "story_video_export_failed", exception.message, null)
            }
        }.start()
    }

    private fun copyTrimmedMedia(
        sourcePath: String,
        outputPath: String,
        trimStartUs: Long,
        trimEndUs: Long,
    ) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            extractor.setDataSource(sourcePath)
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackIndexMap = mutableMapOf<Int, Int>()
            var maxInputSize = 4 * 1024 * 1024

            for (trackIndex in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(trackIndex)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) {
                    continue
                }
                extractor.selectTrack(trackIndex)
                trackIndexMap[trackIndex] = muxer.addTrack(format)
                if (format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxInputSize = max(maxInputSize, format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                if (
                    mime.startsWith("video/") &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                    format.containsKey(MediaFormat.KEY_ROTATION)
                ) {
                    muxer.setOrientationHint(format.getInteger(MediaFormat.KEY_ROTATION))
                }
            }

            if (trackIndexMap.isEmpty()) {
                throw UnsupportedOperationException("No audio or video tracks were found.")
            }

            muxer.start()
            muxerStarted = true
            extractor.seekTo(trimStartUs, MediaExtractor.SEEK_TO_NEXT_SYNC)

            val buffer = ByteBuffer.allocateDirect(maxInputSize.coerceAtMost(16 * 1024 * 1024))
            val bufferInfo = MediaCodec.BufferInfo()
            var firstSampleTimeUs: Long? = null
            var wroteSamples = false

            while (true) {
                val sourceTrackIndex = extractor.sampleTrackIndex
                if (sourceTrackIndex < 0) {
                    break
                }
                val sampleTimeUs = extractor.sampleTime
                if (sampleTimeUs < 0 || sampleTimeUs > trimEndUs) {
                    break
                }
                val destinationTrackIndex = trackIndexMap[sourceTrackIndex]
                if (destinationTrackIndex == null) {
                    extractor.advance()
                    continue
                }

                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) {
                    break
                }
                if (firstSampleTimeUs == null) {
                    firstSampleTimeUs = sampleTimeUs
                }
                bufferInfo.set(
                    0,
                    sampleSize,
                    max(0L, sampleTimeUs - firstSampleTimeUs!!),
                    extractor.sampleFlags,
                )
                muxer.writeSampleData(destinationTrackIndex, buffer, bufferInfo)
                wroteSamples = true
                extractor.advance()
            }

            if (!wroteSamples) {
                throw IllegalStateException("No story video samples were exported.")
            }
        } finally {
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (_: RuntimeException) {
                }
            }
            muxer?.release()
            extractor.release()
        }
    }

    private fun trimmedVideoName(sourceName: String): String {
        val baseName = File(sourceName).nameWithoutExtension.trim()
        val safeBase = baseName
            .replace(Regex("[^A-Za-z0-9._-]+"), "_")
            .replace(Regex("_+"), "_")
            .trim('_')
            .ifEmpty { "story-video" }
        return "$safeBase-trim-${System.currentTimeMillis()}.mp4"
    }

    private fun success(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun error(
        result: MethodChannel.Result,
        code: String,
        message: String?,
        details: Any?,
    ) {
        mainHandler.post { result.error(code, message, details) }
    }
}

fun hideKeyboard(activity: Activity) {
    val imm = activity.getSystemService(Activity.INPUT_METHOD_SERVICE) as InputMethodManager
    //Find the currently focused view, so we can grab the correct window token from it.
    var view = activity.getCurrentFocus()
    //If no view currently has focus, create a new one, just so we can grab a window token from it
    if (view == null) {
        view = View(activity)
    }
    imm.hideSoftInputFromWindow(view.getWindowToken(), 0)
}

fun isKeyboardOpen(activity: Activity): Boolean {
    val insets = ViewCompat.getRootWindowInsets(activity.window.decorView.rootView)
    return insets?.isVisible(WindowInsetsCompat.Type.ime()) == true
}

fun setLauncherIconAlias(activity: Activity, mode: String, brightness: String?) {
    val packageManager = activity.packageManager
    val lightAlias = ComponentName(activity, LAUNCHER_LIGHT_ALIAS)
    val darkAlias = ComponentName(activity, LAUNCHER_DARK_ALIAS)
    val systemAlias = ComponentName(activity, LAUNCHER_SYSTEM_ALIAS)

    val targetAlias = when (mode) {
        "light" -> lightAlias
        "dark" -> darkAlias
        else -> when (brightness ?: resolveSystemBrightness(activity)) {
            "dark" -> darkAlias
            "light" -> lightAlias
            else -> systemAlias
        }
    }

    val aliases = listOf(lightAlias, darkAlias, systemAlias)

    // Enable the target alias first, then disable the others to avoid transient
    // launcher gaps while the icon is switching.
    updateAliasState(packageManager, targetAlias, true)

    aliases
        .filter { it != targetAlias }
        .forEach { alias ->
            updateAliasState(packageManager, alias, false)
        }
}

fun updateAliasState(
    packageManager: PackageManager,
    componentName: ComponentName,
    enabled: Boolean
) {
    val desiredState = if (enabled) {
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    } else {
        PackageManager.COMPONENT_ENABLED_STATE_DISABLED
    }

    if (packageManager.getComponentEnabledSetting(componentName) == desiredState) {
        return
    }

    packageManager.setComponentEnabledSetting(
        componentName,
        desiredState,
        PackageManager.DONT_KILL_APP
    )
}

fun resolveSystemBrightness(activity: Activity): String {
    val nightMode =
        activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return if (nightMode == Configuration.UI_MODE_NIGHT_YES) {
        "dark"
    } else {
        "light"
    }
}

fun getBiometricAvailability(activity: Activity): Map<String, Any> {
    val available = canAuthenticateWithBiometrics(activity)
    return mapOf(
        "available" to available,
        "biometryType" to if (available) resolveBiometryType(activity) else "none",
    )
}

fun canAuthenticateWithBiometrics(activity: Activity): Boolean {
    val manager = BiometricManager.from(activity)
    return manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) ==
        BiometricManager.BIOMETRIC_SUCCESS
}

fun resolveBiometryType(context: Context): String {
    val packageManager = context.packageManager
    return when {
        packageManager.hasSystemFeature(PackageManager.FEATURE_FACE) -> "face_unlock"
        packageManager.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT) -> "fingerprint"
        packageManager.hasSystemFeature(PackageManager.FEATURE_IRIS) -> "iris"
        else -> "biometric"
    }
}

fun authenticateWithBiometrics(
    activity: Activity,
    reason: String?,
    result: MethodChannel.Result,
) {
    if (activity !is FragmentActivity || !canAuthenticateWithBiometrics(activity)) {
        result.success(false)
        return
    }

    val executor: Executor = ContextCompat.getMainExecutor(activity)
    var resultSubmitted = false

    val prompt = BiometricPrompt(
        activity,
        executor,
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                authenticationResult: BiometricPrompt.AuthenticationResult,
            ) {
                if (!resultSubmitted) {
                    resultSubmitted = true
                    result.success(true)
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (!resultSubmitted) {
                    resultSubmitted = true
                    result.success(false)
                }
            }
        },
    )

    val promptInfo = BiometricPrompt.PromptInfo.Builder()
        .setTitle(reason?.takeIf { it.isNotBlank() } ?: "Authenticate with biometrics")
        .setNegativeButtonText("Cancel")
        .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        .build()

    activity.runOnUiThread {
        prompt.authenticate(promptInfo)
    }
}
