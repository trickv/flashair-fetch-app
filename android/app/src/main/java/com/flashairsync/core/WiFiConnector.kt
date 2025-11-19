package com.flashairsync.core

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

/**
 * Handles WiFi network connection to FlashAir card
 * Uses WifiNetworkSpecifier for Android 10+ (API 29+)
 */
@RequiresApi(Build.VERSION_CODES.Q)
class WiFiConnector(private val context: Context) {

    companion object {
        private const val TAG = "WiFiConnector"
        private const val CONNECTION_TIMEOUT_MS = 30_000L // 30 seconds
    }

    private val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var currentNetwork: Network? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // MARK: - Public API

    /**
     * Connect to FlashAir WiFi network
     * @param ssid Network SSID (e.g., "flashair")
     * @param passphrase WPA2 passphrase
     * @return Network object if successful
     * @throws FlashAirError.WiFiConnectionFailed if connection fails
     */
    suspend fun connect(ssid: String, passphrase: String): Network {
        Log.d(TAG, "Attempting to connect to SSID: $ssid")

        // Check if already connected
        currentNetwork?.let { network ->
            if (isNetworkAvailable(network)) {
                Log.d(TAG, "Already connected to network")
                return network
            }
        }

        // Build network specifier
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(passphrase)
            .build()

        val networkRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) // FlashAir has no internet
            .setNetworkSpecifier(specifier)
            .build()

        // Request network connection
        return withTimeoutOrNull(CONNECTION_TIMEOUT_MS) {
            suspendCoroutine { continuation ->
                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        Log.d(TAG, "Network available: $network")
                        currentNetwork = network

                        // Bind process to this network
                        connectivityManager.bindProcessToNetwork(network)

                        continuation.resume(network)
                    }

                    override fun onUnavailable() {
                        Log.w(TAG, "Network unavailable")
                        continuation.resumeWithException(FlashAirError.WiFiConnectionFailed)
                    }

                    override fun onLost(network: Network) {
                        Log.w(TAG, "Network lost: $network")
                        if (currentNetwork == network) {
                            currentNetwork = null
                        }
                    }

                    override fun onCapabilitiesChanged(
                        network: Network,
                        networkCapabilities: NetworkCapabilities
                    ) {
                        Log.d(TAG, "Network capabilities changed: $networkCapabilities")
                    }
                }

                networkCallback = callback
                connectivityManager.requestNetwork(networkRequest, callback)
            }
        } ?: throw FlashAirError.WiFiConnectionFailed
    }

    /**
     * Disconnect from current WiFi network
     */
    fun disconnect() {
        Log.d(TAG, "Disconnecting from WiFi")

        // Unbind process from network
        connectivityManager.bindProcessToNetwork(null)

        // Unregister callback
        networkCallback?.let { callback ->
            try {
                connectivityManager.unregisterNetworkCallback(callback)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to unregister network callback: ${e.message}")
            }
            networkCallback = null
        }

        currentNetwork = null
    }

    /**
     * Check if currently connected to a network
     */
    fun isConnected(): Boolean {
        return currentNetwork?.let { isNetworkAvailable(it) } ?: false
    }

    /**
     * Get current network
     */
    fun getCurrentNetwork(): Network? = currentNetwork

    // MARK: - Private Helpers

    /**
     * Check if a network is still available
     */
    private fun isNetworkAvailable(network: Network): Boolean {
        return try {
            val capabilities = connectivityManager.getNetworkCapabilities(network)
            capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        } catch (e: Exception) {
            false
        }
    }
}

/**
 * Result of WiFi connection state
 */
sealed class WiFiConnectionState {
    object Disconnected : WiFiConnectionState()
    object Connecting : WiFiConnectionState()
    data class Connected(val network: Network) : WiFiConnectionState()
    data class Failed(val error: String) : WiFiConnectionState()
}
