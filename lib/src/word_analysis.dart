import 'models.dart';

/// Source contracts understood by [InterlinearWordAnalyzer]. Language alone
/// never selects a contract. Unknown sources retain their uninterpreted values.
enum InterlinearAnalysisSource { unknown, stepBibleTagnt, stepBibleTahot }

enum InterlinearGrammaticalFunction { directObjectMarker, questionMarker }

enum InterlinearSourceAnnotationKind {
  verseReference,
  homonymNumber,
  sourceFormCode,
  dictionaryFormatting,
  sourceCorrection,
  unpairedDictionaryAnalysis,
}

/// An interpretation of source notation, with the complete original field.
final class InterlinearSourceAnnotation {
  const InterlinearSourceAnnotation(this.kind, this.rawValue);
  final InterlinearSourceAnnotationKind kind;
  final String rawValue;
}

/// Text or a source-confirmed grammatical marker within a contextual gloss.
/// A UI supplies localized labels for functions; this package supplies no UI
/// language or replacement translation for them.
final class InterlinearGlossPart {
  const InterlinearGlossPart.text(String value)
      : text = value,
        function = null;
  const InterlinearGlossPart.function(InterlinearGrammaticalFunction value)
      : function = value,
        text = null;
  final String? text;
  final InterlinearGrammaticalFunction? function;
}

final class InterlinearGloss {
  InterlinearGloss({
    required this.rawText,
    required List<InterlinearGlossPart> parts,
    List<InterlinearSourceAnnotation> annotations = const [],
  })  : parts = List.unmodifiable(parts),
        annotations = List.unmodifiable(annotations);

  factory InterlinearGloss.raw(String text) => InterlinearGloss(
        rawText: text,
        parts: [InterlinearGlossPart.text(text)],
      );

  final String rawText;
  final List<InterlinearGlossPart> parts;
  final List<InterlinearSourceAnnotation> annotations;
  bool get hasFunction => parts.any((part) => part.function != null);
  bool get isFunctionOnly => parts.length == 1 && parts.single.function != null;

  /// Renders text while delegating function names and punctuation to the UI.
  String render(
    String Function(InterlinearGrammaticalFunction function, bool standalone)
        functionLabel,
  ) =>
      parts.map((part) {
        final function = part.function;
        return function == null
            ? part.text!
            : functionLabel(function, isFunctionOnly);
      }).join();
}

/// One dictionary analysis, preserving the association between its form,
/// meanings and lexical reference when the source establishes that pairing.
final class InterlinearDictionaryEntry {
  InterlinearDictionaryEntry({
    required this.rawForm,
    required this.form,
    Map<String, String> rawGlosses = const {},
    Map<String, String> glosses = const {},
    List<LexicalReference> lexicalReferences = const [],
    this.isPhrase = false,
    List<InterlinearSourceAnnotation> annotations = const [],
  })  : rawGlosses = Map.unmodifiable(rawGlosses),
        glosses = Map.unmodifiable(glosses),
        lexicalReferences = List.unmodifiable(lexicalReferences),
        annotations = List.unmodifiable(annotations);
  final String rawForm;
  final String form;
  final Map<String, String> rawGlosses;
  final Map<String, String> glosses;
  final List<LexicalReference> lexicalReferences;
  final bool isPhrase;
  final List<InterlinearSourceAnnotation> annotations;
}

final class InterlinearSegmentAnalysis {
  InterlinearSegmentAnalysis({
    required this.raw,
    required this.isWordPart,
    Map<String, InterlinearGloss> contextualGlosses = const {},
    List<InterlinearDictionaryEntry> dictionaryEntries = const [],
    this.grammaticalFunction,
    this.sourceFormCode,
    List<InterlinearSourceAnnotation> annotations = const [],
  })  : contextualGlosses = Map.unmodifiable(contextualGlosses),
        dictionaryEntries = List.unmodifiable(dictionaryEntries),
        annotations = List.unmodifiable(annotations);
  final InterlinearSegment raw;
  final bool isWordPart;
  final Map<String, InterlinearGloss> contextualGlosses;
  final List<InterlinearDictionaryEntry> dictionaryEntries;
  final InterlinearGrammaticalFunction? grammaticalFunction;
  final String? sourceFormCode;
  final List<InterlinearSourceAnnotation> annotations;
}

final class InterlinearWordAnalysis {
  InterlinearWordAnalysis({
    required this.raw,
    required this.source,
    required Map<String, InterlinearGloss> contextualGlosses,
    required List<InterlinearSegmentAnalysis> segments,
  })  : contextualGlosses = Map.unmodifiable(contextualGlosses),
        segments = List.unmodifiable(segments);
  final InterlinearToken raw;
  final InterlinearAnalysisSource source;
  final Map<String, InterlinearGloss> contextualGlosses;
  final List<InterlinearSegmentAnalysis> segments;
  List<InterlinearSegmentAnalysis> get parts =>
      List.unmodifiable(segments.where((part) => part.isWordPart));
}

