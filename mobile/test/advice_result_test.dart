import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/models/models.dart';
import 'package:farmtrack/features/result/advice_result.dart';

/// A word list that shows its key and arguments, so the tests see exactly what the code asked for.
String _t(String key, {Map<String, Object> args = const {}}) =>
    args.isEmpty ? key : '$key(${args.entries.map((e) => '${e.key}=${e.value}').join(',')})';

ProductOut _product({
  String id = 'P1',
  String dose = '30 ml in 200 litres of water',
  String? unit = 'ml/200L',
  double? min = 30,
  double? max = 30,
  int? wait = 14,
  List<WarningOut> warnings = const [],
}) => ProductOut(
  productId: id,
  activeIngredient: LocalizedText.pair(en: 'Dodine', hi: 'डोडीन'),
  doseText: LocalizedText.pair(en: dose, hi: '$dose (hi)'),
  doseMin: min,
  doseMax: max,
  doseUnit: unit,
  waitingPeriodDays: wait,
  warnings: warnings,
);

WarningOut _warning(String en, {Severity level = Severity.yellow}) => WarningOut(
  code: en,
  level: level,
  text: LocalizedText.pair(en: en, hi: 'हि $en'),
);

LocalizedText _text(String en) => LocalizedText.pair(en: en, hi: 'हि $en');

