import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../core/tokens.dart';

/// The three ways into Discover, as one control.
///
/// **Why a control and not three stacked sections.** Discover used to render
/// Upcoming, Latest Results and Communities one under another down a single
/// page, so finding a community meant scrolling past every fixture and every
/// result, and a guest and a member saw the page reorganise itself around what
/// they were allowed to read. The approved direction is one shell with three
/// tabs, identical for both readers: what changes with a session is what the
/// cards inside can *do*, never the shape of the page.
///
/// **Built on [TabBar] on purpose.** The selected state has to reach a screen
/// reader and the control has to be reachable from a keyboard on the web, and
/// Material's tabs already carry both — `Tab` exposes `Semantics(selected:)`
/// and the bar joins the focus traversal. A hand-rolled row of buttons would
/// have meant reimplementing that, badly. What is custom here is only the
/// paint: a filled green pill for the selected tab, quiet ink for the rest.
///
/// **It measures before it decides.** Three full labels across a 320px phone
/// do not fit in Arabic — `المباريات القادمة` alone wants more than a third of
/// the line — and the approved contract refuses both shrinking them into
/// unreadability and abbreviating them. So the bar lays the labels out equally
/// when they fit and becomes scrollable when they do not, which keeps every
/// word intact at every width.
class DiscoverTabs extends StatelessWidget {
  const DiscoverTabs({
    super.key,
    required this.controller,
    required this.labels,
  });

  final TabController controller;

  /// Upcoming, Latest Results, Communities — already localized, and never
  /// shortened here.
  final List<String> labels;

  /// The type scale the tabs are painted in. Read twice: once to measure, once
  /// to draw, so the decision and the result cannot disagree.
  static const _labelStyle = TextStyle(
    fontSize: 13,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );

  static const _horizontalPadding = 14.0;
  static const _barHeight = 44.0;

  double _widestLabel(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: _labelStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
      painter.dispose();
    }
    return widest;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Layout.sheetGutter,
        Gap.md,
        Layout.sheetGutter,
        Gap.sm,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Equal thirds only if the longest label still fits inside one,
          // padding included. Otherwise every label keeps its full width and
          // the bar scrolls.
          final third = constraints.maxWidth / labels.length;
          final fits = _widestLabel(context) + _horizontalPadding * 2 <= third;

          return DecoratedBox(
            decoration: BoxDecoration(
              color: GoColors.rowTintLight,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: SizedBox(
              height: _barHeight,
              child: TabBar(
                key: const Key('discoverTabs'),
                controller: controller,
                isScrollable: !fits,
                tabAlignment: fits ? TabAlignment.fill : TabAlignment.start,
                // The pill *is* the indicator, so it sits behind the label
                // rather than under it.
                indicator: BoxDecoration(
                  color: GoColors.primaryDeep,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(3),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: GoColors.onSurfaceVariant,
                labelStyle: _labelStyle,
                unselectedLabelStyle:
                    _labelStyle.copyWith(fontWeight: FontWeight.w600),
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: _horizontalPadding,
                ),
                splashBorderRadius: BorderRadius.circular(Radii.pill),
                tabs: [
                  for (final label in labels)
                    Tab(
                      height: _barHeight - 6,
                      child: Text(
                        label,
                        maxLines: 1,
                        // Never ellipsized: the bar scrolls instead, which is
                        // what keeps an Arabic label whole at 320px.
                        softWrap: false,
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