/// Additive interpretation of schema-1 tokens; it never mutates raw data.
///
/// STEP interpretation is enabled only for the audited source revision,
/// reference system and reading profile. A new revision or another provider is
/// intentionally uninterpreted until its field contract has been reviewed.
final class InterlinearWordAnalyzer {
  const InterlinearWordAnalyzer({this.metadata});
  final InterlinearMetadata? metadata;
  static const stepBibleSourceRevision =
      'b99716b0cddb648ddb95cc786a197180f2f97d48';

  InterlinearAnalysisSource _source(InterlinearToken token) {
    final data = metadata;
    if (data == null ||
        data.sourceRevision != stepBibleSourceRevision ||
        data.referenceSystem != 'STEPBible-NRSV') {
      return InterlinearAnalysisSource.unknown;
    }
    if (data.source == 'STEPBible TAGNT' &&
        data.profile == 'N' &&
        data.readingPolicy == null &&
        token.language == 'grc') {
      return InterlinearAnalysisSource.stepBibleTagnt;
    }
    if (data.source == 'STEPBible TAHOT' &&
        data.profile == 'L+Q+R' &&
        data.readingPolicy == 'qere' &&
        (token.language == 'hbo' || token.language == 'arc')) {
      return InterlinearAnalysisSource.stepBibleTahot;
    }
    return InterlinearAnalysisSource.unknown;
  }

  InterlinearWordAnalysis analyze(InterlinearToken token) {
    final source = _source(token);
    final segments = token.segments.map((part) {
      final visible = _isWordPart(part);
      if (source == InterlinearAnalysisSource.unknown || !visible) {
        return InterlinearSegmentAnalysis(raw: part, isWordPart: visible);
      }
      if (source == InterlinearAnalysisSource.stepBibleTagnt) {
        return _greekPart(part);
      }
      final code = _sourceFormCode(part);
      final function = _function(part);
      return InterlinearSegmentAnalysis(
        raw: part,
        isWordPart: true,
        grammaticalFunction: function,
        sourceFormCode: code,
        contextualGlosses: {
          for (final entry in part.glosses.entries)
            entry.key: entry.key == 'en'
                ? _hebrewGloss(entry.value, token, question: _isQuestion(part))
                : InterlinearGloss.raw(entry.value),
        },
        dictionaryEntries: [
          if (code == null && (part.lemma?.isNotEmpty ?? false))
            InterlinearDictionaryEntry(
              rawForm: part.lemma!,
              form: part.lemma!,
              lexicalReferences: part.lexicalReferences,
              isPhrase: part.lemma!.contains('['),
            ),
        ],
        annotations: [
          if (code != null)
            InterlinearSourceAnnotation(
                InterlinearSourceAnnotationKind.sourceFormCode, code),
        ],
      );
    }).toList();
    return InterlinearWordAnalysis(
      raw: token,
      source: source,
      segments: segments,
      contextualGlosses: {
        for (final entry in token.glosses.entries)
          entry.key: entry.key != 'en'
              ? InterlinearGloss.raw(entry.value)
              : switch (source) {
                  InterlinearAnalysisSource.stepBibleTagnt =>
                    _greekGloss(entry.value),
                  InterlinearAnalysisSource.stepBibleTahot => _hebrewGloss(
                      entry.value, token,
                      question: token.segments.any(_isQuestion)),
                  InterlinearAnalysisSource.unknown =>
                    InterlinearGloss.raw(entry.value),
                },
      },
    );
  }
}

bool _isWordPart(InterlinearSegment part) =>
    part.kind != 'punctuation' &&
    ((part.text?.trim().isNotEmpty ?? false) ||
        (part.lemma?.trim().isNotEmpty ?? false) ||
        part.lexicalReferences.isNotEmpty ||
        part.morphology.isNotEmpty ||
        part.glosses.values.any((value) => value.trim().isNotEmpty));

final _hebrewLetter = RegExp(r'[\u05D0-\u05EA\u05F0-\u05F2]');
String? _sourceFormCode(InterlinearSegment part) {
  final lemma = part.lemma;
  return part.morphology.any((tag) => tag.scheme == 'STEPBible-TAHOT') &&
          lemma != null &&
          lemma.isNotEmpty &&
          !_hebrewLetter.hasMatch(lemma)
      ? lemma
      : null;
}

bool _isQuestion(InterlinearSegment part) =>
    part.glosses['en'] == '?' &&
    part.lexicalReferences.any(
        (ref) => ref.system == 'STEPBible-dStrongs' && ref.value == 'H9008');

InterlinearGrammaticalFunction? _function(InterlinearSegment part) =>
    part.glosses['en'] == '<obj.>'
        ? InterlinearGrammaticalFunction.directObjectMarker
        : _isQuestion(part)
            ? InterlinearGrammaticalFunction.questionMarker
            : null;

