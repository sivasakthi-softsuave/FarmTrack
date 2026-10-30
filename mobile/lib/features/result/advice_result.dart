import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/widgets/big_buttons.dart';
import '../../core/widgets/design.dart';
import '../scan/crop_picture.dart';

/// An interface word with its arguments, as `ref.watch(stringsProvider)` gives it.
typedef Strings = String Function(String key, {Map<String, Object> args});

String _number(double value) => value.roundToDouble() == value ? value.toStringAsFixed(0) : value.toString();

/// A medicine dose of the form "X ml (or g, kg, L) in N litres of water", cut into the two things the farmer does: take
/// X, then mix it in N litres of water. Any other kind of dose (per litre, per hectare, a percent solution, ...) is not
/// cut: the server's own dose sentence is shown instead, so the app never invents a dose.
class DoseSteps {
  const DoseSteps({required this.low, required this.high, required this.unit, required this.water});

  /// The dose, or its range ([low] equals [high] for a single figure).
  final double low;
  final double high;

  /// `g`, `ml`, `kg` or `L`.
  final String unit;

  /// Litres of water the dose is mixed in.
  final double water;

  static final _perWater = RegExp(r'^(g|ml|L|kg)/(\d+(?:\.\d+)?)L$');

  static DoseSteps? of(ProductOut product) {
    final match = _perWater.firstMatch((product.doseUnit ?? '').trim());
    final figures = [product.doseMin, product.doseMax].whereType<double>().toList();
    if (match == null || figures.isEmpty) return null;
    final water = double.tryParse(match.group(2)!);
    if (water == null) return null;
    figures.sort();
    return DoseSteps(low: figures.first, high: figures.last, unit: match.group(1)!, water: water);
  }

  String amount(Strings t) =>
      low == high ? _number(low) : t('advice_amount_range', args: {'a': _number(low), 'b': _number(high)});

  /// "Take 150 ml of Dodine." With [spoken] the unit is a whole word ("millilitres"), which a voice reads better.
  String take(Strings t, String name, {bool spoken = false}) => t(
    'advice_step_take',
    args: {'amount': amount(t), 'unit': t('advice_${spoken ? 'say' : 'unit'}_$unit'), 'name': name},
  );

  /// "Mix it in 200 litres of water."
  String mix(Strings t) => t('advice_step_mix', args: {'water': _number(water)});

  /// The whole dose in a few words, for a small tag: "30 ml in 200 L".
  String chip(Strings t) =>
      t('advice_dose_chip', args: {'amount': amount(t), 'unit': t('advice_unit_$unit'), 'water': _number(water)});
}

/// The name of a medicine as the card shows it: its active ingredient.
String medicineName(ProductOut product, String lang) => product.activeIngredient.forLang(lang);

/// What the speaker of a medicine card says: the name, the two steps (or the server's dose sentence) and the waiting
/// period. The unit is spoken as a whole word.
String medicineSpeech(ProductOut product, String lang, Strings t) {
  final name = medicineName(product, lang);
  final steps = DoseSteps.of(product);
  final waiting = product.waitingPeriodDays;
  return [
    '$name.',
    if (steps != null) ...[steps.take(t, name, spoken: true), steps.mix(t)] else product.doseText.forLang(lang),
    if (waiting != null) '${t('advice_wait_days', args: {'n': waiting})}.',
  ].where((s) => s.trim().isNotEmpty).join(' ');
}

/// What a line of the advice card is about; it picks the picture and its colour.
enum NoteKind { go, wait, again, info, warning, serious }

class AdviceNote {
  const AdviceNote(this.kind, this.text);

  final NoteKind kind;
  final String text;
}

final _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// [text] as bare lower-case words (any language), to tell whether two lines say the same.
String _plain(String text) => text.toLowerCase().replaceAll(_notLetters, ' ').trim();

final _endsWithStop = RegExp(r'[.!?।]$');

