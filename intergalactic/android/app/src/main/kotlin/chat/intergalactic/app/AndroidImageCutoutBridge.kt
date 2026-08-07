package chat.intergalactic.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenter
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.nio.FloatBuffer
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private const val IMAGE_CUTOUT_CHANNEL = "chat.intergalactic.app/image_cutout"
private const val IMAGE_CUTOUT_ANDROID_BACKEND = "androidMlKitSubjectSegmentation"
private const val IMAGE_CUTOUT_TAG = "IGImageCutout"
private const val IMAGE_CUTOUT_DEFAULT_MAX_DIMENSION = 1024
private const val IMAGE_CUTOUT_MIN_MAX_DIMENSION = 64
private const val IMAGE_CUTOUT_MAX_MAX_DIMENSION = 2048

object AndroidImageCutoutBridge {
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IMAGE_CUTOUT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "generateMask" -> generateMask(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun generateMask(call: MethodCall, result: MethodChannel.Result) {
        if (call.argument<String>("backend") != IMAGE_CUTOUT_ANDROID_BACKEND) {
            result.error("unsupported_platform", null, null)
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.error("unsupported_os_version", null, null)
            return
        }

        val imageBytes = call.argument<ByteArray>("imageBytes")
        if (imageBytes == null || imageBytes.isEmpty()) {
            result.error("image_decode_failed", null, null)
            return
        }

        val maxProcessingDimension = maxProcessingDimension(call)
        Log.d(
            IMAGE_CUTOUT_TAG,
            "generate_start backend=$IMAGE_CUTOUT_ANDROID_BACKEND bytes=${imageBytes.size} max_dim=$maxProcessingDimension",
        )

        Thread {
            var sourceBitmap: Bitmap? = null
            var segmenter: SubjectSegmenter? = null
            try {
                val activeSegmenter =
                    SubjectSegmentation.getClient(
                        SubjectSegmenterOptions.Builder()
                            .enableForegroundConfidenceMask()
                            .build(),
                    )
                segmenter = activeSegmenter
                sourceBitmap = decodePreparedBitmap(
                    imageBytes = imageBytes,
                    maxProcessingDimension = maxProcessingDimension,
                )
                val inputImage = InputImage.fromBitmap(sourceBitmap, 0)
                activeSegmenter.process(inputImage)
                    .addOnSuccessListener { segmentationResult ->
                        try {
                            val mask = segmentationResult.foregroundConfidenceMask
                            val alpha = alphaFromConfidenceMask(
                                mask = mask,
                                width = inputImage.width,
                                height = inputImage.height,
                            )
                            Log.d(
                                IMAGE_CUTOUT_TAG,
                                "generate_success backend=$IMAGE_CUTOUT_ANDROID_BACKEND width=${inputImage.width} height=${inputImage.height} alpha_count=${alpha.size}",
                            )
                            success(
                                result,
                                mapOf(
                                    "width" to inputImage.width,
                                    "height" to inputImage.height,
                                    "alpha" to alpha,
                                ),
                            )
                        } catch (exception: ImageCutoutBridgeException) {
                            Log.w(
                                IMAGE_CUTOUT_TAG,
                                "generate_failure backend=$IMAGE_CUTOUT_ANDROID_BACKEND code=${exception.code}",
                            )
                            error(result, exception.code)
                        } catch (exception: Exception) {
                            Log.w(
                                IMAGE_CUTOUT_TAG,
                                "generate_failure backend=$IMAGE_CUTOUT_ANDROID_BACKEND code=processing_failed",
                                exception,
                            )
                            error(result, "processing_failed")
                        } finally {
                            closeSegmenter(segmenter)
                            recycleBitmap(sourceBitmap)
                        }
                    }
                    .addOnFailureListener { exception ->
                        val code = platformFailureCode(exception)
                        Log.w(
                            IMAGE_CUTOUT_TAG,
                            "generate_failure backend=$IMAGE_CUTOUT_ANDROID_BACKEND code=$code",
                        )
                        closeSegmenter(segmenter)
                        recycleBitmap(sourceBitmap)
                        error(result, code)
                    }
            } catch (exception: ImageCutoutBridgeException) {
                closeSegmenter(segmenter)
                recycleBitmap(sourceBitmap)
                Log.w(
                    IMAGE_CUTOUT_TAG,
                    "generate_failure backend=$IMAGE_CUTOUT_ANDROID_BACKEND code=${exception.code}",
                )
                error(result, exception.code)
            } catch (exception: Exception) {
                closeSegmenter(segmenter)
                recycleBitmap(sourceBitmap)
                Log.w(
                    IMAGE_CUTOUT_TAG,
                    "generate_failure backend=$IMAGE_CUTOUT_ANDROID_BACKEND code=processing_failed",
                    exception,
                )
                error(result, "processing_failed")
            }
        }.start()
    }

    private fun maxProcessingDimension(call: MethodCall): Int {
        val settings = call.argument<Map<String, Any?>>("settings")
        val value = settings?.get("maxProcessingDimension") as? Number
        return (value?.toInt() ?: IMAGE_CUTOUT_DEFAULT_MAX_DIMENSION)
            .coerceIn(
                IMAGE_CUTOUT_MIN_MAX_DIMENSION,
                IMAGE_CUTOUT_MAX_MAX_DIMENSION,
            )
    }

    private fun decodePreparedBitmap(
        imageBytes: ByteArray,
        maxProcessingDimension: Int,
    ): Bitmap {
        val bounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw ImageCutoutBridgeException("image_decode_failed")
        }

        val decodeOptions = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSizeFor(
                width = bounds.outWidth,
                height = bounds.outHeight,
                maxDimension = maxProcessingDimension,
            )
        }
        val decoded = BitmapFactory.decodeByteArray(
            imageBytes,
            0,
            imageBytes.size,
            decodeOptions,
        ) ?: throw ImageCutoutBridgeException("image_decode_failed")

