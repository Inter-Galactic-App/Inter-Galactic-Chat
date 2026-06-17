package chat.intergalactic.app

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ClipData
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaRecorder
import android.media.MediaMuxer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.View
import android.view.inputmethod.InputMethodManager
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
        if (AndroidVoiceRecorderBridge.onRequestPermissionsResult(requestCode, grantResults)) {
            return
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
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
        if (AndroidVoiceRecorderBridge.onRequestPermissionsResult(requestCode, grantResults)) {
            return
        }

        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}

class BubbleActivity : BaseActivity() {
    override var entryPoint = "bubble"
}

private const val APP_ICON_CHANNEL = "chat.intergalactic.app/app_icon"
private const val BIOMETRIC_CHANNEL = "chat.intergalactic.app/biometrics"
private const val MEDIA_SHARE_CHANNEL = "chat.intergalactic.app/media_share"
private const val NOTIFICATION_DIAGNOSTICS_CHANNEL = "chat.intergalactic.app/notification_diagnostics"
private const val STORY_VIDEO_EXPORT_CHANNEL = "chat.intergalactic.app/story_video_export"
private const val VOICE_RECORDER_CHANNEL = "chat.intergalactic.app/voice_recorder"
private const val VOICE_RECORDER_PERMISSION_REQUEST = 7301
private const val LAUNCHER_LIGHT_ALIAS = "chat.intergalactic.app.LauncherLightAlias"
private const val LAUNCHER_DARK_ALIAS = "chat.intergalactic.app.LauncherDarkAlias"
private const val LAUNCHER_SYSTEM_ALIAS = "chat.intergalactic.app.LauncherSystemAlias"

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
    AndroidStoryVideoExportBridge.register(flutterEngine, activity)
    AndroidVoiceRecorderBridge.register(flutterEngine, activity)
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
