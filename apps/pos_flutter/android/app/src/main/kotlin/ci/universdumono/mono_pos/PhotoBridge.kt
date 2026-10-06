package ci.universdumono.mono_pos

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import kotlin.math.max

/** Android's document picker; no storage-wide permission or third-party SDK. */
class PhotoBridge(private val activity: Activity) {
    companion object {
        const val REQUEST_CODE = 4107
        const val MAX_SOURCE_BYTES = 12 * 1024 * 1024
        const val MAX_OUTPUT_BYTES = 2 * 1024 * 1024
        const val MAX_EDGE = 1280
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val directory: File get() = File(activity.filesDir, "catalog_images")

    @Suppress("DEPRECATION")
    fun choose(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("PICKER_BUSY", "Une sélection de photo est déjà ouverte.", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/webp"))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: Exception) {
            pending = null
            result.error("PICKER_UNAVAILABLE", "Le sélecteur de photos n’est pas disponible.", null)
        }
    }

    fun onResult(resultCode: Int, data: Intent?) {
        val result = pending ?: return
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending = null
            result.success(null)
            return
        }
        val uri = data.data!!
        executor.execute {
            try {
                val path = importPhoto(uri)
                main.post {
                    if (pending === result) { pending = null; result.success(path) }
                    else { File(path).delete() }
                }
            } catch (_: Exception) {
                main.post {
                    if (pending === result) {
                        pending = null
                        result.error("INVALID_IMAGE", "Choisissez une image JPEG, PNG ou WebP de moins de 12 Mo.", null)
                    }
                }
            }
        }
    }

    private fun importPhoto(uri: Uri): String {
        val mime = activity.contentResolver.getType(uri)
        require(mime in setOf("image/jpeg", "image/png", "image/webp"))
        val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16384)
            var total = 0
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                total += n
                require(total <= MAX_SOURCE_BYTES)
                output.write(buffer, 0, n)
            }
            output.toByteArray()
        } ?: error("No image data")
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0)
        require(bounds.outMimeType in setOf("image/jpeg", "image/png", "image/webp"))
        require(bounds.outWidth.toLong() * bounds.outHeight.toLong() <= 64_000_000)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > MAX_EDGE) sample *= 2
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size,
            BitmapFactory.Options().apply { inSampleSize = sample }) ?: error("Invalid image")
        val matrix = Matrix()
        val orientation = if (bounds.outMimeType == "image/jpeg") {
            ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } else ExifInterface.ORIENTATION_NORMAL
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.setRotate(90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.setRotate(-90f); matrix.postScale(-1f, 1f) }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
        }
        val rotated = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
        if (rotated !== decoded) decoded.recycle()
        val scale = minOf(1.0, MAX_EDGE.toDouble() / max(rotated.width, rotated.height))
        val width = maxOf(1, (rotated.width * scale).toInt())
        val height = maxOf(1, (rotated.height * scale).toInt())
        val scaled = Bitmap.createScaledBitmap(rotated, width, height, true)
        if (scaled !== rotated) rotated.recycle()
        // Flatten transparency on white and re-encode; no EXIF/GPS is copied.
        val clean = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
        val canvas = Canvas(clean)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(scaled, 0f, 0f, null)
        scaled.recycle()
        val output = ByteArrayOutputStream()
        try {
            require(clean.compress(Bitmap.CompressFormat.JPEG, 85, output))
        } finally { clean.recycle() }
        require(output.size() in 1..MAX_OUTPUT_BYTES)
        require(directory.isDirectory || directory.mkdirs())
        val destination = File(directory, "${UUID.randomUUID()}.jpg")
        try {
            destination.outputStream().use { it.write(output.toByteArray()) }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
        return destination.absolutePath
    }

    fun discardDraft(path: String?, result: MethodChannel.Result) {
        try {
            val file = File(requireNotNull(path)).canonicalFile
            require(file.parentFile == directory.canonicalFile)
            require(file.name.matches(Regex("[a-f0-9-]{36}\\.jpg")))
            if (file.exists() && !file.delete()) error("Unable to remove draft")
            result.success(null)
        } catch (_: Exception) {
            result.error("DRAFT_DELETE_FAILED", "La photo provisoire n’a pas pu être supprimée.", null)
        }
    }

    fun close() {
        pending?.error("PICKER_CLOSED", "La sélection de photo a été interrompue.", null)
        pending = null
        executor.shutdown()
    }
}
