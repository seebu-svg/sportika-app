import 'package:sportika/shared/models/enums.dart';

class CommunityGame {
  CommunityGame({
    required this.id,
    required this.title,
    required this.sport,
    required this.venue,
    required this.at,
    required this.capacity,
    required this.organizerId,
    this.category = 'Friendly',
    this.format = 'Standard',
    this.description = 'Respect all players. Arrive 15 minutes early and bring your equipment.',
    this.visibility = 'Public',
    List<String>? members,
    this.isDemo = false,
  }) : members = members ?? [];
  final String id,
      title,
      venue,
      organizerId,
      category,
      format,
      description,
      visibility;
  final Sport sport;
  final DateTime at;
  final int capacity;
  final List<String> members;

  /// True when the game was created for preview/testing.
  final bool isDemo;
  bool get full => members.length >= capacity;
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sport': sport.name,
    'venue': venue,
    'at': at.toIso8601String(),
    'capacity': capacity,
    'organizerId': organizerId,
    'category': category,
    'format': format,
    'description': description,
    'visibility': visibility,
    'members': members,
    'isDemo': isDemo,
  };
  factory CommunityGame.fromJson(Map<String, dynamic> j) => CommunityGame(
    id: j['id'],
    title: j['title'],
    sport: SportX.fromKey(j['sport']),
    venue: j['venue'],
    at: DateTime.parse(j['at']),
    capacity: j['capacity'],
    organizerId: j['organizerId'],
    category: j['category'],
    format: j['format'],
    description: j['description'],
    visibility: j['visibility'],
    members: List<String>.from(j['members']),
    isDemo: j['isDemo'] as bool? ?? false,
  );
}

List<CommunityGame> seedCommunityGames() => List.generate(24, (i) {
  final sport = Sport.values[i % 4];
  final venues = [
    'DHA Sports Club',
    'Clifton Padel Club',
    'Kokan Football Arena',
    'Kashmir Road Sports Complex',
  ];
  final names = [
    'Karachi weekend cricket',
    'Sunset padel doubles',
    'Friday night futsal',
    'Clifton shuttle club',
  ];
  final capacity = [22, 4, 10, 4][i % 4];
  return CommunityGame(
    id: 'game-$i',
    title: '${names[i % 4]}${i < 4 ? '' : ' · Round ${i ~/ 4 + 1}'}',
    sport: sport,
    venue: venues[i % 4],
    at: DateTime.now().add(Duration(days: i + 1)),
    capacity: capacity,
    organizerId: 'acc-yasir',
    category: ['Friendly', 'League', 'Tournament'][i % 3],
    format: [
      'T10 · 10 overs',
      'Best of 3 sets',
      '2 × 20 min',
      'Best of 3 games',
    ][i % 4],
    members: List.generate(
      i % 5 == 0 ? capacity : capacity - 2,
      (n) => 'demo-player-$n',
    ),
  );
});
