/// Running tally of everything that went *wrong or degraded* during a run, so
/// the export can be honest about its own completeness.
///
/// The export feature's whole point is to hand a maintainer as big and accurate
/// a picture of real data as possible. Unknown-unknown inputs (garbage records,
/// pathological bodies, formats the normalizer mis-handles) are the enemy of
/// that. The tool's response is: **degrade, never crash, and never fabricate** —
/// process what it can, drop what it can't *trust*, and record the drops here so
/// nobody mistakes a partial export for a complete one. Every counter is a
/// denominator that keeps the exported data from being misleading.
class DataQuality {
  // --- dataset load ---------------------------------------------------------
  /// Records/lines that could not be parsed as a message and were skipped.
  int datasetMalformed = 0;

  /// Records dropped because their body was empty after trimming.
  int datasetEmptyBodies = 0;

  /// Usable messages that made it into the run.
  int messagesLoaded = 0;

  // --- parse ----------------------------------------------------------------
  /// Messages the host parser threw on; counted as unmatched, never dropped.
  int parseErrors = 0;

  // --- normalization / clustering ------------------------------------------
  /// Messages whose normalization hit a rule failure (partial anonymization).
  int normalizationDegraded = 0;

  /// Messages truncated before normalization because the body was over-long.
  int normalizationTruncated = 0;

  /// Messages that could not be normalized at all and were left out of any
  /// cluster (still counted in coverage totals).
  int clusteringSkipped = 0;

  // --- export ---------------------------------------------------------------
  /// Units emitted successfully.
  int unitsExported = 0;

  /// Units emitted with redacted text/shape because their source was degraded
  /// (kept as a count signal, never with untrusted content).
  int unitsRedacted = 0;

  /// Families that failed to produce a unit at all and were skipped.
  int unitErrors = 0;

  /// Fields whose shape could not be generalized and fell back to a coarse
  /// class rather than an exact (potentially misleading) one.
  int fieldShapeFallbacks = 0;

  /// True when nothing anomalous happened — a fully trustworthy, complete run.
  bool get clean =>
      datasetMalformed == 0 &&
      parseErrors == 0 &&
      normalizationDegraded == 0 &&
      normalizationTruncated == 0 &&
      clusteringSkipped == 0 &&
      unitsRedacted == 0 &&
      unitErrors == 0 &&
      fieldShapeFallbacks == 0;

  Map<String, dynamic> toJson() => {
        'clean': clean,
        'datasetMalformed': datasetMalformed,
        'datasetEmptyBodies': datasetEmptyBodies,
        'messagesLoaded': messagesLoaded,
        'parseErrors': parseErrors,
        'normalizationDegraded': normalizationDegraded,
        'normalizationTruncated': normalizationTruncated,
        'clusteringSkipped': clusteringSkipped,
        'unitsExported': unitsExported,
        'unitsRedacted': unitsRedacted,
        'unitErrors': unitErrors,
        'fieldShapeFallbacks': fieldShapeFallbacks,
      };

  /// A one-line human summary for the console/preview.
  String summary() => clean
      ? 'clean (no anomalies)'
      : [
          if (datasetMalformed > 0) '$datasetMalformed malformed record(s)',
          if (parseErrors > 0) '$parseErrors parse error(s)',
          if (normalizationDegraded > 0)
            '$normalizationDegraded degraded normalization(s)',
          if (normalizationTruncated > 0)
            '$normalizationTruncated truncated body(ies)',
          if (clusteringSkipped > 0) '$clusteringSkipped unclustered',
          if (unitsRedacted > 0) '$unitsRedacted redacted unit(s)',
          if (unitErrors > 0) '$unitErrors dropped unit(s)',
          if (fieldShapeFallbacks > 0)
            '$fieldShapeFallbacks coarse field shape(s)',
        ].join(', ');
}
