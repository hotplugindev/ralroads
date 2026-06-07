import 'package:flutter/material.dart';

import '../controllers/app_session_controller.dart';
import '../widgets/product_components.dart';

class MatrixConnectionScreen extends StatefulWidget {
  const MatrixConnectionScreen({required this.controller, super.key});

  final AccountConnectionController controller;

  @override
  State<MatrixConnectionScreen> createState() => _MatrixConnectionScreenState();
}

class _MatrixConnectionScreenState extends State<MatrixConnectionScreen> {
  final _homeserver = TextEditingController(text: 'https://matrix.org');
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _homeserver.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return RalRoadsPage(
            title: 'Connect Matrix',
            children: [
              const EmptyState(
                icon: Icons.hub_outlined,
                title: 'Matrix powers RalRoads community',
                message:
                    'Friends, groups, shared challenges, sync and moderation use your Matrix homeserver. Offline navigation and local trips work without it.',
              ),
              TextField(
                controller: _homeserver,
                decoration: const InputDecoration(
                  labelText: 'Homeserver',
                  prefixIcon: Icon(Icons.dns_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Matrix username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.controller.message != null)
                StatusChip(label: widget.controller.message!),
              FilledButton.icon(
                onPressed: widget.controller.busy ? null : _connect,
                icon: widget.controller.busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Connect Matrix'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _connect() async {
    await widget.controller.connectMatrix(
      homeserver: Uri.parse(_homeserver.text.trim()),
      username: _username.text.trim(),
      password: _password.text,
    );
  }
}
