import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_session_controller.dart';
import '../repositories/app_repositories.dart';
import '../repositories/profile_repository.dart';
import '../services/ors_service.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';

// ─── Entry point ────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.storage,
    required this.settings,
    required this.session,
    required this.accountController,
    required this.repositories,
    super.key,
  });

  final RouteStorageService storage;
  final SettingsService settings;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final AppRepositories repositories;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  int _currentPage = 0;
  static const int _totalPages = 5;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _next() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentPage < _totalPages - 1) {
      setState(() => _currentPage += 1);
    }
  }

  void _prev() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentPage > 0) {
      setState(() => _currentPage -= 1);
    }
  }

  void _finish() => widget.session.completeOnboarding();

  Widget _currentStep() {
    return switch (_currentPage) {
      0 => _WelcomePage(onNext: _next, onSkip: _finish),
      1 => _OrsKeyPage(settings: widget.settings, onNext: _next),
      2 => _ProfilePage(repositories: widget.repositories, onNext: _next),
      3 => _MatrixPage(
        accountController: widget.accountController,
        session: widget.session,
        onNext: _next,
      ),
      _ => _ReadyPage(onFinish: _finish),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: scheme.surface,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth >= 700 ? 560.0 : null;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxWidth ?? double.infinity,
                          ),
                          child: _OnboardingProgress(
                            current: _currentPage,
                            total: _totalPages,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          24,
                          8,
                          24,
                          24 + keyboardBottom,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: maxWidth ?? double.infinity,
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: KeyedSubtree(
                                key: ValueKey<int>(_currentPage),
                                child: _currentStep(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _OnboardingNav(
                      current: _currentPage,
                      total: _totalPages,
                      keyboardVisible: keyboardBottom > 0,
                      onBack: _currentPage > 0 ? _prev : null,
                      onSkip: _currentPage < _totalPages - 1 ? _finish : null,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Progress indicator ──────────────────────────────────────────────────────

class _OnboardingProgress extends StatelessWidget {
  const _OnboardingProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(total, (i) {
        final active = i == current;
        final done = i < current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(right: 6),
          height: 4,
          width: active ? 32 : 16,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: done
                ? scheme.primary
                : active
                ? scheme.primary
                : scheme.outlineVariant,
          ),
        );
      }),
    );
  }
}

// ─── Bottom navigation row ───────────────────────────────────────────────────

class _OnboardingNav extends StatelessWidget {
  const _OnboardingNav({
    required this.current,
    required this.total,
    required this.keyboardVisible,
    this.onBack,
    this.onSkip,
  });

  final int current;
  final int total;
  final bool keyboardVisible;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    if (current == 0 || current == total - 1) return const SizedBox(height: 12);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          if (onBack != null)
            TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left),
              label: const Text('Back'),
            )
          else
            const SizedBox.shrink(),
          if (onSkip != null)
            TextButton(onPressed: onSkip, child: const Text('Skip setup')),
          if (keyboardVisible)
            IconButton(
              tooltip: 'Hide keyboard',
              onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
              icon: const Icon(Icons.keyboard_hide_outlined),
            ),
        ],
      ),
    );
  }
}

// ─── Page 0 — Welcome ────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onNext, required this.onSkip});

  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(
                Icons.add_road,
                size: 56,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'RalRoads',
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Your pocket co-driver.\nNavigation, road-aware callouts,\nlocal trips and clean challenge attempts.',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Get started', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onSkip,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Use offline without setup'),
          ),
        ],
      ),
    );
  }
}

// ─── Page 1 — ORS API Key ────────────────────────────────────────────────────

class _OrsKeyPage extends StatefulWidget {
  const _OrsKeyPage({required this.settings, required this.onNext});

  final SettingsService settings;
  final VoidCallback onNext;

  @override
  State<_OrsKeyPage> createState() => _OrsKeyPageState();
}

class _OrsKeyPageState extends State<_OrsKeyPage> {
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  String? _statusMsg;
  bool? _statusOk;

  @override
  void initState() {
    super.initState();
    final existing = widget.settings.getOrsApiKey();
    if (existing != null) {
      _controller.text = existing;
      _statusMsg = 'API key saved';
      _statusOk = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) return;
    await widget.settings.saveOrsApiKey(key);
    setState(() {
      _statusMsg = 'API key saved';
      _statusOk = true;
    });
  }

