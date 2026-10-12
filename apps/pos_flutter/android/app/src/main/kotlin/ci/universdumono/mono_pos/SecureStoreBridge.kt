package ci.universdumono.mono_pos

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Small secrets (sync server origin and token) encrypted with an AES-GCM key
 * held by the Android Keystore; the key never leaves secure hardware and only
 * the ciphertext is stored in private preferences. No value is ever logged.
 */
class SecureStoreBridge(context: Context) {
    companion object {
        private const val KEY_ALIAS = "mono_secure_store_v1"
        private const val PREFS = "mono_secure_store"
        private val ALLOWED_KEYS = setOf("sync_origin", "sync_token", "sync_auto")
        private const val MAX_VALUE = 2048
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    fun write(name: String?, value: String?, result: MethodChannel.Result) {
        if (name !in ALLOWED_KEYS || value == null || value.length > MAX_VALUE) {
            result.error("INVALID_SECRET", "Valeur refusée.", null)
            return
        }
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            prefs.edit().putString(name, Base64.encodeToString(sealed, Base64.NO_WRAP)).apply()
            result.success(null)
        } catch (_: Exception) {
            result.error("SECURE_STORE_FAILED", "Enregistrement sécurisé impossible.", null)
        }
    }

    fun read(name: String?, result: MethodChannel.Result) {
        if (name !in ALLOWED_KEYS) {
            result.error("INVALID_SECRET", "Clé refusée.", null)
            return
        }
        val stored = prefs.getString(name, null) ?: return result.success(null)
        try {
            val sealed = Base64.decode(stored, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, 12))
            result.success(String(cipher.doFinal(sealed, 12, sealed.size - 12), Charsets.UTF_8))
        } catch (_: Exception) {
            // Unreadable (key reset, tampering): drop it and ask for it again.
            prefs.edit().remove(name).apply()
            result.success(null)
        }
    }

    fun delete(name: String?, result: MethodChannel.Result) {
        if (name !in ALLOWED_KEYS) {
            result.error("INVALID_SECRET", "Clé refusée.", null)
            return
        }
        prefs.edit().remove(name).apply()
        result.success(null)
    }
}
