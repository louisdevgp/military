package ci.universdumono.mono_pos

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.util.concurrent.Executors
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import kotlin.system.exitProcess

/**
 * Encrypted backups: AES-256-GCM with a key derived from the administrator's
 * backup passphrase (PBKDF2-HMAC-SHA256). File layout:
 * "MONOBAK1" | salt (16) | iterations (int32) | iv (12) | ciphertext + tag.
 * Files are written and read through Android's document picker only.
 */
class BackupBridge(private val activity: Activity) {
    companion object {
        const val SAVE_REQUEST = 4109
        const val OPEN_REQUEST = 4110
        private val MAGIC = "MONOBAK1".toByteArray(Charsets.US_ASCII)
        private const val ITERATIONS = 210_000
        private const val MAX_BYTES = 200 * 1024 * 1024
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var toSave: ByteArray? = null

    private fun key(passphrase: CharArray, salt: ByteArray, iterations: Int): SecretKeySpec {
        val spec = PBEKeySpec(passphrase, salt, iterations, 256)
        val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        spec.clearPassword()
        return SecretKeySpec(bytes, "AES")
    }

    private fun run(result: MethodChannel.Result, body: () -> Any?) {
        executor.execute {
            try {
                val value = body()
                main.post { result.success(value) }
            } catch (_: AEADBadTagException) {
                main.post { result.error("BAD_PASSPHRASE", "Mot de passe incorrect ou fichier modifié.", null) }
            } catch (e: IllegalArgumentException) {
                main.post { result.error("INVALID_BACKUP", e.message, null) }
            } catch (_: Exception) {
                main.post { result.error("BACKUP_FAILED", "Opération de sauvegarde impossible.", null) }
            }
        }
    }

    fun encrypt(data: ByteArray?, passphrase: String?, result: MethodChannel.Result) = run(result) {
        require(data != null && data.size <= MAX_BYTES) { "Sauvegarde trop volumineuse." }
        require(passphrase != null && passphrase.length >= 10) { "Mot de passe trop court." }
        val random = SecureRandom()
        val salt = ByteArray(16).also(random::nextBytes)
        val iv = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(passphrase.toCharArray(), salt, ITERATIONS), GCMParameterSpec(128, iv))
        cipher.updateAAD(MAGIC)
        val sealed = cipher.doFinal(data)
        ByteBuffer.allocate(MAGIC.size + 16 + 4 + 12 + sealed.size)
            .put(MAGIC).put(salt).putInt(ITERATIONS).put(iv).put(sealed).array()
    }

    fun decrypt(data: ByteArray?, passphrase: String?, result: MethodChannel.Result) = run(result) {
        require(data != null && data.size > MAGIC.size + 32 && data.size <= MAX_BYTES) { "Fichier de sauvegarde invalide." }
        require(data.copyOfRange(0, MAGIC.size).contentEquals(MAGIC)) { "Ce fichier n’est pas une sauvegarde Mono." }
        require(passphrase != null) { "Mot de passe requis." }
        val buffer = ByteBuffer.wrap(data, MAGIC.size, data.size - MAGIC.size)
        val salt = ByteArray(16).also(buffer::get)
        val iterations = buffer.int
        require(iterations in 100_000..2_000_000) { "Fichier de sauvegarde invalide." }
        val iv = ByteArray(12).also(buffer::get)
        val sealed = ByteArray(buffer.remaining()).also(buffer::get)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(passphrase.toCharArray(), salt, iterations), GCMParameterSpec(128, iv))
        cipher.updateAAD(MAGIC)
        cipher.doFinal(sealed)
    }

    @Suppress("DEPRECATION")
    fun save(name: String?, data: ByteArray?, result: MethodChannel.Result) {
        if (pending != null) return result.error("BACKUP_BUSY", "Opération déjà en cours.", null)
        if (name == null || !name.matches(Regex("[\\w .-]{1,80}\\.monobak")) || data == null) {
            return result.error("INVALID_BACKUP", "Nom ou contenu invalide.", null)
        }
        pending = result
        toSave = data
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            activity.startActivityForResult(intent, SAVE_REQUEST)
        } catch (_: Exception) {
            finish()
            result.error("BACKUP_UNAVAILABLE", "Sélecteur de fichiers indisponible.", null)
        }
    }

    @Suppress("DEPRECATION")
    fun open(result: MethodChannel.Result) {
        if (pending != null) return result.error("BACKUP_BUSY", "Opération déjà en cours.", null)
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            activity.startActivityForResult(intent, OPEN_REQUEST)
        } catch (_: Exception) {
            finish()
            result.error("BACKUP_UNAVAILABLE", "Sélecteur de fichiers indisponible.", null)
        }
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?) {
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            finish()
            result.success(null) // cancelled
            return
        }
        val bytes = toSave
        finish()
        run(result) {
            if (requestCode == SAVE_REQUEST) {
                activity.contentResolver.openOutputStream(uri, "wt").use { requireNotNull(it).write(requireNotNull(bytes)) }
                true
            } else {
                activity.contentResolver.openInputStream(uri).use { input ->
                    val read = requireNotNull(input).readBytes()
                    require(read.size <= MAX_BYTES) { "Fichier trop volumineux." }
                    read
                }
            }
        }
    }

    /** Restarts the app so the staged restore is applied before the database opens. */
    fun relaunch() {
        val intent = activity.packageManager.getLaunchIntentForPackage(activity.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        activity.startActivity(intent)
        activity.finishAffinity()
        exitProcess(0)
    }

    private fun finish() {
        pending = null
        toSave = null
    }

    fun close() {
        pending?.error("BACKUP_CLOSED", "Opération interrompue.", null)
        finish()
        executor.shutdown()
    }
}
