package com.grobing.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors

/**
 * The backup's only way off the phone (ADR-004 pkt 1): files the user picks in the system
 * "save as" window (Storage Access Framework), with a persisted permission to that one file. No API
 * keys, no OAuth, no INTERNET permission — the cloud app behind the window (Google Drive) uploads.
 *
 * Writing needs only a [Context], not an Activity, so a background backup can reuse it (ISSUE-010).
 * Errors carry a code and the exception type only, never a path or file content.
 */
class BackupDocuments(
    private val context: Context,
    messenger: BinaryMessenger,
    private val startForResult: (Intent, Int) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingCreate: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(call.argument<String>("name")!!, result)
            "keepAccess" -> withUri(call, result) { uri ->
                context.contentResolver.takePersistableUriPermission(uri, READ_WRITE)
                null
            }
            "releaseAccess" -> withUri(call, result) { uri ->
                context.contentResolver.releasePersistableUriPermission(uri, READ_WRITE)
                null
            }
            "hasAccess" -> withUri(call, result) { uri ->
                context.contentResolver.persistedUriPermissions.any {
                    it.uri == uri && it.isReadPermission && it.isWritePermission
                }
            }
            "writeFile" -> writeFile(
                Uri.parse(call.argument<String>("uri")!!),
                File(call.argument<String>("path")!!),
                result,
            )
            else -> result.notImplemented()
        }
    }

    private fun createDocument(name: String, result: MethodChannel.Result) {
        if (pendingCreate != null) {
            result.error("busy", "A save window is already open", null)
            return
        }
        pendingCreate = result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        startForResult(intent, REQUEST_CREATE)
    }

    /** Called from [MainActivity.onActivityResult]; true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CREATE) return false
        val result = pendingCreate ?: return true
        pendingCreate = null
        val uri = data?.data
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null)
        return true
    }

    /** Mode "wt": truncate, then write — a shorter backup never leaves the tail of a longer one. */
    private fun writeFile(uri: Uri, source: File, result: MethodChannel.Result) {
        io.execute {
            val error: Pair<String, String>? = try {
                val output = context.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("No output stream")
                output.use { out -> source.inputStream().use { it.copyTo(out, 64 * 1024) } }
                null
            } catch (e: FileNotFoundException) {
                "not_found" to e.javaClass.simpleName
            } catch (e: SecurityException) {
                "no_access" to e.javaClass.simpleName
            } catch (e: Exception) {
                "write_failed" to e.javaClass.simpleName
            }
            main.post {
                if (error == null) result.success(null) else result.error(error.first, error.second, null)
            }
        }
    }

    private fun withUri(call: MethodCall, result: MethodChannel.Result, action: (Uri) -> Any?) {
        try {
            result.success(action(Uri.parse(call.argument<String>("uri")!!)))
        } catch (e: SecurityException) {
            result.error("no_access", e.javaClass.simpleName, null)
        }
    }

    companion object {
        const val CHANNEL = "com.grobing.app/documents"
        private const val REQUEST_CREATE = 4801
        private const val READ_WRITE =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }
}
