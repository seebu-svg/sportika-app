import 'package:sportika/shared/models/enums.dart';

/// A single recorded scoring action.
///
/// The whole match is reconstructed by folding these in order, which gives
/// Sportika three properties the spec asks for:
///  * undo is always exact (drop the last event and re-fold),
///  * resume works from the persisted log alone,
///  * a retried action is recorded only once, because [id] is a dedupe key.
class ScoringEvent {
  final String id;
  final String kind;

  /// Which side benefits. Null when the event is not side-specific (clock,
  /// end-of-innings, …).
  final int? side;
  final Map<String, dynamic> data;
  final DateTime at;
  final String byAccountId;

  ScoringEvent({
    required this.id,
    required this.kind,
    required this.side,
    required this.data,
    required this.at,
    required this.byAccountId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'side': side,
    'data': data,
    'at': at.toIso8601String(),
    'by': byAccountId,
  };

  /// Engine actions are built without an id; the store assigns a stable one
  /// when the event is appended, which is also the dedupe key.
  factory ScoringEvent.fromJson(Map<String, dynamic> j) => ScoringEvent(
    id: j['id'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    side: (j['side'] as num?)?.toInt(),
    data: Map<String, dynamic>.from(j['data'] as Map? ?? const {}),
    at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
    byAccountId: j['by'] as String? ?? '',
  );

  int flag(String key) => (data[key] as num?)?.toInt() ?? 0;
  bool get flagBool => data['value'] == true || data['value'] == 1;
}

/// Visual weight of a scorecard button, mapped to colours in the UI layer.
enum ActionStyle { primary, neutral, danger, highlight, subtle }

/// A scoring action offered by an engine for the current match situation.
class ScoreAction {
  final String id;
  final String label;
  final String? hint;
  final ActionStyle style;

  /// When true the scorecard asks which side the action belongs to first.
  final bool pickSide;
  final ScoringEvent Function(ActionContext ctx) build;

  ScoreAction({
    required this.id,
    required this.label,
    this.hint,
    this.style = ActionStyle.neutral,
    this.pickSide = false,
    required this.build,
  });
}

/// What the scorecard hands an action when it is tapped.
class ActionContext {
  final int? side;
  final String by;

  const ActionContext({this.side, required this.by});
}

/// One row of the big score readout.
class ScoreLine {
  final String label;
  final String value;
  final String? sub;
  final bool leading;
  final bool muted;

  ScoreLine({
    required this.label,
    required this.value,
    this.sub,
    this.leading = false,
    this.muted = false,
  });
}

/// Everything the UI needs to render a scorecard, produced by an engine.
class MatchProgress {
  final Sport sport;
  final List<String> sides;
  final List<ScoreLine> lines;
  final String headline;
  final String? statusLabel;
  final List<String> detailRows;
  final List<String> contextChips;

  final bool isComplete;
  final int winnerIndex;
  final String resultLabel;
  final String completionReason;

  /// Normalised numbers used to build an [OfficialResult] (0 = side A).
  final List<int> scoreValues;
  final List<String> scoreDisplay;
  final List<ScoreAction> actions;

  /// Sport-specific state the engine needs to keep going (carried in memory
  /// only; the event log remains the single source of truth).
  final Map<String, dynamic> state;

  const MatchProgress({
    required this.sport,
    required this.sides,
    required this.lines,
    required this.headline,
    this.statusLabel,
    this.detailRows = const [],
    this.contextChips = const [],
    this.isComplete = false,
    this.winnerIndex = -1,
    this.resultLabel = '',
    this.completionReason = '',
    this.scoreValues = const [0, 0],
    this.scoreDisplay = const ['', ''],
    this.actions = const [],
    this.state = const {},
  });

  static MatchProgress empty(Sport sport, List<String> sides) => MatchProgress(
    sport: sport,
    sides: sides,
    headline: '',
    lines: [
      ScoreLine(label: sides.isNotEmpty ? sides[0] : 'Side A', value: '0'),
      ScoreLine(label: sides.length > 1 ? sides[1] : 'Side B', value: '0'),
    ],
  );
}

/// Contract every MVP sport implements. Personal and official scoring share it,
/// so both use identical sport rules on separate match records (spec §3).
abstract class SportEngine {
  Sport get sport;

  /// Format labels offered when starting a scorecard, e.g. "T10 · 10 overs".
  List<String> get formats;

  /// Engine rules derived from the chosen format label.
  Map<String, dynamic> rulesForFormat(String format);

  /// Short human summary of a rules map, shown on tournament detail pages.
  String describeRules(Map<String, dynamic> rules);

  /// Pure fold of the event log into a renderable progress object.
  MatchProgress evaluate({
    required List<String> sides,
    required Map<String, dynamic> rules,
    required List<ScoringEvent> events,
  });
}
