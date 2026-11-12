import 'package:flutter/material.dart';

void main() => runApp(const SportikaApp());

class SportikaApp extends StatelessWidget {
  const SportikaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sportika',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        colorScheme: ColorScheme.fromSeed(seedColor: SportikaColors.blue),
      ),
      home: const SportikaHomeScreen(),
    );
  }
}

class SportikaColors {
  static const navy = Color(0xFF09182D);
  static const blue = Color(0xFF1769FF);
  static const mint = Color(0xFF36D8BD);
  static const gold = Color(0xFFF6B84B);
  static const muted = Color(0xFF738096);
}

class SportikaHomeScreen extends StatefulWidget {
  const SportikaHomeScreen({super.key});

  @override
  State<SportikaHomeScreen> createState() => _SportikaHomeScreenState();
}

class _SportikaHomeScreenState extends State<SportikaHomeScreen> {
  int selectedSport = 0;
  int selectedTab = 0;
  final sports = const [
    (name: 'All', icon: Icons.apps_rounded),
    (name: 'Cricket', icon: Icons.sports_cricket_rounded),
    (name: 'Padel', icon: Icons.sports_tennis_rounded),
    (name: 'Futsal', icon: Icons.sports_soccer_rounded),
    (name: 'Badminton', icon: Icons.sports_tennis_rounded),
  ];