InterlinearGloss _hebrewGloss(String raw, InterlinearToken token,
    {required bool question}) {
  var value = raw;
  final annotations = <InterlinearSourceAnnotation>[];
  if (token.occurrenceId == 'TAHOT:Isa.7.23#15') {
    value = value.replaceAll('<into> the>', '<into> the');
    if (value != raw) {
      annotations.add(InterlinearSourceAnnotation(
          InterlinearSourceAnnotationKind.sourceCorrection, raw));
    }
  }
  // Match object markers directly. Question markers must be an entire source
  // constituent, never an ordinary question mark within translated words.
  final marks = <(int, int, InterlinearGrammaticalFunction)>[
    for (final match in RegExp(r'<obj\.>').allMatches(value))
      (
        match.start,
        match.end,
        InterlinearGrammaticalFunction.directObjectMarker
      ),
    if (question)
      for (final match
          in RegExp(r'(^|/)(\s*)(\?)(?=\s*(/|$))').allMatches(value))
        (
          match.end - 1,
          match.end,
          InterlinearGrammaticalFunction.questionMarker
        ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final parts = <InterlinearGlossPart>[];
  var cursor = 0;
  for (final mark in marks) {
    if (mark.$1 > cursor) {
      parts.add(InterlinearGlossPart.text(value.substring(cursor, mark.$1)));
    }
    parts.add(InterlinearGlossPart.function(mark.$3));
    cursor = mark.$2;
  }
  if (cursor < value.length || parts.isEmpty) {
    parts.add(InterlinearGlossPart.text(value.substring(cursor)));
  }
  return InterlinearGloss(rawText: raw, parts: parts, annotations: annotations);
}

InterlinearSegmentAnalysis _greekPart(InterlinearSegment part) {
  final rawForm = part.lemma;
  if (rawForm == null || rawForm.isEmpty) {
    return InterlinearSegmentAnalysis(raw: part, isWordPart: true);
  }
  final forms = rawForm.split(' + ');
  final meanings = part.glosses['en']?.split(' + ');
  if (meanings != null && meanings.length != forms.length) {
    return InterlinearSegmentAnalysis(
      raw: part,
      isWordPart: true,
      annotations: [
        InterlinearSourceAnnotation(
            InterlinearSourceAnnotationKind.unpairedDictionaryAnalysis,
            rawForm),
      ],
    );
  }
  return InterlinearSegmentAnalysis(
    raw: part,
    isWordPart: true,
    dictionaryEntries: [
      for (var i = 0; i < forms.length; i++)
        _dictionaryEntry(
            forms[i],
            meanings?[i],
            part.lexicalReferences.length == forms.length
                ? [part.lexicalReferences[i]]
                : const []),
    ],
  );
}

InterlinearDictionaryEntry _dictionaryEntry(
    String rawForm, String? rawGloss, List<LexicalReference> references) {
  var form = rawForm.trim();
  var gloss = rawGloss?.trim();
  final annotations = <InterlinearSourceAnnotation>[];
  if (form == 'ἰός (2)' || form == 'ἰός (2)') {
    form = form.substring(0, form.length - 4);
    annotations.add(InterlinearSourceAnnotation(
        InterlinearSourceAnnotationKind.homonymNumber, rawForm));
  }
  if (gloss == 'to_step_out') {
    gloss = 'to step out';
    annotations.add(InterlinearSourceAnnotation(
        InterlinearSourceAnnotationKind.dictionaryFormatting, rawGloss!));
  }
  return InterlinearDictionaryEntry(
    rawForm: rawForm,
    form: form,
    rawGlosses: {if (rawGloss != null) 'en': rawGloss},
    glosses: {if (gloss != null) 'en': gloss},
    lexicalReferences: references,
    annotations: annotations,
  );
}

// Audited reference annotations in the pinned TAGNT contextual-gloss column.
const _greekReferencePrefixes = {
  '[3]',
  '[5]',
  '[6]',
  '[7]',
  '[8]',
  '[10]',
  '[11]',
  '[12]',
  '[13]',
  '[13.1]',
  '[14]',
  '[15]',
  '[16]',
  '[17]',
  '[18]',
  '[19]',
  '[20]',
  '[21]',
  '[22]',
  '[23]',
  '[28]',
  '[40]',
  '[74]',
  '(15)',
  '(26)',
  '(39)',
  '{6}',
  '{7}',
  '{8}',
  '{11}',
  '{12}',
  '{14.24}',
  '{14.25}',
  '{14.26}',
  '{22}',
};

InterlinearGloss _greekGloss(String raw) {
  var value = raw.trim();
  final annotations = <InterlinearSourceAnnotation>[];
  for (final prefix in _greekReferencePrefixes) {
    if (value.startsWith('$prefix ')) {
      value = value.substring(prefix.length).trimLeft();
      annotations.add(InterlinearSourceAnnotation(
          InterlinearSourceAnnotationKind.verseReference, raw));
      break;
    }
  }
  return InterlinearGloss(
    rawText: raw,
    parts: [InterlinearGlossPart.text(value)],
    annotations: annotations,
  );
}
