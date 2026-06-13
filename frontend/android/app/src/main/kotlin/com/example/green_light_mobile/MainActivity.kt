package com.example.green_light_mobile

import android.content.Intent
import android.os.Build
import android.provider.Settings
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
    private val strategy = Strategy.P2P_CLUSTER
    private val connectedEndpoints = linkedSetOf<String>()
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
                displayName = call.argument<String>("displayName") ?: "Green Light"
                startNearby()
                result.success(true)
            }
            "stop" -> {
                stopNearby()
                result.success(true)
            }
            "sendConsentRequest" -> {
                val sender = call.argument<String>("displayName") ?: displayName
                result.success(
                    sendJson(
                        JSONObject()
                            .put("type", "consent_request")
                            .put("requesterName", sender)
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
            "androidSdkVersion" -> {
                result.success(Build.VERSION.SDK_INT)
            }
            else -> result.notImplemented()
        }
    }

    private fun startNearby() {
        stopNearby()
        startAdvertising()
        startDiscovery()
    }

    private fun stopNearby() {
        if (::connectionsClient.isInitialized) {
            connectionsClient.stopAdvertising()
            connectionsClient.stopDiscovery()
            connectionsClient.stopAllEndpoints()
        }
        connectedEndpoints.clear()
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
            sendStatus("Found nearby user ${info.endpointName}")
            connectionsClient
                .requestConnection(displayName, endpointId, connectionLifecycleCallback)
                .addOnFailureListener {
                    sendStatus(nearbyFailureMessage("connect to ${info.endpointName}", it))
                }
        }

        override fun onEndpointLost(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            sendStatus("Nearby user moved away")
        }
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            sendStatus("Connecting to ${info.endpointName}")
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.statusCode == ConnectionsStatusCodes.STATUS_OK) {
                connectedEndpoints.add(endpointId)
                sendStatus("Nearby user connected")
            } else {
                connectedEndpoints.remove(endpointId)
                sendStatus("Nearby connection failed")
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
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
                    mapOf("requesterName" to data.optString("requesterName", "Nearby user"))
                )
                "consent_decision" -> sendEvent(
                    "consentDecision",
                    mapOf("accepted" to data.optBoolean("accepted", false))
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

    private fun openSettings(action: String) {
        startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun nearbyFailureMessage(action: String, throwable: Exception): String {
        val code = (throwable as? ApiException)?.statusCode
        val reason = when (code) {
            8007 -> "Nearby is already running. Reopen the app and try again."
            8010 -> "The nearby connection timed out."
            8011 -> "This phone rejected the nearby connection."
            8012 -> "The nearby connection was interrupted."
            8013 -> "This phone is already connected to that user."
            8032 -> "Nearby scanning could not start on this phone."
            else -> "Nearby could not $action."
        }
        return "$reason Turn on Bluetooth, Wi-Fi, and Location, keep both phones unlocked with Green Light open, then try again."
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
