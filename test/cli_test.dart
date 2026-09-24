import 'dart:convert';
import 'dart:io';

import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory output;
  final fixture = File('test/fixtures/stepbible/tagnt.txt').absolute.path;

  Future<ProcessResult> convert({
    List<String> extra = const [],
    String? input,
  }) =>
      Process.run(Platform.resolvedExecutable, [
        'run',
        'bin/convert_stepbible.dart',
        '--source-type',
        'tagnt',
        '--profile',
        'N',
        '--dataset-id',
        'cli-test',
        '--dataset-revision',
        '1',
        '--input',
        input ?? fixture,
        '--output',
        output.path,
        ...extra,
      ]);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('interlinear-cli-test-');
    output = Directory.fromUri(temporary.uri.resolve('dataset'));
  });
  tearDown(() => temporary.delete(recursive: true));

  test('CLI converts authentic data that loads through the runtime', () async {
    final report = File.fromUri(temporary.uri.resolve('reports/result.json'));
    final result = await convert(extra: ['--report', report.path]);
    expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
    final data = JsonInterlinearDataSource(
      reader: (path) => File('${output.path}/$path').readAsBytes(),
    );
    final bible = await InterlinearBible.open(data);
    final acts = bibleBookFromUsfmIdentifier('ACT');
    final chapter = await bible.loadChapter(acts, 4);
    expect(chapter.getVerse(25).tokens.first.surface, 'ὁ');
    final decoded = jsonDecode(await report.readAsString()) as Map;
    expect(decoded['valid'], true);
    expect(File('${output.path}/import-report.json').existsSync(), true);
  });

  test('invalid input fails without publishing a partial dataset', () async {
    final invalid = File.fromUri(temporary.uri.resolve('malformed.txt'));
    await invalid.writeAsString(
      '${await File(fixture).readAsString()}\nAct.4.26#01=NKO\tbroken\n',
    );
    final report = File.fromUri(temporary.uri.resolve('failure.json'));
    final result =
        await convert(input: invalid.path, extra: ['--report', report.path]);
    expect(result.exitCode, isNot(0));
    expect(output.existsSync(), false);
    expect((jsonDecode(await report.readAsString()) as Map)['valid'], false);
  });

  test('existing output is protected; explicit overwrite retains prior data',
      () async {
    final first = await convert();
    expect(first.exitCode, 0, reason: first.stderr.toString());
    final original = await File('${output.path}/manifest.json').readAsBytes();
    final refused = await convert();
    expect(refused.exitCode, isNot(0));
    expect(await File('${output.path}/manifest.json').readAsBytes(), original);
    final replaced = await convert(extra: ['--overwrite']);
    expect(replaced.exitCode, 0, reason: replaced.stderr.toString());
    final backups = temporary.listSync().whereType<Directory>().where(
          (directory) => directory.path.contains('dataset.previous-'),
        );
    expect(backups, hasLength(1));
    expect(await File('${backups.single.path}/manifest.json').readAsBytes(),
        original);
  });

  test('report cannot overwrite the prepared manifest or an input', () async {
    final collision =
        await convert(extra: ['--report', '${output.path}/manifest.json']);
    expect(collision.exitCode, isNot(0));
    expect(collision.stderr, contains('outside the output dataset'));
    expect(output.existsSync(), false);

    final original = await File(fixture).readAsBytes();
    final sourceCollision =
        await convert(extra: ['--diagnostic', '--report', fixture]);
    expect(sourceCollision.exitCode, isNot(0));
    expect(sourceCollision.stderr, contains('must not replace a source input'));
    expect(await File(fixture).readAsBytes(), original);
  });

  test('diagnostic mode writes a report without publishing a dataset',
      () async {
    final report = File.fromUri(temporary.uri.resolve('diagnostic.json'));
    final result =
        await convert(extra: ['--diagnostic', '--report', report.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(output.existsSync(), false);
    expect((jsonDecode(await report.readAsString()) as Map)['valid'], true);
  });
}
