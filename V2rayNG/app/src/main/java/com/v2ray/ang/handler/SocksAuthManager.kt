package com.v2ray.ang.handler

import com.v2ray.ang.AppConfig
import java.util.UUID

/**
 * Manages persistent SOCKS5 inbound credentials.
 * Credentials are generated once and stored in MMKV so the user
 * can copy them into Telegram or any other app that needs the local proxy.
 * Call loadOrGenerate() before starting the VPN service.
 */
object SocksAuthManager {

    val username: String
        get() = MmkvManager.decodeSettingsString(AppConfig.PREF_SOCKS5_USERNAME).orEmpty()

    val password: String
        get() = MmkvManager.decodeSettingsString(AppConfig.PREF_SOCKS5_PASSWORD).orEmpty()

    /**
     * Load credentials from MMKV. If not yet generated, create and persist them.
     */
    fun loadOrGenerate() {
        if (username.isEmpty() || password.isEmpty()) {
            regenerate()
        }
    }

    /**
     * Generate new credentials and save to MMKV.
     * Call this when the user explicitly requests regeneration.
     */
    fun regenerate() {
        MmkvManager.encodeSettings(AppConfig.PREF_SOCKS5_USERNAME, randomToken())
        MmkvManager.encodeSettings(AppConfig.PREF_SOCKS5_PASSWORD, randomToken())
    }

    /** Clear credentials (e.g. on VPN stop — optional, credentials are persistent by design). */
    fun clear() {
        MmkvManager.encodeSettings(AppConfig.PREF_SOCKS5_USERNAME, "")
        MmkvManager.encodeSettings(AppConfig.PREF_SOCKS5_PASSWORD, "")
    }

    private fun randomToken(): String =
        UUID.randomUUID().toString().replace("-", "").substring(0, 16)
}
