import 'package:flutter/material.dart';

import '../../core/theme/qesto_theme.dart';
import '../../core/formatters/qesto_formatters.dart';
import 'mobile_source_attention_controller.dart';

/// A compact, accessible entry to source problems from every mobile root.
class MobileSourceAttentionBanner extends StatelessWidget {
  const MobileSourceAttentionBanner({
    required this.controller,
    required this.onTap,
    super.key,
  });

  final MobileSourceAttentionController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.needsAttention) return const SizedBox.shrink();
      final colors = context.qestoColors;
      final summary = <String>[
        if (controller.permissionDenied) 'Нет доступа к уведомлениям',
        if (controller.pendingCount > 0)
          'Входящих уведомлений: ${controller.pendingCount}',
        if (controller.failedCount > 0)
          'Ошибок импорта: ${controller.failedCount}',
        if (controller.error != null) 'Ошибка проверки источника',
      ].join(' · ');
      return Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          key: const Key('mobile-source-attention-banner'),
          color: colors.surfaceElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.warning.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colors.warning, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Источники требуют внимания',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          summary,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (controller.isLoading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Status/settings over the existing native gateway; import remains explicit.
class MobileSourceStatusPage extends StatelessWidget {
  const MobileSourceStatusPage({
    required this.controller,
    required this.onOpenInbox,
    this.onOpenBankConnections,
    super.key,
  });

  final MobileSourceAttentionController controller;
  final VoidCallback onOpenInbox;
  final VoidCallback? onOpenBankConnections;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final colors = context.qestoColors;
      return Scaffold(
        key: const Key('mobile-source-status-page'),
        appBar: AppBar(
          title: const Text('Источники'),
          actions: [
            IconButton(
              key: const Key('mobile-source-refresh'),
              tooltip: 'Обновить статус',
              onPressed: controller.supported && !controller.isLoading
                  ? controller.refresh
                  : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (controller.isLoading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              if (onOpenBankConnections case final openBankConnections?) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Банковский браузер',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Существующие подключения через локальный '
                          'браузер доступны на этом компьютере.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const Key('mobile-source-bank-connections'),
                          onPressed: openBankConnections,
                          icon: const Icon(Icons.account_balance_outlined),
                          label: const Text('Подключения к банкам'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.notifications_outlined,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Уведомления Android',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(_permissionLabel(controller)),
                      if (controller.hasPermission == false) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Разрешите Qesto читать банковские уведомления в системных настройках. '
                          'После возврата доступ проверится автоматически. '
                          'Пароли, PIN и подтверждения банков не импортируются.',
                        ),
                      ],
                      if (controller.hasPermission == true &&
                          controller.pendingCount == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Захват включён. Новых входящих для проверки нет.',
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        controller.supported
                            ? 'Уведомления банков и SMS, показанные '
                                  'в уведомлениях приложений.'
                            : 'Захват уведомлений доступен только на Android. '
                                  'Ручное добавление и импорт доступны через «+».',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.secondaryText,
                        ),
                      ),
                      if (controller.supported) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          key: const Key('mobile-source-permission-settings'),
                          onPressed: controller.isOpeningSettings
                              ? null
                              : controller.openPermissionSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: Text(
                            controller.hasPermission == false
                                ? 'Открыть настройки'
                                : 'Настроить доступ',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (controller.error case final error?) ...[
                const SizedBox(height: 12),
                Material(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      error,
                      key: const Key('mobile-source-error'),
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
                ),
              ],
              if (controller.failedCount > 0) ...[
                const SizedBox(height: 12),
                Material(
                  color: colors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Последняя попытка автоматического импорта: '
                      'ошибок ${controller.failedCount}. '
                      'Проверьте входящие уведомления.',
                      key: const Key('mobile-source-import-failures'),
                      style: TextStyle(color: colors.warning),
                    ),
                  ),
                ),
              ],
              if (controller.supported) ...[
                if (controller.lastUpdated != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Статус проверен: ${formatDate(controller.lastUpdated!.toLocal(), includeYear: true)} · '
                      '${controller.lastUpdated!.hour.toString().padLeft(2, '0')}:${controller.lastUpdated!.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Входящие уведомления: ${controller.pendingCount}',
                          key: const Key('mobile-source-inbox-count'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Это сохранённые уведомления, а не подтверждённые '
                          'денежные операции. Уже обработанные записи '
                          'удаляются из входящих существующим импортом.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          key: const Key('mobile-source-open-inbox'),
                          onPressed: onOpenInbox,
                          icon: const Icon(Icons.inbox_outlined),
                          label: const Text('Открыть входящие'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  String _permissionLabel(MobileSourceAttentionController state) {
    if (!state.supported) return 'Недоступно на этой платформе';
    return switch (state.hasPermission) {
      true => 'Доступ к уведомлениям разрешён',
      false => 'Доступ к уведомлениям не предоставлен',
      null => 'Доступ ещё не проверен',
    };
  }
}
