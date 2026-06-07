import 'package:flutter/material.dart';

class RalRoadsPage extends StatelessWidget {
  const RalRoadsPage({
    required this.title,
    required this.children,
    this.actions = const [],
    super.key,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(title),
            actions: actions,
            floating: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.separated(
              itemBuilder: (context, index) => children[index],
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemCount: children.length,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, this.icon, this.color, super.key});

  final String label;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.primary;
    return Chip(
      avatar: icon == null ? null : Icon(icon, size: 16, color: effectiveColor),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: effectiveColor.withValues(alpha: 0.35)),
      backgroundColor: effectiveColor.withValues(alpha: 0.10),
      labelStyle: TextStyle(color: scheme.onSurface),
    );
  }
}

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.trailing,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ListTile(
        minTileHeight: 64,
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    required this.title,
    required this.status,
    required this.icon,
    required this.actionLabel,
    required this.onAction,
    this.description,
    super.key,
  });

  final String title;
  final String status;
  final String? description;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusChip(label: status),
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(description!),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(message),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({this.label = 'Loading', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: 'Something needs attention',
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    );
  }
}

class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return StatusChip(icon: Icons.sync, label: label);
  }
}

class PrimaryActionCard extends StatelessWidget {
  const PrimaryActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onPressed,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class RouteCard extends FeatureCard {
  const RouteCard({
    required super.title,
    required super.subtitle,
    super.onTap,
    super.trailing,
    super.key,
  }) : super(icon: Icons.route);
}

class TripCard extends FeatureCard {
  const TripCard({
    required super.title,
    required super.subtitle,
    super.onTap,
    super.trailing,
    super.key,
  }) : super(icon: Icons.timeline);
}

class SegmentCard extends FeatureCard {
  const SegmentCard({
    required super.title,
    required super.subtitle,
    super.onTap,
    super.trailing,
    super.key,
  }) : super(icon: Icons.linear_scale);
}

class ChallengeCard extends FeatureCard {
  const ChallengeCard({
    required super.title,
    required super.subtitle,
    super.onTap,
    super.trailing,
    super.key,
  }) : super(icon: Icons.emoji_events_outlined);
}

class AttemptStatusBadge extends StatelessWidget {
  const AttemptStatusBadge({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'valid_clean' || 'finished' => Colors.green,
      'invalid_speed_limit' || 'invalid_route_mismatch' => Colors.red,
      'suspicious' => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    return StatusChip(label: status.replaceAll('_', ' '), color: color);
  }
}