  Future<void> _test() async {
    final key = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : widget.settings.getEffectiveOrsApiKey();
    if (key == null) {
      setState(() {
        _statusMsg = 'Enter a key first';
        _statusOk = false;
      });
      return;
    }
    setState(() {
      _testing = true;
      _statusMsg = 'Testing…';
      _statusOk = null;
    });
    try {
      final ors = OrsService(settings: widget.settings);
      final ok = await ors.validateApiKey(key);
      if (ok) await widget.settings.saveOrsApiKey(key);
      if (mounted) {
        setState(() {
          _statusMsg = ok ? 'Key works — saved!' : 'Key rejected by ORS';
          _statusOk = ok;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMsg = 'Network error — try again';
          _statusOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasKey = widget.settings.hasEffectiveOrsApiKey();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.route_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Route planning',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a free OpenRouteService API key to enable online route planning and place search. '
            'RalRoads stores only your key — never a password.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autocorrect: false,
            scrollPadding: const EdgeInsets.all(96),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.key),
              labelText: 'ORS API Key',
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show' : 'Hide',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              ),
            ),
          ),
          if (_statusMsg != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  _statusOk == true
                      ? Icons.check_circle
                      : _statusOk == false
                      ? Icons.error_outline
                      : Icons.info_outline,
                  size: 16,
                  color: _statusOk == true
                      ? Colors.green
                      : _statusOk == false
                      ? scheme.error
                      : scheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  _statusMsg!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _statusOk == true
                        ? Colors.green
                        : _statusOk == false
                        ? scheme.error
                        : scheme.primary,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Test & Save'),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: hasKey ? null : scheme.secondary,
            ),
            child: Text(
              hasKey ? 'Continue' : 'Skip for now',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => launchUrl(
              Uri.parse('https://openrouteservice.org/sign-up/'),
              mode: LaunchMode.externalApplication,
            ),
            child: const Text('Get a free key at openrouteservice.org'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Page 2 — Profile ────────────────────────────────────────────────────────

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({required this.repositories, required this.onNext});

  final AppRepositories repositories;
  final VoidCallback onNext;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  final _nameController = TextEditingController(text: 'Local driver');
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await widget.repositories.profiles.createOrUpdateLocalProfile(
      LocalProfileInput(id: 'local-profile', displayName: name),
    );
    if (mounted) {
      setState(() {
        _saving = false;
        _saved = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.person_outline, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Your profile',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a local profile to label your trips and segments. '
            'This is stored only on your device.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            scrollPadding: const EdgeInsets.all(96),
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.drive_file_rename_outline),
              labelText: 'Display name',
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _saved ? Icons.check_circle : Icons.save_outlined,
                    size: 18,
                  ),
            label: Text(_saved ? 'Saved!' : 'Save profile'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Page 3 — Matrix ─────────────────────────────────────────────────────────

class _MatrixPage extends StatefulWidget {
  const _MatrixPage({
    required this.accountController,
    required this.session,
    required this.onNext,
  });

  final AccountConnectionController accountController;
  final AppSessionController session;
  final VoidCallback onNext;

  @override
  State<_MatrixPage> createState() => _MatrixPageState();
}

class _MatrixPageState extends State<_MatrixPage> {
  final _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _autoAdvanced = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_maybeAdvance);
    widget.accountController.addListener(_maybeAdvance);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAdvance());
  }

  @override
  void dispose() {
    widget.session.removeListener(_maybeAdvance);
    widget.accountController.removeListener(_maybeAdvance);
    _homeserverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _maybeAdvance() {
    if (_autoAdvanced || !mounted) return;
    final connected =
        widget.session.snapshot.matrixStatus ==
            MatrixConnectionStatus.connected ||
        widget.session.snapshot.matrixStatus == MatrixConnectionStatus.syncing;
    if (!connected || widget.accountController.busy) return;
    _autoAdvanced = true;
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) widget.onNext();
    });
  }

  Future<void> _connect() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final homeserverText = _homeserverController.text.trim();
    if (homeserverText.isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter homeserver, Matrix ID and password.'),
        ),
      );
      return;
    }
    await widget.accountController.connectMatrix(
      homeserverInput: homeserverText,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.hub_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(
            'Social & sync',
            style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect a Matrix account to enable friends, groups, shared challenges, '
            'federated leaderboards and cross-device sync.\n\n'
            'RalRoads does not operate this account service — you bring your own.',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          _FeatureBullet(icon: Icons.people_outline, label: 'Friends & groups'),
          _FeatureBullet(
            icon: Icons.emoji_events_outlined,
            label: 'Shared challenges',
          ),
          _FeatureBullet(icon: Icons.sync, label: 'Cross-device trip sync'),
          _FeatureBullet(
            icon: Icons.leaderboard_outlined,
            label: 'Federated leaderboards',
          ),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: Listenable.merge([
              widget.session,
              widget.accountController,
            ]),
            builder: (context, _) {
              final connected =
                  widget.session.snapshot.matrixStatus ==
                  MatrixConnectionStatus.connected;
              if (connected) {
                return _ConnectedBanner(
                  matrixUserId:
                      widget.session.snapshot.matrixSession?.matrixUserId,
                  syncing: widget.session.syncService.isRunning,
                  onNext: widget.onNext,
                );
              }
              final message = widget.accountController.message;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _homeserverController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    scrollPadding: const EdgeInsets.all(96),
                    decoration: InputDecoration(
                      labelText: 'Homeserver',
                      prefixIcon: const Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    scrollPadding: const EdgeInsets.all(96),
                    decoration: InputDecoration(
                      labelText: 'Matrix ID or username',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        widget.accountController.busy ? null : _connect(),
                    scrollPadding: const EdgeInsets.all(120),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    _InlineStatus(
                      label: message,
                      error: !message.startsWith('Connected as'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: widget.accountController.busy ? null : _connect,
                    icon: widget.accountController.busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: const Text(
                      'Connect Matrix',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: widget.onNext,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Skip — use offline'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InlineStatus extends StatelessWidget {
  const _InlineStatus({required this.label, required this.error});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(
          error ? Icons.error_outline : Icons.check_circle_outline,
          size: 18,
          color: error ? scheme.error : Colors.green,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: error ? scheme.error : Colors.green,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  const _FeatureBullet({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

class _ConnectedBanner extends StatelessWidget {
  const _ConnectedBanner({
    required this.onNext,
    required this.syncing,
    this.matrixUserId,
  });

  final VoidCallback onNext;
  final bool syncing;
  final String? matrixUserId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 10),
              Text(
                'Matrix connected!',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              if (matrixUserId != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    matrixUserId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (syncing) ...[
          const SizedBox(height: 8),
          Text(
            'Community data is syncing in the background.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: onNext,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text('Continue', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}

// ─── Page 4 — Ready ──────────────────────────────────────────────────────────

class _ReadyPage extends StatelessWidget {
  const _ReadyPage({required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.15),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 60,
                color: Colors.green,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            "You're ready!",
            style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Open the map, plan a route, and start your first drive.\n\n'
            'Trips are private by default — nothing leaves your device unless you share it.',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onFinish,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Start driving',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
