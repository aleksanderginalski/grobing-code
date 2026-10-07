package com.grobing.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The photo the app keeps (ISSUE-016, D2'): a JPEG whose longer side is at most `maxEdge` pixels,
 * turned upright, without EXIF — a view copy; the original stays in the gallery or on paper. Any format
 * Android decodes goes in (HEIF too, from Android 9), so the image_picker package, which cannot shrink
 * HEIF, only picks.
 *
 * Decoding samples down by a power of two first and then scales by the decoded bitmap's own size, so
 * the result does not depend on whether a decoder reports the size before or after turning the picture.
 * Errors carry a code and the exception type only, never a path or a pixel.
 */
class PhotoPreparation(messenger: BinaryMessenger) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepare" -> {
                    val source = File(call.argument<String>("source")!!)
                    val target = File(call.argument<String>("target")!!)
                    val maxEdge = call.argument<Number>("maxEdge")!!.toInt()
                    val quality = call.argument<Number>("quality")!!.toInt()
                    io.execute {
                        try {
                            prepare(source, target, maxEdge, quality)
                            main.post { result.success(null) }
                        } catch (e: Exception) {
                            File(target.path + PART).delete()
                            main.post { result.error("prepare_failed", e.javaClass.simpleName, null) }
                        } catch (e: OutOfMemoryError) {
                            File(target.path + PART).delete()
                            main.post { result.error("too_large", e.javaClass.simpleName, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun prepare(source: File, target: File, maxEdge: Int, quality: Int) {
        val decoded = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            decodeUpright(source, maxEdge)
        } else {
            decodeUprightLegacy(source, maxEdge)
        }
        val scaled = scaleDown(decoded, maxEdge)
        if (scaled !== decoded) decoded.recycle()
        // Written under another name and renamed at the end: an interrupted write never looks finished.
        val part = File(target.path + PART)
        try {
            FileOutputStream(part).use { out ->
                if (!scaled.compress(Bitmap.CompressFormat.JPEG, quality, out)) {
                    throw IOException("compress")
                }
                out.fd.sync()
            }
        } finally {
            scaled.recycle()
        }
        if (!part.renameTo(target)) throw IOException("rename")
    }

    /** Android 9+: [ImageDecoder] turns the picture by its EXIF orientation itself. */
    private fun decodeUpright(source: File, maxEdge: Int): Bitmap =
        ImageDecoder.decodeBitmap(ImageDecoder.createSource(source)) { decoder, info, _ ->
            decoder.setTargetSampleSize(sampleSize(info.size.width, info.size.height, maxEdge))
            // A software bitmap: hardware ones cannot be scaled with a Canvas on every device.
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }

    /** Android 7–8 (minSdk 24): [BitmapFactory] ignores EXIF, so the picture is turned here. */
    private fun decodeUprightLegacy(source: File, maxEdge: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw IOException("decode")
        val options = BitmapFactory.Options().apply {
            inSampleSize = sampleSize(bounds.outWidth, bounds.outHeight, maxEdge)
        }
        val bitmap = BitmapFactory.decodeFile(source.path, options) ?: throw IOException("decode")
        val matrix = orientation(source) ?: return bitmap
        val upright = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (upright !== bitmap) bitmap.recycle()
        return upright
    }

    private fun orientation(source: File): Matrix? {
        val tag = try {
            ExifInterface(source.path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (e: IOException) {
            return null
        }
        val m = Matrix()
        when (tag) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> m.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> m.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> m.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                m.setRotate(90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> m.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                m.setRotate(-90f)
                m.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> m.setRotate(-90f)
            else -> return null
        }
        return m
    }

    companion object {
        const val CHANNEL = "com.grobing.app/photos"
        private const val PART = ".part"

        /** The largest power of two that keeps the longer side at or above [maxEdge] after sampling. */
        fun sampleSize(width: Int, height: Int, maxEdge: Int): Int {
            var sample = 1
            while (max(width, height) / (sample * 2) >= maxEdge) sample *= 2
            return sample
        }

        /** The longer side down to [maxEdge], keeping the proportions; a smaller picture stays as it is. */
        fun scaleDown(bitmap: Bitmap, maxEdge: Int): Bitmap {
            val longer = max(bitmap.width, bitmap.height)
            if (longer <= maxEdge) return bitmap
            val scale = maxEdge.toDouble() / longer
            val width = max(1, (bitmap.width * scale).roundToInt())
            val height = max(1, (bitmap.height * scale).roundToInt())
            return Bitmap.createScaledBitmap(bitmap, width, height, true)
        }
    }
}
