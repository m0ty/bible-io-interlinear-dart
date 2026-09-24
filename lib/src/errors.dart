/// A failure with a stable machine-readable code and optional resource path.
class InterlinearException implements Exception {
  const InterlinearException(this.code, this.message, {this.path, this.cause});

  final String code;
  final String message;
  final String? path;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType($code${path == null ? '' : ', $path'}): $message';
}

/// Invalid prepared data, including unsupported schemas and integrity failures.
class InterlinearDataException extends InterlinearException {
  const InterlinearDataException(super.code, super.message,
      {super.path, super.cause});
}

/// A declared resource could not be obtained from the injected reader.
class InterlinearResourceException extends InterlinearException {
  const InterlinearResourceException(super.code, super.message,
      {super.path, super.cause});
}

/// A requested chapter is outside the dataset's declared coverage.
class UnsupportedCoverageException extends InterlinearException {
  const UnsupportedCoverageException(super.code, super.message,
      {super.path, super.cause});
}

/// A loaded chapter does not contain the requested source entry.
class InterlinearVerseNotFoundException extends InterlinearException {
  const InterlinearVerseNotFoundException(super.code, super.message,
      {super.path, super.cause});
}

/// A numeric query covers several subdivided source entries.
class InterlinearAmbiguousVerseException extends InterlinearException {
  const InterlinearAmbiguousVerseException(super.code, super.message,
      {super.path, super.cause});
}
