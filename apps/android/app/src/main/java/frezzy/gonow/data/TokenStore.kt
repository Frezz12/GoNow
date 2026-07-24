package frezzy.gonow.data

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import frezzy.gonow.models.TokenSet
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

interface SessionStore {
    fun saveTokens(tokens: TokenSet)
    fun getAccessToken(): String?
    fun getRefreshToken(): String?
    fun getAccessTokenExpiresAt(): String?
    fun hasTokens(): Boolean = getRefreshToken() != null
    fun clearTokens()
}

/**
 * Stores one encrypted session blob using a non-exportable Android Keystore key.
 * Existing EncryptedSharedPreferences/plain fallback values are migrated once and removed.
 */
class TokenStore(context: Context) : SessionStore {

    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private val lock = Any()

    @Volatile
    private var cachedTokens: TokenSet? = null

    init {
        synchronized(lock) {
            cachedTokens = readEncryptedTokens() ?: migrateLegacyTokens()
        }
    }

    override fun saveTokens(tokens: TokenSet) {
        synchronized(lock) {
            val encoded = encrypt(json.encodeToString(tokens).toByteArray(StandardCharsets.UTF_8))
            check(prefs.edit().putString(KEY_SESSION_BLOB, encoded).commit()) {
                "Unable to persist encrypted session"
            }
            cachedTokens = tokens
        }
    }

    override fun getAccessToken(): String? = synchronized(lock) { cachedTokens?.accessToken }

    override fun getRefreshToken(): String? = synchronized(lock) { cachedTokens?.refreshToken }

    override fun getAccessTokenExpiresAt(): String? = synchronized(lock) {
        cachedTokens?.accessTokenExpiresAt
    }

    override fun clearTokens() {
        synchronized(lock) {
            cachedTokens = null
            prefs.edit().clear().commit()
            clearLegacyStores()
        }
    }

    private fun readEncryptedTokens(): TokenSet? {
        val blob = prefs.getString(KEY_SESSION_BLOB, null) ?: return null
        return try {
            val decoded = decrypt(blob).toString(StandardCharsets.UTF_8)
            json.decodeFromString<TokenSet>(decoded)
        } catch (error: Exception) {
            Log.e(TAG, "Encrypted session is unavailable; requiring a new login", error)
            prefs.edit().remove(KEY_SESSION_BLOB).commit()
            null
        }
    }

    private fun migrateLegacyTokens(): TokenSet? {
        val candidates = buildList {
            legacyEncryptedPrefs()?.let(::add)
            add(appContext.getSharedPreferences(LEGACY_PLAIN_PREFS, Context.MODE_PRIVATE))
        }
        val tokens = candidates.firstNotNullOfOrNull { legacy ->
            val access = legacy.getString(LEGACY_ACCESS_TOKEN, null)
            val refresh = legacy.getString(LEGACY_REFRESH_TOKEN, null)
            val expiresAt = legacy.getString(LEGACY_EXPIRES_AT, null)
            if (access != null && refresh != null && expiresAt != null) {
                TokenSet(access, refresh, expiresAt)
            } else {
                null
            }
        } ?: return null

        return try {
            saveTokens(tokens)
            candidates.forEach { it.edit().clear().commit() }
            tokens
        } catch (error: Exception) {
            Log.e(TAG, "Legacy session could not be migrated securely", error)
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun legacyEncryptedPrefs(): SharedPreferences? = try {
        val masterKey = androidx.security.crypto.MasterKey.Builder(appContext)
            .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
            .build()
        androidx.security.crypto.EncryptedSharedPreferences.create(
            appContext,
            LEGACY_ENCRYPTED_PREFS,
            masterKey,
            androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    } catch (error: Exception) {
        Log.w(TAG, "Legacy encrypted session is not readable", error)
        null
    }

    private fun clearLegacyStores() {
        legacyEncryptedPrefs()?.edit()?.clear()?.commit()
        appContext.getSharedPreferences(LEGACY_PLAIN_PREFS, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    private fun encrypt(plainText: ByteArray): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val encrypted = cipher.doFinal(plainText)
        val buffer = ByteBuffer.allocate(Int.SIZE_BYTES + cipher.iv.size + encrypted.size)
            .putInt(cipher.iv.size)
            .put(cipher.iv)
            .put(encrypted)
        return Base64.encodeToString(buffer.array(), Base64.NO_WRAP)
    }

    private fun decrypt(value: String): ByteArray {
        val buffer = ByteBuffer.wrap(Base64.decode(value, Base64.NO_WRAP))
        val ivLength = buffer.int
        require(ivLength in 12..32 && buffer.remaining() > ivLength) { "Invalid session blob" }
        val iv = ByteArray(ivLength).also(buffer::get)
        val encrypted = ByteArray(buffer.remaining()).also(buffer::get)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
        return cipher.doFinal(encrypted)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "TokenStore"
        const val PREFS_NAME = "gonow_session_v2"
        const val KEY_SESSION_BLOB = "encrypted_session"
        const val KEY_ALIAS = "gonow_session_key_v2"
        const val ANDROID_KEY_STORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"

        const val LEGACY_ENCRYPTED_PREFS = "gonow_session"
        const val LEGACY_PLAIN_PREFS = "gonow_session_plain"
        const val LEGACY_ACCESS_TOKEN = "access_token"
        const val LEGACY_REFRESH_TOKEN = "refresh_token"
        const val LEGACY_EXPIRES_AT = "access_token_expires_at"
    }
}
