import 'package:flutter/services.dart';

/// Shown when another operation on the data holds the [DataLock] — in practice the background backup,
/// since the screens run one operation at a time.
const String dataBusyMessage = 'Trwa kopia w tle — spróbuj za chwilę.';

/// One operation on the data at a time, across Flutter engines (ISSUE-010, D3): the background backup,
/// "Zrób kopię teraz", the backup setup and a restore. The app's engine and the background backup's
/// engine share no Dart memory, and a Dart file lock is an fcntl lock, which is per process — so the
/// lock lives on the native side (`DataLock` in `BackgroundBackup.kt`).
abstract interface class DataLock {
  /// False when another operation, in this engine or another one, holds the lock.
  Future<bool> tryAcquire();

  Future<void> release();
}

/// How long the data must stay unchanged before the background backup runs, so that one session of
/// work makes one backup (ISSUE-010, D2) — also the delay of every request (`BackgroundBackup.kt`).
const Duration backupQuiet = Duration(minutes: 10);

/// The longest a change waits for that quiet: a long, unbroken session still gets a backup this long
/// after its first unsaved change.
const Duration backupCap = Duration(minutes: 60);

/// Asks Android for a background backup (ISSUE-010, D2).
abstract interface class BackgroundBackups {
  /// A backup some minutes from now, unless one is already waiting — it will cover this change too.
  /// One that runs is never cancelled; this one then follows it.
  Future<void> request();
}

/// How a background run ended, for the worker (`BackupWorker.kt`).
enum BackgroundOutcome {
  /// Nothing to do, or the backup succeeded.
  done,

  /// The backup succeeded, but the data changed while it ran: one more is needed (D2 iii).
  again,

  /// The backup failed or the lock was taken: WorkManager tries again later (D2 iv).
  retry,

  /// The data is still changing: run again once it has been quiet for [backupQuiet] (D2).
  later,
}

/// How a background run ended, and for [BackgroundOutcome.later] how long to wait.
typedef BackgroundRun = ({BackgroundOutcome outcome, Duration wait});

/// [DataLock] and [BackgroundBackups] over the native channel in `BackgroundBackup.kt`.
class PlatformBackground implements DataLock, BackgroundBackups {
  const PlatformBackground();

  static const MethodChannel _channel = MethodChannel(
    'com.grobing.app/background',
  );

  @override
  Future<bool> tryAcquire() async =>
      await _channel.invokeMethod<bool>('tryLock') ?? false;

  @override
  Future<void> release() => _channel.invokeMethod<void>('unlock');

  @override
  Future<void> request() => _channel.invokeMethod<void>('request');

  /// The last call of a background run: the worker ends with its outcome and destroys the engine.
  Future<void> finished(BackgroundRun run) => _channel.invokeMethod<void>(
    'finished',
    {'outcome': run.outcome.name, 'waitMs': run.wait.inMilliseconds},
  );
}
