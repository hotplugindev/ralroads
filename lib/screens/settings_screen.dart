import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ors_service.dart';
import '../services/settings_service.dart';
import '../services/route_storage_service.dart';
import 'offline_maps_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.storage,
    required this.settings,
    super.key,
  });

  final RouteStorageService storage;
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_key_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'OPENROUTESERVICE API KEY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.key),
                      labelText: 'API Key',
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
                  Text(
                    _status,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (usingDevelopmentKey) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Using development API key from build configuration.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _saveKey,
                        icon: const Icon(Icons.save, size: 18),
                        label: const Text('Save'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _testing ? null : _testKey,
                        icon: _testing
                            ? const SizedBox.square(
                                dimension: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Test Key'),
                      ),
                      if (hasSavedKey)
                        TextButton.icon(
                          onPressed: _deleteKey,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete Key'),
                        ),
                    ],
                  ),
                  if (!hasSavedKey) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Need a free API key?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _openLink(_signUpUri),
                        child: const Text('Sign up at openrouteservice.org'),
                      ),
                    ),
                  ],
                  if (hasSavedKey) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => _openLink(_dashboardUri),
                        icon: const Icon(Icons.open_in_browser, size: 16),
                        label: const Text('OpenRouteService dashboard'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'ROAD WARNINGS VISIBILITY',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildSwitchRow(
                  context,
                  icon: Icons.speed,
                  title: 'Show speed limits',
                  value: widget.settings.showSpeedLimits,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowSpeedLimits(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.traffic,
                  title: 'Show traffic lights',
                  value: widget.settings.showTrafficLights,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowTrafficLights(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.signpost_outlined,
                  title: 'Show stop/give-way signs',
                  value: widget.settings.showStopGiveWay,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowStopGiveWay(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.waves,
                  title: 'Show speed bumps',
                  value: widget.settings.showSpeedBumps,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowSpeedBumps(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.category_outlined,
                  title: 'Show road features',
                  subtitle: 'Surface, tunnels, bridges, roundabouts',
                  value: widget.settings.showRoadFeatures,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowRoadFeatures(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.camera_alt_outlined,
                  title: 'Show speed camera warnings',
                  subtitle: 'Use only where legally permitted',
                  value: widget.settings.showSpeedCameras,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setShowSpeedCameras(value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.record_voice_over_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'PACENOTE DETAIL LEVEL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<PacenoteStyle>(
                        segments: const [
                          ButtonSegment<PacenoteStyle>(
                            value: PacenoteStyle.calm,
                            icon: Icon(Icons.volume_mute),
                            label: Text('Calm'),
                          ),
                          ButtonSegment<PacenoteStyle>(
                            value: PacenoteStyle.balanced,
                            icon: Icon(Icons.volume_down),
                            label: Text('Balanced'),
                          ),
                          ButtonSegment<PacenoteStyle>(
                            value: PacenoteStyle.rally,
                            icon: Icon(Icons.volume_up),
                            label: Text('Rally'),
                          ),
                        ],
                        selected: {widget.settings.pacenoteStyle},
                        onSelectionChanged: (Set<PacenoteStyle> selection) async {
                          await widget.settings.setPacenoteStyle(selection.first);
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        switch (widget.settings.pacenoteStyle) {
                          PacenoteStyle.calm =>
                            'Filters minor curves (only alerts for severe curves). Reduced co-driver verbal warnings for a quieter drive.',
                          PacenoteStyle.balanced =>
                            'Standard curve detection. Alerts for all typical turns and hazards.',
                          PacenoteStyle.rally =>
                            'Extremely detailed rally-style pacenotes. Alerts for all bends, micro-corners, and slight curves.',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.explore_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'MAP VIEW SETTINGS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildSwitchRow(
                  context,
                  icon: Icons.navigation_outlined,
                  title: 'Heading-up map orientation',
                  subtitle: 'Rotate map in driving direction. If disabled, map remains North-up.',
                  value: widget.settings.mapHeadingUp,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setMapHeadingUp(value),
                  ),
                ),
                _buildDivider(theme),
                _buildSwitchRow(
                  context,
                  icon: Icons.map_outlined,
                  title: 'Use new black map style',
                  subtitle: 'If disabled, use the old simple map style',
                  value: widget.settings.useCleanMap,
                  onChanged: (value) => _setWarningSetting(
                    () => widget.settings.setUseCleanMap(value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OfflineMapsScreen(
                      storage: widget.storage,
                      settings: widget.settings,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.offline_pin_outlined, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Offline Maps Manager',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Manage cached regions and download maps for saved routes',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 64,
      endIndent: 16,
      color: theme.colorScheme.outlineVariant.withOpacity(0.3),
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
