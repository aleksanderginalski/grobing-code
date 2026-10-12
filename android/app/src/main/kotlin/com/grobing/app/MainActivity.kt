package com.grobing.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var documents: BackupDocuments? = null
    private var background: BackgroundChannel? = null
    private var here: HereLocation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        documents = BackupDocuments(applicationContext, messenger) { intent, requestCode ->
            startActivityForResult(intent, requestCode)
        }
        background = BackgroundChannel(applicationContext, messenger)
        // From the activity, so "back" in Maps returns to Grobing.
        ExternalLinks(messenger) { intent -> startActivity(intent) }
        // The 2048 px JPEG the app keeps of a picked photo (ISSUE-016, D2').
        PhotoPreparation(messenger)
        // "Gdzie jestem" on the cemetery's map — the satellites alone, only while listened to (ISSUE-029).
        here = HereLocation(this, messenger)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (here?.onRequestPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // An engine destroyed in the middle of a restore or a backup must not keep the data lock.
        background?.releaseLock()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
