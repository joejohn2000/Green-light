package com.example.green_light_mobile

import android.content.Intent
import android.bluetooth.BluetoothManager
import android.content.Context
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private lateinit var connectionsClient: ConnectionsClient
    private val strategy = Strategy.P2P_POINT_TO_POINT
    private val connectedEndpoints = linkedSetOf<String>()
    private val endpointNames = mutableMapOf<String, String>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var displayName = "Green Light"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        connectionsClient = Nearby.getConnectionsClient(this)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result -> handleMethod(call, result) }
    }

    override fun onDestroy() {
        stopNearby()
        super.onDestroy()
    }

    private fun handleMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val name = call.argument<String>("displayName") ?: "Green Light"
                val idSuffix = call.argument<String>("idSuffix") ?: ""
                displayName = endpointDisplayName(name, idSuffix)
                startNearby()
                result.success(true)
            }
            "stop" -> {
                stopNearby()
                result.success(true)
            }
            "sendConsentRequest" -> {
                val sender = call.argument<String>("displayName") ?: displayName
                val agreementId = call.argument<String>("agreementId") ?: ""
                result.success(
                    sendJson(
                        JSONObject()
                            .put("type", "consent_request")
                            .put("requesterName", sender)
                            .put("agreementId", agreementId)
                    )
                )
            }
            "sendDecision" -> {
                val accepted = call.argument<Boolean>("accepted") ?: false
                result.success(
                    sendJson(
                        JSONObject()
                            .put("type", "consent_decision")
                            .put("accepted", accepted)
                    )
                )
            }
            "sendSignatureState" -> {
                val state = call.argument<String>("state") ?: ""
                val signerName = call.argument<String>("signerName") ?: displayName
                result.success(
                    sendJson(
                        JSONObject()
                            .put("type", "signature_state")
                            .put("state", state)
                            .put("signerName", signerName)
                            .put("timestamp", System.currentTimeMillis())
                    )
                )
            }
            "openBluetoothSettings" -> {
                openSettings(Settings.ACTION_BLUETOOTH_SETTINGS)
                result.success(true)
            }
            "openLocationSettings" -> {
                openSettings(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                result.success(true)
            }
            "openWifiSettings" -> {
                openSettings(Settings.ACTION_WIFI_SETTINGS)
                result.success(true)
            }
            "phoneSettingsStatus" -> {
                result.success(phoneSettingsStatus())
            }
            "androidSdkVersion" -> {
                result.success(Build.VERSION.SDK_INT)
            }
            else -> result.notImplemented()
        }
    }

    private fun startNearby() {
        stopNearby()
        startAdvertising()
        mainHandler.postDelayed({ startDiscovery() }, 750)
    }

    private fun stopNearby() {
        if (::connectionsClient.isInitialized) {
            connectionsClient.stopAdvertising()
            connectionsClient.stopDiscovery()
            connectionsClient.stopAllEndpoints()
        }
        connectedEndpoints.clear()
        endpointNames.clear()
    }

    private fun startAdvertising() {
        val options = AdvertisingOptions.Builder().setStrategy(strategy).build()
        connectionsClient
            .startAdvertising(displayName, SERVICE_ID, connectionLifecycleCallback, options)
            .addOnSuccessListener { sendStatus("Nearby ready. Waiting for users.") }
            .addOnFailureListener { sendStatus(nearbyFailureMessage("start sharing", it)) }
    }

    private fun startDiscovery() {
        val options = DiscoveryOptions.Builder().setStrategy(strategy).build()
        connectionsClient
            .startDiscovery(SERVICE_ID, endpointDiscoveryCallback, options)
            .addOnSuccessListener { sendStatus("Scanning nearby devices") }
            .addOnFailureListener { sendStatus(nearbyFailureMessage("scan for users", it)) }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            endpointNames[endpointId] = info.endpointName
            sendNearbyDevice("nearbyDeviceFound", endpointId, info.endpointName)
            sendStatus("Found nearby user ${info.endpointName}")

            // Avoid both phones initiating at once. Both discover each other, but only
            // the lexicographically lower display name starts the connection.
            if (displayName <= info.endpointName) {
                connectionsClient
                    .requestConnection(displayName, endpointId, connectionLifecycleCallback)
                    .addOnFailureListener {
                        sendStatus(nearbyFailureMessage("connect to ${info.endpointName}", it))
                    }
            }
        }

        override fun onEndpointLost(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            val name = endpointNames.remove(endpointId) ?: "Nearby user"
            sendNearbyDevice("nearbyDeviceLost", endpointId, name)
            sendStatus("Nearby user moved away")
        }
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            endpointNames[endpointId] = info.endpointName
            sendNearbyDevice("nearbyDeviceFound", endpointId, info.endpointName)
            sendStatus("Connecting to ${info.endpointName}")
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.statusCode == ConnectionsStatusCodes.STATUS_OK) {
                connectedEndpoints.add(endpointId)
                val name = endpointNames[endpointId] ?: "Nearby user"
                sendNearbyDevice("nearbyDeviceConnected", endpointId, name)
                sendStatus("Nearby user connected")
            } else {
                connectedEndpoints.remove(endpointId)
                val name = endpointNames[endpointId] ?: "Nearby user"
                sendNearbyDevice("nearbyDeviceLost", endpointId, name)
                sendStatus("Nearby connection failed")
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            val name = endpointNames.remove(endpointId) ?: "Nearby user"
            sendNearbyDevice("nearbyDeviceLost", endpointId, name)
            sendStatus("Nearby user disconnected")
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            val bytes = payload.asBytes() ?: return
            val data = JSONObject(String(bytes, Charsets.UTF_8))
            when (data.optString("type")) {
                "consent_request" -> sendEvent(
                    "incomingConsentRequest",
                    mapOf(
                        "requesterName" to data.optString("requesterName", "Nearby user"),
                        "agreementId" to data.optString("agreementId", "")
                    )
                )
                "consent_decision" -> sendEvent(
                    "consentDecision",
                    mapOf("accepted" to data.optBoolean("accepted", false))
                )
                "signature_state" -> sendEvent(
                    "signatureState",
                    mapOf(
                        "state" to data.optString("state", ""),
                        "signerName" to data.optString("signerName", "Nearby user"),
                        "timestamp" to data.optLong("timestamp", 0L)
                    )
                )
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) = Unit
    }

    private fun sendJson(data: JSONObject): Boolean {
        if (connectedEndpoints.isEmpty()) return false
        val payload = Payload.fromBytes(data.toString().toByteArray(Charsets.UTF_8))
        connectedEndpoints.forEach { endpointId ->
            connectionsClient.sendPayload(endpointId, payload)
        }
        return true
    }

    private fun sendStatus(message: String) {
        sendEvent("nearbyStatus", mapOf("message" to message))
    }

    private fun sendNearbyDevice(method: String, endpointId: String, endpointName: String) {
        sendEvent(
            method,
            mapOf(
                "endpointId" to endpointId,
                "endpointName" to endpointName
            )
        )
    }

    private fun openSettings(action: String) {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun phoneSettingsStatus(): Map<String, Boolean> {
        return mapOf(
            "bluetoothEnabled" to isBluetoothEnabled(),
            "locationEnabled" to isLocationEnabled(),
            "wifiEnabled" to isWifiEnabled()
        )
    }

    private fun isBluetoothEnabled(): Boolean {
        return try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            manager.adapter?.isEnabled == true
        } catch (_: Exception) {
            false
        }
    }

    private fun isLocationEnabled(): Boolean {
        return try {
            val manager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.isLocationEnabled
            } else {
                manager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                    manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isWifiEnabled(): Boolean {
        return try {
            val manager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            manager.isWifiEnabled
        } catch (_: Exception) {
            false
        }
    }

    private fun nearbyFailureMessage(action: String, throwable: Exception): String {
        val code = (throwable as? ApiException)?.statusCode
        return when (code) {
            8007 -> "SETUP_ISSUE: Nearby is already running. Reopen the app and try again."
            8032 -> "SETUP_ISSUE: Nearby scanning could not start on this phone. Restart Bluetooth and Location, then search again."
            else -> "Nearby could not $action${if (code != null) " ($code)" else ""}. Check Bluetooth and Location are on."
        }
    }

    private fun endpointDisplayName(name: String, idSuffix: String): String {
        val cleanName = name
            .replace(Regex("[^A-Za-z0-9 ._-]"), "")
            .trim()
            .ifBlank { "GreenLight" }
            .take(20)
        val cleanSuffix = idSuffix
            .replace(Regex("[^A-Za-z0-9]"), "")
            .takeLast(4)
        val deviceSuffix = Settings.Secure
            .getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?.replace(Regex("[^A-Za-z0-9]"), "")
            ?.takeLast(4)
            .orEmpty()
        val suffix = cleanSuffix.ifBlank { deviceSuffix }
        return if (suffix.isBlank()) cleanName else "$cleanName-$suffix"
    }

    private fun sendEvent(method: String, arguments: Map<String, Any>) {
        runOnUiThread {
            if (::channel.isInitialized) {
                channel.invokeMethod(method, arguments)
            }
        }
    }

    companion object {
        private const val CHANNEL = "green_light/nearby"
        private const val SERVICE_ID = "com.greenlight.localconsent"
    }
}