/// [text] with a full stop at its end when it has none, so a voice pauses between lines.
String _sentence(String text) => _endsWithStop.hasMatch(text) ? text : '$text.';

/// The lines of the one card at the end of an advice: when to spray, the warnings (the advice's and those of its
/// medicines, each once, the serious ones first) and the general measures (for example "better in open, well-pruned
/// orchards"). The long safety notes are not here ([safetyNotes]).
///
/// The server's `steps` list is "when, the weather risks, choose one, one line per medicine, the measures": the medicine
/// lines are shown as medicine cards, so only the measures after the last medicine line are taken from it.
List<AdviceNote> adviceNotes(AdviceOut advice, String lang) {
  final notes = <AdviceNote>[];
  final seen = <String>{};
  void add(NoteKind kind, String text) {
    final key = _plain(text);
    if (key.isNotEmpty && seen.add(key)) notes.add(AdviceNote(kind, text.trim()));
  }

  final timing = advice.timing;
  if (timing != null && !timing.text.isEmpty) {
    add(switch (timing.action) {
      TimingAction.sprayNow => NoteKind.go,
      TimingAction.wait => NoteKind.wait,
      TimingAction.repeatWithinDays => NoteKind.again,
      TimingAction.notNeeded || TimingAction.unknown => NoteKind.info,
    }, timing.text.forLang(lang));
  }

  final warnings = [...advice.warnings, for (final product in advice.products) ...product.warnings]
    ..sort((a, b) => (a.level == Severity.red ? 0 : 1).compareTo(b.level == Severity.red ? 0 : 1));
  for (final w in warnings) {
    add(w.level == Severity.red ? NoteKind.serious : NoteKind.warning, w.text.forLang(lang));
  }

  final steps = [for (final s in advice.steps) s.forLang(lang)];
  var from = 0;
  if (advice.products.isNotEmpty) {
    final doses = [for (final p in advice.products) p.doseText.forLang(lang)].where((d) => d.isNotEmpty);
    // No medicine line among the steps (a free-written advice): they are all measures.
    final last = steps.lastIndexWhere((s) => doses.any(s.contains));
    from = last + 1;
  }
  for (final s in steps.skip(from)) {
    // A step that only repeats a line already in the card (the "spray now" sentence) is left out.
    final plain = _plain(s);
    final repeats = notes.any((n) {
      final other = _plain(n.text);
      return other.contains(plain) || plain.contains(other);
    });
    if (!repeats) add(NoteKind.info, s);
  }
  return notes;
}

/// The safety notes of an advice (keep children away, protective clothes, ...): long, so they are behind "More".
List<String> safetyNotes(AdviceOut advice, String lang) => [
  for (final s in advice.safety)
    if (s.forLang(lang).trim().isNotEmpty) s.forLang(lang).trim(),
];

/// The advice of a scan, as the owner asked for it (27 Oct 2026): the crop's round picture and name, the disease, the
/// medicines one by one (each with its two steps: take, then mix in water), and last one card with the advice and the
/// warnings. Nothing is read aloud from the cards: each medicine card and the last card has a speaker that says it when
/// it is tapped ([onSpeak] gets the sentence).
class AdviceResult extends ConsumerStatefulWidget {
  const AdviceResult({
    super.key,
    required this.advice,
    required this.cropId,
    required this.cropName,
    required this.diseaseName,
    required this.onSpeak,
  });

  final AdviceOut advice;

  /// Empty when the scan named no crop (no picture, no name).
  final String cropId;
  final String cropName;

  /// Empty: the advice's own headline is shown instead.
  final String diseaseName;
  final void Function(String sentence) onSpeak;

  @override
  ConsumerState<AdviceResult> createState() => _AdviceResultState();
}

class _AdviceResultState extends ConsumerState<AdviceResult> {
  bool _more = false;

