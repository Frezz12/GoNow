package frezzy.gonow.data

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import frezzy.gonow.models.DevicePayload
import java.util.UUID

class DeviceIdentity(context: Context) {

    private val prefs: SharedPreferences = createPrefs(context)

    private fun createPrefs(context: Context): SharedPreferences {
        return try {
            val masterKey = androidx.security.crypto.MasterKey.Builder(context)
                .setKeyScheme(androidx.security.crypto.MasterKey.KeyScheme.AES256_GCM)
                .build()
            androidx.security.crypto.EncryptedSharedPreferences.create(
                context,
                "gonow_device",
                masterKey,
                androidx.security.crypto.EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                androidx.security.crypto.EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        } catch (e: Exception) {
            Log.w("DeviceIdentity", "EncryptedSharedPreferences unavailable, using plain prefs", e)
            context.getSharedPreferences("gonow_device_plain", Context.MODE_PRIVATE)
        }
    }

    fun getDevicePayload(): DevicePayload {
        val deviceId = getOrCreateDeviceId()
        val deviceName = Build.MODEL ?: "Android Device"
        return DevicePayload(
            deviceId = deviceId,
            deviceName = deviceName,
            platform = "android"
        )
    }

    private fun getOrCreateDeviceId(): String {
        val existing = prefs.getString(KEY_DEVICE_ID, null)
        if (existing != null) return existing
        val newId = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_DEVICE_ID, newId).apply()
        return newId
    }

    companion object {
        private const val KEY_DEVICE_ID = "device_id"
    }
}
