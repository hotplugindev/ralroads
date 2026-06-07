import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/app_session_controller.dart';
import '../repositories/app_repositories.dart';
import '../repositories/profile_repository.dart';
import '../services/ors_service.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import 'matrix_connection_screen.dart';

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
  final PageController _pageController = PageController();
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
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _prev() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _finish() => widget.session.completeOnboarding();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // ── Progress bar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: _OnboardingProgress(
                  current: _currentPage,
                  total: _totalPages,
                ),
              ),
              // ── Pages ──
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  children: [
                    _WelcomePage(onNext: _next, onSkip: _finish),
                    _OrsKeyPage(settings: widget.settings, onNext: _next),
                    _ProfilePage(
                      repositories: widget.repositories,
                      onNext: _next,
                    ),
                    _MatrixPage(
                      accountController: widget.accountController,
                      session: widget.session,
                      onNext: _next,
                    ),
                    _ReadyPage(onFinish: _finish),
                  ],
                ),
              ),
              // ── Bottom nav row ──
              _OnboardingNav(
                current: _currentPage,
                total: _totalPages,
                onBack: _currentPage > 0 ? _prev : null,
                onSkip: _currentPage < _totalPages - 1 ? _finish : null,
              ),
            ],
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
    this.onBack,
    this.onSkip,
  });

  final int current;
  final int total;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    if (current == 0 || current == total - 1) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
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
          const Spacer(flex: 2),
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
          const Spacer(),
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
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
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
          const Spacer(),
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
    if (mounted)
      setState(() {
        _saving = false;
        _saved = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
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
          const Spacer(),
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

class _MatrixPage extends StatelessWidget {
  const _MatrixPage({
    required this.accountController,
    required this.session,
    required this.onNext,
  });

  final AccountConnectionController accountController;
  final AppSessionController session;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
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
          const Spacer(),
          ListenableBuilder(
            listenable: session,
            builder: (context, _) {
              final connected =
                  session.snapshot.matrixStatus ==
                  MatrixConnectionStatus.connected;
              if (connected) {
                return _ConnectedBanner(onNext: onNext);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MatrixConnectionScreen(
                          controller: accountController,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.login),
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
                    onPressed: onNext,
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
          Text(label, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ConnectedBanner extends StatelessWidget {
  const _ConnectedBanner({required this.onNext});
  final VoidCallback onNext;

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
            ],
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),
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
          const Spacer(flex: 2),
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
          const Spacer(),
        ],
      ),
    );
  }
}
