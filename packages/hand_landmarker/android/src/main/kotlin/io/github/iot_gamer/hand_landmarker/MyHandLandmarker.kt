package io.github.iot_gamer.hand_landmarker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.core.RunningMode    
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

interface HandLandmarkListener {
    fun onLandmarksDetected(landmarksJson: String)
}

class MyHandLandmarker(private val context: Context) {
    private var handLandmarker: HandLandmarker? = null
    var listener: HandLandmarkListener? = null // Attach the listener here

    fun initialize(
        numHands: Int,
        minHandDetectionConfidence: Float,
        useGpu: Boolean
    ) {
        val delegate = if (useGpu) Delegate.GPU else Delegate.CPU
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath("hand_landmarker.task")
            .setDelegate(delegate)
            .build()
            
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setNumHands(numHands)
            // Switch to LIVE_STREAM mode for async processing
            .setRunningMode(com.google.mediapipe.tasks.vision.core.RunningMode.LIVE_STREAM)
            .setMinHandDetectionConfidence(minHandDetectionConfidence)
            // Listen for results on the background thread
            .setResultListener { result, _ ->
                // FiloSign: frame -> result delay, sent along for the debug panel
                if (result != null) {
                    submitted.remove(result.timestampMs())?.let {
                        latencyMs = latencyMs * 0.9 + (System.nanoTime() - it) / 1e6 * 0.1
                    }
                }
                val timing = "\"c\":${"%.1f".format(java.util.Locale.US, convertMs)}," +
                        "\"l\":${"%.1f".format(java.util.Locale.US, latencyMs)}"
                if (result == null || result.landmarks().isEmpty()) {
                    HandLandmarkerPlugin.sendLandmarks("{$timing,\"h\":[]}")
                    return@setResultListener
                }

                // Build a JSON string of the landmarks
                val handsJson = StringBuilder()
                handsJson.append("{").append(timing).append(",\"h\":")
                handsJson.append("[")
                result.landmarks().forEachIndexed { handIndex, handLandmarks ->
                    handsJson.append("[")
                    handLandmarks.forEachIndexed { landmarkIndex, landmark ->
                        handsJson.append("{")
                        handsJson.append("\"x\":${landmark.x()},")
                        handsJson.append("\"y\":${landmark.y()},")
                        handsJson.append("\"z\":${landmark.z()}")
                        handsJson.append("}")
                        if (landmarkIndex < handLandmarks.size - 1) {
                            handsJson.append(",")
                        }
                    }
                    handsJson.append("]")
                    if (handIndex < result.landmarks().size - 1) {
                        handsJson.append(",")
                    }
                }
                handsJson.append("]}")

                // Send the generated JSON string to Dart via the plugin's companion object
                HandLandmarkerPlugin.sendLandmarks(handsJson.toString())
            }
            .setErrorListener { error ->
                android.util.Log.e("HandLandmarker", "MediaPipe Error: ${error.message}")
            }
            .build()
            
        handLandmarker = HandLandmarker.createFromOptions(context, options)
    }

    // FiloSign patch: the YUV->RGB conversion used to run on the CALLER's
    // thread (Flutter's UI thread, via JNI), pixel by pixel through
    // ByteBuffer.get - at 640x480 that stalled the whole app. Now the planes
    // are bulk-copied (the Dart side frees its buffers right after this call)
    // and converted + detected on one worker thread; frames that arrive while
    // the worker is busy are dropped instead of queued (no growing lag).
    private val worker = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val busy = java.util.concurrent.atomic.AtomicBoolean(false)
    private var lastTimestampMs = 0L

    // Buffers are reused: allocating ~3 MB per frame (planes, pixels, bitmap)
    // made weak phones spend their time in garbage collection. Only touched
    // while `busy` is held, so the next frame can't overwrite them early.
    private var yArr = ByteArray(0)
    private var uArr = ByteArray(0)
    private var vArr = ByteArray(0)
    private var argb = IntArray(0)
    private val bitmaps = arrayOfNulls<Bitmap>(3)    // ring: MediaPipe may still read the last one
    private var nextBitmap = 0

