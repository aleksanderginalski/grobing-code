import 'dart:io';

import 'package:flutter/services.dart';

/// What the provider says about a picked document.
class DocumentInfo {
  const DocumentInfo({required this.size, required this.writable, this.name});

  /// Bytes, or null when the provider does not know (remote files may not).
  final int? size;

  /// The name the window showed, for the screen.
  final String? name;

  /// Whether the provider lets the app write the document (`FLAG_SUPPORTS_WRITE`).
  final bool writable;
}

/// Files the user picks in the system "save as" and "open" windows (Storage Access Framework). The
/// app keeps a permission to the backup file and nothing else — no API keys, no OAuth, no `INTERNET`
/// permission: the cloud app behind the window (Google Drive) uploads and downloads (ADR-004 pkt 1).
abstract interface class DocumentStore {
  /// Opens the "save as" window with [suggestedName]; null when the user cancels.
  Future<String?> createDocument(String suggestedName);

  /// Opens the "open" window; null when the user cancels. Read access lasts until the phone
  /// restarts unless [keepAccess] makes it persistent.
  Future<String?> openDocument();

  /// Keeps read and write access to [uri] across restarts. Fails with `no_access` when the provider
  /// granted read only.
  Future<void> keepAccess(String uri);

  Future<void> releaseAccess(String uri);

  /// Whether the persisted read and write access to [uri] still exists.
  Future<bool> hasAccess(String uri);

  Future<DocumentInfo> documentInfo(String uri);

  /// Replaces the content of [uri] with [file] (mode `"wt"`: truncate, then write).
  Future<void> writeFile(String uri, File file);

  /// Copies [uri] into [target]; fails with `too_large` once more than [maxBytes] arrive, and leaves
  /// no partial [target] behind.
  Future<void> readFile(String uri, File target, {required int maxBytes});

  /// Free bytes in the app's private storage, where restore stages its files.
  Future<int> freeSpace();
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
  Future<String?> openDocument() =>
      _channel.invokeMethod<String>('openDocument');

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
  Future<DocumentInfo> documentInfo(String uri) async {
    final Map<Object?, Object?> info = (await _channel
        .invokeMapMethod<Object?, Object?>('documentInfo', {'uri': uri}))!;
    return DocumentInfo(
      size: info['size'] as int?,
      name: info['name'] as String?,
      writable: info['writable']! as bool,
    );
  }

  @override
  Future<void> writeFile(String uri, File file) =>
      _channel.invokeMethod<void>('writeFile', {'uri': uri, 'path': file.path});

  @override
  Future<void> readFile(String uri, File target, {required int maxBytes}) =>
      _channel.invokeMethod<void>('readFile', {
        'uri': uri,
        'path': target.path,
        'maxBytes': maxBytes,
      });

  @override
  Future<int> freeSpace() async =>
      (await _channel.invokeMethod<int>('freeSpace'))!;
}
