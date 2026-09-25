import 'package:bible_io/bible_io.dart';
import 'package:bible_io_interlinear/bible_io_interlinear.dart';
import 'package:test/test.dart';

InterlinearMetadata metadata({
  bool hebrew = false,
  String? source,
  String? revision,
  String? profile,
  String? readingPolicy,
  String referenceSystem = 'STEPBible-NRSV',
}) =>
    InterlinearMetadata(
      datasetId: 'test-conversion',
      datasetRevision: '0.1.0',
      source: source ?? (hebrew ? 'STEPBible TAHOT' : 'STEPBible TAGNT'),
      sourceRevision:
          revision ?? InterlinearWordAnalyzer.stepBibleSourceRevision,
      profile: profile ?? (hebrew ? 'L+Q+R' : 'N'),
      readingPolicy: readingPolicy ?? (hebrew ? 'qere' : null),
      referenceSystem: referenceSystem,
      originalLanguages: [hebrew ? 'hbo' : 'grc'],
      glossLanguages: ['en'],
      coverage: {
        hebrew ? BibleBookEnum.genesis : BibleBookEnum.matthew: [1]
      },
    );

InterlinearToken greek({
  String gloss = '[11] Cretans',
  String lemma = 'ἰός (2)',
  String dictionaryGloss = 'to_step_out',
  List<LexicalReference> references = const [],
}) =>
    InterlinearToken(
      occurrenceId: 'TAGNT:test',
      surface: 'ἰός',
      language: 'grc',
      glosses: {'en': gloss, 'es': '[11] raw Spanish'},
      segments: [
        InterlinearSegment(
          text: 'ἰός',
          kind: 'whole-word',
          lemma: lemma,
          glosses: {'en': dictionaryGloss},
          lexicalReferences: references,
        ),
      ],
    );

String render(InterlinearGloss gloss) => gloss.render(
      (function, standalone) => '${standalone ? '' : '['}${function.name}'
          '${standalone ? '' : ']'}',
    );

