package chat.intergalactic.noise_suppression

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class IntergalacticNoiseSuppressionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var context: Context? = null
    private var channel: MethodChannel? = null
    private var processor: AndroidDeepFilterNetProcessor? = null
    private var initializationExecutor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /// See [captureWebRtcPluginForThisEngine]. Held per plugin instance, so each
    /// engine keeps its own reference instead of racing over one static.
    private var webRtcPlugin: Any? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        initializationExecutor = Executors.newSingleThreadExecutor()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        webRtcPlugin = captureWebRtcPluginForThisEngine()
    }

    /// The FlutterWebRTCPlugin instance belonging to THIS engine, captured now
    /// rather than read at attach time.
    ///
    /// FlutterWebRTCPlugin assigns its `sharedSingleton` static in its
    /// CONSTRUCTOR, and its own source comments that it "can be instantiated
    /// multiple times". This app has more than one FlutterEngine: Firebase
    /// Cloud Messaging starts FlutterFirebaseMessagingBackgroundService a few
    /// seconds after launch, and GeneratedPluginRegistrant registers every
    /// plugin on that headless engine too. Its FlutterWebRTCPlugin constructor
    /// then OVERWRITES sharedSingleton, so from that moment the static names
    /// the background engine's instance - which never handles a call and whose
    /// audioProcessingController is therefore null forever.
    ///
    /// Measured on device 2026-08-21 (TCL T767W, build 1003): app engine
    /// attaches at 10:49:15.1, the FCM background engine at 10:49:19.0, and
    /// every later attach attempt read the wrong instance and reported
    /// audio_processing_unavailable even with a live call whose
    /// PeerConnectionFactory had already loaded. It is an identity mismatch,
    /// not a timing window - waiting longer or retrying more cannot fix it.
    ///
    /// This is a HINT, not a guarantee, and attachToWebRtcLocked treats it as
    /// one. It is captured here because GeneratedPluginRegistrant adds
    /// flutter_webrtc before this plugin in the same pass over the same engine,
    /// so at this moment the static usually still names our engine's instance.
    /// But that only holds while no OTHER engine registers in between, and what
    /// actually prevents that today is main-thread serialization - measured
    /// 2026-08-21, both engines' plugins log on tid == pid - not the ordering.
    /// Firebase building its engine off the main thread would reopen the window
    /// silently.
    ///
    /// So nothing depends on this being right. attachToWebRtcLocked tries this
    /// instance AND the live static and takes whichever actually has an
    /// AudioProcessingController, which is the only instance that can have
    /// handled a call.
    private fun captureWebRtcPluginForThisEngine(): Any? {
        return try {
            val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            pluginClass.getField("sharedSingleton").get(null)
        } catch (error: Throwable) {
            Log.w(TAG, "Could not capture the flutter_webrtc plugin for this engine", error)
            null
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val active = processor
        val executor = initializationExecutor
        processor = null
        initializationExecutor = null
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
        // Dropped with the engine it belongs to: this holds another plugin
        // instance from the same engine, and keeping it past detach would pin a
        // torn-down engine's object for the life of the process.
        webRtcPlugin = null
        if (executor != null) {
            try {
                executor.execute { active?.close() }
            } catch (_: RejectedExecutionException) {
                active?.close()
            }
            executor.shutdown()
        } else {
            active?.close()
        }
    }

    // Both broad catches in here are deliberate: rethrowIfFatal narrows the
    // handled set, and the reply-before-rethrow order is the channel contract.
    @Suppress("TooGenericExceptionCaught")
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val applicationContext = context
                    val executor = initializationExecutor
                    if (applicationContext == null || executor == null) {
                        result.error(
                            "android_noise_suppression_unavailable",
                            "Plugin is not attached to an engine",
                            null,
                        )
                        return
                    }
                    val active = processor
                        ?: AndroidDeepFilterNetProcessor(applicationContext, webRtcPlugin)
                            .also { processor = it }
                    val requestedEnabled = call.argument<Boolean>("enabled") == true
                    executor.execute {
                        try {
                            val status = active.initialize(requestedEnabled)
                            mainHandler.post { result.success(status) }
                        } catch (error: Throwable) {
                            // Reply BEFORE the fatal rethrow. The channel
                            // contract is reply-exactly-once; rethrowing first
                            // abandons the Result and leaves the Dart await -
                            // and the single operation chain behind it -
                            // wedged in any process that survives the error.
                            mainHandler.post {
                                result.error(
                                    "android_noise_suppression_error",
                                    error.message,
                                    null,
                                )
                            }
                            rethrowIfFatal(error)
                        }
                    }
                }
                "configure" -> result.error(
                    "android_configuration_unsupported",
                    "Android DeepFilterNet does not support RNNoise tuning parameters",
                    processor?.status() ?: unavailable("not_initialized"),
                )
                "setPipelineMode" -> {
                    processor?.setPipelineMode(call.argument<Int>("mode") ?: 0)
                    result.success(processor?.status() ?: unavailable("not_initialized"))
                }
                "setEnabled" -> {
                    processor?.setEnabled(call.argument<Boolean>("enabled") == true)
                    result.success(processor?.status() ?: unavailable("not_initialized"))
                }
                "getStatus" -> result.success(processor?.status() ?: unavailable("not_initialized"))
                "getPlatformAudioStatus" -> result.success(platformAudioStatus())
                "shutdown" -> {
                    // close() waits on the lifecycle lock, which an in-flight
                    // initialize can hold for seconds (model extraction plus
                    // df_create). Closing here would block the platform thread
                    // for that whole window - an ANR, not a shutdown. The
                    // single-threaded executor serializes it behind any
                    // in-flight initialize instead, as onDetachedFromEngine
                    // already does.
                    val active = processor
                    processor = null
                    val executor = initializationExecutor
                    if (active == null || executor == null) {
                        active?.close()
                        result.success(unavailable("shutdown"))
                        return
                    }
                    try {
                        executor.execute {
                            try {
                                active.close()
                            } catch (error: Throwable) {
                                // Reply before the fatal rethrow - same
                                // contract as the initialize branch. The
                                // return keeps the non-fatal path from
                                // replying twice.
                                mainHandler.post {
                                    result.success(unavailable("shutdown"))
                                }
                                rethrowIfFatal(error)
                                return@execute
                            }
                            mainHandler.post { result.success(unavailable("shutdown")) }
                        }
                    } catch (_: RejectedExecutionException) {
                        active.close()
                        result.success(unavailable("shutdown"))
                    }
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            // Reply first for the same reason as the async branches. No branch
            // that reaches this catch has already replied: every throwing call
            // in the `when` above sits before its branch's result call.
            result.error("android_noise_suppression_error", error.message, null)
            rethrowIfFatal(error)
        }
    }

    private fun platformAudioStatus(): Map<String, Any> {
        val hardwarePath = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        return mapOf(
            "platform" to "android",
            "webrtcAecRequested" to true,
            "webrtcNsRequested" to true,
            "webrtcHardwareEffectsRequested" to hardwarePath,
            "hardwareAecAvailable" to AcousticEchoCanceler.isAvailable(),
            "hardwareNsAvailable" to NoiseSuppressor.isAvailable(),
            "audioMode" to (audioManager?.mode?.toString() ?: "unknown"),
        )
    }

    private fun unavailable(reason: String): Map<String, Any> = mapOf(
        "supported" to true, "available" to false, "requestedEnabled" to false,
        "enabled" to false, "active" to false, "pipelineMode" to "off", "reason" to reason,
    )

    companion object { private const val CHANNEL = "intergalactic_noise_suppression/android" }
}

