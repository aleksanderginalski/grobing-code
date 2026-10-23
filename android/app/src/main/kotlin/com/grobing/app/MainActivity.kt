package com.grobing.app

import android.content.Intent
import android.util.Log
import android.view.View
import android.view.ViewGroup
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
        ExternalLinks(messenger, applicationContext) { intent -> startActivity(intent) }
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

    // A turn ("Obróć" on the tree, ISSUE-055): the app drawn at the portrait size inside a landscape window and the other
    // way round, until something resized the window — every time on the emulator (Android 16). `dumpsys activity top`:
    // FlutterView 1080×2400, its FlutterSurfaceView 2400×1080. The engine of Flutter 3.41.1 asks, at the start of every
    // frame, to size the surface to that frame (external_view_embedder.cc → FlutterJNI.maybeResizeSurfaceView →
    // FlutterView.resizeEngineView): a frame of the old size arriving after the turn pins the surface's layout to the
    // old size in pixels and makes the view drop the next size change (shouldSendViewportMetrics), so Flutter never
    // hears the new one. Flutter is pinned (ADR-002), so here: when the surface does not fill the view after a layout
    // change of either, the surface fills it again and the insets are applied anew, which sends the view's size to
    // Flutter (FlutterView.onApplyWindowInsets → sendViewportMetricsToFlutter).
    private var surfaceWatch: View.OnLayoutChangeListener? = null

    override fun onStart() {
        super.onStart()
        if (surfaceWatch != null) return
        val flutterView = findViewById<ViewGroup>(FlutterActivity.FLUTTER_VIEW_ID) ?: return
        val watch = View.OnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            flutterView.post { refitSurface(flutterView) }
        }
        flutterView.addOnLayoutChangeListener(watch)
        for (i in 0 until flutterView.childCount) flutterView.getChildAt(i).addOnLayoutChangeListener(watch)
        surfaceWatch = watch
    }

    private fun refitSurface(flutterView: ViewGroup) {
        for (i in 0 until flutterView.childCount) {
            val surface = flutterView.getChildAt(i)
            if (surface.width == flutterView.width && surface.height == flutterView.height) continue
            Log.i(
                "GROBING_SURFACE",
                "${surface.width}x${surface.height} in ${flutterView.width}x${flutterView.height}: refitted",
            )
            val params = surface.layoutParams
            params.width = ViewGroup.LayoutParams.MATCH_PARENT
            params.height = ViewGroup.LayoutParams.MATCH_PARENT
            surface.layoutParams = params
            flutterView.requestApplyInsets()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documents?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}