void main() {
  test('only the audited source revision and reading profile enable rules', () {
    final raw = greek();
    for (final data in [
      null,
      metadata(source: 'Another Greek provider'),
      metadata(revision: 'a-new-source-revision'),
      metadata(profile: 'K'),
      metadata(readingPolicy: 'other-reading'),
      metadata(referenceSystem: 'another-reference-system'),
    ]) {
      final result = InterlinearWordAnalyzer(metadata: data).analyze(raw);
      expect(result.source, InterlinearAnalysisSource.unknown);
      expect(render(result.contextualGlosses['en']!), '[11] Cretans');
      expect(result.parts.single.dictionaryEntries, isEmpty);
      expect(result.parts.single.contextualGlosses, isEmpty);
      expect(result.parts.single.grammaticalFunction, isNull);
      expect(result.raw, same(raw));
      expect(result.parts.single.raw, same(raw.segments.single));
      expect(result.parts.single.raw.lemma, 'ἰός (2)');
    }
    final known = InterlinearWordAnalyzer(metadata: metadata()).analyze(raw);
    expect(known.source, InterlinearAnalysisSource.stepBibleTagnt);
    expect(render(known.contextualGlosses['en']!), 'Cretans');
    expect(known.contextualGlosses['en']!.rawText, '[11] Cretans');
    expect(known.contextualGlosses['es']!.rawText, '[11] raw Spanish');
    final entry = known.parts.single.dictionaryEntries.single;
    expect(entry.form, 'ἰός');
    expect(entry.rawForm, 'ἰός (2)');
    expect(entry.glosses, {'en': 'to step out'});
    expect(entry.rawGlosses, {'en': 'to_step_out'});
    expect(entry.annotations.map((item) => item.kind), [
      InterlinearSourceAnnotationKind.homonymNumber,
      InterlinearSourceAnnotationKind.dictionaryFormatting,
    ]);
  });

  test('ordinary source notation, unknown prefixes and accents survive', () {
    final analyzer = InterlinearWordAnalyzer(metadata: metadata());
    for (final text in [
      '[The] book',
      '[him]',
      '[to the] only',
      '<the>',
      '<from/before>',
      '12 tribes',
      '(2) people',
      '[2] people',
      '{2} people',
      'meaning [14]',
      '[14]letters without a boundary',
      '[14]',
    ]) {
      expect(
          render(analyzer.analyze(greek(gloss: text)).contextualGlosses['en']!),
          text);
    }
    for (final form in ['ἰός', 'ἰός (3)', 'unknown (2)', 'ὅς, ἥ']) {
      expect(
          analyzer
              .analyze(greek(lemma: form))
              .parts
              .single
              .dictionaryEntries
              .single
              .form,
          form);
    }
  });

  test('combined Greek entries retain each form, meaning and lexical reference',
      () {
    final refs = [
      LexicalReference(system: 'STEPBible-dStrongs', value: 'G3361'),
      LexicalReference(system: 'STEPBible-dStrongs', value: 'G5100'),
    ];
    final raw = greek(
        lemma: 'μή + τις', dictionaryGloss: 'not + one', references: refs);
    final result = InterlinearWordAnalyzer(metadata: metadata()).analyze(raw);
    final entries = result.parts.single.dictionaryEntries;
    expect(entries.map((entry) => entry.form), ['μή', 'τις']);
    expect(entries.map((entry) => entry.glosses['en']), ['not', 'one']);
    expect(entries[0].lexicalReferences, [refs[0]]);
    expect(entries[1].lexicalReferences, [refs[1]]);
    expect(result.parts.single.contextualGlosses, isEmpty);
    expect(raw.segments.single.lemma, 'μή + τις');
    expect(() => entries.clear(), throwsUnsupportedError);
    expect(() => entries.first.glosses.clear(), throwsUnsupportedError);
    expect(() => result.contextualGlosses.clear(), throwsUnsupportedError);
  });

  test('unmatched combined forms stay raw instead of inventing pairings', () {
    final raw =
        greek(lemma: 'μή + τις', dictionaryGloss: 'one unsplit meaning');
    final result = InterlinearWordAnalyzer(metadata: metadata()).analyze(raw);
    expect(result.parts.single.dictionaryEntries, isEmpty);
    expect(result.parts.single.annotations.single.kind,
        InterlinearSourceAnnotationKind.unpairedDictionaryAnalysis);
    expect(result.parts.single.raw.glosses['en'], 'one unsplit meaning');
  });

  test(
      'Hebrew contextual pieces, lexical phrases and source forms stay distinct',
      () {
    final code = InterlinearSegment(
      text: 'הּ',
      lemma: 'Os3f',
      glosses: {'en': 'her'},
      morphology: [MorphologyTag(scheme: 'STEPBible-TAHOT', code: 'Sp3fs')],
    );
    final phrase = InterlinearSegment(
      text: 'כִּי',
      lemma: 'כִּי [אם]',
      glosses: {'en': 'but'},
    );
    final raw = InterlinearToken(
      occurrenceId: 'TAHOT:test',
      surface: 'כִּי',
      language: 'hbo',
      glosses: {'en': 'but/ her'},
      segments: [phrase, code],
    );
    final result =
        InterlinearWordAnalyzer(metadata: metadata(hebrew: true)).analyze(raw);
    expect(result.parts[0].dictionaryEntries.single.isPhrase, isTrue);
    expect(result.parts[0].dictionaryEntries.single.form, 'כִּי [אם]');
    expect(result.parts[0].dictionaryEntries.single.glosses, isEmpty);
    expect(render(result.parts[0].contextualGlosses['en']!), 'but');
    expect(result.parts[1].sourceFormCode, 'Os3f');
    expect(result.parts[1].dictionaryEntries, isEmpty);
    expect(render(result.parts[1].contextualGlosses['en']!), 'her');
    expect(code.lemma, 'Os3f');
  });

  test('function markers are typed and localized by the caller', () {
    final question = InterlinearSegment(text: 'ה', glosses: {
      'en': '?'
    }, lexicalReferences: [
      LexicalReference(system: 'STEPBible-dStrongs', value: 'H9008')
    ]);
    final object = InterlinearSegment(text: 'אֵת', glosses: {'en': '<obj.>'});
    final raw = InterlinearToken(
      occurrenceId: 'TAHOT:test',
      surface: 'אֵת',
      language: 'hbo',
      glosses: {'en': 'and/ <obj.>/ ?'},
      segments: [object, question],
    );
    final result =
        InterlinearWordAnalyzer(metadata: metadata(hebrew: true)).analyze(raw);
    expect(result.parts[0].grammaticalFunction,
        InterlinearGrammaticalFunction.directObjectMarker);
    expect(result.parts[1].grammaticalFunction,
        InterlinearGrammaticalFunction.questionMarker);
    expect(render(result.contextualGlosses['en']!),
        'and/ [directObjectMarker]/ [questionMarker]');
    expect(result.parts[0].contextualGlosses['en']!.isFunctionOnly, isTrue);
    expect(result.contextualGlosses['en']!.rawText, 'and/ <obj.>/ ?');
    final unknown = const InterlinearWordAnalyzer().analyze(raw);
    expect(render(unknown.contextualGlosses['en']!), 'and/ <obj.>/ ?');
    expect(unknown.parts.every((part) => part.grammaticalFunction == null),
        isTrue);
  });

  test('punctuation and empty separators are not word parts; nulls remain safe',
      () {
    final blank = InterlinearSegment(text: ' ');
    final punctuation = InterlinearSegment(text: '־', kind: 'punctuation');
    final analysisOnly = InterlinearSegment(
        morphology: [MorphologyTag(scheme: 'custom', code: 'uninterpreted')]);
    final raw = InterlinearToken(
        occurrenceId: 'empty',
        surface: 'x',
        language: 'grc',
        segments: [blank, punctuation, analysisOnly]);
    final result = InterlinearWordAnalyzer(metadata: metadata()).analyze(raw);
    expect(result.contextualGlosses, isEmpty);
    expect(result.segments, hasLength(3));
    expect(result.parts.single.raw, same(analysisOnly));
    expect(result.parts.single.dictionaryEntries, isEmpty);
    expect(raw.segments, hasLength(3));
  });
}