private const val TAG = "IGNoiseSuppression"
private const val MODEL_ASSET = "DeepFilterNet3_onnx.tar.gz"
private const val MODEL_STAMP = "DeepFilterNet3_onnx.tar.gz.build"
private const val GZIP_MAGIC_0 = 0x1f.toByte()
private const val GZIP_MAGIC_1 = 0x8b.toByte()

/// The rate the DeepFilterNet runtime is initialized at. Capture is expected to
/// be 48 kHz; [AndroidDeepFilterNetProcessor.inferCaptureFormat] warns when the
/// stream disagrees, because the runtime cannot be told after the fact.
private const val NATIVE_INIT_SAMPLE_RATE_HZ = 48000

/// Rethrows anything in the `Error` hierarchy that this plugin has no business
/// handling.
///
/// The broad `Throwable` catches here are deliberate - the attach path is
/// entirely reflection, so a renamed flutter_webrtc method or a stripped class
/// must not escape into call setup. `LinkageError` is exactly that case and is
/// caught. Every other `Error` is not: `OutOfMemoryError`, `StackOverflowError`
/// and `ThreadDeath` say nothing about whether the reflection target exists,
/// and the Dart side treats `audio_processing_unavailable` as RETRYABLE - so
/// converting them made the app retry attachment while the VM was already
/// dying. Guarding only `VirtualMachineError` left `ThreadDeath` and the rest
/// of the hierarchy still being converted.
private fun rethrowIfFatal(error: Throwable) {
    if (error is Error && error !is LinkageError) {
        throw error
    }
}

