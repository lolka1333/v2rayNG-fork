package com.v2ray.ang.service

import android.content.Context
import android.content.pm.PackageManager
import android.os.ParcelFileDescriptor
import android.util.Log
import com.v2ray.ang.AppConfig
import com.v2ray.ang.contracts.Tun2SocksControl
import com.v2ray.ang.handler.MmkvManager
import com.v2ray.ang.handler.SettingsManager
import com.v2ray.ang.handler.SocksAuthManager
import java.io.File

/**
 * Manages the tun2socks process that handles VPN traffic
 */
class TProxyService(
    private val context: Context,
    private val vpnInterface: ParcelFileDescriptor,
    private val isRunningProvider: () -> Boolean,
    private val restartCallback: () -> Unit
) : Tun2SocksControl {
    companion object {
        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyStartService(configPath: String, fd: Int)
        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyStopService()
        @JvmStatic
        @Suppress("FunctionName")
        private external fun TProxyGetStats(): LongArray?

        init {
            System.loadLibrary("hev-socks5-tunnel")
        }
    }

    /**
     * Starts the tun2socks process with the appropriate parameters.
     */
    override fun startTun2Socks() {
//        Log.i(AppConfig.TAG, "Starting HevSocks5Tunnel via JNI")

        val configContent = buildConfig()
        val configFile = File(context.filesDir, "hev-socks5-tunnel.yaml").apply {
            writeText(configContent)
        }
//        Log.i(AppConfig.TAG, "Config file created: ${configFile.absolutePath}")
        Log.d(AppConfig.TAG, "HevSocks5Tunnel Config content:\n$configContent")

        try {
//            Log.i(AppConfig.TAG, "TProxyStartService...")
            TProxyStartService(configFile.absolutePath, vpnInterface.fd)
        } catch (e: Exception) {
            Log.e(AppConfig.TAG, "HevSocks5Tunnel exception: ${e.message}")
        }
    }

    private fun buildConfig(): String {
        val socksPort = SettingsManager.getSocksPort()
        val vpnConfig = SettingsManager.getCurrentVpnInterfaceAddressConfig()
        return buildString {
            appendLine("tunnel:")
            appendLine("  mtu: ${SettingsManager.getVpnMtu()}")
            appendLine("  ipv4: ${vpnConfig.ipv4Client}")

            if (MmkvManager.decodeSettingsBool(AppConfig.PREF_PREFER_IPV6)) {
                appendLine("  ipv6: '${vpnConfig.ipv6Client}'")
            }

            appendLine("socks5:")
            appendLine("  port: ${socksPort}")
            appendLine("  address: ${AppConfig.LOOPBACK}")
            appendLine("  udp: 'udp'")
            appendLine("  username: '${SocksAuthManager.username}'")
            appendLine("  password: '${SocksAuthManager.password}'")

            // Read-write timeout settings
            val timeoutSetting = MmkvManager.decodeSettingsString(AppConfig.PREF_HEV_TUNNEL_RW_TIMEOUT) ?: AppConfig.HEVTUN_RW_TIMEOUT
            val parts = timeoutSetting.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() }
            val tcpTimeout = parts.getOrNull(0)?.toIntOrNull() ?: 300
            val udpTimeout = parts.getOrNull(1)?.toIntOrNull() ?: 60

            appendLine("misc:")
            appendLine("  tcp-read-write-timeout: ${tcpTimeout * 1000}")
            appendLine("  udp-read-write-timeout: ${udpTimeout * 1000}")
            appendLine("  log-level: ${MmkvManager.decodeSettingsString(AppConfig.PREF_HEV_TUNNEL_LOGLEVEL) ?: "warn"}")

            // UID-based blocking inside hev-socks5-tunnel, derived from the existing
            // per-app proxy app list — no separate UI needed.
            //
            // uid-rules are generated whenever PREF_PER_APP_PROXY_SET is non-empty,
            // regardless of whether the per-app proxy toggle is on or off:
            //
            //  • Per-app proxy OFF  → ALL apps go through tun0.  uid-rules block
            //    the listed apps inside the tunnel (they get RST, no internet via VPN).
            //    This is the primary test/use scenario for this feature.
            //
            //  • Per-app proxy ON, bypass mode → listed apps also get
            //    addDisallowedApplication() so they bypass tun0 entirely.  uid-rules
            //    serve as defense-in-depth for the brief window at VPN startup before
            //    bypass routing rules are applied by the kernel.
            //
            //  • Per-app proxy ON, proxy mode → listed apps are the only ones allowed
            //    through tun0, so uid-rules: block for them would immediately RST their
            //    connections — skip this combination to avoid breaking proxy mode.
            val bypassMode = MmkvManager.decodeSettingsBool(AppConfig.PREF_BYPASS_APPS)
            val proxyModeActive = MmkvManager.decodeSettingsBool(AppConfig.PREF_PER_APP_PROXY) && !bypassMode
            if (!proxyModeActive) {
                val packages = MmkvManager.decodeSettingsStringSet(AppConfig.PREF_PER_APP_PROXY_SET)
                if (!packages.isNullOrEmpty()) {
                    val pm = context.packageManager
                    val uids = packages.mapNotNull { pkg ->
                        try { pm.getApplicationInfo(pkg, 0).uid }
                        catch (_: PackageManager.NameNotFoundException) { null }
                    }.toSortedSet()          // deduplicate (shared-UID apps)

                    if (uids.isNotEmpty()) {
                        appendLine("uid-rules:")
                        for (uid in uids) {
                            appendLine("  - uid: $uid")
                            appendLine("    action: block")
                        }
                    }
                }
            }
        }
    }

    /**
     * Stops the tun2socks process
     */
    override fun stopTun2Socks() {
        try {
            Log.i(AppConfig.TAG, "TProxyStopService...")
            TProxyStopService()
        } catch (e: Exception) {
            Log.e(AppConfig.TAG, "Failed to stop hev-socks5-tunnel", e)
        }
    }
}
