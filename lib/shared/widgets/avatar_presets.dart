import 'package:flutter/material.dart';

import 'package:sportika/shared/theme/theme.dart';

/// Gradient avatars stand in for photo uploads, which the prototype has no
/// storage for. The id is persisted on the account, so every avatar in the app
/// can render the same choice.
class AvatarOption {
  const AvatarOption(this.id, this.label, this.colors, this.ink);

  final String id;
  final String label;
  final List<Color> colors;
  final Color ink;
}

const List<AvatarOption> avatarOptions = [
  AvatarOption(
    'midnight',
    'Midnight',
    [Color(0xFF2E7DFF), Color(0xFF0B1D33)],
    Colors.white,
  ),
  AvatarOption(
    'mint',
    'Mint',
    [Color(0xFF36D8BD), Color(0xFF0A6C60)],
    SportikaColors.deepest,
  ),
  AvatarOption(
    'gold',
    'Gold',
    [Color(0xFFF6B84B), Color(0xFF9A5E0C)],
    SportikaColors.deepest,
  ),
  AvatarOption(
    'court',
    'Court',
    [Color(0xFF2E7DFF), Color(0xFF36D8BD)],
    SportikaColors.deepest,
  ),
  AvatarOption(
    'ember',
    'Ember',
    [Color(0xFFE85A66), Color(0xFF5C1018)],
    Colors.white,
  ),
  AvatarOption(
    'dusk',
    'Dusk',
    [Color(0xFFA8B8CF), Color(0xFF233A54)],
    SportikaColors.deepest,
  ),
];

AvatarOption avatarOptionFor(String id) => avatarOptions.firstWhere(
  (option) => option.id == id,
  orElse: () => avatarOptions.first,
);
