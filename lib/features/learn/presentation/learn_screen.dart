import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/design_widgets.dart';

class LearnScreen extends StatefulWidget {
  final VoidCallback onPractice;
  const LearnScreen({super.key, required this.onPractice});
  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  int _tab = 0;
  static const _tabs = [
    'المنهج الأساسي',
    'التدريب',
    'تقنيات متقدمة',
    'كورسات الأغاني',
  ];
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('learn'),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 12),
                        child: ChoiceChip(
                          label: Text(_tabs[i]),
                          selected: _tab == i,
                          onSelected: (_) => setState(() => _tab = i),
                          selectedColor: AppTheme.gold.withValues(alpha: .16),
                          labelStyle: TextStyle(
                            color: _tab == i ? AppTheme.gold : AppTheme.cream,
                          ),
                          side: BorderSide(
                            color: _tab == i ? AppTheme.gold : AppTheme.border,
                          ),
                          showCheckmark: false,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.border.withValues(alpha: .4),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withValues(alpha: .15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.workspace_premium_outlined,
                            color: AppTheme.gold,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'فتح المسار الكامل',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'الوصول إلى جميع الدروس والأغاني المميزة',
                                style: TextStyle(
                                  fontSize: 17,
                                  color: AppTheme.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => showPreviewInfo(
                          context,
                          title: 'فتح المسار الكامل',
                        ),
                        child: const Text('بدء التجربة المجانية'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppTheme.gold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tab == 0 ? 'الأساسيات - المستوى ١' : _tabs[_tab],
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        showPreviewInfo(context, title: _tabs[_tab]),
                    child: const Text('الكل ‹'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, c) => SizedBox(
                  height: c.maxWidth < 600 ? 300 : 340,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    separatorBuilder: (_, _) => const SizedBox(width: 18),
                    itemBuilder: (context, i) => SizedBox(
                      width: c.maxWidth < 600 ? c.maxWidth * .86 : 300,
                      child: _lesson(context, i),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F0F),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.gold),
                        SizedBox(width: 10),
                        Text(
                          'الأساسيات',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Spacer(),
                        Text('Level 1', style: TextStyle(color: AppTheme.gold)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 1; i <= 10; i++)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 14,
                              ),
                              child: Tooltip(
                                message: i == 1 ? 'المستوى الحالي' : 'قريباً',
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == 1
                                        ? AppTheme.gold
                                        : AppTheme.card,
                                    border: Border.all(
                                      color: i == 1
                                          ? AppTheme.gold
                                          : AppTheme.border,
                                    ),
                                  ),
                                  child: Text(
                                    '$i',
                                    style: TextStyle(
                                      color: i == 1
                                          ? Colors.black
                                          : AppTheme.cream,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _lesson(BuildContext context, int i) {
    const titles = [
      'مقدمة في اللازمات (Riffs)',
      'مقدمة في الألحان',
      'الأوتار - مقدمة',
      'تغيير الأوتار',
    ];
    const kinds = ['لازمات • ١', 'لحن • ١', 'أوتار • ١', 'أوتار • ١'];
    const counts = ['1/8', '1/7', '1/7', '0/6'];
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titles[i],
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'محتوى الدرس قيد الإعداد. يمكنك الآن تجربة واجهة العزف.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onPractice();
                    },
                    child: const Text('تجربة العزف'),
                  ),
                ],
              ),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DesignImage('s3_${i + 1}.png'),
                  if (i == 3)
                    const ColoredBox(
                      color: Colors.black45,
                      child: Center(
                        child: Icon(
                          Icons.lock_outline,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        kinds[i],
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.gold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Text(
                titles[i],
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  for (var star = 0; star < 3; star++)
                    Icon(
                      star == 0 && i == 0 ? Icons.star : Icons.star_border,
                      size: 21,
                      color: star == 0 && i == 0
                          ? AppTheme.gold
                          : AppTheme.cream,
                    ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      counts[i],
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.cream,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: i == 3 ? 0 : 1 / (i == 0 ? 8 : 7),
              minHeight: 4,
              backgroundColor: Colors.transparent,
              color: i == 0 ? AppTheme.gold : const Color(0xFFA0B7B7),
            ),
          ],
        ),
      ),
    );
  }
}
