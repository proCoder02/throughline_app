package com.nodexdata.speechtotext

import android.net.Uri
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

private const val TAG = "TL_CallConnService"

/**
 * Registered as a self-managed android.telecom.ConnectionService (see the
 * PhoneAccount registration in MainActivity.kt) -- this is what lets an
 * incoming call show the OS's native ringing UI instantly, independent of
 * whether the Flutter engine has booted yet. Each incoming_call push
 * (see MyFirebaseMessagingReceiver) calls
 * TelecomManager.addNewIncomingCall(), which the OS turns into a call to
 * onCreateIncomingConnection() here.
 */
class CallConnectionService : ConnectionService() {

    companion object {
        // Keyed by our own call_id (the backend's integer call id, as a
        // String) so call_ended (see MyFirebaseMessagingReceiver) can look
        // up and end the right native Connection.
        val activeConnections = mutableMapOf<String, CallConnection>()

        // Set by MainActivity once its engine is up; survives across any
        // number of onNewIntent calls for as long as that engine lives.
        // Shared here (rather than a MainActivity-only field) so
        // MyFirebaseMessagingReceiver can reach it too -- see
        // handleIncomingCall(), which needs to tell Dart a call started
        // ringing natively even though the Flutter engine may just be
        // backgrounded, not gone.
        var methodChannel: MethodChannel? = null
    }

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        Log.d(TAG, "onCreateIncomingConnection: extras=${request?.extras}")
        val extras = request?.extras
        val callId = extras?.getString("call_id") ?: ""
        val callerName = extras?.getString("caller_name") ?: "Unknown"

        val connection = CallConnection(applicationContext, callId, extras)
        connection.setConnectionProperties(Connection.PROPERTY_SELF_MANAGED)
        connection.setAudioModeIsVoip(true)
        connection.setCallerDisplayName(callerName, TelecomManager.PRESENTATION_ALLOWED)
        connection.setAddress(Uri.fromParts("tel", callId, null), TelecomManager.PRESENTATION_ALLOWED)
        connection.setRinging()

        if (callId.isNotEmpty()) {
            activeConnections[callId] = connection
            // Telecom reaching RINGING does not guarantee any visible UI --
            // some OEM dialers never render third-party self-managed calls
            // (confirmed on ColorOS via adb/logcat). Post our own ringing
            // screen so this doesn't depend on the OEM dialer at all.
            CallNotificationHelper.show(
                applicationContext, callId, callerName,
                extras?.getString("caller_id"), extras?.getString("room_name")
            )
        }
        Log.d(TAG, "onCreateIncomingConnection: created connection for callId=$callId")
        return connection
    }

    override fun onCreateIncomingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ) {
        Log.e(TAG, "onCreateIncomingConnectionFailed: extras=${request?.extras}")
        super.onCreateIncomingConnectionFailed(connectionManagerPhoneAccount, request)
    }
}
