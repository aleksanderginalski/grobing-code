package com.grobing.app

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * "Gdzie jestem" on the cemetery's map (ISSUE-029, ADR-017): the phone's position from the GNSS satellites
 * alone — `LocationManager.GPS_PROVIDER`, no Wi-Fi or cell lookup, no Google services, no new dependency —
 * and only while the app listens (the event channel's listen/cancel). Nothing leaves the phone, and **no
 * position is ever written to the log**: in real use it is where the family lies (NFR-005).
 *
 * Permissions as Android 12+ wants them: FINE and COARSE in one request, the user choosing "Dokładna" or
 * "Przybliżona". After a refusal without a rationale to show, the system will not ask again (Android 11+) —
 * "blocked", and the app's settings are the way back.
 */
class HereLocation(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val locations = activity.getSystemService(Activity.LOCATION_SERVICE) as LocationManager
    private var pending: MethodChannel.Result? = null
    private var sink: EventChannel.EventSink? = null

    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            val fix = HashMap<String, Any>()
            fix["lat"] = location.latitude
            fix["lon"] = location.longitude
            if (location.hasAccuracy()) fix["accuracy"] = location.accuracy.toDouble()
            sink?.success(fix)
        }

        override fun onProviderEnabled(provider: String) {
            sink?.success(mapOf("on" to true))
        }

        override fun onProviderDisabled(provider: String) {
            sink?.success(mapOf("on" to false))
        }

        // Called before Android 10; deprecated and without meaning since.
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "access" -> result.success(access())
                "request" -> request(result)
                "enabled" -> result.success(enabled())
                "openAppSettings" -> {
                    start(
                        Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", activity.packageName, null),
                        ),
                    )
                    result.success(null)
                }
                "openLocationSettings" -> {
                    start(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENTS).setStreamHandler(this)
    }

    private fun granted(permission: String) =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun access(): String = when {
        granted(Manifest.permission.ACCESS_FINE_LOCATION) -> "precise"
        granted(Manifest.permission.ACCESS_COARSE_LOCATION) -> "approximate"
        else -> "denied"
    }

    private fun request(result: MethodChannel.Result) {
        if (access() != "denied") {
            result.success(access())
            return
        }
        if (pending != null) {
            result.error("busy", "A request is already open", null)
            return
        }
        pending = result
        activity.requestPermissions(
            arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ),
            REQUEST_CODE,
        )
    }

    /** From [MainActivity.onRequestPermissionsResult]; true when it was this request. */
    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        pending = null
        val now = access()
        val blocked = now == "denied" &&
            !activity.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_FINE_LOCATION)
        result.success(if (blocked) "blocked" else now)
        return true
    }

    private fun enabled(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        locations.isLocationEnabled
    } else {
        locations.isProviderEnabled(LocationManager.GPS_PROVIDER)
    }

    private fun start(intent: Intent) {
        try {
            activity.startActivity(intent)
        } catch (e: Exception) {
            // No settings screen to open: the app's message stays.
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION)) {
            events.error("no_permission", "Precise location is not granted", null)
            return
        }
        try {
            locations.requestLocationUpdates(
                LocationManager.GPS_PROVIDER,
                INTERVAL_MS,
                0f,
                listener,
                Looper.getMainLooper(),
            )
        } catch (e: SecurityException) {
            events.error("no_permission", e.javaClass.simpleName, null)
        } catch (e: IllegalArgumentException) {
            // A phone without GNSS.
            events.error("no_gps", e.javaClass.simpleName, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        locations.removeUpdates(listener)
        sink = null
    }

    companion object {
        const val CHANNEL = "grobing/location"
        const val EVENTS = "grobing/location/fixes"
        private const val REQUEST_CODE = 4029
        private const val INTERVAL_MS = 1000L
    }
}