  @override
  Widget build(BuildContext context) {
    final advice = widget.advice;
    final lang = ref.watch(languageProvider);
    final t = ref.watch(stringsProvider);
    final products = advice.products;
    final disease = widget.diseaseName.isNotEmpty ? widget.diseaseName : advice.headline.forLang(lang);
    final notes = adviceNotes(advice, lang);
    final safety = safetyNotes(advice, lang);

    // The mockup's `.pad`: 12 between blocks; a label sits 10 above what it heads.
    final blocks = <Widget>[
      _CropCard(
        cropId: widget.cropId,
        cropName: widget.cropName,
        disease: disease,
        severity: advice.severity,
        severityWord: t('severity_${advice.severity.wire}'),
      ),
      if (products.isNotEmpty) ...[
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(t('advice_medicine'), hindi: isDevanagari(t('advice_medicine'))),
            if (products.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Text(t('advice_choose_one'), key: const ValueKey('advice-choose-one'), style: AppText.hMeta),
              ),
          ],
        ),
        for (final p in products)
          _MedicineCard(product: p, lang: lang, onSpeak: () => widget.onSpeak(medicineSpeech(p, lang, t))),
      ],
      if (notes.isNotEmpty || safety.isNotEmpty)
        _NotesCard(
          notes: notes,
          safety: safety,
          open: _more,
          onToggle: () => setState(() => _more = !_more),
          onSpeak: () => widget.onSpeak([for (final n in notes) n.text, if (_more) ...safety].map(_sentence).join(' ')),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: i == 2 && products.isNotEmpty ? 10 : 12),
          blocks[i],
        ],
      ],
    );
  }
}

/// The crop's round picture (its photo when it has one), its name and under it the disease.
class _CropCard extends StatelessWidget {
  const _CropCard({
    required this.cropId,
    required this.cropName,
    required this.disease,
    required this.severity,
    required this.severityWord,
  });

  final String cropId;
  final String cropName;
  final String disease;
  final Severity severity;

  /// The severity in words ("Be careful"), for a screen reader only.
  final String severityWord;

  @override
  Widget build(BuildContext context) => AppCard(
    key: const ValueKey('advice-crop-card'),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cropId.isNotEmpty) Center(child: CropPicture(cropId: cropId, size: 104)),
        if (cropName.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(cropName, key: const ValueKey('advice-crop'), textAlign: TextAlign.center, style: AppText.big),
        ],
        if (disease.isNotEmpty) ...[
          const SizedBox(height: 10),
          // The disease is its name; how serious it is stays in the semantics (no picture beside it).
          Semantics(
            key: ValueKey('severity-${severity.wire}'),
            container: true,
            label: '$severityWord. $disease',
            excludeSemantics: true,
            child: Text(
              disease,
              key: const ValueKey('advice-headline'),
              textAlign: TextAlign.center,
              style: AppText.hName.copyWith(fontSize: 18),
            ),
          ),
        ],
      ],
    ),
  );
}

/// One medicine: its name, a speaker, and the steps to use it.
class _MedicineCard extends ConsumerWidget {
  const _MedicineCard({required this.product, required this.lang, required this.onSpeak});

  final ProductOut product;
  final String lang;
  final VoidCallback onSpeak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final name = medicineName(product, lang);
    final brand = [
      product.brandExamples.take(2).join(' / '),
      ?product.formulation,
    ].where((s) => s.isNotEmpty).join(' · ');
    final steps = DoseSteps.of(product);
    final waiting = product.waitingPeriodDays;
    final dose = product.doseText.forLang(lang);
    return AppCard(
      key: ValueKey('product-${product.productId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconDot(
                AppIcons.medicine,
                background: AppColors.blueSoft,
                foreground: AppColors.blue,
                size: 52,
                round: true,
                iconSize: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.3)),
                    if (brand.isNotEmpty) Text(brand, style: AppText.hMeta),
                  ],
                ),
              ),
              _SpeakerButton(
                key: ValueKey('product-speak-${product.productId}'),
                label: t('field_listen_card'),
                onPressed: onSpeak,
              ),
            ],
          ),
          Container(height: 1, color: AppColors.line, margin: const EdgeInsets.symmetric(vertical: 14)),
          if (steps != null) ...[
            NumberedStep(number: 1, text: steps.take(t, name)),
            const SizedBox(height: 10),
            NumberedStep(number: 2, text: steps.mix(t)),
          ] else if (dose.isNotEmpty)
            IconLine(icon: AppIcons.drop, text: dose, color: AppColors.blue, bold: true),
          if (waiting != null) ...[
            const SizedBox(height: 12),
            IconLine(
              icon: AppIcons.clock,
              text: t('advice_wait_days', args: {'n': waiting}),
              color: AppColors.inkSoft,
            ),
          ],
        ],
      ),
    );
  }
}

