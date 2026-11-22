import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/widgets.dart';
import '../features/conversion/conversion_controller.dart';
import '../features/conversion/workbench_screen.dart';
import '../features/history/history_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_theme.dart';

class FileKitApp extends ConsumerWidget {
  const FileKitApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      appControllerProvider.select((s) => s.settings.theme),
    );
    return MaterialApp(
      title: 'FileKit',
      debugShowCheckedModeBanner: false,
      theme: fileKitTheme(Brightness.light),
      darkTheme: fileKitTheme(Brightness.dark),
      themeMode: switch (mode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    ref.listen<String?>(appControllerProvider.select((s) => s.notice), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next),
          duration: const Duration(seconds: 7),
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: controller.dismissNotice,
          ),
        ),
      );
    });
    return PopScope(
      canPop: selected == 0 && !state.busy,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (state.busy) {
          controller.showNotice(
            'A job is running. Use Cancel to stop after the current step.',
          );
        } else {
          setState(() => selected = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: selected == 0
              ? const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FileKitMark(),
                    SizedBox(width: 10),
                    Text('FileKit'),
                  ],
                )
              : Text(selected == 1 ? 'History' : 'Settings'),
          actions: selected == 1 && state.history.isNotEmpty
              ? [
                  PopupMenuButton<String>(
                    tooltip: 'History options',
                    enabled: !state.busy,
                    onSelected: (_) => confirmClearHistory(context, ref),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text('Clear history'),
                      ),
                    ],
                  ),
                ]
              : null,
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: IndexedStack(
                index: selected,
                children: [
                  WorkbenchScreen(key: ValueKey(state.tool)),
                  const HistoryScreen(),
                  const SettingsScreen(),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) => setState(() => selected = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Tools',
            ),
            NavigationDestination(
              icon: Icon(Icons.history_outlined),
              selectedIcon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
