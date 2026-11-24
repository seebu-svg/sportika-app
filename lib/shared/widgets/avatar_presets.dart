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
    SportikaGradients.avatarMidnight,
    SportikaColors.onAccent,
  ),
  AvatarOption(
    'mint',
    'Mint',
    SportikaGradients.avatarMint,
    SportikaColors.onMint,
  ),
  AvatarOption(
    'gold',
    'Gold',
    SportikaGradients.avatarGold,
    SportikaColors.onMint,
  ),
  AvatarOption(
    'court',
    'Court',
    SportikaGradients.avatarCourt,
    SportikaColors.onMint,
  ),
  AvatarOption(
    'ember',
    'Ember',
    SportikaGradients.avatarEmber,
    SportikaColors.onAccent,
  ),
  AvatarOption(
    'dusk',
    'Dusk',
    SportikaGradients.avatarDusk,
    SportikaColors.onMint,
  ),
];

AvatarOption avatarOptionFor(String id) => avatarOptions.firstWhere(
  (option) => option.id == id,
  orElse: () => avatarOptions.first,
);
