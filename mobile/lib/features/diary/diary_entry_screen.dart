import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../core/offline/offline_queue.dart' show newIdempotencyKey;
import '../../core/providers.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/haptics.dart';
import '../../core/voice/utterance.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/voice_scaffold.dart';
import '../scan/scan_flow.dart';
import 'date_words.dart';
import 'diary_providers.dart';
import 'diary_widgets.dart';
import 'saved_speech.dart';

enum _Step { crop, medicine, summary, day, saved }

/// Writes one spray into the diary. Two ways in, one set of screens:
///
/// * "I sprayed this" on an advice card ([adviceId] set): the medicine is known, so the farmer only confirms with
///   the green tick (or picks one of several medicines, or another day).
/// * "Write a spray" (plus button of the diary): crop, then the medicine's name typed or tapped from names used
///   before, then the same confirm screen.
///
/// Every step is its own screen with its own speech; saving shows the warnings the server found, in words, pictures and
/// colour, and says them aloud. With no internet the entry waits in the offline queue.
class DiaryEntryScreen extends ConsumerStatefulWidget {
  const DiaryEntryScreen({super.key, this.adviceId, this.cropId, this.productId});

  final String? adviceId;
  final String? cropId;
  final String? productId;

  @override
  ConsumerState<DiaryEntryScreen> createState() => _DiaryEntryScreenState();
}

class _DiaryEntryScreenState extends ConsumerState<DiaryEntryScreen> {
  /// One speech identity per step: a step that closes must not cut off what the next step says.
  final Map<_Step, Object> _owners = {for (final s in _Step.values) s: Object()};
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameFocus = FocusNode();

  late _Step _step;
  String? _cropId;
  int _cropPage = 0;
  String? _productId;
  DayChoice _choice = DayChoice.today;
  DateTime? _otherDay;

  /// Coming back from the day chooser: the screen only says the chosen day, not its whole script again.
  bool _quietSummary = false;
  bool _saving = false;
  String? _draftKey;
  Object? _error;
  SaveOutcome? _outcome;

