import 'package:flutter/material.dart';

import '../controllers/app_session_controller.dart';
import '../controllers/driving_session_controller.dart';
import '../controllers/matrix_social_controller.dart';
import '../repositories/app_repositories.dart';
import '../services/route_storage_service.dart';
import '../services/settings_service.dart';
import '../screens/onboarding_screen.dart';

import '../features/navigate/screens/navigate_screen.dart';
import '../features/trips/screens/trips_screen.dart';
import '../features/challenges/screens/challenges_screen.dart';
import '../features/community/screens/community_screen.dart';
import 'settings_tab.dart';
import 'active_session_bar.dart';
import 'root_navigation_controller.dart';

class RalRoadsAppShell extends StatefulWidget {
  RalRoadsAppShell({
    required this.storage,
    required this.settings,
    required this.repositories,
    required this.session,
    required this.accountController,
    required this.drivingSession,
    super.key,
  }) : socialController = MatrixSocialController(
          repositories: repositories,
          clientService: session.syncService.matrixAccount.clientService,
          syncService: session.syncService,
        );

  final RouteStorageService storage;
  final SettingsService settings;
  final AppRepositories repositories;
  final AppSessionController session;
  final AccountConnectionController accountController;
  final DrivingSessionController drivingSession;
  final MatrixSocialController socialController;

  @override
  State<RalRoadsAppShell> createState() => _RalRoadsAppShellState();
}

class _RalRoadsAppShellState extends State<RalRoadsAppShell> {
  late final RootNavigationController _navController;

  @override
  void initState() {
    super.initState();
    _navController = RootNavigationController();
    widget.session.load();
  }

  @override
  void dispose() {
    _navController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (!widget.session.snapshot.onboardingComplete) {
          return OnboardingScreen(
            storage: widget.storage,
            settings: widget.settings,
            session: widget.session,
            accountController: widget.accountController,
            repositories: widget.repositories,
          );
        }

        final tabs = [
          NavigateScreen(
            storage: widget.storage,
            settings: widget.settings,
            repositories: widget.repositories,
            session: widget.session,
            accountController: widget.accountController,
            drivingSession: widget.drivingSession,
          ),
          ChallengesScreen(
            repositories: widget.repositories,
            session: widget.session,
            socialController: widget.socialController,
            accountController: widget.accountController,
            settings: widget.settings,
          ),
          TripsScreen(
            repositories: widget.repositories,
            settings: widget.settings,
          ),
          CommunityScreen(
            repositories: widget.repositories,
            session: widget.session,
            accountController: widget.accountController,
            socialController: widget.socialController,
          ),
          SettingsTab(
            storage: widget.storage,
            settings: widget.settings,
            session: widget.session,
            accountController: widget.accountController,
          ),
        ];

        final destinations = const [
          NavigationDestination(
            icon: Icon(Icons.navigation),
            label: 'Navigate',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            label: 'Challenges',
          ),
          NavigationDestination(icon: Icon(Icons.timeline), label: 'Trips'),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            label: 'Community',
          ),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ];

        return ListenableBuilder(
          listenable: _navController,
          builder: (context, _) {
            final index = _navController.currentIndex;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 800) {
                  return Scaffold(
                    body: Row(
                      children: [
                        NavigationRail(
                          selectedIndex: index,
                          onDestinationSelected: _navController.setIndex,
                          labelType: NavigationRailLabelType.all,
                          destinations: const [
                            NavigationRailDestination(
                              icon: Icon(Icons.navigation),
                              label: Text('Navigate'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.emoji_events_outlined),
                              label: Text('Challenges'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.timeline),
                              label: Text('Trips'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.groups_outlined),
                              label: Text('Community'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(Icons.settings),
                              label: Text('Settings'),
                            ),
                          ],
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(
                                child: IndexedStack(
                                  index: index,
                                  children: tabs,
                                ),
                              ),
                              ActiveSessionBar(
                                drivingSession: widget.drivingSession,
                                settings: widget.settings,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: IndexedStack(
                          index: index,
                          children: tabs,
                        ),
                      ),
                      ActiveSessionBar(
                        drivingSession: widget.drivingSession,
                        settings: widget.settings,
                      ),
                    ],
                  ),
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: index,
                    destinations: destinations,
                    onDestinationSelected: _navController.setIndex,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