/// A green numbered circle and one sentence.
class NumberedStep extends StatelessWidget {
  const NumberedStep({super.key, required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
        child: Text(
          '$number',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.4)),
        ),
      ),
    ],
  );
}

/// A small picture, then a sentence that wraps beside it.
class IconLine extends StatelessWidget {
  const IconLine({super.key, required this.icon, required this.text, required this.color, this.bold = false});

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 24, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: bold ? 17 : 15.5,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

/// The round green speaker of a card: tapping it says that card.
class _SpeakerButton extends StatelessWidget {
  const _SpeakerButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => BigIconButton(
    icon: AppIcons.speaker,
    semanticLabel: label,
    color: AppColors.greenSoft,
    foreground: AppColors.green,
    size: Dimens.minTouch,
    onPressed: onPressed,
  );
}

/// The last card: the advice and the warnings, each line with a small picture. The safety notes are behind "More".
class _NotesCard extends ConsumerWidget {
  const _NotesCard({
    required this.notes,
    required this.safety,
    required this.open,
    required this.onToggle,
    required this.onSpeak,
  });

  final List<AdviceNote> notes;
  final List<String> safety;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onSpeak;

  static (IconData, Color) _look(NoteKind kind) => switch (kind) {
    NoteKind.go => (AppIcons.tickBold, AppColors.green),
    NoteKind.wait => (AppIcons.hourglass, AppColors.inkSoft),
    NoteKind.again => (AppIcons.roundArrow, AppColors.blue),
    NoteKind.info => (AppIcons.info, AppColors.blue),
    NoteKind.warning => (AppIcons.warning, AppColors.amberDark),
    NoteKind.serious => (AppIcons.danger, AppColors.red),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    Widget line(IconData icon, Color color, String text, {Key? key}) => Padding(
      key: key,
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppText.body.copyWith(fontSize: 15.5))),
        ],
      ),
    );
    return AppCard(
      key: const ValueKey('advice-notes'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(t('advice_notes'), style: AppText.hName)),
              _SpeakerButton(
                key: const ValueKey('advice-notes-speak'),
                label: t('field_listen_card'),
                onPressed: onSpeak,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < notes.length; i++)
                  line(
                    _look(notes[i].kind).$1,
                    _look(notes[i].kind).$2,
                    notes[i].text,
                    key: ValueKey('advice-note-$i'),
                  ),
                if (open)
                  for (var i = 0; i < safety.length; i++)
                    line(AppIcons.warning, AppColors.amberDark, safety[i], key: ValueKey('advice-safety-$i')),
                if (safety.isNotEmpty) _MoreRow(open: open, onTap: onToggle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "More" / "Less" inside the last card (56 high to tap): opens the long safety notes.
class _MoreRow extends ConsumerWidget {
  const _MoreRow({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final label = t(open ? 'less_label' : 'more_label');
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        key: const ValueKey('advice-more'),
        height: Dimens.minTouch,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Dimens.radiusSmall),
            onTap: () {
              Haptics.tap();
              onTap();
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The word shrinks rather than overflow at a big text size.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppText.button.copyWith(fontSize: 16, color: AppColors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(open ? AppIcons.up : AppIcons.down, size: 24, color: AppColors.blue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
