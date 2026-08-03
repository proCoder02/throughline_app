package com.nodexdata.speechtotext

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * A second, native-owned copy of the bearer token + API base URL, kept in
 * sync from Dart (see push_service.dart's cacheTokenForNative/
 * clearTokenForNative, called from api_client.dart on save/clear) whenever
 * they change. Exists purely so CallConnection.onReject() can call
 * POST /calls/<id>/decline directly from native code without needing a
 * Flutter engine running at all -- flutter_secure_storage's own on-disk
 * format is a plugin-internal, versioned custom cipher scheme (see that
 * plugin's StorageCipherFactory), not something safe for separate native
 * code to read directly. This store owns its own encryption end to end
 * instead, via the stable public EncryptedSharedPreferences API.
 */
object NativeAuthStore {
    private const val PREFS_NAME = "native_auth_store"
    private const val KEY_TOKEN = "token"
    private const val KEY_BASE_URL = "base_url"

    private fun prefs(context: Context) = EncryptedSharedPreferences.create(
        context.applicationContext,
        PREFS_NAME,
        MasterKey.Builder(context.applicationContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveToken(context: Context, token: String, baseUrl: String) {
        prefs(context).edit().putString(KEY_TOKEN, token).putString(KEY_BASE_URL, baseUrl).apply()
    }

    fun clearToken(context: Context) {
        prefs(context).edit().clear().apply()
    }

    /**
     * Fire-and-forget POST /calls/<id>/decline on a background thread.
     * Best-effort: if this fails for any reason (no cached token yet, no
     * network, backend unreachable), the backend's own 45s ring-timeout
     * worker still ends the call and notifies the caller -- just later
     * instead of instantly.
     */
    fun declineCall(context: Context, callId: String) {
        Thread {
            try {
                val p = prefs(context)
                val token = p.getString(KEY_TOKEN, null) ?: return@Thread
                val baseUrl = p.getString(KEY_BASE_URL, null) ?: return@Thread
                val url = URL("$baseUrl/calls/$callId/decline")
                val connection = url.openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "POST"
                    connection.setRequestProperty("Authorization", "Bearer $token")
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.doOutput = true
                    connection.connectTimeout = 10_000
                    connection.readTimeout = 10_000
                    OutputStreamWriter(connection.outputStream).use { it.write("{}") }
                    connection.responseCode // forces the request to actually execute
                } finally {
                    connection.disconnect()
                }
            } catch (e: Exception) {
                // Best-effort -- see doc comment above.
            }
        }.start()
    }
}
