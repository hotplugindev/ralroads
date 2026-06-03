import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ors_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.settings, super.key});

  final SettingsService settings;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final _signUpUri = Uri.parse('https://openrouteservice.org/sign-up/');
  static final _dashboardUri = Uri.parse('https://api.openrouteservice.org/');

  late final TextEditingController _controller;
  late final OrsService _orsService;
  bool _obscureKey = true;
  bool _testing = false;
  String _status = 'No API key saved';

  @override
  void initState() {
    super.initState();
    _orsService = OrsService(settings: widget.settings);
    _controller = TextEditingController(
      text: widget.settings.getOrsApiKey() ?? '',
    );
    _status = widget.settings.hasOrsApiKey()
        ? 'API key saved'
        : 'No API key saved';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSavedKey = widget.settings.hasOrsApiKey();
    final usingDevelopmentKey = widget.settings.isUsingDevelopmentKey;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'OpenRouteService API Key',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'API key',
              suffixIcon: IconButton(
                tooltip: _obscureKey ? 'Show key' : 'Hide key',
                onPressed: () {
                  setState(() {
                    _obscureKey = !_obscureKey;
                  });
                },
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(_status),
          if (usingDevelopmentKey) ...[
            const SizedBox(height: 8),
            const Text('Using development API key from build configuration.'),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: _saveKey,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: _testing ? null : _testKey,
                icon: _testing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Test Key'),
              ),
              TextButton.icon(
                onPressed: hasSavedKey ? _deleteKey : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Key'),
              ),
            ],
          ),
          if (!hasSavedKey) ...[
            const SizedBox(height: 24),
            const Text('Need a free OpenRouteService key? Create one here:'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _openLink(_signUpUri),
                child: const Text('https://openrouteservice.org/sign-up/'),
              ),
            ),
          ],
          if (hasSavedKey) ...[
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _openLink(_dashboardUri),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('OpenRouteService dashboard'),
              ),
            ),
          ],
          const SizedBox(height: 32),
          Text('Road warnings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show speed limits'),
            value: widget.settings.showSpeedLimits,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowSpeedLimits(value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show traffic lights'),
            value: widget.settings.showTrafficLights,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowTrafficLights(value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show stop/give-way signs'),
            value: widget.settings.showStopGiveWay,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowStopGiveWay(value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show speed bumps'),
            value: widget.settings.showSpeedBumps,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowSpeedBumps(value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Show surface, tunnel, bridge, and roundabout warnings',
            ),
            value: widget.settings.showRoadFeatures,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowRoadFeatures(value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show speed camera warnings'),
            subtitle: const Text(
              'Speed camera warnings may be restricted in some countries. Use only where legal.',
            ),
            value: widget.settings.showSpeedCameras,
            onChanged: (value) => _setWarningSetting(
              () => widget.settings.setShowSpeedCameras(value),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveKey() async {
    await widget.settings.saveOrsApiKey(_controller.text);
    _refreshStatus(
      status: widget.settings.hasOrsApiKey()
          ? 'API key saved'
          : 'No API key saved',
    );
  }

  Future<void> _testKey() async {
    final key = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : widget.settings.getEffectiveOrsApiKey();

    if (key == null) {
      _refreshStatus(status: 'No API key saved');
      return;
    }

    setState(() {
      _testing = true;
    });

    try {
      final works = await _orsService.validateApiKey(key);
      _refreshStatus(status: works ? 'API key works' : 'API key rejected');
    } on OrsNetworkException {
      _refreshStatus(status: 'Network error while testing key');
    } catch (_) {
      _refreshStatus(status: 'API key rejected');
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  Future<void> _deleteKey() async {
    await widget.settings.deleteOrsApiKey();
    _controller.clear();
    _refreshStatus(status: 'No API key saved');
  }

  Future<void> _openLink(Uri uri) async {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _refreshStatus({String? status}) {
    setState(() {
      _status =
          status ??
          (widget.settings.hasOrsApiKey()
              ? 'API key saved'
              : 'No API key saved');
    });
  }

  Future<void> _setWarningSetting(Future<void> Function() update) async {
    await update();
    if (mounted) {
      setState(() {});
    }
  }
}