    /** Timing for the app's debug panel: YUV->RGB ms and frame->result ms (moving averages). */
    @Volatile var convertMs = 0.0
    @Volatile var latencyMs = 0.0
    private val submitted = java.util.concurrent.ConcurrentHashMap<Long, Long>()

    fun processFrame(
        yBuffer: ByteBuffer, uBuffer: ByteBuffer, vBuffer: ByteBuffer,
        width: Int, height: Int, yRowStride: Int, uvRowStride: Int, uvPixelStride: Int,
        rotation: Int, timestampMs: Long // Live_stream requires a monotonic timestamp
    ) {
        if (handLandmarker == null) return
        if (!busy.compareAndSet(false, true)) return // still working on the last frame

        yArr = copyInto(yBuffer, yArr)
        uArr = copyInto(uBuffer, uArr)
        vArr = copyInto(vBuffer, vArr)

        worker.execute {
            try {
                val lm = handLandmarker ?: return@execute
                val t0 = System.nanoTime()
                val bitmap = yuvToBitmap(width, height, yRowStride, uvRowStride, uvPixelStride)
                convertMs = convertMs * 0.9 + (System.nanoTime() - t0) / 1e6 * 0.1
                val mpImage = BitmapImageBuilder(bitmap).build()
                val imageProcessingOptions = ImageProcessingOptions.builder()
                    .setRotationDegrees(rotation)
                    .build()
                val ts = if (timestampMs > lastTimestampMs) timestampMs else lastTimestampMs + 1
                lastTimestampMs = ts
                submitted[ts] = System.nanoTime()
                if (submitted.size > 32) submitted.keys.filter { it < ts - 2000 }.forEach { submitted.remove(it) }
                // detectAsync: MediaPipe runs the model on its own thread
                lm.detectAsync(mpImage, imageProcessingOptions, ts)
                mpImage.close()
            } catch (e: Exception) {
                android.util.Log.e("HandLandmarker", "processFrame failed: ${e.message}")
            } finally {
                busy.set(false)
            }
        }
    }

    private fun copyInto(src: ByteBuffer, dst: ByteArray): ByteArray {
        val n = src.remaining()
        val out = if (dst.size == n) dst else ByteArray(n)
        src.duplicate().get(out)
        return out
    }

    /** Integer YUV->ARGB (same math as [yuvToRgbBitmap]) into reused buffers;
     *  each chroma sample is decoded once for its 2x2 block of pixels. */
    private fun yuvToBitmap(
        width: Int, height: Int, yRowStride: Int, uvRowStride: Int, uvPixelStride: Int
    ): Bitmap {
        val n = width * height
        if (argb.size != n) argb = IntArray(n)
        val px = argb; val ys = yArr; val us = uArr; val vs = vArr
        var j = 0
        while (j < height) {
            val uvRow = (j shr 1) * uvRowStride
            val y0 = j * yRowStride
            val y1 = if (j + 1 < height) y0 + yRowStride else -1
            val o0 = j * width
            var i = 0
            while (i < width) {
                val uv = uvRow + (i shr 1) * uvPixelStride
                val u = (us[uv].toInt() and 0xFF) - 128
                val v = (vs[uv].toInt() and 0xFF) - 128
                val rv = 1634 * v
                val guv = -833 * v - 400 * u
                val bu = 2066 * u
                px[o0 + i] = pack(ys[y0 + i], rv, guv, bu)
                if (i + 1 < width) px[o0 + i + 1] = pack(ys[y0 + i + 1], rv, guv, bu)
                if (y1 >= 0) {
                    px[o0 + width + i] = pack(ys[y1 + i], rv, guv, bu)
                    if (i + 1 < width) px[o0 + width + i + 1] = pack(ys[y1 + i + 1], rv, guv, bu)
                }
                i += 2
            }
            j += 2
        }
        var bmp = bitmaps[nextBitmap]
        if (bmp == null || bmp.width != width || bmp.height != height) {
            bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmaps[nextBitmap] = bmp
        }
        nextBitmap = (nextBitmap + 1) % bitmaps.size
        bmp!!.setPixels(px, 0, width, 0, 0, width, height)
        return bmp
    }

