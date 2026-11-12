import 'package:flutter/foundation.dart';

import 'package:sportika/core/data/local_sportika_repository.dart';

/// Base for every feature controller.
///
/// Controllers are the only thing the UI depends on. They rebuild whenever the
/// repository document changes. Reads currently delegate straight to the local
/// repository because local mutations are synchronous; when a remote repository
/// replaces it, this is the layer that gains loading and error state without
/// screens changing.
abstract class FeatureController extends ChangeNotifier {
  FeatureController(this.repo) {
    repo.addListener(_onRepositoryChanged);
  }

  @protected
  final LocalSportikaRepository repo;

  void _onRepositoryChanged() => notifyListeners();

  @override
  void dispose() {
    repo.removeListener(_onRepositoryChanged);
    super.dispose();
  }
}
