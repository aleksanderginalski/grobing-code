package com.grobing.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * One operation on the data at a time, across Flutter engines (ISSUE-010, D3): the background backup,
 * "Zrób kopię teraz", the backup setup and a restore. A flag in Dart does not cross engines, and a
 * Dart file lock is an fcntl lock — per process, so it would not exclude two engines of one process.
 * WorkManager runs the worker in the app's process, so a process-wide object is enough; the lock dies
 * with the process.
 */
object DataLock {
    private var holder: Any? = null

    @Synchronized
    fun tryAcquire(owner: Any): Boolean {
        if (holder != null) return false
        holder = owner
        return true
    }

    @Synchronized
    fun release(owner: Any) {
        if (holder === owner) holder = null
    }
}

/**
 * The background channel of one Flutter engine: the data lock, the request for a background backup and
 * — in the worker's engine only — the end of the run. The lock is held per channel, so an engine that
 * goes away holding it can be released by its owner ([releaseLock]).
 */
class BackgroundChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val onFinished: ((Finished) -> Unit)? = null,
) : MethodChannel.MethodCallHandler {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "tryLock" -> result.success(DataLock.tryAcquire(this))
            "unlock" -> {
                DataLock.release(this)
                result.success(null)
            }
            "request" -> io.execute {
                val error = try {
                    BackupWorker.request(context)
                    null
                } catch (e: Exception) {
                    e.javaClass.simpleName
                }
                main.post {
                    if (error == null) result.success(null) else result.error("request_failed", error, null)
                }
            }
            "finished" -> {
                val finished = onFinished
                if (finished == null) {
                    result.notImplemented()
                } else {
                    finished(
                        Finished(
                            call.argument<String>("outcome")!!,
                            call.argument<Number>("waitMs")!!.toLong(),
                        ),
                    )
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun releaseLock() = DataLock.release(this)

    /** How the Dart run ended, and for "later" how long to wait. */
    data class Finished(val outcome: String, val waitMs: Long)

    companion object {
        const val CHANNEL = "com.grobing.app/background"
    }
}

/**
 * The background backup (ISSUE-010, D1): WorkManager runs this worker [QUIET_MS] after a change of the
 * data (D2); it starts a headless Flutter engine with the documents channel (no windows) and runs the
 * Dart function [ENTRYPOINT] with the time of the first unsaved change. Dart decides — wait for the
 * data to go quiet, back up, or nothing — and reports how it ended.
 *
 * Never opens `grobing.db` itself: a second copy of SQLite in the process would not see the Dart
 * side's locks (https://www.sqlite.org/howtocorrupt.html, 2.3).
 */
class BackupWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val outcome = CompletableDeferred<BackgroundChannel.Finished>()
        val firstChangeAt = inputData.getLong(KEY_FIRST_CHANGE, System.currentTimeMillis())
        var engine: FlutterEngine? = null
        var channel: BackgroundChannel? = null
        try {
            withContext(Dispatchers.Main) {
                val started = FlutterEngine(applicationContext)
                engine = started
                val messenger = started.dartExecutor.binaryMessenger
                BackupDocuments(applicationContext, messenger, startForResult = null)
                channel = BackgroundChannel(applicationContext, messenger) { outcome.complete(it) }
                started.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                        ENTRYPOINT,
                    ),
                    listOf(firstChangeAt.toString()),
                )
            }
            val finished = withTimeoutOrNull(TIMEOUT_MS) { outcome.await() }
            return when (finished?.outcome) {
                OUTCOME_DONE -> Result.success()
                OUTCOME_LATER -> {
                    // Still changing: once more when it has been quiet, same first change (D2).
                    request(applicationContext, firstChangeAt, finished.waitMs)
                    Result.success()
                }
                OUTCOME_AGAIN -> {
                    // Data changed while the backup ran: one more, after this one (D2 iii).
                    request(applicationContext)
                    Result.success()
                }
                // A failure, the lock held elsewhere, or no answer in time (D2 iv).
                else -> if (runAttemptCount + 1 >= MAX_ATTEMPTS) Result.failure() else Result.retry()
            }
        } finally {
            withContext(NonCancellable + Dispatchers.Main) {
                channel?.releaseLock()
                engine?.destroy()
            }
        }
    }

    companion object {
        /** In `lib/main.dart`, kept in release builds by `@pragma('vm:entry-point')`. */
        const val ENTRYPOINT = "backgroundBackupMain"

        private const val WORK_NAME = "grobing-backup"
        private const val KEY_FIRST_CHANGE = "first_change_at"
        private const val OUTCOME_DONE = "done"
        private const val OUTCOME_AGAIN = "again"
        private const val OUTCOME_LATER = "later"

        /**
         * From a change to the first look, and the quiet the data needs before the backup runs — one
         * backup per session of work (D2). Equal to `backupQuiet` in `lib/backup/background.dart`.
         */
        private val QUIET_MS = TimeUnit.MINUTES.toMillis(10)

        /** Retries after a failure before the next trigger (leaving or starting the app) tries again. */
        private const val MAX_ATTEMPTS = 4

        /** Below WorkManager's ~10 minutes, so the run ends here rather than being stopped mid-write. */
        private val TIMEOUT_MS = TimeUnit.MINUTES.toMillis(9)

        private val requestLock = Any()

        /**
         * Asks for a background backup (D2): nothing when one is already waiting — it will cover this
         * change too; never cancels one that runs (a cancelled "wt" write would leave a cut file in
         * Drive), but queues one after it. [firstChangeAt] travels with the request so that a long,
         * unbroken session still gets its backup (`backupCap` in Dart).
         */
        fun request(
            context: Context,
            firstChangeAt: Long = System.currentTimeMillis(),
            delayMs: Long = QUIET_MS,
        ) = synchronized(requestLock) {
            val work = WorkManager.getInstance(context)
            val waiting = work.getWorkInfosForUniqueWork(WORK_NAME).get().any {
                it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED
            }
            if (!waiting) {
                work.enqueueUniqueWork(
                    WORK_NAME,
                    ExistingWorkPolicy.APPEND_OR_REPLACE,
                    OneTimeWorkRequestBuilder<BackupWorker>()
                        .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                        .setInputData(workDataOf(KEY_FIRST_CHANGE to firstChangeAt))
                        // No network constraint: the app has none; the Drive app uploads.
                        .setConstraints(Constraints.Builder().setRequiresStorageNotLow(true).build())
                        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES)
                        .build(),
                )
            }
        }
    }
}
