package com.grobing.app

import android.content.Context
import android.os.Build
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.TimeUnit

/**
 * The cemeteries' plans with the app closed (ISSUE-052 B1; 05_DESIGN/cmentarz.md D40): WorkManager runs
 * this worker once the phone has a network; it starts a headless Flutter engine and runs the Dart
 * function [ENTRYPOINT], which downloads the missing plans one after another, as the app does, and
 * reports how it ended. The same pattern as [BackupWorker], whose channel it shares.
 *
 * Never opens `grobing.db` itself, for the backup's reason: a second copy of SQLite in the process would
 * not see the Dart side's locks.
 */
class PlanWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // Started by WorkManager's in-process scheduler, not by the system: such a run holds no job of
        // the system, so Android freezes the cached process about 10 s later and the run stalls until the
        // app is opened — measured on the emulator (ISSUE-052): after a kill the app's next start
        // rescheduled the work ("force-stopped"), the system's job ended, and the in-process scheduler ran
        // it. The system's start hands over the network it checked; the in-process one has none. Back to
        // the system, which runs it with the next wait.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && network == null) {
            return Result.retry()
        }
        val outcome = CompletableDeferred<BackgroundChannel.Finished>()
        var engine: FlutterEngine? = null
        try {
            withContext(Dispatchers.Main) {
                val started = FlutterEngine(applicationContext)
                engine = started
                BackgroundChannel(applicationContext, started.dartExecutor.binaryMessenger) {
                    outcome.complete(it)
                }
                started.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                        ENTRYPOINT,
                    ),
                )
            }
            val finished = withTimeoutOrNull(TIMEOUT_MS) { outcome.await() }
            return when (finished?.outcome) {
                OUTCOME_DONE -> Result.success()
                OUTCOME_AGAIN -> {
                    // The run stored plans and ran out of time with cemeteries left: the next one at once.
                    request(applicationContext, replace = true)
                    Result.success()
                }
                // The server gave nothing, no network, a failure, or no answer in time: WorkManager's
                // growing waits, until the next leaving of the app asks again.
                else -> if (runAttemptCount + 1 >= MAX_ATTEMPTS) Result.failure() else Result.retry()
            }
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                engine?.destroy()
            }
        }
    }

    companion object {
        /** In `lib/main.dart`, kept in release builds by `@pragma('vm:entry-point')`. */
        const val ENTRYPOINT = "backgroundPlansMain"

        private const val WORK_NAME = "grobing-plans"
        private const val OUTCOME_DONE = "done"
        private const val OUTCOME_AGAIN = "again"

        /**
         * Waits of 5, 10, 20… minutes (WorkManager caps them at 5 hours): about two days of tries, and
         * every leaving of the app with a plan missing starts them again.
         */
        private const val MAX_ATTEMPTS = 14
        private const val FIRST_WAIT_MINUTES = 5L

        /** Below WorkManager's ~10 minutes, as the backup's; the Dart run starts no cemetery after 1 min. */
        private val TIMEOUT_MS = TimeUnit.MINUTES.toMillis(9)

        /**
         * Before a run: asked for at once, the in-process scheduler would start it in the app that is just
         * being left — and Android freezes it (the guard in [doWork]). After this the left app is frozen,
         * so the system starts the run, holding its job: from leaving the app, and between two runs.
         */
        private const val AFTER_LEAVING_S = 60L
        private const val BETWEEN_RUNS_S = 30L

        private val requestLock = Any()

        /**
         * Asks for a run once there is a network: nothing when one already waits or runs — it reads the
         * missing plans again before each cemetery — unless [replace], from a run that is ending.
         */
        fun request(context: Context, replace: Boolean = false) = synchronized(requestLock) {
            val work = WorkManager.getInstance(context)
            val pending = work.getWorkInfosForUniqueWork(WORK_NAME).get().any {
                it.state == WorkInfo.State.ENQUEUED ||
                    it.state == WorkInfo.State.BLOCKED ||
                    it.state == WorkInfo.State.RUNNING
            }
            if (replace || !pending) {
                work.enqueueUniqueWork(
                    WORK_NAME,
                    // From a run that is ending: after it, not instead of it (a cancelled run would stop
                    // a plan mid-write).
                    if (replace) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
                    OneTimeWorkRequestBuilder<PlanWorker>()
                        .setInitialDelay(
                            if (replace) BETWEEN_RUNS_S else AFTER_LEAVING_S,
                            TimeUnit.SECONDS,
                        )
                        .setConstraints(
                            Constraints.Builder()
                                .setRequiredNetworkType(NetworkType.CONNECTED)
                                .build(),
                        )
                        .setBackoffCriteria(
                            BackoffPolicy.EXPONENTIAL,
                            FIRST_WAIT_MINUTES,
                            TimeUnit.MINUTES,
                        )
                        .build(),
                )
            }
        }
    }
}
