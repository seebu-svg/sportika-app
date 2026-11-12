import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/shared/theme/theme.dart';
import 'package:sportika/shared/models/enums.dart';
import 'package:sportika/shared/state/app_state.dart';
import 'package:sportika/shared/widgets/widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final me = context.read<AppState>().currentAccount;
    _name = TextEditingController(text: me?.displayName ?? '');
    _city = TextEditingController(text: me?.city ?? '');
    _email = TextEditingController(text: me?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentAccount;

    return Scaffold(
      appBar: sportikaAppBar('Edit profile'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
        children: [
          if (me != null) Center(child: AccountAvatar(account: me, size: 74)),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'City'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          if (me != null) ...[
            const SectionTitle('Roles'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final role in me.roles)
                  StatusPill(role.label, color: SportikaColors.blueBright),
              ],
            ),
            const SizedBox(height: 8),
            const InfoBanner(
              icon: Icons.lock_outline,
              text:
                  'Roles are fixed for the prototype. Organizer tools unlock as soon '
                  'as an account carries the organizer role.',
            ),
          ],
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Save changes',
            icon: Icons.check,
            onPressed: () {
              state.updateProfile(
                displayName: _name.text,
                city: _city.text.trim(),
                email: _email.text.trim(),
              );
              showSnack(context, 'Profile updated');
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }
}
