import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late File lock;
  final payload = utf8.encode('Synthetic acquisition fixture.\n');

  Future<void> writeLock({String localPath = 'source.txt'}) async {
    await lock.writeAsString(
      jsonEncode({
        'lockVersion': 1,
        'repository': 'https://github.com/STEPBible/STEPBible-Data',
        'revision': 'b99716b0cddb648ddb95cc786a197180f2f97d48',
        'files': [
          {
            'path': 'synthetic/source.txt',
            'localPath': localPath,
            'bytes': payload.length,
            'sha256': sha256.convert(payload).toString(),
          },
        ],
      }),
    );
  }

  Future<ProcessResult> verify() => Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/acquire_sources.dart',
        '--verify-only',
        '--lock',
        lock.path,
        '--output',
        temporary.path,
      ]);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('source-lock-test-');
    lock = File.fromUri(temporary.uri.resolve('lock.json'));
    await writeLock();
  });

  tearDown(() => temporary.delete(recursive: true));

  test('offline source verification accepts exact locked bytes', () async {
    await File.fromUri(
      temporary.uri.resolve('source.txt'),
    ).writeAsBytes(payload);
    final result = await verify();
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, contains('Verified source.txt'));
  });

  test('offline source verification rejects modified bytes', () async {
    final changed = [...payload]..[0] = payload[0] + 1;
    await File.fromUri(
      temporary.uri.resolve('source.txt'),
    ).writeAsBytes(changed);
    final result = await verify();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('does not match lock'));
  });

  test('offline source verification rejects unavailable files', () async {
    final result = await verify();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Pinned source is unavailable'));
  });

  test('acquisition rejects a traversing lock path before file access',
      () async {
    await writeLock(localPath: '../outside.txt');
    final result = await verify();
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Invalid source path'));
  });
}
