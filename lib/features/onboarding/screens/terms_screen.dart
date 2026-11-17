import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app/env.dart';
import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

class _Section {
  const _Section(this.heading, this.body);
  final String heading;
  final String body;
}

/// The demo build runs on seeded device data, so three clauses have to say so.
/// A live build promises the opposite: the account and its data live on the
/// server. One switch keeps the two copies honest.
List<_Section> _terms() => [
  const _Section(
    'One account, real details',
    'Use an email you control and a name your team will recognise. You are '
        'responsible for keeping your sign-in details private.',
  ),
  const _Section(
    'Scorecards stay private',
    'Personal scorecards belong to you and never feed official standings. '
        'Only an organizer can publish an official result.',
  ),
  const _Section(
    'Fair play',
    'Do not submit false results, abuse officials or use Sportika to harass '
        'other players. Organizers can remove entries that break these rules.',
  ),
  const _Section(
    'Photography & marks',
    'Editorial photographs are credited in the app and do not depict fictional '
        'fixtures. Sportika names and marks remain the property of Sportika.',
  ),
  const _Section(
    'Closing your account',
    AppEnv.demoMode
        ? 'You can request deletion at any time. In this prototype, clearing '
              'demo data removes everything stored on the device.'
        : 'You can request deletion at any time by writing to '
              'privacy@sportika.pk from your account address. We delete the '
              'account, its profile and its scorecards.',
  ),
];

List<_Section> _privacy() => [
  const _Section(
    'What we store',
    AppEnv.demoMode
        ? 'Your name, email, city, sports preferences, avatar choice and, if '
              'you add one, the profile picture you imported. Scorecards, demo '
              'results and that picture file are stored on this device, not on '
              'a server.'
        : 'Your name, email, city, sports preferences and avatar choice, plus '
              'the profile picture you imported. Your profile and scorecards '
              'belong to your Sportika account.',
  ),
  const _Section(
    'What we never do',
    'We do not sell personal data, build advertising profiles or read private '
        'scorecards for marketing.',
  ),
  const _Section(
    'Photos & location',
    'A profile picture you take or pick is cropped and shrunk on this device '
        'before it is used anywhere. We ask for a city only; no background '
        'location is collected.',
  ),
  const _Section(
    'Your controls',
    AppEnv.demoMode
        ? 'Edit your profile, replace or remove your picture, change '
              'preferences, sign out, reset demo data or clear everything from '
              'the Me tab at any time.'
        : 'Edit your profile, replace or remove your picture, change your '
              'password or email, sign out of every device, or clear what this '
              'device stores from Settings at any time.',
  ),
  const _Section('Contact', 'Questions about data: privacy@sportika.pk.'),
];

/// 17 · Terms & Privacy. Editorial legal copy, readable in two tabs, with one
/// explicit acceptance action.
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<AuthFlowController>();
    final sections = _tab == 0 ? _terms() : _privacy();

    return AuthPage(
      sport: Sport.badminton,
      photoAlignment: const Alignment(0, -.1),
      showBack: true,
      onBack: flow.closeTerms,
      stepLabel: 'LEGAL',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuthAction(
            label: 'ACCEPT & CONTINUE',
            onPressed: flow.acceptTerms,
            icon: Icons.check,
          ),
          const SizedBox(height: 8),
          AuthLink(
            'Go back without accepting',
            align: TextAlign.center,
            tone: SportikaColors.textDim,
            onTap: flow.closeTerms,
          ),
        ],
      ),
      children: [
        const SizedBox(height: 22),
        const AuthEyebrow('TERMS & PRIVACY'),
        const SizedBox(height: 14),
        const AuthHeadline('THE FINE', accent: 'PRINT.', size: 44),
        const SizedBox(height: 16),
        const AuthLead(
          'Plain-language terms for playing, organizing and keeping score on '
          'Sportika.',
        ),
        const SizedBox(height: 22),
        _Tabs(index: _tab, onChanged: (value) => setState(() => _tab = value)),
        const SizedBox(height: 8),
        for (var i = 0; i < sections.length; i++) ...[
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '0${i + 1}',
                style: authDisplay(
                  18,
                  color: SportikaColors.mint,
                  height: 1.1,
                  letterSpacing: .5,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sections[i].heading,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: SportikaColors.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      sections[i].body,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.55,
                        color: SportikaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const AuthRule(),
        ],
        const SizedBox(height: 16),
        const AuthMicro(
          'Version 1.0 · November 2026 · Sportika, Karachi',
          icon: Icons.description_outlined,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: SportikaColors.surfaceSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SportikaColors.borderSubtle),
      ),
      child: Row(
        children: [
          _Tab(
            label: 'TERMS OF USE',
            selected: index == 0,
            onTap: () => onChanged(0),
          ),
          _Tab(
            label: 'PRIVACY',
            selected: index == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: selected ? SportikaColors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? SportikaColors.border : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: selected ? SportikaColors.text : SportikaColors.textDim,
            ),
          ),
        ),
      ),
    );
  }
}
