import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/payments/payment_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/billing.dart';
import '../../data/models/vehicle.dart';
import '../../providers/auth_provider.dart';
import '../../providers/core_providers.dart';
import '../../providers/fleet_provider.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/glass_card.dart';

/// Renewal checkout.
///
/// Flow: pick plan → [PaymentService.pay] (currently the dummy gateway) →
/// `POST /api/billing/renewal/verify` → refresh the fleet so the new expiry
/// date is reflected everywhere.
///
/// The client treats only the *verify* response as proof of renewal.
class RenewalCheckoutSheet extends ConsumerStatefulWidget {
  const RenewalCheckoutSheet({required this.vehicle, super.key});

  final Vehicle vehicle;

  @override
  ConsumerState<RenewalCheckoutSheet> createState() =>
      _RenewalCheckoutSheetState();
}

enum _Stage { loading,selecting, processing, success, failed }

class _RenewalCheckoutSheetState extends ConsumerState<RenewalCheckoutSheet> {
  List<RenewalPlan> _plans = <RenewalPlan>[];
  VehiclePrice? _price;
  RenewalPlan? _selected;

  _Stage _stage = _Stage.loading;
  String? _error;
  RenewalRecord? _record;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });

    try {
      final List<RenewalPlan> plans =
          await ref.read(billingRepositoryProvider).getPlans();

      VehiclePrice? price;
      try {
        price = await ref
            .read(billingRepositoryProvider)
            .getVehiclePrice(widget.vehicle.id);
      } on ApiException {
        price = null; // optional endpoint
      }

      if (!mounted) return;
      setState(() {
        _plans = plans;
        _price = price;
        _selected = plans.isEmpty
            ? null
            : plans.firstWhere(
                (RenewalPlan p) => p.isPopular,
                orElse: () => plans.first,
              );
        _stage = _Stage.selecting;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = _Stage.failed;
      });
    }
  }

  double get _amount {
    if (_selected == null) return _price?.total ?? 0;
    if (_price != null && _price!.amount > 0) {
      // Server-quoted price scales by plan duration.
      return _price!.total * (_selected!.durationMonths / 12);
    }
    return _selected!.price;
  }

  Future<void> _pay() async {
    final RenewalPlan? plan = _selected;
    if (plan == null) return;

    setState(() {
      _stage = _Stage.processing;
      _error = null;
    });

    try {
      final PaymentService gateway = ref.read(paymentServiceProvider);
      await gateway.initialize();

      final AppUserSnapshot user = AppUserSnapshot(ref);

      final PaymentResult result = await gateway.pay(
        PaymentRequest(
          amount: _amount,
          currency: _price?.currency ?? 'INR',
          vehicleId: widget.vehicle.id,
          planId: plan.id,
          description:
              '${plan.durationLabel} renewal — ${widget.vehicle.displayName}',
          customerName: user.name,
          customerEmail: user.email,
          customerPhone: user.phone,
        ),
      );

      if (!result.isSuccess) {
        if (!mounted) return;
        setState(() {
          _stage = _Stage.failed;
          _error = result.message ?? 'Payment was not completed.';
        });
        return;
      }

      // Server-side verification is the only source of truth.
      final RenewalRecord record =
          await ref.read(billingRepositoryProvider).verifyRenewal(
                payment: result,
                vehicleId: widget.vehicle.id,
                planId: plan.id,
                amount: _amount,
              );

      // Pull the new expiry date into the fleet state.
      await ref.read(fleetProvider.notifier).load(silent: true);

      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _record = record;
        _stage = _Stage.success;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scroll) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Renew subscription',
                          style: theme.textTheme.titleLarge),
                      Text(
                        widget.vehicle.displayName,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(theme, scroll)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ScrollController scroll) {
    switch (_stage) {
      case _Stage.loading:
        return const Center(child: CircularProgressIndicator());

      case _Stage.processing:
        return _ProcessingView(amount: _amount, currency: _price?.currency ?? 'INR');

      case _Stage.success:
        return _SuccessView(
          record: _record,
          vehicle: widget.vehicle,
          onDone: () => Navigator.pop(context),
        );

      case _Stage.failed:
        return ErrorState(
          title: 'Payment could not be completed',
          message: _error ?? 'Something went wrong.',
          icon: Icons.credit_card_off_rounded,
          onRetry: () => _plans.isEmpty ? _load() : setState(() {
            _stage = _Stage.selecting;
            _error = null;
          }),
        );

      case _Stage.selecting:
        if (_plans.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No plans available',
            message: 'Renewal plans are not configured for your account. '
                'Please contact your service provider.',
          );
        }

        return Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.lg, Gap.lg),
                children: <Widget>[
                  Container(
                    padding: Gap.cardTight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: Corners.rSm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.event_rounded,
                            size: 16, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Text(
                            'Current expiry: ${Fmt.date(widget.vehicle.expiryDate)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text(
                    'CHOOSE A PLAN',
                    style: AppTypography.eyebrow(
                        theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Gap.md),
                  ..._plans.map(
                    (RenewalPlan p) => _PlanTile(
                      plan: p,
                      selected: _selected?.id == p.id,
                      currency: _price?.currency ?? 'INR',
                      onTap: () => setState(() => _selected = p),
                    ),
                  ),
                ],
              ),
            ),
            _CheckoutBar(
              amount: _amount,
              currency: _price?.currency ?? 'INR',
              taxPercent: _price?.taxPercent ?? 0,
              gateway: ref.read(paymentServiceProvider).gatewayName,
              onPay: _selected == null ? null : _pay,
            ),
          ],
        );
    }
  }
}

