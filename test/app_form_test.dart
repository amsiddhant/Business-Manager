import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:salesforce_business_manager/state/user_prefs.dart';
import 'package:salesforce_business_manager/widgets/forms/app_form.dart';
import 'package:salesforce_business_manager/widgets/forms/form_dialog.dart';
import 'package:salesforce_business_manager/widgets/forms/form_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThingForm extends StatefulWidget {
  const _ThingForm({this.draftKey});

  final String? draftKey;

  @override
  State<_ThingForm> createState() => _ThingFormState();
}

class _ThingFormState extends State<_ThingForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController(text: '125000');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: 'Add Thing',
      draftKey: widget.draftKey,
      onSubmit: () async => _formKey.currentState!.validate(),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            AppTextField(
              label: 'Name',
              controller: _name,
              isRequired: true,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Name is required' : null,
            ),
            const FormGap(),
            AppMoneyField(label: 'Price', controller: _price, symbol: r'$'),
          ],
        ),
      ),
    );
  }
}

/// A page with an "Open" button; the form's result lands in [results].
Future<void> _pump(WidgetTester tester, UserPrefs prefs, List<bool?> results,
    {double width = 1280, String? draftKey}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider<UserPrefs>.value(
    value: prefs,
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(await showAppForm<bool>(
                context: context,
                builder: (_) => _ThingForm(draftKey: draftKey))),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  late UserPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = UserPrefs(await SharedPreferences.getInstance())..bindUser('u1');
  });

  test('groupMoneyDigits groups Indian and western style', () {
    expect(groupMoneyDigits('125000', indian: true), '1,25,000');
    expect(groupMoneyDigits('12500000.5', indian: true), '1,25,00,000.5');
    expect(groupMoneyDigits('125000', indian: false), '125,000');
    expect(groupMoneyDigits('1,250', indian: false), '1,250');
    expect(groupMoneyDigits('999', indian: true), '999');
    expect(groupMoneyDigits('007', indian: true), '7');
    expect(groupMoneyDigits('', indian: true), '');
    expect(groupMoneyDigits('12a', indian: true), '12a');
  });

  testWidgets('opens as a side panel and saves on Ctrl+Enter',
      (tester) async {
    final results = <bool?>[];
    await _pump(tester, prefs, results);
    await _open(tester);

    expect(find.text('Add Thing'), findsOneWidget);
    expect(find.textContaining('Enter to save'), findsOneWidget);
    // The panel hugs the right edge.
    final panel = tester.getRect(find
        .descendant(
            of: find.byType(FormDialog), matching: find.byType(Scaffold))
        .first);
    expect(panel.right, 1280);
    expect(panel.width, lessThan(800));
    // Money is grouped (western style for $) until the field is focused.
    expect(find.text('125,000'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Lamp');
    await tester.pump();
    expect(find.text('Unsaved'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(find.text('Add Thing'), findsNothing);
    expect(results, [true]);
  });

  testWidgets('a failed save lists the fields that need attention',
      (tester) async {
    final results = <bool?>[];
    await _pump(tester, prefs, results);
    await _open(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('1 field needs attention'), findsOneWidget);
    expect(find.text('Name: Name is required'), findsOneWidget);
    expect(find.text('Add Thing'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('unsaved changes ask before closing', (tester) async {
    final results = <bool?>[];
    await _pump(tester, prefs, results);
    await _open(tester);

    // Untouched: closes straight away.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(results, [false]);

    await _open(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Lamp');
    await tester.pump();

    // Tapping the scrim asks first; Keep editing stays.
    await tester.tapAt(const Offset(20, 450));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Add Thing'), findsOneWidget);
    expect(find.text('Lamp'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Add Thing'), findsNothing);
    expect(results, [false, false]);
  });

  testWidgets('a kept draft is offered next time', (tester) async {
    final results = <bool?>[];
    await _pump(tester, prefs, results, draftKey: 'thing.new');
    await _open(tester);
    expect(find.textContaining('unsaved draft'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Desk');
    await tester.pump(const Duration(seconds: 1)); // autosave
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep draft'));
    await tester.pumpAndSettle();
    expect(find.text('Add Thing'), findsNothing);

    await _open(tester);
    expect(find.textContaining('unsaved draft'), findsOneWidget);
    expect(find.text('Desk'), findsNothing);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);

    // Saving clears the draft.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(results.last, true);
    await _open(tester);
    expect(find.textContaining('unsaved draft'), findsNothing);
  });

  testWidgets('opens full screen on a phone', (tester) async {
    final results = <bool?>[];
    await _pump(tester, prefs, results, width: 400);
    await _open(tester);

    final form = tester.getRect(find.byType(FormDialog));
    expect(form.width, 400);
    expect(find.textContaining('Enter to save'), findsNothing);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
