int _seq = 0;

/// Human-unfriendly but collision-safe local id for mock objects.
String newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
    '${(_seq++).toRadixString(36)}';