void main() {
  group('DoseSteps: "X in N litres of water" cut into take and mix', () {
    test('one figure', () {
      final steps = DoseSteps.of(_product())!;
      expect((steps.low, steps.high, steps.unit, steps.water), (30.0, 30.0, 'ml', 200.0));
      expect(steps.amount(_t), '30');
      expect(steps.take(_t, 'Dodine'), 'advice_step_take(amount=30,unit=advice_unit_ml,name=Dodine)');
      expect(
        steps.take(_t, 'Dodine', spoken: true),
        'advice_step_take(amount=30,unit=advice_say_ml,name=Dodine)',
        reason: 'a voice gets the whole word for the unit',
      );
      expect(steps.mix(_t), 'advice_step_mix(water=200)');
    });

    test('a range, decimals and every unit the dose table has', () {
      final range = DoseSteps.of(_product(min: 30, max: 40))!;
      expect(range.amount(_t), 'advice_amount_range(a=30,b=40)');
      final decimal = DoseSteps.of(_product(unit: 'kg/200L', min: 2.5, max: 2.5))!;
      expect((decimal.unit, decimal.amount(_t)), ('kg', '2.5'));
      final litres = DoseSteps.of(_product(unit: 'L/100L', min: 1, max: 1))!;
      expect((litres.unit, litres.water), ('L', 100.0));
      expect(DoseSteps.of(_product(unit: 'g/200L'))!.unit, 'g');
      expect(DoseSteps.of(_product(min: null, max: 40))!.low, 40, reason: 'one end of the range is enough');
    });

    test('a dose of any other shape is not cut: the server sentence is shown instead', () {
      for (final unit in ['ml/L', 'g/L', 'kg/ha', 'ml/ha in 500L', 'percent', 'percent_drench', null, 'ml', '']) {
        expect(DoseSteps.of(_product(unit: unit)), isNull, reason: '$unit');
      }
      expect(DoseSteps.of(_product(min: null, max: null)), isNull, reason: 'no figure');
    });

    test('what a medicine card says: the name, take, mix, wait; or the server sentence', () {
      expect(
        medicineSpeech(_product(), 'en', _t),
        'Dodine. advice_step_take(amount=30,unit=advice_say_ml,name=Dodine) advice_step_mix(water=200) '
        'advice_wait_days(n=14).',
      );
      expect(medicineSpeech(_product(unit: 'ml/L', wait: null), 'en', _t), 'Dodine. 30 ml in 200 litres of water');
      expect(medicineSpeech(_product(), 'hi', _t), startsWith('डोडीन. '));
    });
  });

  group('adviceNotes: the lines of the last card', () {
    AdviceOut advice({
      List<ProductOut>? products,
      TimingOut? timing,
      List<String> steps = const [],
      List<WarningOut> warnings = const [],
    }) => AdviceOut(
      id: 'a',
      products: products ?? [_product()],
      timing: timing,
      steps: [for (final s in steps) _text(s)],
      warnings: warnings,
    );

    final spray = TimingOut(action: TimingAction.sprayNow, text: _text('Spray today.'));

    List<String> texts(AdviceOut a, [String lang = 'en']) => [for (final n in adviceNotes(a, lang)) n.text];

    test('the server step list "when, risk, choose one, medicine lines, measures" keeps only the measures', () {
      final notes = texts(
        advice(
          timing: spray,
          steps: [
            'Spray today. No rain is expected.',
            'The leaves stayed wet for many hours.',
            'Choose one of the medicines below for each spray.',
            'Dodine (for example Dodin): 30 ml in 200 litres of water. Wait at least 14 days.',
            'Better in open, well-pruned orchards; compost leaf litter',
          ],
        ),
      );
      expect(notes, ['Spray today.', 'Better in open, well-pruned orchards; compost leaf litter']);
    });

    test('warnings come once, the serious first, those of the medicines too', () {
      final a = advice(
        timing: spray,
        products: [
          _product(warnings: [_warning('Do not mix.'), _warning('Dose is for 200 litres.')]),
          _product(id: 'P2', warnings: [_warning('Do not mix.')]),
        ],
        warnings: [
          _warning('Do not mix.'),
          _warning('Heavy rain: spray again.', level: Severity.red),
        ],
      );
      final notes = adviceNotes(a, 'en');
      expect(
        [for (final n in notes) n.text],
        ['Spray today.', 'Heavy rain: spray again.', 'Do not mix.', 'Dose is for 200 litres.'],
      );
      expect(notes[1].kind, NoteKind.serious);
      expect(notes[2].kind, NoteKind.warning);
    });

    test('an advice with no medicine (an expert case) keeps all its steps', () {
      final notes = texts(
        advice(products: const [], steps: ['Do not spray until the expert has looked.', 'Remove fallen leaves.']),
      );
      expect(notes, ['Do not spray until the expert has looked.', 'Remove fallen leaves.']);
    });

    test('free-written steps with no medicine line are all measures, except one that repeats the timing', () {
      final notes = texts(advice(timing: spray, steps: ['Spray today.', 'Spray the whole tree.']));
      expect(notes, ['Spray today.', 'Spray the whole tree.']);
    });

    test('the timing action picks the kind of its line', () {
      NoteKind kind(TimingAction action) => adviceNotes(
        advice(
          timing: TimingOut(action: action, text: _text('x')),
        ),
        'en',
      ).first.kind;
      expect(kind(TimingAction.sprayNow), NoteKind.go);
      expect(kind(TimingAction.wait), NoteKind.wait);
      expect(kind(TimingAction.repeatWithinDays), NoteKind.again);
      expect(kind(TimingAction.notNeeded), NoteKind.info);
      expect(kind(TimingAction.unknown), NoteKind.info);
    });

    test('Hindi lines are kept (they have no English letters to compare)', () {
      final notes = adviceNotes(
        advice(timing: spray, warnings: [_warning('Do not mix.')], steps: ['Spray today.', 'Remove fallen leaves.']),
        'hi',
      );
      expect([for (final n in notes) n.text], ['हि Spray today.', 'हि Do not mix.', 'हि Remove fallen leaves.']);
    });

    test('safety notes are separate, and empty ones are left out', () {
      final a = AdviceOut(
        id: 'a',
        safety: [
          _text('Wear gloves.'),
          const LocalizedText(),
          LocalizedText.pair(en: ' ', hi: ' '),
        ],
      );
      expect(safetyNotes(a, 'en'), ['Wear gloves.']);
    });
  });
}