private class AndroidDeepFilterNetProcessor(
    private val context: Context,
    /// The FlutterWebRTCPlugin instance for the engine this processor belongs
    /// to, or null when it could not be captured. Never read the
    /// sharedSingleton static in preference to this - see
    /// IntergalacticNoiseSuppressionPlugin.captureWebRtcPluginForThisEngine.
    private val webRtcPlugin: Any?,
) {
    // Attachment and shutdown are not on the same thread: attachToWebRtc() runs
    // on the initialization executor, close() arrives on the main handler from
    // the `shutdown` channel call. @Volatile makes each reference visible but
    // does NOT make the attach sequence atomic, and the gap is real: close()
    // can land after addProcessor() has registered the proxy but before
    // `attachedProcessor` is assigned. The detach then sees null and returns,
    // nativeShutdown() runs, and the attach task publishes afterwards
    // - leaving a processor registered with WebRTC that nothing will ever
    // remove, and status() reporting attachedToWebRtc after shutdown. The
    // `nativeReady` guard in process() keeps that from reaching native code,
    // so this is an orphaned registration and a lying status rather than a
    // crash, but neither is acceptable.
    //
    // One lock over attach, detach and close makes the sequences mutually
    // exclusive. Shutdown blocking until an in-flight attach completes is the
    // correct ordering, not a cost.
    private val lifecycleLock = Any()

    /// Set by [close] under [lifecycleLock]. An initialize that was queued
    /// before shutdown but has not started yet must not run afterwards - this
    /// object is discarded by the plugin on shutdown, so anything it publishes
    /// after that point is native state with no owner.
    @Volatile
    private var closed = false

    private val enabled = AtomicBoolean(false)
    private val framesProcessed = AtomicLong(0)
    private val bypassFrames = AtomicLong(0)
    @Volatile
    private var frameLength = 0
    @Volatile
    private var sampleRateHz = 0
    @Volatile
    private var channels = 0
    @Volatile
    private var pipelineMode = 0
    // @Volatile like every other field behind status(): `available`, `active`
    // and `attachedToWebRtc` all read `attachedProcessor` through `attached`,
    // and status() is called from a different thread than attachToWebRtc() /
    // detachFromWebRtc(). A stale read reports the wrong availability, which
    // the Dart contract turns into a suppressed or spurious retry.
    @Volatile
    private var attachedAdapter: Any? = null
    @Volatile
    private var attachedProcessor: Any? = null
    @Volatile
    private var nativeReady = false
    @Volatile
    private var reason = "deepfilternet_not_initialized"

    // attachToWebRtc() used to run last in initialize(), so a missing WebRTC
    // audio pipeline left its reason in place for status() to report. It now has
    // to run first, because it must still happen when noise suppression is
    // switched off and that path returns early. Its failure is therefore
    // recorded here and re-applied by finishInitialize(): without that, a build
    // that never attached would report "deepfilternet_ready" while processing no
    // audio whatsoever.
    @Volatile
    private var attachFailureReason: String? = null

    /// Inflated size measured by the last [ensureModelFile] verification, so
    /// logging it does not inflate the archive all over again.
    @Volatile
    private var lastVerifiedInflatedSize: Long = -1L

    fun initialize(requestedEnabled: Boolean): Map<String, Any> =
        synchronized(lifecycleLock) { initializeLocked(requestedEnabled) }

    private fun initializeLocked(requestedEnabled: Boolean): Map<String, Any> {
        // Attachment alone was serialized; native initialization was not. It ran
        // after attachToWebRtc() released the lock, so close() could detach and
        // call nativeShutdown() in the gap - and this method would then run
        // nativeInitialize() and publish nativeReady = true against a processor
        // the plugin had already discarded. The whole body is under the lock
        // now, and a shutdown that has already happened refuses the attempt
        // rather than resurrecting native state behind it.
        //
        // Shutdown blocking until an in-flight initialize finishes is the
        // intended ordering. df_create can abort the process outright, which no
        // lock can help with; the guard file below is what handles that.
        if (closed) {
            frameLength = 0
            nativeReady = false
            return finishInitialize("shutdown")
        }

        enabled.set(requestedEnabled)
        pipelineMode = if (requestedEnabled) 6 else 0
        // The *Locked body: this method already holds lifecycleLock. Reentrant
        // monitors make the wrapper harmless, but close() deliberately calls
        // the locked body for the same reason and one convention is clearer
        // than two.
        attachToWebRtcLocked()

        // df_create aborts the process on any failure instead of returning an
        // error, so it must not run at all for users who have noise suppression
        // switched off - they gain nothing from it and would still pay the crash.
        if (!requestedEnabled) {
            frameLength = 0
            nativeReady = false
            return finishInitialize("deepfilternet_disabled")
        }

        // The runtime is already up, so everything below - the guard write, the
        // archive verification, and a ~700 ms df_create - would rebuild state
        // that is already correct. Attach is the part that had to re-run, and
        // it just did.
        //
        // This matters because initialize() is now a RETRY path. On Android the
        // first attach of a cold call join always fails (flutter_webrtc has no
        // AudioProcessingController until it builds its PeerConnectionFactory),
        // so the health refresh re-initializes 2 s and 5 s after the microphone
        // is enabled. Measured on device 2026-08-21: two extra model loads per
        // call on top of the join-time one, each ~700 ms, for nothing. It is
        // also the "repeated expensive work" hazard REVIEW recorded on the
        // prewarmed_deepfilternet_ready row - a retry policy that reloads the
        // model every time turns a cheap recovery into an expensive one.
        //
        // Deliberately keyed on frameLength as well as nativeReady: the two are
        // set together by a successful nativeInitialize, and a runtime claiming
        // ready with no frame length would bypass every frame in process().
        // The "reset" callback clears both, so a genuine WebRTC reconfiguration
        // still rebuilds the runtime rather than being skipped here.
        if (nativeReady && frameLength > 0) {
            return finishInitialize("deepfilternet_ready")
        }

        // A native abort cannot be caught from Kotlin, so the only way to avoid
        // an unlaunchable app is to notice that a previous attempt never
        // finished and refuse to repeat it.
        //
        // The guard records WHICH build tripped it. Keyed on nothing, it was a
        // one-way door: any single process death during df_create - a user
        // swiping the app away, the system reclaiming memory, an unrelated
        // crash on another thread - disabled noise suppression for the life of
        // the install, with no UI to clear it and no recovery after an update
        // that fixed the actual cause. Honouring it only for the build that
        // wrote it keeps the crash-loop protection while letting a new build
        // try once.
        val guard = File(context.filesDir, "audio-models/.df_create_attempt")
        val guardOwner = readBuildStamp(guard)
        if (guardOwner != null && guardOwner == buildFingerprint()) {
            frameLength = 0
            nativeReady = false
            Log.w(
                TAG,
                "Skipping DeepFilterNet: a previous df_create attempt on this same build " +
                    "($guardOwner) did not return",
            )
            return finishInitialize("deepfilternet_disabled_after_abort")
        }
        if (guardOwner != null) {
            Log.w(
                TAG,
                "Clearing a DeepFilterNet abort guard left by a different build " +
                    "($guardOwner); retrying once on ${buildFingerprint()}",
            )
        }

        val model = ensureModelFile()
        // Reuse the size measured during verification. Recomputing it here
        // inflated the whole archive a second time (a third on the re-extract
        // path) purely to print a byte count, on the initialization path.
        // INFO with the file name only: this fires on every successful launch,
        // and absolutePath is the app-private location, which logcat exposes
        // well beyond this process.
        Log.i(
            TAG,
            "DeepFilterNet model verified name=${model.name} " +
                "archiveBytes=${model.length()} inflatedBytes=$lastVerifiedInflatedSize; " +
                "calling df_create",
        )
        // Refuse the call rather than make it unprotected. df_create aborts the
        // whole process on failure, and the guard is the only thing that stops
        // that from repeating on every launch - without one on disk, a bad
        // model would crash-loop the app forever.
        if (!markAttemptStarted(guard)) {
            // Zeroed like every other early return. A re-run of initialize
            // after a previously successful one would otherwise report
            // available=true beside this refusal reason.
            frameLength = 0
            nativeReady = false
            return finishInitialize("deepfilternet_guard_unwritable")
        }
        try {
            frameLength = IntergalacticNoiseSuppressionNative.nativeInitialize(
                model.absolutePath, NATIVE_INIT_SAMPLE_RATE_HZ, 60.0f, 0.02f,
            )
        } finally {
            // Skipped entirely if df_create aborted the process, which is
            // exactly what leaves the guard behind for the next launch.
            guard.delete()
        }
        nativeReady = frameLength > 0
        return finishInitialize(
            if (nativeReady) "deepfilternet_ready" else "deepfilternet_create_failed",
        )
    }

    /// Reports [computed] unless the processor never attached to the WebRTC
    /// audio pipeline, in which case that failure is the more useful answer:
    /// native init can succeed perfectly while no frame ever reaches it.
    private fun finishInitialize(computed: String): Map<String, Any> {
        reason = attachFailureReason ?: computed
        return status()
    }

    /// Returns true only when the guard is durably on disk.
    private fun markAttemptStarted(guard: File): Boolean {
        try {
            guard.parentFile?.mkdirs()
            FileOutputStream(guard).use { output ->
                // The build identity, not a bare flag: a guard that cannot say
                // who wrote it can only ever be a permanent off switch.
                output.write(buildFingerprint().toByteArray(Charsets.UTF_8))
                output.flush()
                // The guard only works if it survives the abort, so force it to
                // disk before the call that may never return.
                output.fd.sync()
            }
            return true
        } catch (error: IOException) {
            Log.w(TAG, "Could not persist DeepFilterNet attempt guard", error)
            return false
        }
    }

    /// The build recorded in [stamp], or null when there is no readable stamp.
    ///
    /// Shared by the abort guard and the extracted-model stamp. A stamp from an
    /// older format (or a truncated write) reads as empty and is treated as
    /// absent, which is the safe direction for both callers: at worst one extra
    /// df_create attempt on a build that may abort, and one extra model
    /// extraction. Both are strictly better than staying disabled forever.
    private fun readBuildStamp(stamp: File): String? {
        if (!stamp.exists()) {
            return null
        }
        return try {
            stamp.readText(Charsets.UTF_8).trim().ifEmpty { null }
        } catch (error: IOException) {
            Log.w(TAG, "Could not read DeepFilterNet build stamp name=${stamp.name}", error)
            null
        }
    }

    /// Identifies this build for guard ownership and for the extracted model's
    /// stamp. The app version is what changes when a fix ships, which is
    /// exactly when a previously aborting install should be allowed to try
    /// again - with that build's own model asset, not the one already on disk.
    private fun buildFingerprint(): String {
        return try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName}+$code"
        } catch (error: Exception) {
            // Exception, not Throwable: getPackageInfo throws
            // NameNotFoundException, and widening this to Throwable would also
            // swallow OutOfMemoryError and coroutine cancellation.
            //
            // Logged, because the fallback is not harmless. A constant
            // fingerprint restores the old behaviour where the guard is a
            // one-way door - honoured forever, including by the build that
            // would have fixed the abort - so it needs to leave a trace.
            Log.w(TAG, "Could not read the build fingerprint for the DeepFilterNet guard", error)
            "unknown-build"
        }
    }

    fun setPipelineMode(mode: Int) { pipelineMode = mode }
    fun setEnabled(value: Boolean) { enabled.set(value) }

    /// True only when a frame can actually reach the processor.
    ///
    /// [nativeReady] alone means df_create succeeded - the model loaded. It says
    /// nothing about whether this processor was ever added to WebRTC's capture
    /// post-processing chain, and those are independent failures: the model can
    /// load perfectly while [attachToWebRtc] found no AudioProcessingController
    /// and no audio is ever handed to it.
    ///
    /// Reporting readiness from [nativeReady] alone is what made this
    /// unrecoverable in v0.8.1+1001. status() said available=true with
    /// reason=audio_processing_unavailable and framesProcessed=0, and the Dart
    /// retry that exists for exactly that reason is guarded by `status.available`
    /// - so a true flag disabled the recovery path built for this failure.
    private val attached: Boolean
        get() = attachedProcessor != null

    fun status(): Map<String, Any> = mapOf(
        "supported" to true, "available" to (nativeReady && attached),
        "requestedEnabled" to enabled.get(), "enabled" to enabled.get(),
        "active" to (nativeReady && attached && enabled.get() && pipelineMode == 6),
        "attachedToWebRtc" to attached,
        // Whether the per-engine HINT was captured at all. Attach does not
        // depend on it - it tries this instance and the live static and takes
        // whichever has a controller - so false here is not itself a fault. It
        // is reported because false means the hint is unavailable and the
        // resolution is relying on the static alone, which is worth knowing if
        // a future report shows attach failing.
        "webRtcPluginBound" to (webRtcPlugin != null),
        "pipelineMode" to if (pipelineMode == 6) "deepfilternet" else "off",
        "framesProcessed" to framesProcessed.get(), "bypassFrames" to bypassFrames.get(),
        "deepFilterNetRuntimeAvailable" to nativeReady,
        "deepFilterNetProcessingApplied" to (framesProcessed.get() > 0),
        // The generic key the Dart status parser actually reads. Android emitted
        // only the deepFilterNet-prefixed one, so `processingApplied` fell back
        // to false and Call Diagnostics printed "processingApplied=false"
        // alongside "dfFrames=225" - the pipeline plainly working while its own
        // summary said it was not. On a device report that reads as "still
        // broken", which is the exact misreading that cost two diagnosis rounds
        // on 2026-08-21.
        "processingApplied" to (framesProcessed.get() > 0),
        "deepFilterNetFramesProcessed" to framesProcessed.get(),
        "deepFilterNetBypassFrames" to bypassFrames.get(),
        "deepFilterNetFrameLength" to frameLength, "deepFilterNetReason" to reason,
        "sampleRateHz" to sampleRateHz, "numChannels" to channels,
        "lastNumFrames" to frameLength, "expectedFramesPer10ms" to frameLength,
        "reason" to reason,
    )

    fun close() = synchronized(lifecycleLock) {
        // Under the same lock as initialize and attachToWebRtc, so a shutdown
        // arriving mid attach waits for it rather than detaching against a
        // half-published attachment and letting the attach task republish
        // afterwards. Flag first: an initialize still queued behind this lock
        // reads it and declines rather than re-initializing native state that
        // the plugin has already stopped owning.
        closed = true
        // Cleared, or shutdown reports the wrong reason AND a retryable one.
        // finishInitialize returns `attachFailureReason ?: computed`, so an
        // earlier failed attach left "audio_processing_unavailable" latched -
        // and the `closed` branch's finishInitialize("shutdown") would return
        // that instead. It is on the Dart retryable allowlist, so the service
        // would retry initialization without bound against a processor the
        // plugin had already discarded.
        attachFailureReason = null
        detachFromWebRtcLocked()
        // Readiness drops BEFORE the native handle is invalidated: the WebRTC
        // audio thread checks nativeReady without this lock, and the reverse
        // order left a window where a frame arriving mid-close could call into
        // freed native state.
        nativeReady = false
        IntergalacticNoiseSuppressionNative.nativeShutdown()
        frameLength = 0
        pipelineMode = 0
        enabled.set(false)
        reason = "shutdown"
    }

    /// Callers must hold [lifecycleLock]; `initializeLocked` is the only one.
    ///
    /// The `*Locked` split exists because this body's `run { ... return }`
    /// blocks are non-local returns out of the function, which a `synchronized`
    /// expression body cannot host. There is deliberately no locking wrapper -
    /// it would be dead code, exactly as with [detachFromWebRtcLocked].
    @Suppress("TooGenericExceptionCaught")
    private fun attachToWebRtcLocked() {
        if (attachedProcessor != null) return
        try {
            // Selected by the property we actually need, not by which instance
            // we believe is ours.
            //
            // FlutterWebRTCPlugin assigns its `sharedSingleton` static in its
            // CONSTRUCTOR and its own source says it "can be instantiated
            // multiple times". This app runs a second FlutterEngine for Firebase
            // background messaging, and GeneratedPluginRegistrant registers
            // flutter_webrtc on it too, so the static can name a plugin that
            // never handles a call and whose controller is null forever.
            //
            // An earlier version captured the static during our own
            // onAttachedToEngine and called that deterministic because the
            // registrant adds flutter_webrtc before this plugin in the same
            // pass. That reasoning was too weak. Registration order only helps
            // if no OTHER engine registers in between, and the thing that
            // actually prevents that today is main-thread serialization -
            // measured 2026-08-21, both engines' plugins log on tid == pid - not
            // the ordering itself. Depending on either is depending on Firebase
            // continuing to build its engine on the main thread.
            //
            // So try both, and take whichever has a live controller. Only the
            // engine that ran flutter_webrtc's initialize() - the one that built
            // the PeerConnectionFactory, i.e. the one handling the call - has a
            // non-null one. That is exactly the instance we want, and asking the
            // question directly is immune to registration order, thread, and
            // whichever constructor happened to run last.
            val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            val candidates = LinkedHashSet<Any>()
            webRtcPlugin?.let { candidates.add(it) }
            pluginClass.getField("sharedSingleton").get(null)?.let { candidates.add(it) }
            if (candidates.isEmpty()) {
                reason = "flutter_webrtc_unavailable"
                attachFailureReason = reason
                return
            }
            var controller: Any? = null
            for (candidate in candidates) {
                controller = candidate.javaClass
                    .getMethod("getAudioProcessingController").invoke(candidate)
                if (controller != null) break
            }
            if (controller == null) {
                // The EXPECTED failure, and the reason this must be retried
                // rather than treated as terminal. flutter_webrtc creates its
                // AudioProcessingController inside MethodCallHandlerImpl
                // .initialize(), which builds the PeerConnectionFactory - so
                // this getter returns null until WebRTC has been initialized.
                // The app calls ensureInitialized() during call join BEFORE the
                // room connects and before the microphone is enabled, so on a
                // cold join this is null on the first attempt, every time.
                reason = "audio_processing_unavailable"
                attachFailureReason = reason
                Log.i(
                    TAG,
                    "DeepFilterNet not attached yet: none of ${candidates.size} " +
                        "flutter_webrtc instance(s) has an AudioProcessingController " +
                        "(WebRTC not initialized). Retry after the microphone is enabled.",
                )
                return
            }
            val adapter = controller.javaClass.getField("capturePostProcessing").get(controller)
            val processorInterface = Class.forName(
                "com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter\$ExternalAudioFrameProcessing",
            )
            val proxy = Proxy.newProxyInstance(processorInterface.classLoader, arrayOf(processorInterface)) { _, method, args ->
                when (method.name) {
                    "initialize" -> {
                        sampleRateHz = args?.getOrNull(0) as? Int ?: 0
                        channels = args?.getOrNull(1) as? Int ?: 0
                    }
                    "reset" -> {
                        sampleRateHz = args?.getOrNull(0) as? Int ?: 0
                        // Cleared so the next process() re-derives it. `reset`
                        // carries the new RATE but not the channel count, and a
                        // reconfiguration can change both. Leaving the old value
                        // in place reported a stale channel count for the rest of
                        // the call, and because the rate came back non-zero the
                        // inference guard never re-ran to correct it.
                        channels = 0
                        IntergalacticNoiseSuppressionNative.nativeReset(sampleRateHz)
                        frameLength = 0
                        nativeReady = false
                        // "not_initialized", not "deepfilternet_not_initialized":
                        // NoiseSuppressionService.shouldRetryInitialization only
                        // accepts the former, so the other spelling reported
                        // available=false with no retry and left suppression off
                        // for the rest of the call after a WebRTC reset.
                        reason = "not_initialized"
                    }
                    "process" -> process(args?.getOrNull(1) as? Int ?: 0, args?.getOrNull(2) as? ByteBuffer)
                }
                null
            }
            adapter.javaClass.getMethod("addProcessor", processorInterface).invoke(adapter, proxy)
            attachedAdapter = adapter
            attachedProcessor = proxy
            attachFailureReason = null
        } catch (error: Throwable) {
            // Fatal Errors first: see rethrowIfFatal. LinkageError is the one
            // this path means to handle; the rest of the hierarchy propagates.
            rethrowIfFatal(error)
            // Logged, not swallowed. This catch and the null-controller branch
            // above both report "audio_processing_unavailable", which is correct
            // for the Dart retry list but made the two indistinguishable in a
            // bug report: a transient "WebRTC is not up yet" and a durable
            // reflection break (a renamed flutter_webrtc method, a stripped
            // class) looked identical and neither carried the exception. Throwable
            // is otherwise deliberate - this whole path is reflection, so it must
            // not let a LinkageError or NoSuchMethodError escape into call setup.
            reason = "audio_processing_unavailable"
            attachFailureReason = reason
            Log.w(TAG, "DeepFilterNet could not attach to the WebRTC capture chain", error)
        }
    }

    // No locking wrapper: `close()` is the only caller and it already holds the
    // lock. Adding one would be an unused private function, and re-acquiring a
    // reentrant monitor to say so buys nothing.
    @Suppress("TooGenericExceptionCaught")
    private fun detachFromWebRtcLocked() {
        val adapter = attachedAdapter
        val processing = attachedProcessor
        // Cleared unconditionally, before the early return. Returning with one
        // of the pair still set left the object reporting a half-attachment
        // that no later detach would clear, because the next call takes the
        // same early return.
        attachedAdapter = null
        attachedProcessor = null
        if (adapter == null || processing == null) {
            return
        }
        try {
            val processorInterface = Class.forName(
                "com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter\$ExternalAudioFrameProcessing",
            )
            adapter.javaClass.getMethod("removeProcessor", processorInterface).invoke(adapter, processing)
        } catch (error: Throwable) {
            // Detach is best-effort - the references are already cleared above,
            // so a failure to unregister cannot leave this object inconsistent.
            // A fatal Error still must not be swallowed here: silently
            // discarding an OutOfMemoryError during shutdown hides the reason
            // the process is about to die.
            rethrowIfFatal(error)
        }
    }

    /// Recovers the capture format when the adapter's `initialize` callback was
    /// never delivered to us.
    ///
    /// That callback carries the sample rate and channel count, but it fires
    /// when flutter_webrtc configures the processing chain - and a processor
    /// added AFTER that has already missed it. On Android the attach is always
    /// late (the first cold-join attempt cannot succeed), so in practice we
    /// never receive it and `sampleRateHz` stayed 0 for the whole call. Device
    /// diagnostics on 2026-08-21 read "0 Hz, 0 channel(s)" while 225 frames
    /// were being processed.
    ///
    /// WebRTC's APM contract is fixed 10 ms frames, so the rate is
    /// numFrames * 100, and the buffer is interleaved 16-bit PCM, so the
    /// channel count follows from its size. Both are derived, not guessed, but
    /// they are recorded as inferred because they came from the data rather
    /// than from the callback that is supposed to state them.
    ///
    /// The warning matters more than the numbers: nativeInitialize is called
    /// with a HARD-CODED 48000. If capture is running at any other rate, the
    /// native runtime has been configured for a rate it is not receiving.
    /// process() already bypasses on the frame-length mismatch that causes, but
    /// it reports it as "deepfilternet_frame_size_mismatch", which does not say
    /// why. This does.
    private fun inferCaptureFormat(numFrames: Int, buffer: ByteBuffer) {
        val inferredRate = numFrames * 100
        // remaining(), not capacity(): if the adapter ever hands us a slice of a
        // larger allocation, capacity would describe the allocation rather than
        // the frame and inflate the channel count. Neither call moves position,
        // so the buffer is untouched for the nativeProcess() below.
        val frameBytes = if (buffer.remaining() > 0) buffer.remaining() else buffer.capacity()
        // Deliberately the same arithmetic nativeProcess() uses, so the number
        // reported here cannot disagree with the one the processor acts on:
        // the buffer is 32-bit FLOAT, interleaved, and channels falls out of
        // sample count over frame count.
        //
        // Getting this wrong is not hypothetical - the first version assumed
        // 16-bit PCM and divided by 2, which reported a mono 48 kHz capture as
        // "48000Hz/2ch" on device. The rate was right because it comes from the
        // frame count, but the channel count was a phantom.
        val sampleCount = frameBytes / Float.SIZE_BYTES
        val inferredChannels = if (numFrames > 0) sampleCount / numFrames else 0
        if (inferredChannels > 0) {
            channels = inferredChannels
        }
        // The rate is only DERIVED when nothing authoritative supplied one. A
        // `reset` carries the real new rate, and overwriting it with a value
        // computed from the frame count would replace a fact with an inference.
        // The channel count above has no such source - `reset` does not carry
        // one - so it is always re-derived.
        if (sampleRateHz == 0) {
            sampleRateHz = inferredRate
        }
        if (sampleRateHz != NATIVE_INIT_SAMPLE_RATE_HZ) {
            Log.w(
                TAG,
                "Capture format is ${sampleRateHz}Hz/${inferredChannels}ch, but the " +
                    "DeepFilterNet runtime was initialized at ${NATIVE_INIT_SAMPLE_RATE_HZ}Hz. " +
                    "Frames will bypass on the length mismatch.",
            )
        } else {
            Log.i(
                TAG,
                "Capture format resolved as ${sampleRateHz}Hz/${inferredChannels}ch " +
                    "(attached after the adapter's initialize callback)",
            )
        }
    }

    private fun process(numFrames: Int, buffer: ByteBuffer?) {
        if (buffer != null && numFrames > 0 && (sampleRateHz == 0 || channels == 0)) {
            inferCaptureFormat(numFrames, buffer)
        }
        if (!enabled.get() || pipelineMode != 6 || !nativeReady || buffer == null) {
            bypassFrames.incrementAndGet()
            return
        }
        if (numFrames != frameLength || !buffer.isDirect) {
            bypassFrames.incrementAndGet()
            reason = "deepfilternet_frame_size_mismatch"
            return
        }
        if (IntergalacticNoiseSuppressionNative.nativeProcess(buffer, numFrames) == 1) {
            framesProcessed.incrementAndGet()
            reason = "deepfilternet_ready"
        } else {
            bypassFrames.incrementAndGet()
        }
    }

    private fun ensureModelFile(): File {
        val directory = File(context.filesDir, "audio-models")
        directory.mkdirs()
        val model = File(directory, "DeepFilterNet3_onnx.tar.gz")
        val stamp = File(directory, MODEL_STAMP)

        // The archive was extracted once and then reused for the life of the
        // install, so a new APK's model asset never reached disk. That quietly
        // undid the version-scoped abort guard above: when the fix IS a new
        // model, the one retry the guard grants would re-run df_create against
        // the same bad archive and trip it again. It also stranded the installs
        // that got a double-compressed archive from the old single-read() gzip
        // probe - inflating one succeeds (it just yields more gzip), so
        // verification cannot detect it and only a re-extract recovers it.
        //
        // Stamping the extracted archive with the build that wrote it ties the
        // model's identity to the guard's, so one build change refreshes both.
        val fingerprint = buildFingerprint()
        val stampedBuild = readBuildStamp(stamp)
        val stale = stampedBuild != fingerprint
        if (stale && stampedBuild != null) {
            Log.i(
                TAG,
                "Re-extracting the DeepFilterNet model: on disk from build " +
                    "$stampedBuild, running $fingerprint",
            )
        }

        // A previously interrupted extract leaves a non-empty but truncated
        // file. df_create aborts the whole process on a bad archive rather than
        // reporting an error, so the file is verified (not merely present)
        // before it is handed to native code, and re-extracted if unreadable.
        //
        // The inflated size is kept from the verification pass rather than
        // recomputed for logging: inflating a model archive is not free, and
        // this runs on every initialize. A stale stamp skips the probe outright
        // rather than inflating an archive that is about to be replaced, so
        // this still inflates exactly once per initialize.
        var inflated = if (stale || !model.exists() || model.length() == 0L) {
            -1L
        } else {
            gzipInflatedSize(model)
        }
        if (inflated <= 0L) {
            extractModel(model)
            inflated = gzipInflatedSize(model)
            if (inflated <= 0L) {
                throw IOException(
                    "DeepFilterNet model archive is unreadable after extraction " +
                        "(${model.length()} bytes)",
                )
            }
            // Stamped only after the fresh archive verifies, so a failed
            // extract is retried on the next launch instead of being recorded
            // as current.
            writeModelStamp(stamp, fingerprint)
        }
        lastVerifiedInflatedSize = inflated
        return model
    }

    /// Records [fingerprint] as the build whose model asset is on disk.
    ///
    /// Best-effort, and deliberately not fsynced: unlike the abort guard,
    /// nothing depends on this surviving a process death. A stamp that cannot
    /// be written costs one re-extract on the next launch, which is not worth
    /// failing initialization over.
    private fun writeModelStamp(stamp: File, fingerprint: String) {
        try {
            stamp.writeText(fingerprint, Charsets.UTF_8)
        } catch (error: IOException) {
            Log.w(TAG, "Could not record the DeepFilterNet model build stamp", error)
        }
    }

    /// Extracts the model asset as a genuine gzip stream.
    ///
    /// aapt decompresses `.gz` assets while packaging the APK and drops the
    /// extension, so `DeepFilterNet3_onnx.tar.gz` ships as a plain, uncompressed
    /// `DeepFilterNet3_onnx.tar`. DeepFilterNet's loader always wraps the file in
    /// a GzDecoder, and on failure it panics rather than returning an error -
    /// aborting the whole process. Feeding it a plain tar therefore killed the
    /// app at launch. The asset is re-compressed here when aapt has already
    /// expanded it, and copied verbatim when it survived intact, so the loader
    /// receives valid gzip either way.
    private fun extractModel(target: File) {
        val assetName = when {
            context.assets.list("")?.contains(MODEL_ASSET) == true -> MODEL_ASSET
            else -> MODEL_ASSET.removeSuffix(".gz")
        }
        val staging = File(target.parentFile, "${target.name}.part")
        try {
            context.assets.open(assetName).buffered().use { input ->
                val header = ByteArray(2)
                input.mark(header.size)
                // Filled with an explicit loop, not a single read(): read() may
                // legally return one byte, which would read as "not gzip" and
                // re-wrap an archive that was already gzip - producing a
                // double-compressed file that only fails later, inside
                // df_create. InputStream.readNBytes would say this more
                // directly but is API 33+, and this module is minSdk 24.
                var headerBytes = 0
                while (headerBytes < header.size) {
                    val read = input.read(header, headerBytes, header.size - headerBytes)
                    if (read < 0) break
                    headerBytes += read
                }
                input.reset()
                val alreadyGzip = headerBytes == header.size &&
                    header[0] == GZIP_MAGIC_0 &&
                    header[1] == GZIP_MAGIC_1
                Log.w(
                    TAG,
                    "Extracting DeepFilterNet model asset=$assetName alreadyGzip=$alreadyGzip",
                )
                staging.outputStream().buffered().use { raw ->
                    if (alreadyGzip) {
                        input.copyTo(raw)
                    } else {
                        GZIPOutputStream(raw).use { gzip -> input.copyTo(gzip) }
                    }
                }
            }
            // Publish atomically so an interrupted write can never be mistaken
            // for a complete model on the next launch.
            if (!staging.renameTo(target)) {
                throw IOException("Could not publish DeepFilterNet model archive")
            }
        } finally {
            staging.delete()
        }
    }

    /// Fully inflates the archive to confirm it is a complete, valid gzip
    /// stream. Returns the decompressed byte count, or -1 when unreadable.
    private fun gzipInflatedSize(file: File): Long {
        return try {
            GZIPInputStream(file.inputStream().buffered()).use { input ->
                var total = 0L
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val read = input.read(buffer)
                    if (read < 0) break
                    total += read
                }
                total
            }
        } catch (_: IOException) {
            -1L
        }
    }

    // isReadableGzip() was removed: every caller now needs the inflated size
    // itself, and keeping a boolean wrapper invited inflating the archive twice.
}

private object IntergalacticNoiseSuppressionNative {
    init { System.loadLibrary("intergalactic_noise_suppression") }
    external fun nativeInitialize(modelPath: String, sampleRateHz: Int, attenuationLimitDb: Float, postFilterBeta: Float): Int
    external fun nativeProcess(buffer: ByteBuffer, numFrames: Int): Int
    external fun nativeReset(newRate: Int)
    external fun nativeShutdown()
}