        val oriented = applyExifOrientation(decoded, imageBytes)
        if (oriented != decoded) {
            recycleBitmap(decoded)
        }

        return scaleToMaxDimension(oriented, maxProcessingDimension)
    }

    private fun sampleSizeFor(
        width: Int,
        height: Int,
        maxDimension: Int,
    ): Int {
        var sampleSize = 1
        while (max(width / sampleSize, height / sampleSize) > maxDimension * 2) {
            sampleSize *= 2
        }
        return sampleSize
    }

    private fun applyExifOrientation(
        bitmap: Bitmap,
        imageBytes: ByteArray,
    ): Bitmap {
        val orientation = try {
            ExifInterface(ByteArrayInputStream(imageBytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return bitmap
        }

        return Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            matrix,
            true,
        )
    }

    private fun scaleToMaxDimension(
        bitmap: Bitmap,
        maxProcessingDimension: Int,
    ): Bitmap {
        val maxSide = max(bitmap.width, bitmap.height)
        if (maxSide <= maxProcessingDimension) {
            return bitmap
        }

        val scale = maxProcessingDimension.toFloat() / maxSide.toFloat()
        val scaledWidth = max(1, (bitmap.width * scale).roundToInt())
        val scaledHeight = max(1, (bitmap.height * scale).roundToInt())
        val scaled = Bitmap.createScaledBitmap(
            bitmap,
            scaledWidth,
            scaledHeight,
            true,
        )
        if (scaled != bitmap) {
            recycleBitmap(bitmap)
        }
        return scaled
    }

    private fun alphaFromConfidenceMask(
        mask: FloatBuffer?,
        width: Int,
        height: Int,
    ): ByteArray {
        if (mask == null ||
            width <= 0 ||
            height <= 0 ||
            mask.capacity() < width * height
        ) {
            throw ImageCutoutBridgeException("processing_failed")
        }

        mask.rewind()
        val alpha = ByteArray(width * height)
        var foregroundPixels = 0
        for (index in alpha.indices) {
            val confidence = mask.get().coerceIn(0f, 1f)
            val value = (confidence * 255f).roundToInt().coerceIn(0, 255)
            if (value > 18) {
                foregroundPixels += 1
            }
            alpha[index] = value.toByte()
        }

        if (foregroundPixels == 0) {
            throw ImageCutoutBridgeException("no_subject_found")
        }

        return alpha
    }

    private fun platformFailureCode(exception: Exception): String {
        val text = "${exception.javaClass.simpleName} ${exception.message.orEmpty()}"
            .lowercase(Locale.US)
        return when {
            "download" in text && "fail" in text -> "model_download_failed"
            "download" in text || "model" in text || "unavailable" in text ->
                "model_download_required"
            else -> "processing_failed"
        }
    }

    private fun success(
        result: MethodChannel.Result,
        response: Map<String, Any>,
    ) {
        mainHandler.post {
            result.success(response)
        }
    }

    private fun error(result: MethodChannel.Result, code: String) {
        mainHandler.post {
            result.error(code, null, null)
        }
    }

    private fun closeSegmenter(segmenter: Any?) {
        if (segmenter == null) {
            return
        }
        try {
            if (segmenter is AutoCloseable) {
                segmenter.close()
                return
            }
            segmenter.javaClass.getMethod("close").invoke(segmenter)
        } catch (_: Exception) {
        }
    }

    private fun recycleBitmap(bitmap: Bitmap?) {
        if (bitmap != null && !bitmap.isRecycled) {
            bitmap.recycle()
        }
    }
}

private class ImageCutoutBridgeException(val code: String) : Exception()