  bool get _fromAdvice => (widget.adviceId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    // The name field draws its green glow while it has focus.
    _nameFocus.addListener(() {
      if (mounted) setState(() {});
    });
    final crop = widget.cropId;
    _cropId = crop == null || crop.isEmpty ? null : crop;
    _productId = widget.productId;
    final advice = _advice(ref.read(scanFlowProvider).scan?.advice);
    // An advice without medicines (the expert route) needs a typed name.
    _step = !_fromAdvice || _cropId == null
        ? _Step.crop
        : (advice != null && advice.products.isEmpty ? _Step.medicine : _Step.summary);
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The advice this entry is for, when the scan it came from is still in memory.
  AdviceOut? _advice(AdviceOut? current) => current != null && current.id == widget.adviceId ? current : null;

  Object _owner(_Step step) => _owners[step]!;

  Future<void> _say(_Step step, List<Utterance> items) =>
      ref.read(voiceServiceProvider).speak(items, owner: _owner(step));

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  void _goTo(_Step step) => setState(() {
    _step = step;
    _quietSummary = false;
  });

  // ---------------------------------------------------------------------------------------------- what is chosen

  /// The medicine of an advice that the farmer picked (the preselected one, else the first).
  ProductOut? _selectedProduct(AdviceOut? advice) {
    final products = advice?.products ?? const <ProductOut>[];
    if (products.isEmpty) return null;
    return products.firstWhere((p) => p.productId == _productId, orElse: () => products.first);
  }

  String _productName(ProductOut product, String lang) {
    final name = product.activeIngredient.forLang(lang);
    final brand = product.brandExamples.isEmpty ? '' : product.brandExamples.first;
    return brand.isEmpty ? name : '$name, $brand';
  }

  /// The medicine's name as shown and spoken: from the advice, else what was typed.
  String _medicineName(AdviceOut? advice, String lang) {
    final typed = _name.text.trim();
    if (typed.isNotEmpty) return typed;
    final product = _selectedProduct(advice);
    return product == null ? '' : _productName(product, lang);
  }

  /// The day of the spray: null for today (the server's own clock is used), else noon of that day.
  DateTime? _sprayedAt() {
    final today = dayOnly(ref.read(clockProvider)());
    final day = switch (_choice) {
      DayChoice.today => null,
      DayChoice.yesterday => DateTime(today.year, today.month, today.day - 1),
      DayChoice.other => _otherDay,
    };
    return day == null ? null : DateTime(day.year, day.month, day.day, 12).toUtc();
  }

  DateTime _chosenDay() {
    final today = dayOnly(ref.read(clockProvider)());
    return switch (_choice) {
      DayChoice.today => today,
      DayChoice.yesterday => DateTime(today.year, today.month, today.day - 1),
      DayChoice.other => _otherDay ?? today,
    };
  }

  // ---------------------------------------------------------------------------------------------- saving

  Future<void> _save() async {
    final cropId = _cropId;
    if (_saving || cropId == null) return;
    final lang = ref.read(languageProvider);
    final advice = _advice(ref.read(scanFlowProvider).scan?.advice);
    final typed = _name.text.trim();
    if (!_fromAdvice && typed.isEmpty) return;

    // Only name the medicine when the farmer chose it: one of several, or typed. With a single medicine the
    // advice id alone means "the one that was read out".
    final several = (advice?.products.length ?? 0) > 1;
    final productId = _fromAdvice && typed.isEmpty
        ? (several ? _selectedProduct(advice)?.productId : (advice == null ? widget.productId : null))
        : null;
    final log = SprayLogIn(
      cropId: cropId,
      adviceId: _fromAdvice ? widget.adviceId : null,
      productId: productId,
      freeText: typed.isEmpty ? null : typed,
      sprayedAt: _sprayedAt(),
    );
    final name = _medicineName(advice, lang);

    setState(() => _saving = true);
    _draftKey ??= newIdempotencyKey();
    final outcome = await ref.read(spraySaverProvider).save(log, name: name, idempotencyKey: _draftKey);
    if (!mounted) return;
    switch (outcome) {
      case SavedOnline() || SavedOffline():
        Haptics.success();
        _draftKey = null;
        setState(() {
          _saving = false;
          _outcome = outcome;
          _step = _Step.saved;
        });
      case SaveFailed(:final error):
        Haptics.error();
        setState(() {
          _saving = false;
          _error = error;
        });
    }
  }

  // ---------------------------------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ErrorRetryScreen(
        error: error,
        onRetry: () {
          setState(() => _error = null);
          _save();
        },
        onBack: () => setState(() => _error = null),
      );
    }
    return switch (_step) {
      _Step.crop => _cropStep(),
      _Step.medicine => _medicineStep(),
      _Step.summary => _summaryStep(),
      _Step.day => _dayStep(),
      _Step.saved => _savedStep(),
    };
  }

  // ---- crop

  /// The gutter of every step: the mockup's 16 dp, and 16 on top (its `.pad`).
  static const _bodyPadding = EdgeInsets.fromLTRB(Dimens.gutter, Dimens.gutter, Dimens.gutter, 0);

  List<String> _cropChoices() {
    final mine = ref.watch(sessionProvider.select((s) => s.farmer?.crops)) ?? const <String>[];
    final supported = ref.watch(supportedCropsProvider).value ?? const <String>[];
    final seen = <String>{};
    return [
      for (final id in [...mine, ...supported])
        if (id.isNotEmpty && seen.add(id.toLowerCase())) id,
    ];
  }

  Widget _cropStep() {
    final t = ref.watch(stringsProvider);
    final ids = _cropChoices();
    final loading = ids.isEmpty && ref.watch(supportedCropsProvider).isLoading;
    final pages = (ids.length / CropGrid.perPage).ceil().clamp(1, 99);
    final page = _cropPage.clamp(0, pages - 1);
    final shown = ids.skip(page * CropGrid.perPage).take(CropGrid.perPage).toList();
    final hasPrev = page > 0;
    final hasNext = page < pages - 1;
    return VoiceScaffold(
      key: const ValueKey('step-crop'),
      owner: _owner(_Step.crop),
      script: promptList(const ['diary_pick_crop']),
      title: t('diary_add_label'),
      alignTop: true,
      wideAction: true,
      bodyPadding: _bodyPadding,
      onBack: _leave,
      // Six crops to a page: the strip holds the arrows (a square outline one back, a wide green one on).
      bottomRight: pages <= 1
          ? null
          : Row(
              children: [
                if (hasPrev)
                  if (hasNext)
                    AppButton(
                      key: const ValueKey('crops-prev'),
                      style: AppButtonStyle.outline,
                      square: true,
                      icon: AppIcons.back,
                      semanticLabel: t('a11y_prev_page'),
                      onPressed: () => setState(() => _cropPage = page - 1),
                    )
                  else
                    Expanded(
                      child: AppButton(
                        key: const ValueKey('crops-prev'),
                        style: AppButtonStyle.outline,
                        icon: AppIcons.back,
                        label: t('a11y_prev_page'),
                        semanticLabel: t('a11y_prev_page'),
                        onPressed: () => setState(() => _cropPage = page - 1),
                      ),
                    ),
                if (hasPrev && hasNext) const SizedBox(width: 12),
                if (hasNext)
                  Expanded(
                    child: AppButton(
                      key: const ValueKey('crops-next'),
                      icon: AppIcons.greenArrow,
                      label: t('a11y_next_page'),
                      semanticLabel: t('a11y_next_page'),
                      onPressed: () => setState(() => _cropPage = page + 1),
                    ),
                  ),
              ],
            ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : CropGrid(
              cropIds: shown,
              onPick: (id) {
                // An advice that is still in memory brings its medicines: only the confirm screen is left.
                final advice = _advice(ref.read(scanFlowProvider).scan?.advice);
                final known = _fromAdvice && advice != null && advice.products.isNotEmpty;
                setState(() {
                  _cropId = id;
                  _step = known ? _Step.summary : _Step.medicine;
                  _quietSummary = false;
                });
              },
            ),
    );
  }

  // ---- medicine (typed or from names used before)

  List<String> _recentNames() {
    final server = ref.watch(sprayLogsProvider).value ?? const <SprayLogOut>[];
    final pending = ref.watch(pendingSpraysProvider).items;
    final entries = mergeDiaryEntries(server, pending, ref.read(clockProvider)());
    return recentMedicineNames(entries);
  }

  void _chooseName(String name) {
    _name.text = name;
    _goTo(_Step.summary);
  }

  void _nextFromMedicine() {
    if (_name.text.trim().isEmpty) {
      _say(_Step.medicine, promptList(const ['diary_type_medicine']));
      return;
    }
    FocusScope.of(context).unfocus();
    _goTo(_Step.summary);
  }

  /// `.input`: 18 / 600 text.
  static const _inputText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.ink);

  /// `.input`: radius 16, a 2 px border.
  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: 2),
  );

  Widget _medicineStep() {
    final t = ref.watch(stringsProvider);
    final recents = _recentNames();
    final cropId = _cropId;
    final recentTitle = t('diary_recent_title');
    return VoiceScaffold(
      key: const ValueKey('step-medicine'),
      owner: _owner(_Step.medicine),
      script: promptList(const ['diary_type_medicine']),
      replayScript: promptList(['diary_type_medicine', if (recents.isNotEmpty) 'diary_pick_recent']),
      title: t('diary_add_label'),
      alignTop: true,
      wideAction: true,
      // 12 + 4 instead of 16: the field's focus glow reaches 4 dp outside it and the scroll view would cut it off.
      bodyPadding: const EdgeInsets.fromLTRB(12, Dimens.gutter, 12, 0),
      onBack: _fromAdvice ? _leave : () => _goTo(_Step.crop),
      bottomRight: AppButton(
        key: const ValueKey('diary-next'),
        icon: AppIcons.tickBold,
        label: t('diary_next_label'),
        semanticLabel: t('diary_next_label'),
        onPressed: _name.text.trim().isEmpty ? null : _nextFromMedicine,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cropId != null) ...[CropCard(cropId: cropId), const SizedBox(height: 12)],
            _FieldLabel(icon: AppIcons.medicine, text: t('diary_medicine_hint')),
            DecoratedBox(
              // `.input.focus`: a green border and a soft green glow around it.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: _nameFocus.hasFocus
                    ? [BoxShadow(color: AppColors.green.withValues(alpha: 0.14), spreadRadius: 4)]
                    : null,
              ),
              child: Semantics(
                label: t('diary_medicine_hint'),
                child: TextField(
                  key: const ValueKey('diary-name-field'),
                  controller: _name,
                  focusNode: _nameFocus,
                  maxLength: 200,
                  maxLines: 2,
                  minLines: 1,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  autocorrect: false,
                  style: _inputText,
                  buildCounter: (context, {required currentLength, required isFocused, required maxLength}) => null,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.card,
                    // 58 high with one line of 18 / 1.4 text.
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16.4),
                    border: _border(AppColors.line),
                    enabledBorder: _border(AppColors.line),
                    focusedBorder: _border(AppColors.green),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _nextFromMedicine(),
                ),
              ),
            ),
            if (recents.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionLabel(recentTitle, hindi: isDevanagari(recentTitle)),
              const SizedBox(height: 10),
              for (var i = 0; i < recents.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == recents.length - 1 ? 0 : 12),
                  child: _RecentName(
                    key: ValueKey('recent-$i'),
                    name: recents[i],
                    onTap: () => _chooseName(recents[i]),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---- summary: the confirm screen

  Widget _summaryStep() {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final cropId = _cropId ?? '';
    final advice = _advice(ref.watch(scanFlowProvider.select((s) => s.scan?.advice)));
    final products = _name.text.trim().isEmpty ? (advice?.products ?? const <ProductOut>[]) : const <ProductOut>[];
    final selected = _selectedProduct(advice);
    final name = _medicineName(advice, lang);
    final dayTitle = t('diary_pick_day_title');

    // What the screen says: the medicine, the question, what the tick and the cross do.
    final script = <Utterance>[
      if (products.length > 1)
        const PromptUtterance('diary_pick_product')
      else if (name.isNotEmpty)
        TextUtterance(name, lang: lang),
      ...promptList(
        _fromAdvice ? const ['diary_did_spray', 'diary_tick_sprayed', 'diary_cross_back'] : const ['diary_tap_save'],
      ),
    ];

    return VoiceScaffold(
      key: const ValueKey('step-summary'),
      owner: _owner(_Step.summary),
      script: script,
      speakEnabled: !_quietSummary,
      title: t('diary_add_label'),
      alignTop: true,
      wideAction: true,
      bodyPadding: _bodyPadding,
      onBack: _fromAdvice ? _leave : () => _goTo(_Step.medicine),
      // The strip: a red cross to refuse (only for an advice) and the wide green tick that writes it down.
      bottomRight: Row(
        children: [
          if (_fromAdvice) ...[
            AppButton(
              key: const ValueKey('diary-cancel'),
              style: AppButtonStyle.danger,
              square: true,
              icon: AppIcons.cross,
              semanticLabel: t('a11y_no'),
              onPressed: _leave,
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: _saving
                ? const Center(child: SizedBox(width: 36, height: 36, child: CircularProgressIndicator()))
                : AppButton(
                    key: const ValueKey('diary-save'),
                    icon: AppIcons.tickBold,
                    label: t('diary_save_label'),
                    semanticLabel: t('diary_save_label'),
                    onPressed: cropId.isEmpty ? null : _save,
                  ),
          ),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cropId.isNotEmpty) ...[
            CropCard(cropId: cropId, nameKey: const ValueKey('diary-crop-name')),
            const SizedBox(height: 12),
          ],
          if (products.isNotEmpty)
            for (final p in products)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MedicineCard(
                  product: p,
                  selected: p.productId == selected?.productId,
                  onTap: () {
                    setState(() => _productId = p.productId);
                    _say(_Step.summary, [
                      TextUtterance(_productName(p, lang), lang: lang),
                      ?SpokenOut(text: p.doseText).toUtterance(lang),
                    ]);
                  },
                ),
              )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _NameCard(
                key: const ValueKey('diary-medicine-name'),
                name: name.isEmpty ? t('diary_no_name') : name,
                onTap: name.isEmpty ? null : () => _say(_Step.summary, [TextUtterance(name, lang: lang)]),
              ),
            ),
          SectionLabel(dayTitle, hindi: isDevanagari(dayTitle)),
          const SizedBox(height: 10),
          DateChoiceRow(
            choice: _choice,
            otherDay: _otherDay,
            onToday: () => _pickDay(DayChoice.today),
            onYesterday: () => _pickDay(DayChoice.yesterday),
            onOther: () {
              _say(_Step.summary, promptList(const ['diary_other_day']));
              _goTo(_Step.day);
            },
          ),
        ],
      ),
    );
  }

  void _pickDay(DayChoice choice) {
    setState(() {
      _choice = choice;
      _quietSummary = true;
    });
    _say(_Step.summary, promptList([choice == DayChoice.today ? 'diary_today' : 'diary_yesterday']));
  }

  // ---- other day

  Widget _dayStep() {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final words = ref.watch(dateWordsProvider);
    final today = dayOnly(ref.read(clockProvider)());
    return VoiceScaffold(
      key: const ValueKey('step-day'),
      owner: _owner(_Step.day),
      script: promptList(const ['diary_pick_date']),
      // "Which day?" is the name of this screen, in its top bar.
      title: t('diary_pick_day_title'),
      alignTop: true,
      bodyPadding: _bodyPadding,
      onBack: () => _goTo(_Step.summary),
      body: DayChooser(
        onPick: (back) {
          final day = DateTime(today.year, today.month, today.day - back);
          setState(() {
            _choice = switch (back) {
              0 => DayChoice.today,
              1 => DayChoice.yesterday,
              _ => DayChoice.other,
            };
            _otherDay = day;
            _step = _Step.summary;
            _quietSummary = true;
          });
          _say(_Step.summary, [
            if (back == 0)
              const PromptUtterance('diary_today')
            else if (back == 1)
              const PromptUtterance('diary_yesterday')
            else
              TextUtterance(words.spoken(day), lang: lang),
          ]);
        },
      ),
    );
  }

  // ---- saved

  Widget _savedStep() {
    final t = ref.watch(stringsProvider);
    final lang = ref.watch(languageProvider);
    final words = ref.watch(dateWordsProvider);
    final resources = ref.watch(resourcesProvider);
    final outcome = _outcome;
    final online = outcome is SavedOnline;
    final entry = online ? outcome.entry : null;
    final warnings = [
      for (final w in entry?.warnings ?? const <WarningOut>[])
        if (!w.text.isEmpty) w,
    ];
    final advice = _advice(ref.read(scanFlowProvider).scan?.advice);
    final name = (entry?.productName ?? '').trim().isNotEmpty ? entry!.productName! : _medicineName(advice, lang);
    final day = _chosenDay();
    final now = ref.read(clockProvider)();
    final relative = words.relative(day, now);
    final cropId = _cropId ?? '';

    final title = t(online ? 'diary_saved_title' : 'diary_saved_offline_title');
    // With warnings the header shrinks, so the first warning is on screen without scrolling.
    final big = warnings.isEmpty;
    final mark = IconDot(
      key: ValueKey(online ? 'saved-ok' : 'saved-offline'),
      online ? AppIcons.tickBold : AppIcons.clock,
      // Green is "done"; a grey (white on the grey card) clock is "waiting to be sent".
      background: online ? AppColors.green : AppColors.card,
      foreground: online ? Colors.white : AppColors.inkSoft,
      size: big ? 72 : 52,
      iconSize: big ? 38 : 28,
      round: true,
      shadow: online,
    );

    final script = online ? savedScript(entry!, lang) : promptList(const ['diary_saved_offline']);
    return VoiceScaffold(
      key: const ValueKey('step-saved'),
      owner: _owner(_Step.saved),
      script: script,
      title: t('diary_add_label'),
      alignTop: true,
      wideAction: true,
      bodyPadding: _bodyPadding,
      onBack: _finish,
      bottomRight: AppButton(
        key: const ValueKey('diary-done'),
        icon: AppIcons.tickBold,
        label: t('diary_done_label'),
        semanticLabel: t('diary_done_label'),
        onPressed: _finish,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            color: online ? AppColors.greenSoft : AppColors.neutralSoft,
            flat: true,
            padding: big ? const EdgeInsets.symmetric(horizontal: 18, vertical: 24) : const EdgeInsets.all(14),
            child: big
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      mark,
                      const SizedBox(height: 12),
                      Text(title, textAlign: TextAlign.center, style: AppText.big),
                      if (!online) ...[
                        const SizedBox(height: 10),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AppPill(
                            t('diary_waiting_label'),
                            background: AppColors.card,
                            foreground: AppColors.inkSoft,
                            icon: AppIcons.clock,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      mark,
                      const SizedBox(width: 12),
                      Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
                    ],
                  ),
          ),
          for (final w in warnings) ...[
            const SizedBox(height: 12),
            DiaryWarningCard(
              warning: w,
              onSpeak: () {
                final say = warningUtterance(w, lang);
                if (say != null) _say(_Step.saved, [say]);
              },
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Row(
              children: [
                const IconDot(AppIcons.medicine, background: AppColors.blueSoft, foreground: AppColors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name.isEmpty ? t('diary_no_name') : name, style: AppText.hName),
                      Text(
                        [
                          if (cropId.isNotEmpty) resources.cropName(cropId.toLowerCase(), lang),
                          relative == null ? words.written(day) : '$relative, ${words.written(day)}',
                        ].join(' · '),
                        style: AppText.hMeta,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Done: back to the advice's Home, or to the diary list the entry was written from.
  void _finish() {
    if (_fromAdvice || !context.canPop()) {
      context.go(Routes.home);
    } else {
      context.pop();
    }
  }
}

/// `.field-l`: a green picture and a word above a field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.green),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: AppText.hName.copyWith(fontSize: 15))),
        ],
      ),
    ),
  );
}

/// A name used before: a card with the flask and the name, one tap.
class _RecentName extends StatelessWidget {
  const _RecentName({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    semanticLabel: name,
    child: Row(
      children: [
        const IconDot(AppIcons.medicine, background: AppColors.blueSoft, foreground: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: AppText.hName)),
      ],
    ),
  );
}

/// The medicine as one card when there is no advice card to show (typed name, or an advice that is no longer in memory).
class _NameCard extends StatelessWidget {
  const _NameCard({super.key, required this.name, required this.onTap});

  final String name;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    semanticLabel: onTap == null ? null : name,
    child: Row(
      children: [
        const IconDot(AppIcons.medicine, background: AppColors.blueSoft, foreground: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: AppText.hName)),
      ],
    ),
  );
}
