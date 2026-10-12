package ci.universdumono.mono_pos

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Saves a text export (CSV) where the operator chooses, through Android's
 * document creator: no storage-wide permission, no copy left in the app.
 */
class ExportBridge(private val activity: Activity) {
    companion object {
        const val REQUEST_CODE = 4108
        private const val MAX_BYTES = 8 * 1024 * 1024
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var content: ByteArray? = null

    @Suppress("DEPRECATION")
    fun save(name: String?, text: String?, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("EXPORT_BUSY", "Un enregistrement est déjà en cours.", null)
            return
        }
        val bytes = text?.toByteArray(Charsets.UTF_8)
        if (name.isNullOrBlank() || !name.matches(Regex("[\\w .-]{1,80}\\.csv")) ||
            bytes == null || bytes.size > MAX_BYTES
        ) {
            result.error("INVALID_EXPORT", "Export invalide.", null)
            return
        }
        pending = result
        content = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/csv"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (_: Exception) {
            finish()
            result.error("EXPORT_UNAVAILABLE", "L’enregistrement de fichiers est indisponible.", null)
        }
    }

    fun onResult(resultCode: Int, data: Intent?) {
        val result = pending ?: return
        val bytes = content
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
            finish()
            result.success(false) // cancelled by the operator
            return
        }
        executor.execute {
            try {
                activity.contentResolver.openOutputStream(uri, "wt").use { out ->
                    requireNotNull(out).write(bytes)
                }
                main.post { finish(); result.success(true) }
            } catch (_: Exception) {
                main.post {
                    finish()
                    result.error("EXPORT_FAILED", "Le fichier n’a pas pu être écrit.", null)
                }
            }
        }
    }

    private fun finish() {
        pending = null
        content = null
    }

    fun close() {
        pending?.error("EXPORT_CLOSED", "Enregistrement interrompu.", null)
        finish()
        executor.shutdown()
    }
}
