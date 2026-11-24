import 'package:flutter/material.dart';

import 'package:sportika/shared/widgets/cinematic_backdrop.dart';
import 'package:sportika/shared/widgets/global_app_header.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/navigation/navigation.dart';

import 'package:sportika/features/home/screens/home_tab.dart';
import 'package:sportika/features/discover/screens/tournament_tab.dart';
import 'package:sportika/features/matches/screens/matches_tab_host.dart';
import 'package:sportika/features/teams/screens/teams_tab.dart';
import 'package:sportika/features/profile/screens/profile_tab.dart';

/// Sportika primary navigation.
///
/// The order here is the order of [HomeTabIndex], so tab requests, deep links
/// and the navigation bar stay aligned.
enum _SportikaTab {
  home('Home', Icons.home_outlined, Icons.home_rounded),
  tournaments(
    'Tournaments',
    Icons.emoji_events_outlined,
    Icons.emoji_events_rounded,
  ),
  matches('Matches', Icons.sports_score_outlined, Icons.sports_score_rounded),
  team('Team', Icons.groups_outlined, Icons.groups_rounded),
  me('Me', Icons.person_outline_rounded, Icons.person_rounded);

  const _SportikaTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Premium Sportika application shell.
///
/// Features:
/// - Branded contextual header
/// - Cinematic shared backdrop
/// - Five persistent tab screens
/// - Theme-driven bottom navigation
/// - Reduced-motion support
/// - Existing deep-link navigation behavior
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index;

  static const _tabs = _SportikaTab.values;

  @override
  void initState() {
    super.initState();

    _index = widget.initialIndex.clamp(0, _tabs.length - 1);

    homeTabRequest.value = _index;
    homeTabRequest.addListener(_handleTabRequest);
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialIndex != widget.initialIndex) {
      final next = widget.initialIndex.clamp(0, _tabs.length - 1);

      if (next != _index) {
        _index = next;
        homeTabRequest.value = next;
      }
    }
  }

  @override
  void dispose() {
    homeTabRequest.removeListener(_handleTabRequest);
    super.dispose();
  }

  void _handleTabRequest() {
    final next = homeTabRequest.value.clamp(0, _tabs.length - 1);

    if (!mounted || next == _index) {
      return;
    }

    setState(() {
      _index = next;
    });
  }

  void _selectTab(int index) {
    if (index == _index) return;

    // Preserve the existing shared navigation contract.
    homeTabRequest.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;
    final selectedTab = _tabs[_index];

    return Scaffold(
      backgroundColor: theme.page,
      extendBody: false,

      // ----------------------------------
      // MAIN APPLICATION CONTENT
      // ----------------------------------
      body: CinematicBackdrop(
        child: Column(
          children: [
            // Existing shared header.
            //
            // Home uses branded actions.
            // Other tabs receive contextual section labels.
            GlobalAppHeader(
              useHomeActions: selectedTab == _SportikaTab.home,
              section: selectedTab.label,
            ),

            // Keep all five tabs mounted.
            //
            // Existing scroll positions and widget states
            // are preserved when switching destinations.
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [
                  HomeTab(),
                  TournamentTab(),
                  MatchesTabHost(),
                  TeamsTab(),
                  ProfileTab(),
                ],
              ),
            ),
          ],
        ),
      ),

      // ----------------------------------
      // PREMIUM BOTTOM NAVIGATION
      // ----------------------------------
      bottomNavigationBar: _SportikaBottomNavigation(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
      ),
    );
  }
}

/// Premium, theme-driven navigation surface.
///
/// Uses Material NavigationBar internally to preserve:
/// - Accessibility
/// - Keyboard navigation
/// - Material semantics
/// - Five-tab navigation behavior
///
/// Styling is controlled centrally through SportikaTheme.
class _SportikaBottomNavigation extends StatelessWidget {
  const _SportikaBottomNavigation({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final theme = context.sportika;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surfaceAlt,
        border: Border(
          top: BorderSide(
            color: theme.borderSubtle,
            width: SportikaBorder.hairline,
          ),
        ),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: theme.surfaceAlt,
          elevation: 0,
          height: SportikaComponentSize.bottomNavHeight,

          // Restrained selected indicator.
          indicatorColor: theme.surfaceAlt,
          indicatorShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SportikaRadius.control),
          ),

          // Theme-aware icon states.
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);

            return IconThemeData(
              size: SportikaIconSize.lg,
              color: selected ? theme.live : theme.textMuted,
            );
          }),

          // Editorial yet compact navigation labels.
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);

            return context.sportikaText
                .of(
                  SportikaTextRole.tabLabel,
                  color: selected ? theme.textPrimary : theme.textMuted,
                )
                .copyWith(
                  fontWeight: selected
                      ? SportikaFontWeight.bold
                      : SportikaFontWeight.medium,
                );
          }),

          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,

          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return theme.live.withValues(alpha: SportikaOpacity.soft);
            }

            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return theme.surfaceAlt;
            }

            return Colors.transparent;
          }),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          animationDuration: reduceMotion ? Duration.zero : SportikaMotion.base,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
              tooltip: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.emoji_events_outlined),
              selectedIcon: Icon(Icons.emoji_events_rounded),
              label: 'Tournaments',
              tooltip: 'Discover tournaments and competitions',
            ),
            NavigationDestination(
              icon: Icon(Icons.sports_score_outlined),
              selectedIcon: Icon(Icons.sports_score_rounded),
              label: 'Matches',
              tooltip: 'Discover, join and score standalone matches',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Team',
              tooltip: 'My teams',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Me',
              tooltip: 'My profile and account',
            ),
          ],
        ),
      ),
    );
  }
}
