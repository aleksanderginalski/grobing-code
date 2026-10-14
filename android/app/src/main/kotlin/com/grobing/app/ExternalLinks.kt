package com.grobing.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Opens a web address in another app — Google Maps when installed, a browser otherwise (ISSUE-015 D1,
 * D2). Only after a tap: the app has no INTERNET permission, the other app loads the page. Android 11+
 * needs no `<queries>` entry for [start] itself; an address no app takes ends in
 * [ActivityNotFoundException], answered with `false`. The same way, the system's cast screen (ISSUE-036).
 */
class ExternalLinks(messenger: BinaryMessenger, private val start: (Intent) -> Unit) {
    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> result.success(open(call.argument<String>("url")))
                "openCastSettings" -> result.success(openCastSettings())
                else -> result.notImplemented()
            }
        }
    }

    private fun open(url: String?): Boolean {
        if (url == null || !url.startsWith("https://")) return false
        return try {
            start(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    /**
     * The system's screen for casting the phone's screen to a TV (ISSUE-036, drzewo.md D29) — the one public
     * door: the system sends the picture, not the app, and the app gets no word whether it does. Its own
     * docs say a phone may have no such screen (`Settings.ACTION_CAST_SETTINGS`), so `false` then.
     */
    private fun openCastSettings(): Boolean = try {
        start(Intent(Settings.ACTION_CAST_SETTINGS))
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    companion object {
        const val CHANNEL = "grobing/external"
    }
}
