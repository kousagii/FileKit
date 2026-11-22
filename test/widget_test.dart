import 'dart:io';

import 'package:filekit/app/app.dart';
import 'package:filekit/core/models.dart';
import 'package:filekit/core/services.dart';
import 'package:filekit/features/conversion/conversion_controller.dart';
import 'package:filekit/features/conversion/workbench_screen.dart';
import 'package:filekit/features/tools/tools_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import 'test_support.dart';

class _SelectedImageController extends AppController {
  _SelectedImageController(this.sources);
  final List<FileSource> sources;
  @override
  FileKitState build() => super.build().copyWith(sources: sources);
}

void main() {
  late Directory root;
  late AppServices services;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('filekit_widget_');
    services = await testServices(root, initialSettings: const AppSettings());
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDown(() async => root.delete(recursive: true));

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    List<FileSource> sources = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          servicesProvider.overrideWithValue(services),
          if (sources.isNotEmpty)
            appControllerProvider.overrideWith(
              () => _SelectedImageController(sources),
            ),
        ],
        child: const FileKitApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseTool(WidgetTester tester, String label) async {
    await tester.tap(find.byType(ToolSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'converter opens directly with compact selector and visible file action',
    (tester) async {
      await mount(tester);
      expect(find.byType(WorkbenchScreen), findsOneWidget);
      expect(find.text('Choose a tool to get started.'), findsNothing);
      expect(find.byType(ToolSelector), findsOneWidget);
      expect(tester.getSize(find.byType(ToolSelector)).height, lessThan(70));
      expect(
        tester
            .getBottomRight(find.widgetWithText(OutlinedButton, 'Add files'))
            .dy,
        lessThan(400),
      );
      expect(find.byType(DropdownButtonFormField<InputFormat>), findsOneWidget);
      expect(
        find.byType(DropdownButtonFormField<OutputFormat>),
        findsOneWidget,
      );
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('../docs/screenshots/tools-light.png'),
      );
    },
  );

  testWidgets('input dropdown restricts PDF output to PNG/JPG', (tester) async {
    await mount(tester);
    await tester.tap(find.byType(DropdownButtonFormField<InputFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF').last);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AppShell));
    final container = ProviderScope.containerOf(context);
    expect(
      container.read(appControllerProvider).options.input,
      InputFormat.pdf,
    );
    await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
    await tester.pumpAndSettle();
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('WebP'), findsNothing);
    expect(find.text('WEBP'), findsNothing);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('../docs/screenshots/pdf-export-light.png'),
    );
  });

  testWidgets('PNG and lossless WebP do not expose a lossy quality slider', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PNG').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Convert'),
    );
    expect(action.onPressed, isNull);
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('../docs/screenshots/convert-light.png'),
    );
    await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebP').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('WebP mode'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('tool sheet includes merge/split and opens PDF workbench', (
    tester,
  ) async {
    await mount(tester);
    await chooseTool(tester, 'Merge PDF');
    expect(find.byType(DropdownButtonFormField<InputFormat>), findsNothing);
    expect(find.text('File name'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Merge PDF'),
    );
    expect(button.onPressed, isNull);
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('../docs/screenshots/merge-light.png'),
    );
    await chooseTool(tester, 'Split PDF');
    expect(find.text('Split by'), findsOneWidget);
    expect(find.text('Each page'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page ranges').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Page ranges'), findsOneWidget);
  });

  testWidgets('history and dark settings remain reachable', (tester) async {
    await mount(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('No conversions yet'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AppShell));
    await ProviderScope.containerOf(context)
        .read(appControllerProvider.notifier)
        .updateSettings(theme: 'dark');
    await tester.pumpAndSettle();
    expect(Theme.of(context).brightness, Brightness.dark);
    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('../docs/screenshots/settings-dark.png'),
    );
  });

  testWidgets(
    'Convert WebP resize controls stay finite and export edited dimensions',
    (tester) async {
      final source = File('${root.path}/notes.png');
      source.writeAsBytesSync(
        img.encodePng(img.Image(width: 640, height: 360)),
      );
      services = (await tester.runAsync(() => testServices(root)))!;
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: Key('seed-image'))),
      );
      await tester.runAsync(
        () => precacheImage(
          FileImage(source),
          tester.element(find.byKey(const Key('seed-image'))),
        ),
      );
      await mount(
        tester,
        sources: [
          SourceFile(
            id: 'resize-notes',
            name: 'notes.png',
            path: source.path,
            thumbnailPath: source.path,
            bytes: source.lengthSync(),
            width: 640,
            height: 360,
            format: 'png',
            hasAlpha: false,
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      await container
          .read(appControllerProvider.notifier)
          .updateSettings(theme: 'dark');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('WebP').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final widthField = find.widgetWithText(TextField, 'Max width');
      final heightField = find.widgetWithText(TextField, 'Max height');
      expect(tester.getSize(widthField).height, lessThan(100));
      expect(tester.getSize(heightField).height, lessThan(100));
      expect(find.byType(ErrorWidget), findsNothing);
      await tester.ensureVisible(widthField);
      await tester.enterText(widthField, '320');
      await tester.enterText(heightField, '180');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final outerScroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(outerScroll.position.maxScrollExtent, lessThan(2000));
      await tester.runAsync(
        () => container.read(appControllerProvider.notifier).run(),
      );
      await tester.pumpAndSettle();
      final job = container.read(appControllerProvider).result!;
      expect(job.status, JobStatus.succeeded);
      final output = img.decodeWebP(
        File.fromUri(Uri.parse(job.outputs.single.uri)).readAsBytesSync(),
      )!;
      expect([output.width, output.height], [320, 180]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'PDF filename remains editable after collapsing and reopening Options',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PDF').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      final filename = find.widgetWithText(TextField, 'File name');
      expect(tester.getSize(filename).height, lessThan(100));
      await tester.ensureVisible(filename);
      await tester.enterText(filename, 'semester-assignment');
      await tester.pump();
      expect(find.byType(ErrorWidget), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      expect(
        container.read(appControllerProvider).options.pdfName,
        'semester-assignment.pdf',
      );
    },
  );

  testWidgets(
    'Convert resize stays usable with large text and the Android keyboard',
    (tester) async {
      await mount(tester, size: const Size(320, 740), textScale: 2);
      await tester.tap(find.byType(DropdownButtonFormField<OutputFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PNG').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Options'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      final widthField = find.widgetWithText(TextField, 'Max width');
      final heightField = find.widgetWithText(TextField, 'Max height');
      expect(tester.getSize(widthField).height, lessThan(120));
      expect(tester.getSize(heightField).height, lessThan(120));
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(widthField);
      await tester.enterText(widthField, '800');
      await tester.ensureVisible(heightField);
      await tester.enterText(heightField, '600');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      expect(container.read(appControllerProvider).options.maxWidth, 800);
      expect(container.read(appControllerProvider).options.maxHeight, 600);
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent,
        lessThan(5000),
      );
    },
  );

  testWidgets('narrow phone and 200 percent text do not overflow', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 740), textScale: 2);
    await chooseTool(tester, 'Resize images');
    await tester.scrollUntilVisible(
      find.text('Max width'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.byType(ToolSelector),
      -250,
      scrollable: find.byType(Scrollable).first,
    );
    await chooseTool(tester, 'Merge PDF');
    await chooseTool(tester, 'Split PDF');
  });
}
