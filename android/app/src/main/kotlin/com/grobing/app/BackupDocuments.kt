package com.grobing.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors

/**
 * The backup's only way off the phone (ADR-004 pkt 1): files the user picks in the system
 * "save as" and "open" windows (Storage Access Framework), with a persisted permission to the backup
 * file only. No API keys, no OAuth, no INTERNET permission — the cloud app behind the window (Google
 * Drive) uploads and downloads.
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

    /** The one system window that may be open, and the request code it answers to. */
    private var pending: Pair<Int, MethodChannel.Result>? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(call.argument<String>("name")!!, result)
            "openDocument" -> openDocument(result)
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
            "documentInfo" -> withUri(call, result) { uri -> documentInfo(uri) }
            "writeFile" -> writeFile(
                Uri.parse(call.argument<String>("uri")!!),
                File(call.argument<String>("path")!!),
                result,
            )
            "readFile" -> readFile(
                Uri.parse(call.argument<String>("uri")!!),
                File(call.argument<String>("path")!!),
                call.argument<Number>("maxBytes")!!.toLong(),
                result,
            )
            // The app's private storage, where restore stages its files (ISSUE-009, D2).
            "freeSpace" -> result.success(StatFs(context.filesDir.path).availableBytes)
            else -> result.notImplemented()
        }
    }

    private fun createDocument(name: String, result: MethodChannel.Result) {
        startWindow(result, REQUEST_CREATE, Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        })
    }

    /**
     * The "open" window. Android returns the document with a persistable read grant, plus write when
     * the provider supports it (Intent.ACTION_OPEN_DOCUMENT); [documentInfo] tells which.
     */
    private fun openDocument(result: MethodChannel.Result) {
        startWindow(result, REQUEST_OPEN, Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // age files have no registered type; Drive may label them either way.
            type = "*/*"
        })
    }

    private fun startWindow(result: MethodChannel.Result, requestCode: Int, intent: Intent) {
        if (pending != null) {
            result.error("busy", "A system window is already open", null)
            return
        }
        pending = requestCode to result
        startForResult(intent, requestCode)
    }

    /** Called from [MainActivity.onActivityResult]; true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CREATE && requestCode != REQUEST_OPEN) return false
        val (expected, result) = pending ?: return true
        if (expected != requestCode) return true
        pending = null
        val uri = data?.data
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null)
        return true
    }

    /**
     * Size, or null when the provider does not know it (remote files may not), the name the window
     * showed, and whether the
     * provider lets the app write the document — FLAG_SUPPORTS_WRITE, not DocumentFile.canWrite(),
     * which is also true for deletable files (Android: "Access documents and other files").
     */
    private fun documentInfo(uri: Uri): Map<String, Any?> {
        var size: Long? = null
        var name: String? = null
        var flags = 0
        val isDocument = DocumentsContract.isDocumentUri(context, uri)
        val projection = if (isDocument) {
            arrayOf(
                OpenableColumns.SIZE,
                OpenableColumns.DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_FLAGS,
            )
        } else {
            arrayOf(OpenableColumns.SIZE, OpenableColumns.DISPLAY_NAME)
        }
        context.contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                if (!cursor.isNull(0)) size = cursor.getLong(0)
                if (!cursor.isNull(1)) name = cursor.getString(1)
                if (isDocument && !cursor.isNull(2)) flags = cursor.getInt(2)
            }
        }
        return mapOf(
            "size" to size,
            "name" to name,
            "writable" to (flags and DocumentsContract.Document.FLAG_SUPPORTS_WRITE != 0),
        )
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
            post(result, error)
        }
    }

    /**
     * Copies [uri] to [target], stopping at [maxBytes]: the provider may not know the size, so the
     * budget is enforced while reading (ISSUE-009, D2). A partial target is deleted.
     */
    private fun readFile(uri: Uri, target: File, maxBytes: Long, result: MethodChannel.Result) {
        io.execute {
            val error: Pair<String, String>? = try {
                val input = context.contentResolver.openInputStream(uri)
                    ?: throw IOException("No input stream")
                var copied = 0L
                input.use { source ->
                    target.outputStream().use { out ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val n = source.read(buffer)
                            if (n < 0) break
                            copied += n
                            if (copied > maxBytes) throw TooLargeException()
                            out.write(buffer, 0, n)
                        }
                        out.fd.sync()
                    }
                }
                null
            } catch (e: TooLargeException) {
                "too_large" to e.javaClass.simpleName
            } catch (e: FileNotFoundException) {
                "not_found" to e.javaClass.simpleName
            } catch (e: SecurityException) {
                "no_access" to e.javaClass.simpleName
            } catch (e: Exception) {
                "read_failed" to e.javaClass.simpleName
            }
            if (error != null) target.delete()
            post(result, error)
        }
    }

    private fun post(result: MethodChannel.Result, error: Pair<String, String>?) {
        main.post {
            if (error == null) result.success(null) else result.error(error.first, error.second, null)
        }
    }

    private fun withUri(call: MethodCall, result: MethodChannel.Result, action: (Uri) -> Any?) {
        try {
            result.success(action(Uri.parse(call.argument<String>("uri")!!)))
        } catch (e: SecurityException) {
            result.error("no_access", e.javaClass.simpleName, null)
        } catch (e: IllegalArgumentException) {
            result.error("not_found", e.javaClass.simpleName, null)
        }
    }

    private class TooLargeException : IOException()

    companion object {
        const val CHANNEL = "com.grobing.app/documents"
        private const val REQUEST_CREATE = 4801
        private const val REQUEST_OPEN = 4802
        private const val READ_WRITE =
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
    }
}
