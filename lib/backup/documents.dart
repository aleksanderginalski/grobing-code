import 'dart:io';

import 'package:flutter/services.dart';

/// Files the user picks in the system "save as" window (Storage Access Framework). The app keeps a
/// permission to that one file and nothing else — no API keys, no OAuth, no `INTERNET` permission:
/// the cloud app behind the window (Google Drive) does the upload (ADR-004 pkt 1).
abstract interface class DocumentStore {
  /// Opens the "save as" window with [suggestedName]; null when the user cancels.
  Future<String?> createDocument(String suggestedName);

  /// Keeps read and write access to [uri] across restarts.
  Future<void> keepAccess(String uri);

  Future<void> releaseAccess(String uri);

  /// Whether the persisted read and write access to [uri] still exists.
  Future<bool> hasAccess(String uri);

  /// Replaces the content of [uri] with [file] (mode `"wt"`: truncate, then write).
  Future<void> writeFile(String uri, File file);
}

/// [DocumentStore] over the native channel in `BackupDocuments.kt`.
class PlatformDocumentStore implements DocumentStore {
  const PlatformDocumentStore();

  static const MethodChannel _channel = MethodChannel(
    'com.grobing.app/documents',
  );

  @override
  Future<String?> createDocument(String suggestedName) =>
      _channel.invokeMethod<String>('createDocument', {'name': suggestedName});

  @override
  Future<void> keepAccess(String uri) =>
      _channel.invokeMethod<void>('keepAccess', {'uri': uri});

  @override
  Future<void> releaseAccess(String uri) =>
      _channel.invokeMethod<void>('releaseAccess', {'uri': uri});

  @override
  Future<bool> hasAccess(String uri) async =>
      await _channel.invokeMethod<bool>('hasAccess', {'uri': uri}) ?? false;

  @override
  Future<void> writeFile(String uri, File file) =>
      _channel.invokeMethod<void>('writeFile', {'uri': uri, 'path': file.path});
}
