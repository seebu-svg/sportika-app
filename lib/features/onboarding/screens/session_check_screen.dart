import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/core/state/session_controller.dart';
import 'package:sportika/features/auth/state/auth_flow.dart';
import 'package:sportika/shared/widgets/widgets.dart';
import 'package:sportika/features/auth/widgets/auth_widgets.dart';

/// 15 · Loading & session verification. Shown only when a session was restored,
/// so the wait explains itself and ends by itself.
class SessionVerificationScreen extends StatefulWidget {
  const SessionVerificationScreen({super.key});

  @override
  State<SessionVerificationScreen> createState() =>
      _SessionVerificationScreenState();
}

class _SessionVerificationScreenState extends State<SessionVerificationScreen> {
  static const _steps = [
    'Secure connection established',
    'Loading your scorecards',
    'Restoring your last session',
  ];

  int _step = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 430), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_step >= _steps.length) {
        timer.cancel();
        return;
      }
      setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.read<AuthFlowController>();
    final account = context.watch<ProfileController>().currentAccount;
    final name = account?.displayName ?? 'Athlete';

    return Scaffold(
      backgroundColor: SportikaColors.deepest,
      body: Stack(
        children: [
          const Positioned.fill(
            child: AuthPhoto(sport: Sport.padel, alignment: Alignment(0, -.1)),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xCC061426),
                    Color(0xF2061426),
                    SportikaColors.deepest,
                  ],
                  stops: [0, .45, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 12, 26, 18),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const BrandMark(size: 26),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text(
                                  'SPORTIKA',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.6,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'SESSION',
                                style: authDisplay(
                                  10,
                                  color: SportikaColors.mint,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Center(
                            child: Column(
                              children: [
                                AuthAvatar(
                                  initials: _initials(name),
                                  avatarId: account?.avatar ?? 'midnight',
                                  size: 86,
                                ),
                                const SizedBox(height: 22),
                                const AuthEyebrow('SESSION FOUND'),
                                const SizedBox(height: 12),
                                AuthHeadline(
                                  'WELCOME BACK,',
                                  accent:
                                      '${name.split(RegExp(r'\s+')).first.toUpperCase()}.',
                                  size: 38,
                                ),
                                const SizedBox(height: 12),
                                AuthLead(
                                  'Signing you back in as $name. Nothing to type.',
                                  maxWidth: 280,
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: SportikaColors.surface.withValues(
                                alpha: .62,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: SportikaColors.borderSubtle,
                              ),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < _steps.length; i++)
                                  _StepLine(
                                    label: _steps[i],
                                    state: i < _step
                                        ? _StepState.done
                                        : i == _step
                                        ? _StepState.active
                                        : _StepState.waiting,
                                  ),
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0, end: 1),
                                    duration: const Duration(
                                      milliseconds: 1650,
                                    ),
                                    curve: Curves.easeInOutCubic,
                                    builder: (context, value, _) =>
                                        LinearProgressIndicator(
                                          value: value,
                                          minHeight: 2.5,
                                          backgroundColor:
                                              SportikaColors.border,
                                          valueColor:
                                              const AlwaysStoppedAnimation(
                                                SportikaColors.mint,
                                              ),
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          AuthAction(
                            label: 'NOT YOU? SWITCH ACCOUNT',
                            ghost: true,
                            icon: Icons.swap_horiz,
                            onPressed: flow.cancelSession,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) => initialsOf(name);
}

enum _StepState { waiting, active, done }

class _StepLine extends StatelessWidget {
  const _StepLine({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final tone = switch (state) {
      _StepState.done => SportikaColors.mint,
      _StepState.active => SportikaColors.blueBright,
      _StepState.waiting => SportikaColors.textDim,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Icon(
            switch (state) {
              _StepState.done => Icons.check_circle,
              _StepState.active => Icons.sync,
              _StepState.waiting => Icons.circle_outlined,
            },
            size: 14,
            color: tone,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: state == _StepState.done
                    ? FontWeight.w600
                    : FontWeight.w500,
                color: state == _StepState.waiting
                    ? SportikaColors.textDim
                    : SportikaColors.textBody,
              ),
            ),
          ),
          if (state == _StepState.active)
            Text(
              'CHECKING',
              style: authDisplay(
                8.5,
                color: SportikaColors.blueBright,
                letterSpacing: 1.4,
              ),
            ),
        ],
      ),
    );
  }
}