    private fun pack(yb: Byte, rv: Int, guv: Int, bu: Int): Int {
        val y = (yb.toInt() and 0xFF) - 16
        val y1192 = if (y < 0) 0 else 1192 * y
        var r = y1192 + rv
        var g = y1192 + guv
        var b = y1192 + bu
        r = if (r < 0) 0 else if (r > 262143) 262143 else r
        g = if (g < 0) 0 else if (g > 262143) 262143 else g
        b = if (b < 0) 0 else if (b > 262143) 262143 else b
        return -0x1000000 or ((r shl 6) and 0xFF0000) or ((g shr 2) and 0xFF00) or ((b shr 10) and 0xFF)
    }

    /**
     * Detects hand landmarks from YUV image planes.
     * This method is more efficient as it avoids YUV->RGBA conversion in Dart.
     */
    fun detectFromYuv(
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        rotation: Int
    ): String {
        
        if (handLandmarker == null) {
            initialize(2, 0.5f, true)
        }

        // Convert YUV planes DIRECTLY to an ARGB Bitmap
        val bitmap = yuvToRgbBitmap(yBuffer, uBuffer, vBuffer, width, height, yRowStride, uvRowStride, uvPixelStride)

        // Create an MPImage from the Bitmap
        val mpImage = BitmapImageBuilder(bitmap).build()

        val imageProcessingOptions = ImageProcessingOptions.builder()
            .setRotationDegrees(rotation)
            .build()

        // Run detection
        val result = handLandmarker?.detect(mpImage, imageProcessingOptions)

        // Clean up memory immediately
        bitmap.recycle()
        mpImage.close()

        if (result == null || result.landmarks().isEmpty()) {
            return "[]"
        }

        // Build a JSON string of the landmarks
        val handsJson = StringBuilder()
        handsJson.append("[")
        result.landmarks().forEachIndexed { handIndex, handLandmarks ->
            handsJson.append("[")
            handLandmarks.forEachIndexed { landmarkIndex, landmark ->
                handsJson.append("{")
                handsJson.append("\"x\":${landmark.x()},")
                handsJson.append("\"y\":${landmark.y()},")
                handsJson.append("\"z\":${landmark.z()}")
                handsJson.append("}")
                if (landmarkIndex < handLandmarks.size - 1) {
                    handsJson.append(",")
                }
            }
            handsJson.append("]")
            if (handIndex < result.landmarks().size - 1) {
                handsJson.append(",")
            }
        }
        handsJson.append("]")

        return handsJson.toString()
    }

    /**
     * Converts Y, U, V planes directly to an ARGB_8888 Bitmap.
     * This avoids both NV21 intermediate allocation and JPEG compression.
     */
    private fun yuvToRgbBitmap(
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int
    ): Bitmap {
        val argbArray = IntArray(width * height)
        var yp = 0
        
        for (j in 0 until height) {
            val uvRowStart = (j / 2) * uvRowStride
            val yRowStart = j * yRowStride
            
            for (i in 0 until width) {
                val uvOffset = uvRowStart + (i / 2) * uvPixelStride
                
                // Extract Y, U, V values and adjust standard ranges
                val y = (yBuffer.get(yRowStart + i).toInt() and 0xFF) - 16
                val u = (uBuffer.get(uvOffset).toInt() and 0xFF) - 128
                val v = (vBuffer.get(uvOffset).toInt() and 0xFF) - 128

                // Fast integer math for YUV to RGB conversion
                val y1192 = if (y < 0) 0 else 1192 * y
                var r = y1192 + 1634 * v
                var g = y1192 - 833 * v - 400 * u
                var b = y1192 + 2066 * u

                // Clamp values to 0-255 using bitwise logic
                r = if (r < 0) 0 else if (r > 262143) 262143 else r
                g = if (g < 0) 0 else if (g > 262143) 262143 else g
                b = if (b < 0) 0 else if (b > 262143) 262143 else b

                // Pack into ARGB pixel
                argbArray[yp++] = -0x1000000 or 
                        ((r shl 6) and 0xFF0000) or 
                        ((g shr 2) and 0xFF00) or 
                        ((b shr 10) and 0xFF)
            }
        }
        
        return Bitmap.createBitmap(argbArray, width, height, Bitmap.Config.ARGB_8888)
    }
}