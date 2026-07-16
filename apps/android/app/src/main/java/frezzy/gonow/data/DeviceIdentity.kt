package frezzy.gonow.data

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import frezzy.gonow.models.DevicePayload
import java.util.UUID

class DeviceIdentity(context: Context) {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs: SharedPreferences = EncryptedSharedPreferences.create(
        context,
        "gonow_device",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

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
