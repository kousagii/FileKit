import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets.dart';
import '../conversion/conversion_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const SectionHeading('Default output folder'),
        FolderPanel(
          destination: state.settings.destination,
          enabled: !state.busy && !state.picking,
          onChoose: controller.chooseFolder,
        ),
        const SizedBox(height: 24),
        const SectionHeading('Appearance'),
        Panel(
          child: DropdownButtonFormField<String>(
            initialValue: state.settings.theme,
            decoration: const InputDecoration(labelText: 'Theme'),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'system', child: Text('System')),
              DropdownMenuItem(value: 'light', child: Text('Light')),
              DropdownMenuItem(value: 'dark', child: Text('Dark')),
            ],
            onChanged: (mode) => controller.updateSettings(theme: mode),
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeading('Default JPEG quality'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${state.settings.quality}%',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Slider(
                value: state.settings.quality.toDouble(),
                min: 50,
                max: 100,
                divisions: 10,
                semanticFormatterCallback: (value) =>
                    '${value.round()} percent',
                onChanged: (value) =>
                    controller.updateSettings(quality: value.round()),
              ),
              Text(
                'Applied when starting a new conversion.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeading('Supported files'),
        const Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Input: JPG, PNG, WebP, BMP, PDF'),
              SizedBox(height: 6),
              Text('Output: JPG, PNG, WebP, PDF'),
              SizedBox(height: 12),
              Text(
                'Up to 10 files per job. Images: up to 20 MB and 12 megapixels each. PDFs: up to 50 MB and 100 pages each.',
              ),
              SizedBox(height: 12),
              Text(
                'Merge up to 200 pages. Export up to 30 PDF pages as images per job. Static images and unencrypted PDFs only.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const SectionHeading('About'),
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FileKitMark(size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FileKit',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 0.2.1',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Image and PDF tools for Android. Processing takes place on this device.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'A cloud folder offered by the system picker may need an internet connection to save files.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'FileKit',
            applicationVersion: '0.2.1',
          ),
          child: const Text('Open-source licenses'),
        ),
      ],
    );
  }
}