  void showPrototypeAction(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label • prototype action')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _hero(),
                  const SizedBox(height: 28),
                  _sectionTitle('Your sports', 'See all', () => showPrototypeAction('Sports')),
                  const SizedBox(height: 14),
                  _sportsSelector(),
                  const SizedBox(height: 28),
                  _sectionTitle('Quick actions', null, null),
                  const SizedBox(height: 14),
                  _quickActions(),
                  const SizedBox(height: 28),
                  _sectionTitle('Upcoming match', 'My matches', () => showPrototypeAction('My matches')),
                  const SizedBox(height: 14),
                  _upcomingMatch(),
                  const SizedBox(height: 28),
                  _sectionTitle('Live now', 'View all', () => showPrototypeAction('Live matches')),
                  const SizedBox(height: 14),
                  _liveScore(),
                  const SizedBox(height: 28),
                  _sectionTitle('Discover games', 'Explore', () => showPrototypeAction('Discover games')),
                  const SizedBox(height: 14),
                  _discoverCard(),
                  const SizedBox(height: 28),
                  _sectionTitle('Your performance', null, null),
                  const SizedBox(height: 14),
                  _performance(),
                ]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        backgroundColor: Colors.white,
        indicatorColor: SportikaColors.blue.withValues(alpha: 0.10),
        onDestinationSelected: (index) {
          setState(() => selectedTab = index);
          if (index != 0) showPrototypeAction(['Home', 'Games', 'Events', 'Scores', 'Profile'][index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.sports_outlined), label: 'Games'),
          NavigationDestination(icon: Icon(Icons.emoji_events_outlined), label: 'Events'),
          NavigationDestination(icon: Icon(Icons.scoreboard_outlined), label: 'Scores'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('GOOD MORNING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: SportikaColors.muted)),
        const SizedBox(height: 5),
        const Text('Hey, Player', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: SportikaColors.navy)),
        const SizedBox(height: 6),
        Row(children: const [Icon(Icons.location_on_outlined, size: 15, color: SportikaColors.muted), SizedBox(width: 3), Text('Karachi, Pakistan', style: TextStyle(fontSize: 12, color: SportikaColors.muted))]),
      ])),
      IconButton(onPressed: () => showPrototypeAction('Notifications'), icon: const Icon(Icons.notifications_none_rounded, size: 27)),
      const SizedBox(width: 5),
      CircleAvatar(radius: 22, backgroundColor: SportikaColors.navy, child: const Icon(Icons.person_rounded, color: Colors.white)),
    ]),
  );

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: SportikaColors.navy,
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(colors: [Color(0xFF09182D), Color(0xFF153E72)], begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: Stack(children: [
      Positioned(right: -16, top: -18, child: Icon(Icons.sports_soccer_rounded, size: 155, color: Colors.white.withValues(alpha: 0.06))),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('YOUR GAME STARTS HERE', style: TextStyle(color: SportikaColors.mint, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
        const SizedBox(height: 12),
        const Text('Ready for your\nnext match?', style: TextStyle(color: Colors.white, fontSize: 29, height: 1.12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        const Text('Find players, join games and make every match count.', style: TextStyle(color: Color(0xFFD5DFED), fontSize: 13, height: 1.5)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => showPrototypeAction('Find a game'),
          style: FilledButton.styleFrom(backgroundColor: SportikaColors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13)),
          icon: const Icon(Icons.arrow_outward_rounded, size: 18),
          label: const Text('Find a game', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    ]),
  );

  Widget _sectionTitle(String title, String? action, VoidCallback? onTap) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: SportikaColors.navy))),
    if (action != null) TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(color: SportikaColors.blue, fontWeight: FontWeight.w700))),
  ]);

  Widget _sportsSelector() => SizedBox(
    height: 85,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: sports.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, index) {
        final selected = selectedSport == index;
        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => setState(() => selectedSport = index),
          child: Container(
            width: 80,
            decoration: BoxDecoration(color: selected ? SportikaColors.navy : Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: selected ? SportikaColors.navy : const Color(0xFFE8ECF3))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(sports[index].icon, size: 26, color: selected ? SportikaColors.mint : SportikaColors.blue),
              const SizedBox(height: 7),
              Text(sports[index].name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : SportikaColors.navy)),
            ]),
          ),
        );
      },
    ),
  );

  Widget _quickActions() {
    final actions = [
      (label: 'Find game', icon: Icons.search_rounded, color: SportikaColors.blue),
      (label: 'Create', icon: Icons.add_circle_outline_rounded, color: SportikaColors.mint),
      (label: 'Personal score', icon: Icons.edit_note_rounded, color: SportikaColors.gold),
      (label: 'My teams', icon: Icons.groups_rounded, color: const Color(0xFF8A72EC)),
    ];
    return Row(children: [
      for (var i = 0; i < actions.length; i++)
        Expanded(child: Padding(
          padding: EdgeInsets.only(right: i == actions.length - 1 ? 0 : 8),
          child: InkWell(onTap: () => showPrototypeAction(actions[i].label), borderRadius: BorderRadius.circular(18), child: Column(children: [
            Container(height: 65, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Icon(actions[i].icon, color: actions[i].color, size: 29)),
            const SizedBox(height: 9),
            Text(actions[i].label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SportikaColors.navy)),
          ])),
        )),
    ]);
  }

  Widget _upcomingMatch() => _surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _pill('PADEL', SportikaColors.blue.withValues(alpha: 0.09), SportikaColors.blue),
      const Spacer(),
      const Icon(Icons.calendar_today_outlined, size: 14, color: SportikaColors.muted),
      const SizedBox(width: 5),
      const Text('Sat, 14 Nov • 6:00 PM', style: TextStyle(fontSize: 11, color: SportikaColors.muted)),
    ]),
    const SizedBox(height: 17),
    const Text('Weekend Padel Doubles', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: SportikaColors.navy)),
    const SizedBox(height: 7),
    const Row(children: [Icon(Icons.location_on_outlined, size: 15, color: SportikaColors.muted), SizedBox(width: 5), Expanded(child: Text('Padel Arena, Karachi', style: TextStyle(color: SportikaColors.muted, fontSize: 12)))]),
    const SizedBox(height: 17),
    Row(children: [
      const Icon(Icons.groups_outlined, color: SportikaColors.blue, size: 19),
      const SizedBox(width: 7),
      const Text('3 / 4 players', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      const Spacer(),
      TextButton(onPressed: () => showPrototypeAction('Match details'), child: const Text('View details →')),
    ]),
  ]));

  Widget _liveScore() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: SportikaColors.navy, borderRadius: BorderRadius.circular(22)),
    child: Column(children: [
      Row(children: [
        _pill('● LIVE', const Color(0xFF244C47), SportikaColors.mint),
        const SizedBox(width: 9),
        const Text('FUTSAL', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w800)),
        const Spacer(),
        const Text('2ND HALF • 34\'', style: TextStyle(fontSize: 10, color: Colors.white70)),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        const Expanded(child: Text('Falcons FC', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        const Text('3  :  2', style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900)),
        const Expanded(child: Text('Titans FC', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
      ]),
      const SizedBox(height: 12),
      TextButton(onPressed: () => showPrototypeAction('Live match center'), child: const Text('Open match center →', style: TextStyle(color: SportikaColors.mint))),
    ]),
  );

  Widget _discoverCard() => _surface(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      _pill('CRICKET', SportikaColors.blue.withValues(alpha: 0.09), SportikaColors.blue),
      const Spacer(),
      const Icon(Icons.people_alt_outlined, size: 15, color: SportikaColors.muted),
      const SizedBox(width: 5),
      const Text('2 spots left', style: TextStyle(fontSize: 12, color: SportikaColors.muted)),
    ]),
    const SizedBox(height: 14),
    const Text('Sunday Evening Cricket', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: SportikaColors.navy)),
    const SizedBox(height: 7),
    const Text('Sun, 15 Nov • 5:30 PM  •  Karachi', style: TextStyle(color: SportikaColors.muted, fontSize: 12)),
    const SizedBox(height: 15),
    SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => showPrototypeAction('Join game'), child: const Text('View & join game'))),
  ]));

  Widget _performance() => Row(children: [
    Expanded(child: _stat('08', 'Matches', Icons.sports_rounded)),
    const SizedBox(width: 10),
    Expanded(child: _stat('03', 'Wins', Icons.emoji_events_outlined)),
    const SizedBox(width: 10),
    Expanded(child: _stat('02', 'Upcoming', Icons.event_available_outlined)),
  ]);

  Widget _stat(String value, String label, IconData icon) => _surface(child: Column(children: [
    Icon(icon, color: SportikaColors.blue, size: 22),
    const SizedBox(height: 8),
    Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: SportikaColors.navy)),
    Text(label, style: const TextStyle(fontSize: 11, color: SportikaColors.muted)),
  ]));

  Widget _pill(String text, Color background, Color foreground) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(30)),
    child: Text(text, style: TextStyle(fontSize: 10, color: foreground, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
  );

  Widget _surface({required Widget child}) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFECF0F5))),
    child: child,
  );
}
