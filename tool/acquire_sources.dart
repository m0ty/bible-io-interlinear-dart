import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:crypto/crypto.dart';

/// Explicit developer operation; never invoked by package imports or tests.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('output', defaultsTo: '.work/sources')
    ..addOption('lock', defaultsTo: 'tool/sources.lock.json')
    ..addFlag('verify-only', negatable: false)
    ..addFlag('overwrite', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);
  try {
    final options = parser.parse(arguments);
    if (options.flag('help')) {
      stdout.writeln('Acquire or verify the exact pinned STEPBible inputs.');
      stdout.writeln('dart run tool/acquire_sources.dart [options]');
      stdout.writeln(parser.usage);
      return;
    }
    if (options.rest.isNotEmpty) {
      throw const FormatException('Unexpected positional arguments.');
    }
    final decoded = jsonDecode(
      await File(options.option('lock')!).readAsString(),
    );
    if (decoded is! Map<String, dynamic> || decoded['lockVersion'] != 1) {
      throw const FormatException('Expected a version 1 source lock.');
    }
    final revision = decoded['revision'];
    if (revision is! String || !RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
      throw const FormatException('Expected a pinned 40-character revision.');
    }
    if (decoded['repository'] !=
        'https://github.com/STEPBible/STEPBible-Data') {
      throw const FormatException('Unexpected source repository.');
    }
    final sourceFiles = decoded['files'];
    if (sourceFiles is! List || sourceFiles.isEmpty) {
      throw const FormatException('No files in source lock.');
    }
    final entries = sourceFiles.map(_SourceEntry.fromJson).toList();
    if (entries.map((entry) => entry.localPath.toLowerCase()).toSet().length !=
        entries.length) {
      throw const FormatException('Duplicate local paths in source lock.');
    }
    final output = Directory(options.option('output')!).absolute;
    final verifyOnly = options.flag('verify-only');
    if (!verifyOnly) await output.create(recursive: true);
    final client = verifyOnly ? null : HttpClient();
    try {
      for (final entry in entries) {
        final target = File.fromUri(output.uri.resolve(entry.localPath));
        final entityType = await FileSystemEntity.type(
          target.path,
          followLinks: false,
        );
        if (entityType != FileSystemEntityType.notFound &&
            entityType != FileSystemEntityType.file) {
          throw FileSystemException('Refusing non-file target', target.path);
        }
        if (entityType == FileSystemEntityType.file) {
          if (await entry.matches(target)) {
            stdout.writeln('Verified ${entry.localPath}');
            continue;
          }
          if (verifyOnly || !options.flag('overwrite')) {
            throw FileSystemException(
              'Existing file does not match lock; use --overwrite to replace',
              target.path,
            );
          }
        } else if (verifyOnly) {
          throw FileSystemException(
              'Pinned source is unavailable', target.path);
        }
        final temporary = await output.createTemp('.acquire-');
        try {
          final uri = Uri(
            scheme: 'https',
            host: 'raw.githubusercontent.com',
            pathSegments: [
              'STEPBible',
              'STEPBible-Data',
              revision,
              ...entry.path.split('/'),
            ],
          );
          stdout.writeln('Downloading ${entry.localPath}');
          final request = await client!.getUrl(uri);
          request.followRedirects = false;
          final response = await request.close();
          if (response.statusCode != HttpStatus.ok) {
            await response.drain<void>();
            throw HttpException('HTTP ${response.statusCode}', uri: uri);
          }
          final downloaded = File.fromUri(temporary.uri.resolve('source'));
          await response.pipe(downloaded.openWrite());
          if (!await entry.matches(downloaded)) {
            throw FileSystemException(
              'Downloaded bytes do not match pinned size/SHA-256',
              entry.localPath,
            );
          }
          // Existing mismatches are replaced only after a validated download.
          if (await target.exists()) await target.delete();
          await downloaded.rename(target.path);
          stdout.writeln('Verified ${entry.localPath}');
        } finally {
          await temporary.delete(recursive: true);
        }
      }
    } finally {
      client?.close(force: true);
    }
  } on Object catch (error) {
    stderr.writeln('Source acquisition failed: $error');
    exitCode = 1;
  }
}

final class _SourceEntry {
  const _SourceEntry(this.path, this.localPath, this.bytes, this.digest);

  factory _SourceEntry.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid source entry.');
    }
    final path = value['path'];
    final localPath = value['localPath'];
    final bytes = value['bytes'];
    final digest = value['sha256'];
    if (path is! String ||
        !_safeRelativePath(path) ||
        localPath is! String ||
        !_safeRelativePath(localPath) ||
        localPath.contains('/') ||
        bytes is! int ||
        bytes < 0 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid source path, size, or SHA-256.');
    }
    return _SourceEntry(path, localPath, bytes, digest);
  }

  final String path;
  final String localPath;
  final int bytes;
  final String digest;

  Future<bool> matches(File file) async =>
      await file.length() == bytes &&
      (await sha256.bind(file.openRead()).first).toString() == digest;

  static bool _safeRelativePath(String value) =>
      value.isNotEmpty &&
      !RegExp(r'[\\:%?#<>"|*\x00-\x1f\x7f]').hasMatch(value) &&
      value.split('/').every(
            (part) =>
                part.isNotEmpty &&
                part != '.' &&
                part != '..' &&
                !part.endsWith('.') &&
                !part.endsWith(' ') &&
                !RegExp(
                  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',
                  caseSensitive: false,
                ).hasMatch(part),
          );
}
