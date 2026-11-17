import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sportika/app/env.dart';
import 'package:sportika/core/data/module_media_store.dart';
import 'package:sportika/shared/widgets/widgets.dart';

/// Resolves an existing team logo through the same media store as Team detail.
class TeamMatchLogo extends StatefulWidget {
  const TeamMatchLogo({
    super.key,
    this.teamId,
    required this.name,
    required this.size,
    required this.color,
  });
  final String? teamId;
  final String name;
  final double size;
  final Color color;
  @override
  State<TeamMatchLogo> createState() => _TeamMatchLogoState();
}

class _TeamMatchLogoState extends State<TeamMatchLogo> {
  String? _url;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TeamMatchLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamId != widget.teamId) {
      _url = null;
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.teamId;
    if (id == null || !AppEnv.hasSupabase || AppEnv.demoMode) return;
    try {
      final client = Supabase.instance.client;
      final path = await ModuleMediaStore(client)
          .path('team-media', id, 'logo');
      if (mounted && id == widget.teamId && path != null) {
        setState(
          () => _url = client.storage.from('team-media').getPublicUrl(path),
        );
      }
    } catch (_) {
      /* Keep the established initials fallback while offline. */
    }
  }

  @override
  Widget build(BuildContext context) => PlayerAvatar(
    initials: initialsOf(widget.name),
    color: widget.color,
    size: widget.size,
    photoUrl: _url,
  );
}