/// Small helper so the sheet does not need to import the user model widely.
class AppUserSnapshot {
  AppUserSnapshot(WidgetRef ref)
      : name = ref.read(authProvider).user?.name,
        email = ref.read(authProvider).user?.email,
        phone = ref.read(authProvider).user?.phone;

  final String? name;
  final String? email;
  final String? phone;
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.currency,
    required this.onTap,
  });

  final RenewalPlan plan;
  final bool selected;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: AnimatedContainer(
        duration: Motion.fast,
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.10)
              : theme.colorScheme.surfaceContainer,
          borderRadius: Corners.rLg,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: Corners.rLg,
          child: InkWell(
            onTap: onTap,
            borderRadius: Corners.rLg,
            child: Padding(
              padding: Gap.card,
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check_rounded,
                            size: 14, color: theme.colorScheme.onPrimary)
                        : null,
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Text(plan.durationLabel,
                                style: theme.textTheme.titleSmall),
                            if (plan.isPopular) ...<Widget>[
                              const SizedBox(width: Gap.sm),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.moving.withOpacity(0.16),
                                  borderRadius: Corners.rPill,
                                ),
                                child: Text(
                                  'BEST VALUE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontSize: 8.5,
                                    color: AppColors.moving,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${Fmt.currency(plan.pricePerMonth, code: currency)} / month',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    Fmt.currency(plan.price, code: currency),
                    style: AppTypography.metric(
                      size: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.amount,
    required this.currency,
    required this.taxPercent,
    required this.gateway,
    required this.onPay,
  });

  final double amount;
  final String currency;
  final double taxPercent;
  final String gateway;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        Gap.lg,
        Gap.lg,
        MediaQuery.paddingOf(context).bottom + Gap.lg,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Total payable', style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                Fmt.currency(amount, code: currency),
                style: AppTypography.metric(
                  size: 24,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          if (taxPercent > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Inclusive of ${taxPercent.round()}% tax',
                style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
              ),
            ),
          const SizedBox(height: Gap.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: const Text('Pay securely'),
            ),
          ),
          if (gateway == 'dummy') ...<Widget>[
            const SizedBox(height: Gap.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.science_outlined,
                    size: 13, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(
                  'Sandbox mode — no real charge will be made',
                  style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 0),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.amount, required this.currency});

  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.x3l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: Gap.xxl),
            Text('Processing payment', style: theme.textTheme.titleLarge),
            const SizedBox(height: Gap.sm),
            Text(
              'Authorising ${Fmt.currency(amount, code: currency)}. '
              'Please do not close this screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.record,
    required this.vehicle,
    required this.onDone,
  });

  final RenewalRecord? record;
  final Vehicle vehicle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(Gap.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: AppColors.moving.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 42, color: AppColors.moving),
          ),
          const SizedBox(height: Gap.xxl),
          Text('Renewal confirmed', style: theme.textTheme.headlineSmall),
          const SizedBox(height: Gap.sm),
          Text(
            '${vehicle.displayName} is active again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.xxl),
          if (record != null)
            SurfaceCard(
              child: Column(
                children: <Widget>[
                  _row(theme, 'Amount paid',
                      Fmt.currency(record!.amount)),
                  const SizedBox(height: Gap.sm),
                  _row(theme, 'New expiry', Fmt.date(record!.newExpiryDate)),
                  if (record!.transactionId != null) ...<Widget>[
                    const SizedBox(height: Gap.sm),
                    _row(theme, 'Reference', record!.transactionId!),
                  ],
                ],
              ),
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDone, child: const Text('Done')),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Row(
        children: <Widget>[
          Text(label, style: theme.textTheme.bodySmall),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
        ],
      );
}
