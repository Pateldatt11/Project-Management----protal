import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

import 'sdui_mobile_ui_config.dart';

typedef SduiTabCallback = void Function(String tab);
typedef SduiActionCallback = void Function(String action);

/// Wrap your existing SDUI-rendered screen body with this widget.
///
/// It preserves the native Android status bar and renders only the floating
/// top/bottom app chrome inside Flutter. The nav bars are responsive for
/// small phones, normal phones, foldables, tablets, and landscape widths.
class SduiFloatingNativeShell extends StatefulWidget {
  const SduiFloatingNativeShell({
    super.key,
    required this.config,
    required this.currentTab,
    required this.child,
    required this.onTabSelected,
    this.onActiveTabRetap,
    this.onAction,
    this.searchQuery = '',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchClear,
    this.forceNestedBackButton = false,
    this.unreadCount = 0,
    this.userInitials = 'U',
  });

  final SduiMobileUiConfig config;
  final String currentTab;
  final Widget child;
  final SduiTabCallback onTabSelected;
  final VoidCallback? onActiveTabRetap;
  final SduiActionCallback? onAction;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final bool forceNestedBackButton;
  final int unreadCount;
  final String userInitials;

  @override
  State<SduiFloatingNativeShell> createState() => _SduiFloatingNativeShellState();
}

class _SduiFloatingNativeShellState extends State<SduiFloatingNativeShell> {
  Timer? _tapDebounceTimer;
  late final ScrollController _primaryScrollController;
  bool _topPaddingCollapsed = false;
  bool _topProtectionCollapseArmed = false;
  bool _sideMenuOpen = false;
  bool _menuLottieAnimating = false;


  @override
  void initState() {
    super.initState();
    _primaryScrollController = ScrollController();
    _primaryScrollController.addListener(_handlePrimaryScroll);
  }

  void _handlePrimaryScroll() {
    // v256: Task Board uses a fixed hard-coded top reserve. Do not let any
    // scroll controller alter that reserve, otherwise a horizontal carousel
    // swipe can make the board appear to jump upward under the floating nav.
    if (_isTaskBoardShellContext(widget.config, widget.currentTab)) return;
    if (!_isScrollAwareTopPaddingEnabled(widget.config)) return;
    if (!_topProtectionCollapseArmed) return;
    if (!_primaryScrollController.hasClients) return;
    final pixels = _primaryScrollController.positions.isEmpty
        ? 0.0
        : _primaryScrollController.positions
            .map((position) => position.pixels)
            .fold<double>(0, (maxValue, pixels) => pixels > maxValue ? pixels : maxValue);
    _updateTopPaddingCollapseFromPixels(pixels);
  }

  void _updateTopPaddingCollapseFromPixels(double pixels) {
    if (!_isScrollAwareTopPaddingEnabled(widget.config)) return;
    final trigger = _scrollAwareCollapseTrigger(widget.config);
    final shouldCollapse = pixels > trigger;
    if (shouldCollapse != _topPaddingCollapsed && mounted) {
      setState(() => _topPaddingCollapsed = shouldCollapse);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // v256: only vertical page scrolls may collapse the scroll-aware top
    // protection. The Task Board carousel is a horizontal PageView; its scroll
    // notifications previously armed/collapsed the top protection using the
    // horizontal page offset, so after a swipe the board looked like it moved
    // upward and could not be dragged back down. Ignore horizontal/nested board
    // carousel notifications completely.
    if (notification.metrics.axis != Axis.vertical) return false;

    if (_isTaskBoardShellContext(widget.config, widget.currentTab)) {
      if (_topPaddingCollapsed || _topProtectionCollapseArmed) {
        setState(() {
          _topPaddingCollapsed = false;
          _topProtectionCollapseArmed = false;
        });
      }
      return false;
    }

    // Keep the first paint protected. Some nested scroll views restore a non-zero
    // offset during route/tab changes; treating that as a real scroll collapses
    // the top protection and lets the page title/search sit under the floating
    // pill. Collapse only after an actual user vertical scroll update.
    if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      _topProtectionCollapseArmed = true;
    }
    if (!_topProtectionCollapseArmed) return false;
    _updateTopPaddingCollapseFromPixels(notification.metrics.pixels);
    return false;
  }

  @override
  void didUpdateWidget(covariant SduiFloatingNativeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentTab != widget.currentTab) {
      _topPaddingCollapsed = false;
      _topProtectionCollapseArmed = false;
    }
  }

  @override
  void dispose() {
    _tapDebounceTimer?.cancel();
    _primaryScrollController.removeListener(_handlePrimaryScroll);
    _primaryScrollController.dispose();
    super.dispose();
  }

  void _runDebounced(VoidCallback action) {
    final debounceMs = _asInt(widget.config.navigationConfig['tapDebounceMs'], fallback: 220);
    if (_tapDebounceTimer?.isActive ?? false) return;
    _tapDebounceTimer = Timer(Duration(milliseconds: debounceMs), () {});
    final haptics = widget.config.navigationConfig['haptics']?.toString();
    if (haptics == 'selectionClick') HapticFeedback.selectionClick();
    action();
  }

  Map<String, dynamic> get _sideMenuConfig => _asMap(widget.config.raw['sideMenuConfig']);

  Map<String, dynamic> get _menuLottieConfig {
    final sideMenu = _sideMenuConfig;
    return _asMap(
      sideMenu['hamburgerLottie'] ??
          sideMenu['menuLottie'] ??
          sideMenu['lottieIcon'] ??
          sideMenu['animationIcon'],
    );
  }

  bool get _menuLottieEnabled {
    final lottie = _menuLottieConfig;
    return _asBool(lottie['enabled']) ||
        _asBool(_sideMenuConfig['useLottieMenuIcon']) ||
        _asString(lottie['asset']).isNotEmpty;
  }

  String get _menuLottieAsset {
    final lottie = _menuLottieConfig;
    return _asString(
      lottie['asset'] ?? _sideMenuConfig['menuLottieAsset'],
      fallback: 'assets/lottie/menu_in_out.json',
    );
  }

  void _startMenuLottieOnce() {
    if (!_menuLottieEnabled || _menuLottieAnimating || !mounted) return;
    setState(() => _menuLottieAnimating = true);
  }

  void _finishMenuLottie() {
    if (!_menuLottieAnimating || !mounted) return;
    setState(() => _menuLottieAnimating = false);
  }

  void _handleTopMenuPressed() {
    if (_menuLottieAnimating) return;
    _startMenuLottieOnce();
    if (_sideMenuOpen) {
      _closeSideMenu();
    } else {
      unawaited(_openSideMenu());
    }
  }

  void _handleTopBackPressed() {
    if (_sideMenuOpen) {
      if (_menuLottieAnimating) return;
      _startMenuLottieOnce();
      _closeSideMenu();
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _handleTabTap(String tab) {
    final route = _canonicalSideMenuRoute(tab);
    _runDebounced(() {
      if (_sideMenuOpen) _closeSideMenu();
      if (route == widget.currentTab) {
        widget.onActiveTabRetap?.call();
        return;
      }
      widget.onTabSelected(route);
    });
  }

  Future<void> _openSideMenu() async {
    final menuConfig = _asMap(widget.config.raw['sideMenuConfig']);
    final items = _sideMenuItemsForConfig(widget.config);
    if (items.isEmpty) return;
    if (!mounted) return;
    setState(() => _sideMenuOpen = true);
  }

  void _closeSideMenu() {
    if (!_sideMenuOpen || !mounted) return;
    setState(() => _sideMenuOpen = false);
  }

  Curve _sideMenuCurve(Map<String, dynamic> menuConfig) {
    final value = _asString(menuConfig['animationCurve'], fallback: 'easeOutCubic').toLowerCase().trim();
    if (value == 'easeoutback') return Curves.easeOutBack;
    if (value == 'decelerate') return Curves.decelerate;
    if (value == 'fastoutslowin' || value == 'fastoutslowin') return Curves.fastOutSlowIn;
    return Curves.easeOutCubic;
  }

  Widget _buildCutSideMenuScaffold({required Widget child, required Color background}) {
    final menuConfig = _asMap(widget.config.raw['sideMenuConfig']);
    final items = _sideMenuItemsForConfig(widget.config);
    if (items.isEmpty) return child;

    final drawerColor = SduiMobileUiConfig.colorFromHex(
      _asString(menuConfig['background'] ?? menuConfig['drawerBackground'], fallback: '#4E8064'),
      const Color(0xFF4E8064),
    );
    final drawerText = SduiMobileUiConfig.colorFromHex(
      _asString(menuConfig['textColor'], fallback: '#FFFFFF'),
      Colors.white,
    );
    final selectedBg = SduiMobileUiConfig.colorFromHex(
      _asString(menuConfig['selectedBackground'], fallback: '#FFFFFF'),
      Colors.white,
    );
    final selectedText = SduiMobileUiConfig.colorFromHex(
      _asString(menuConfig['selectedTextColor'], fallback: '#FFFFFF'),
      Colors.white,
    );
    final animationMs = _asInt(menuConfig['animationMs'], fallback: 360).clamp(220, 520).toInt();
    final curve = _sideMenuCurve(menuConfig);
    final welcomeLabel = _asString(menuConfig['welcomeLabel'], fallback: 'Welcome back,');
    final welcomeName = _asString(menuConfig['welcomeName'], fallback: 'Project Hub');
    final showFooter = _asBool(menuConfig['showFooter'], fallback: true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth <= 0 ? MediaQuery.of(context).size.width : constraints.maxWidth;
        final height = constraints.maxHeight <= 0 ? MediaQuery.of(context).size.height : constraints.maxHeight;
        final drawerWidth = _asDouble(menuConfig['width'], fallback: width * .74).clamp(width * .66, width * .82).toDouble();
        // The active screen keeps its original size and moves farther right. The
        // Stack clips the overflow, creating the reference-style right-side cut.
        final translateRatio = _asDouble(menuConfig['translateXRatio'], fallback: .96).clamp(.76, .98).toDouble();
        final mainLeft = (drawerWidth * translateRatio).clamp(width * .58, width * .80).toDouble();
        final mainRadius = _asDouble(menuConfig['mainPanelBorderRadius'], fallback: 28).clamp(18, 36).toDouble();
        final panelTopInset = _asDouble(menuConfig['mainPanelTopInset'], fallback: 18).clamp(0, 44).toDouble();
        final panelBottomInset = _asDouble(menuConfig['mainPanelBottomInset'], fallback: 24).clamp(0, 48).toDouble();
        final verticalShrinkEnabled = _asBool(
          menuConfig['verticalShrinkEnabled'] ?? menuConfig['mainPanelVerticalShrinkEnabled'],
          fallback: true,
        );
        final verticalShrinkScale = verticalShrinkEnabled
            ? _asDouble(
                menuConfig['verticalShrinkScale'] ??
                    menuConfig['mainPanelVerticalShrinkScale'] ??
                    menuConfig['activePanelVerticalScale'],
                fallback: .965,
              ).clamp(.90, 1.0).toDouble()
            : 1.0;
        final panelContentPadding = EdgeInsets.fromLTRB(
          _asDouble(
            menuConfig['activePanelContentPaddingLeft'] ?? menuConfig['mainPanelContentPaddingLeft'],
            fallback: 18,
          ).clamp(0, 56).toDouble(),
          _asDouble(
            menuConfig['activePanelContentPaddingTop'] ?? menuConfig['mainPanelContentPaddingTop'],
            fallback: 10,
          ).clamp(0, 40).toDouble(),
          _asDouble(
            menuConfig['activePanelContentPaddingRight'] ?? menuConfig['mainPanelContentPaddingRight'],
            fallback: 18,
          ).clamp(0, 56).toDouble(),
          _asDouble(
            menuConfig['activePanelContentPaddingBottom'] ?? menuConfig['mainPanelContentPaddingBottom'],
            fallback: 10,
          ).clamp(0, 40).toDouble(),
        );
        final menuRadius = _asDouble(menuConfig['cornerRadius'], fallback: 30).clamp(22, 42).toDouble();
        final open = _sideMenuOpen;
        final activePanelRadius = open ? mainRadius : 0.0;
        final activePanelElevation = open ? _asDouble(menuConfig['depthElevation'], fallback: 24).clamp(8, 34).toDouble() : 0.0;

        Widget buildMenuItem(_SduiSideMenuItem item) {
          final selected = item.route == widget.currentTab;
          return Padding(
            padding: EdgeInsets.only(bottom: _asDouble(menuConfig['itemGap'], fallback: 9).clamp(4, 14).toDouble()),
            child: Material(
              color: selected ? selectedBg.withOpacity(.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                splashColor: selectedBg.withOpacity(.14),
                highlightColor: selectedBg.withOpacity(.08),
                onTap: () {
                  final route = _canonicalSideMenuRoute(item.route);
                  if (route != widget.currentTab) {
                    widget.onTabSelected(route);
                  } else {
                    widget.onActiveTabRetap?.call();
                  }
                  _closeSideMenu();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _asDouble(menuConfig['itemPaddingHorizontal'], fallback: 18).clamp(14, 26).toDouble(),
                    vertical: _asDouble(menuConfig['itemPaddingVertical'], fallback: 14).clamp(11, 20).toDouble(),
                  ),
                  child: Row(
                    children: [
                      Icon(item.icon, color: selected ? selectedText : drawerText.withOpacity(.86), size: 20),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? selectedText : drawerText.withOpacity(.92),
                            fontSize: 14.6,
                            fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                            letterSpacing: -.06,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final drawer = AnimatedOpacity(
          duration: Duration(milliseconds: (animationMs * .72).round()),
          curve: curve,
          opacity: open ? 1 : 0,
          child: DecoratedBox(
            decoration: BoxDecoration(color: drawerColor, borderRadius: BorderRadius.circular(menuRadius)),
            child: SafeArea(
              right: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _asDouble(menuConfig['drawerContentLeft'], fallback: 30).clamp(18, 42).toDouble(),
                  _asDouble(menuConfig['drawerContentTop'], fallback: 42).clamp(22, 68).toDouble(),
                  _asDouble(menuConfig['drawerContentRight'], fallback: 24).clamp(16, 34).toDouble(),
                  _asDouble(menuConfig['drawerContentBottom'], fallback: 28).clamp(18, 42).toDouble(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: _asDouble(menuConfig['avatarRadius'], fallback: 34).clamp(24, 42).toDouble(),
                      backgroundColor: Colors.white.withOpacity(.20),
                      child: Text(
                        widget.userInitials.isEmpty ? 'U' : (widget.userInitials.length > 2 ? widget.userInitials.substring(0, 2) : widget.userInitials).toUpperCase(),
                        style: TextStyle(color: drawerText, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ),
                    SizedBox(height: _asDouble(menuConfig['avatarTitleGap'], fallback: 28).clamp(20, 38).toDouble()),
                    Text(
                      welcomeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: drawerText.withOpacity(.72), fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      welcomeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: drawerText, fontSize: 27, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -.8),
                    ),
                    SizedBox(height: _asDouble(menuConfig['headerItemsGap'], fallback: 34).clamp(24, 44).toDouble()),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        physics: const BouncingScrollPhysics(),
                        children: [for (final item in items) buildMenuItem(item)],
                      ),
                    ),
                    if (showFooter)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(.10), borderRadius: BorderRadius.circular(16)),
                        child: Row(
                          children: [
                            Icon(Icons.verified_user_outlined, color: drawerText.withOpacity(.84), size: 17),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _asString(menuConfig['footerLabel'], fallback: 'Project workspace'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: drawerText.withOpacity(.84), fontSize: 12.5, fontWeight: FontWeight.w800),
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

        return ClipRRect(
          borderRadius: BorderRadius.circular(_asDouble(menuConfig['screenClipRadius'], fallback: 0).clamp(0, 44).toDouble()),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: Container(color: drawerColor)),
              Positioned(left: 0, top: 0, bottom: 0, width: drawerWidth, child: IgnorePointer(ignoring: !open, child: drawer)),
              AnimatedPositioned(
                duration: Duration(milliseconds: animationMs),
                curve: curve,
                left: open ? mainLeft : 0,
                top: open ? panelTopInset : 0,
                bottom: open ? panelBottomInset : 0,
                width: width,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 1.0, end: open ? verticalShrinkScale : 1.0),
                  duration: Duration(milliseconds: animationMs),
                  curve: curve,
                  builder: (context, scaleY, scaledChild) {
                    return Transform.scale(
                      scaleX: 1.0,
                      scaleY: scaleY,
                      alignment: Alignment.centerLeft,
                      child: scaledChild,
                    );
                  },
                  child: RepaintBoundary(
                    child: Material(
                      color: background,
                      elevation: activePanelElevation,
                      shadowColor: Colors.black.withOpacity(.30),
                      borderRadius: BorderRadius.circular(activePanelRadius),
                      clipBehavior: Clip.antiAlias,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: open ? _closeSideMenu : null,
                        child: AbsorbPointer(
                          absorbing: open,
                          child: AnimatedPadding(
                            duration: Duration(milliseconds: (animationMs * .72).round()),
                            curve: curve,
                            padding: open ? panelContentPadding : EdgeInsets.zero,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleAction(String action) {
    _runDebounced(() async {
      if (action == 'hamburgerMenu' || action == 'openSideMenu' || action == 'sideMenu' || action == 'menu') {
        _handleTopMenuPressed();
        return;
      }
      if (action == 'createTask' || action == 'bottomNavCenterAction') {
        await showSduiQuickActionSheet(
          context: context,
          config: widget.config,
          onAction: (selected) => widget.onAction?.call(selected),
        );
        return;
      }
      widget.onAction?.call(action);
    });
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    if (!config.enabled) return widget.child;

    final metrics = _ResponsiveNavMetrics.of(context, config);
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;
    final hideBottomWhenKeyboard = _asBool(
      config.floatingBottomNav['hideWhenKeyboard'],
      fallback: true,
    );
    final forceFloatingReferenceNav = _asBool(config.navigationConfig['forceFloatingReferenceNav'], fallback: true) ||
        _asString(config.bottomNav['variant'], fallback: '').contains('wireframeReference') ||
        _asString(config.topNav['variant'], fallback: '').contains('wireframeReference');
    final adaptiveNavigation = !forceFloatingReferenceNav &&
        _asBool(config.navigationConfig['adaptiveNavigation'], fallback: false) &&
        _asBool(config.navigationConfig['adaptiveNavRail'], fallback: false);
    final requestedPlacement = _asString(
      config.navigationConfig['preferredPlacement'],
      fallback: 'automatic',
    ).toLowerCase().trim();
    final hasCompanyNavigationPreference = _asString(
      config.navigationConfig['preferenceSource'],
    ) == 'companyNavigationSettings';
    final automaticRail = metrics.useNavigationRail &&
        (adaptiveNavigation || hasCompanyNavigationPreference);
    final resolvedPlacement = requestedPlacement == 'automatic' || requestedPlacement.isEmpty
        ? (automaticRail ? 'left' : 'bottom')
        : requestedPlacement;
    final showRailLeft = config.floatingBottomEnabled && resolvedPlacement == 'left';
    final showRailRight = config.floatingBottomEnabled && resolvedPlacement == 'right';
    final showTopTabs = config.floatingBottomEnabled && resolvedPlacement == 'top';
    final showBottom = config.floatingBottomEnabled &&
        resolvedPlacement == 'bottom' &&
        !(keyboardVisible && hideBottomWhenKeyboard);
    final showTop = config.floatingTopEnabled;

    final background = config.surfaceColor(context);
    final autoContentPadding = _asBool(
      config.navigationConfig['autoContentPadding'],
      fallback: true,
    );

    // v117: top nav now supports the same overlay/pass-under structure as the
    // bottom dock. The screen body is laid out in the Stack behind the floating
    // top nav instead of being forced below it in a Column/header layout.
    final topInsetMode = _asString(config.topNav['contentInset'], fallback: '').toLowerCase().trim();
    final bottomInsetMode = _asString(config.bottomNav['contentInset'], fallback: '').toLowerCase().trim();
    final contentPassUnderTopNav = _asBool(config.navigationConfig['contentPassUnderTopNav']) ||
        _asBool(config.layoutConfig['contentPassUnderTopNav']) ||
        _asBool(config.topNav['overlayContent']) ||
        topInsetMode == 'passunder' ||
        topInsetMode == 'pass_under' ||
        topInsetMode == 'passthrough';
    final contentPassUnderBottomNav = _asBool(config.navigationConfig['contentPassUnderBottomNav']) ||
        _asBool(config.layoutConfig['contentPassUnderBottomNav']) ||
        _asBool(config.bottomNav['overlayContent']) ||
        bottomInsetMode == 'passunder' ||
        bottomInsetMode == 'pass_under' ||
        bottomInsetMode == 'passthrough';

    // v255: keep the top nav behaving exactly like every other screen on the
    // Task Board. Do not hide or special-case the notification shortcut. The
    // board carousel gets only a hard-coded content reserve so the floating
    // search/bell chrome never sits on top of the first phase card.
    final taskBoardTopPaddingOnly = _isTaskBoardShellContext(config, widget.currentTab);

    final fullTopPadding = autoContentPadding ? metrics.contentPaddingTop : config.contentPaddingTop;
    final configuredTopGap = _asDouble(config.layoutConfig['topOverlaySafeGap'] ?? config.topNav['overlaySafeGap'], fallback: 0);
    final allowTopNavOverlap = _asBool(config.layoutConfig['allowTopNavContentOverlap']) ||
        _asBool(config.topNav['allowContentOverlap']) ||
        _asBool(config.navigationConfig['allowTopNavContentOverlap']);
    // v246: initial top-nav protection.
    // Some Firestore configs enable pass-under/overlay mode with no
    // topOverlaySafeGap, which lets the first project/board card render under
    // the floating search pill and notification button. Keep the visual overlay
    // shell, but reserve at least the measured floating-top-nav height unless a
    // config explicitly opts into overlap.
    final effectiveTopOverlayGap = allowTopNavOverlap ? configuredTopGap : _maxDouble(configuredTopGap, metrics.contentPaddingTop);
    final scrollAwareTopPadding = showTop && contentPassUnderTopNav && !taskBoardTopPaddingOnly && _isScrollAwareTopPaddingEnabled(config);
    final topPadding = showTop
        ? (scrollAwareTopPadding
            ? (_topPaddingCollapsed ? _scrollAwareScrolledTopPadding(config) : _scrollAwareInitialTopPadding(config, metrics))
            : (contentPassUnderTopNav ? effectiveTopOverlayGap : fullTopPadding))
        : 0.0;
    final taskBoardHardcodedTopPadding = showTop && taskBoardTopPaddingOnly ? _taskBoardHardcodedTopPadding(metrics) : 0.0;
    // v256: Task Board reserve is fixed, not scroll-aware. The top nav remains
    // fully normal and interactive, but the board body can no longer jump upward
    // after a horizontal carousel swipe.
    final baseBodyTopPadding = taskBoardTopPaddingOnly ? taskBoardHardcodedTopPadding : topPadding;
    final topTabReserve = showTopTabs
        ? metrics.bottomHeight + metrics.bottomMarginBottom + 10
        : 0.0;
    final bodyTopPadding = baseBodyTopPadding + topTabReserve;

    final baseBottomPadding = autoContentPadding
        ? metrics.contentPaddingBottom
        : _maxDouble(config.contentPaddingBottom, metrics.contentPaddingBottom);
    final configuredBottomGap = _asDouble(config.layoutConfig['bottomOverlaySafeGap'] ?? config.bottomNav['overlaySafeGap'], fallback: 0);
    final bottomPadding = showBottom
        ? (contentPassUnderBottomNav ? configuredBottomGap : baseBottomPadding)
        : 0.0;

    Widget buildFloatingContent() {
      return Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: metrics.contentMaxWidth),
                child: AnimatedPadding(
                  duration: config.mediumAnimationDuration,
                  curve: config.defaultCurve,
                  padding: EdgeInsets.only(top: bodyTopPadding, bottom: bottomPadding),
                  child: PrimaryScrollController(
                    controller: _primaryScrollController,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleScrollNotification,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showTop)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _FloatingTopNavBar(
                  config: config,
                  metrics: metrics,
                  currentTab: widget.currentTab,
                  showBack: _sideMenuOpen || widget.forceNestedBackButton || Navigator.of(context).canPop(),
                  unreadCount: widget.unreadCount,
                  userInitials: widget.userInitials,
                  onBack: _handleTopBackPressed,
                  onAction: _handleAction,
                  onMenu: _handleTopMenuPressed,
                  menuLottieEnabled: _menuLottieEnabled,
                  menuLottieAsset: _menuLottieAsset,
                  menuLottieAnimating: _menuLottieAnimating,
                  onMenuLottieCompleted: _finishMenuLottie,
                  searchQuery: widget.searchQuery,
                  onSearchChanged: widget.onSearchChanged,
                  onSearchSubmitted: widget.onSearchSubmitted,
                  onSearchClear: widget.onSearchClear,
                  onTitleTap: widget.onActiveTabRetap,
                ),
              ),
            ),
          if (showTopTabs)
            Positioned(
              left: 0,
              right: 0,
              top: showTop ? metrics.contentPaddingTop : 0,
              child: SafeArea(
                top: !showTop,
                bottom: false,
                child: _FloatingBottomNavBar(
                  config: config,
                  metrics: metrics,
                  currentTab: widget.currentTab,
                  atTop: true,
                  onTabTap: _handleTabTap,
                  onCenterTap: () => _handleAction(
                    widget.config.bottomNav['centerActionRoute']?.toString() ?? 'createTask',
                  ),
                ),
              ),
            ),
          if (showBottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _FloatingBottomNavBar(
                  config: config,
                  metrics: metrics,
                  currentTab: widget.currentTab,
                  onTabTap: _handleTabTap,
                  onCenterTap: () => _handleAction(
                    widget.config.bottomNav['centerActionRoute']?.toString() ?? 'createTask',
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final mainContent = AnimatedSwitcher(
      duration: config.mediumAnimationDuration,
      switchInCurve: config.defaultCurve,
      switchOutCurve: Curves.easeInCubic,
      child: Row(
        key: ValueKey<String>('sdui-navigation-$resolvedPlacement'),
        children: [
          if (showRailLeft)
            SafeArea(
              right: false,
              child: _AdaptiveNavigationRail(
                config: config,
                metrics: metrics,
                currentTab: widget.currentTab,
                placeOnRight: false,
                onTabTap: _handleTabTap,
                onCenterTap: () => _handleAction(
                  widget.config.bottomNav['centerActionRoute']?.toString() ?? 'createTask',
                ),
              ),
            ),
          Expanded(child: buildFloatingContent()),
          if (showRailRight)
            SafeArea(
              left: false,
              child: _AdaptiveNavigationRail(
                config: config,
                metrics: metrics,
                currentTab: widget.currentTab,
                placeOnRight: true,
                onTabTap: _handleTabTap,
                onCenterTap: () => _handleAction(
                  widget.config.bottomNav['centerActionRoute']?.toString() ?? 'createTask',
                ),
              ),
            ),
        ],
      ),
    );

    final sideMenuConfig = _asMap(config.raw['sideMenuConfig']);
    final sideMenuEnabled = _asBool(sideMenuConfig['enabled']) ||
        _asString(sideMenuConfig['presentation'], fallback: '').toLowerCase().contains('calendar') ||
        _asString(sideMenuConfig['animation'], fallback: '').toLowerCase().contains('slidereveal');

    return Scaffold(
      backgroundColor: background,
      resizeToAvoidBottomInset: true,
      body: sideMenuEnabled
          ? _buildCutSideMenuScaffold(child: mainContent, background: background)
          : mainContent,
    );
  }
}

class _ResponsiveNavMetrics {
  const _ResponsiveNavMetrics({
    required this.screenWidth,
    required this.screenHeight,
    required this.deviceAspectRatio,
    required this.isTallPhone,
    required this.isVeryTallPhone,
    required this.isShortPhone,
    required this.isTiny,
    required this.isCompact,
    required this.isTablet,
    required this.isLandscape,
    required this.useNavigationRail,
    required this.railExtended,
    required this.railWidth,
    required this.contentMaxWidth,
    required this.navMaxWidth,
    required this.topNavMaxWidth,
    required this.bottomNavMaxWidth,
    required this.topHeight,
    required this.topMarginHorizontal,
    required this.topMarginTop,
    required this.topRadius,
    required this.topIconButtonSize,
    required this.topIconSize,
    required this.topTitleFontSize,
    required this.topTitleHorizontalPadding,
    required this.hideSearch,
    required this.hideAvatar,
    required this.bottomHeight,
    required this.bottomMarginHorizontal,
    required this.bottomMarginBottom,
    required this.bottomRadius,
    required this.bottomIconSize,
    required this.centerButtonSize,
    required this.centerButtonBorderWidth,
    required this.contentPaddingTop,
    required this.contentPaddingBottom,
  });

  final double screenWidth;
  final double screenHeight;
  final double deviceAspectRatio;
  final bool isTallPhone;
  final bool isVeryTallPhone;
  final bool isShortPhone;
  final bool isTiny;
  final bool isCompact;
  final bool isTablet;
  final bool isLandscape;
  final bool useNavigationRail;
  final bool railExtended;
  final double railWidth;
  final double contentMaxWidth;
  final double navMaxWidth;
  final double topNavMaxWidth;
  final double bottomNavMaxWidth;
  final double topHeight;
  final double topMarginHorizontal;
  final double topMarginTop;
  final double topRadius;
  final double topIconButtonSize;
  final double topIconSize;
  final double topTitleFontSize;
  final double topTitleHorizontalPadding;
  final bool hideSearch;
  final bool hideAvatar;
  final double bottomHeight;
  final double bottomMarginHorizontal;
  final double bottomMarginBottom;
  final double bottomRadius;
  final double bottomIconSize;
  final double centerButtonSize;
  final double centerButtonBorderWidth;
  final double contentPaddingTop;
  final double contentPaddingBottom;

  factory _ResponsiveNavMetrics.of(BuildContext context, SduiMobileUiConfig config) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final safeTop = media.padding.top;
    final safeBottom = media.padding.bottom;
    final isLandscape = width > height;
    final shortestSide = isLandscape ? height : width;
    final longestSide = isLandscape ? width : height;
    final deviceAspectRatio = shortestSide <= 0 ? 1.0 : longestSide / shortestSide;
    final isTallPhone = !isLandscape && width < 600 && deviceAspectRatio >= 1.95;
    final isVeryTallPhone = !isLandscape && width < 600 && deviceAspectRatio >= 2.12;
    final isShortPhone = !isLandscape && width < 600 && deviceAspectRatio < 1.78;
    final isTiny = width < 340;
    final isCompact = width < 390;
    final isTablet = width >= 600;
    final useNavigationRail = width >= 600 || (isLandscape && width >= 520);
    final railExtended = width >= 840;
    final railWidth = railExtended ? 184.0 : 80.0;

    final topNav = config.topNav;
    final bottomNav = config.bottomNav;
    final layout = config.layoutConfig;
    final referenceTopNav = _isReferenceFloatingTopNav(topNav);
    final responsive = _asBool(layout['responsiveNav'], fallback: true);
    final ratioLayout = _asMap(layout['ratioBasedLayout'] ?? config.raw['ratioBasedLayout']);
    final ratioBasedLayout = responsive && _asBool(ratioLayout['enabled'], fallback: true);

    final configuredContentMaxWidth = _asDouble(layout['maxContentWidth'], fallback: config.maxContentWidth);
    final contentMaxWidth = responsive
        ? _clampDouble(configuredContentMaxWidth, 320, isTablet ? 720 : 560)
        : configuredContentMaxWidth;
    final navMaxWidth = responsive ? _clampDouble(contentMaxWidth, 320, 620) : contentMaxWidth;

    final bottomConfiguredMaxWidth = _asDouble(bottomNav['maxWidth'], fallback: navMaxWidth);
    final matchBottomWidth = _asBool(topNav['matchBottomNavWidth']) ||
        _asBool(topNav['matchBottomWidth']) ||
        _asString(topNav['style'], fallback: '') == _asString(bottomNav['style'], fallback: '');
    final topConfiguredMaxWidth = _asDouble(
      topNav['maxWidth'],
      fallback: matchBottomWidth ? bottomConfiguredMaxWidth : navMaxWidth,
    );
    final topNavMaxWidth = responsive
        ? _clampDouble(topConfiguredMaxWidth, 280, navMaxWidth)
        : topConfiguredMaxWidth;
    final bottomNavMaxWidth = responsive
        ? _clampDouble(bottomConfiguredMaxWidth, 280, navMaxWidth)
        : bottomConfiguredMaxWidth;

    // v111: reference-style top nav padding/size.
    // The search pill + notification circle should sit like the provided
    // mockup: compact, horizontally inset, and close to the status-bar line.
    final configuredTopHeight = _asDouble(topNav['height'], fallback: referenceTopNav ? 52 : 58);
    final configuredTopMarginH = _asDouble(topNav['marginHorizontal'], fallback: referenceTopNav ? 16 : 18);
    final configuredTopMarginTop = _asDouble(topNav['marginTop'], fallback: referenceTopNav ? 6 : 8);
    final configuredTopRadius = _asDouble(topNav['cornerRadius'], fallback: referenceTopNav ? 26 : 24);

    final topHeight = responsive
        ? (referenceTopNav
            ? (isTiny
                ? _clampDouble(configuredTopHeight, 48, 52)
                : isCompact
                    ? _clampDouble(configuredTopHeight, 50, 54)
                    : _clampDouble(configuredTopHeight, 52, isTablet ? 58 : 56))
            : (isTiny
                ? _clampDouble(configuredTopHeight, 52, 60)
                : isCompact
                    ? _clampDouble(configuredTopHeight, 54, isVeryTallPhone ? 62 : 64)
                    : isTablet
                        ? _clampDouble(configuredTopHeight, 58, 72)
                        : _clampDouble(configuredTopHeight, 56, isTallPhone ? 64 : 70)))
        : configuredTopHeight;
    final ratioMarginH = ratioBasedLayout && !isLandscape && !isTablet
        ? _clampDouble(width * (isTiny ? 0.026 : isVeryTallPhone ? 0.040 : isTallPhone ? 0.036 : 0.034), 10, 22)
        : configuredTopMarginH;
    final topMarginHorizontal = responsive
        ? (referenceTopNav
            ? (isTiny ? 12.0 : isCompact ? 14.0 : isTablet ? 18.0 : _clampDouble(configuredTopMarginH, 16, 22))
            : (isTiny ? ratioMarginH : isCompact ? _clampDouble(ratioMarginH, 12, 18) : isTablet ? 18.0 : _clampDouble(ratioMarginH, 14, 24)))
        : configuredTopMarginH;
    final ratioMarginTop = ratioBasedLayout && !isLandscape && !isTablet
        ? _clampDouble(height * (isShortPhone ? 0.006 : isVeryTallPhone ? 0.010 : 0.008), 5, 12)
        : configuredTopMarginTop;
    final topMarginTop = responsive
        ? (referenceTopNav
            ? (isTiny ? 5.0 : isCompact ? 6.0 : 7.0)
            : (isTiny ? _clampDouble(ratioMarginTop, 5, 8) : isCompact ? _clampDouble(ratioMarginTop, 6, 10) : _clampDouble(ratioMarginTop, 6, 12)))
        : configuredTopMarginTop;
    final topRadius = responsive
        ? (isTiny ? 20.0 : isCompact ? 22.0 : _clampDouble(configuredTopRadius, 22, isTallPhone ? 32 : 34))
        : configuredTopRadius;
    final topIconButtonSize = responsive ? (isTiny ? 34.0 : isCompact ? 36.0 : 38.0) : 38.0;
    final topIconSize = responsive ? (isTiny ? 19.0 : isCompact ? 20.0 : 22.0) : 22.0;
    final topTitleFontSize = responsive ? (isTiny ? 15.0 : isCompact ? 16.0 : 18.0) : 18.0;
    final topTitleHorizontalPadding = responsive ? (isTiny ? 2.0 : isCompact ? 4.0 : 6.0) : 6.0;
    final hideSearch = responsive && width < 350;
    final hideAvatar = responsive && width < 320;

    final configuredBottomHeight = _asDouble(bottomNav['height'], fallback: 70);
    final configuredBottomMinHeight = _asDouble(bottomNav['minHeight'], fallback: 56);
    final configuredBottomMaxHeight = _asDouble(bottomNav['maxHeight'], fallback: 72);
    final configuredBottomMarginH = _asDouble(bottomNav['marginHorizontal'], fallback: 22);
    final configuredBottomMarginBottom = _asDouble(bottomNav['marginBottom'], fallback: 12);
    final configuredBottomRadius = _asDouble(bottomNav['cornerRadius'], fallback: 26);

    final bottomHeight = responsive
        ? (isTiny
            ? _clampDouble(configuredBottomHeight, 52, configuredBottomMaxHeight)
            : isCompact
                ? _clampDouble(configuredBottomHeight, 54, configuredBottomMaxHeight)
                : _clampDouble(configuredBottomHeight, configuredBottomMinHeight, configuredBottomMaxHeight))
        : configuredBottomHeight;
    final bottomMarginHorizontal = responsive
        ? (isTiny ? 10.0 : isCompact ? 14.0 : isTablet ? 18.0 : _clampDouble(configuredBottomMarginH, 18, 56))
        : configuredBottomMarginH;
    final bottomMarginBottom = responsive
        ? (isTiny ? 8.0 : isCompact ? 10.0 : _clampDouble(configuredBottomMarginBottom, 10, 14))
        : configuredBottomMarginBottom;
    final bottomRadius = responsive
        ? (isTiny ? 22.0 : isCompact ? 24.0 : _clampDouble(configuredBottomRadius, 24, 30))
        : configuredBottomRadius;
    final bottomIconSize = responsive ? (isTiny ? 21.0 : isCompact ? 22.0 : 23.0) : 23.0;
    final centerButtonSize = responsive ? (isTiny ? 50.0 : isCompact ? 54.0 : 58.0) : 58.0;
    final centerButtonBorderWidth = responsive ? (isTiny ? 4.0 : 5.0) : 5.0;

    final actualTopBarBottom = safeTop + topMarginTop + topHeight;
    final actualBottomBarTopInset = safeBottom + bottomMarginBottom + bottomHeight + (centerButtonSize * 0.32);
    final configuredTopPadding = _asDouble(layout['contentPaddingTop'], fallback: 86);
    final configuredBottomPadding = _asDouble(layout['contentPaddingBottom'], fallback: 106);

    final ratioTopProtectionGap = ratioBasedLayout && !isLandscape && !isTablet
        ? _clampDouble(height * (isShortPhone ? 0.016 : isVeryTallPhone ? 0.030 : isTallPhone ? 0.026 : 0.022), 12, isVeryTallPhone ? 34 : 28)
        : (isTiny ? 10.0 : 14.0);
    final contentPaddingTop = responsive
        ? _maxDouble(configuredTopPadding, actualTopBarBottom + ratioTopProtectionGap)
        : configuredTopPadding;
    final contentPaddingBottom = responsive
        ? _maxDouble(configuredBottomPadding, actualBottomBarTopInset + (isTiny ? 8 : 12))
        : configuredBottomPadding;

    return _ResponsiveNavMetrics(
      screenWidth: width,
      screenHeight: height,
      deviceAspectRatio: deviceAspectRatio,
      isTallPhone: isTallPhone,
      isVeryTallPhone: isVeryTallPhone,
      isShortPhone: isShortPhone,
      isTiny: isTiny,
      isCompact: isCompact,
      isTablet: isTablet,
      isLandscape: isLandscape,
      useNavigationRail: useNavigationRail,
      railExtended: railExtended,
      railWidth: railWidth,
      contentMaxWidth: contentMaxWidth,
      navMaxWidth: navMaxWidth,
      topNavMaxWidth: topNavMaxWidth,
      bottomNavMaxWidth: bottomNavMaxWidth,
      topHeight: topHeight,
      topMarginHorizontal: topMarginHorizontal,
      topMarginTop: topMarginTop,
      topRadius: topRadius,
      topIconButtonSize: topIconButtonSize,
      topIconSize: topIconSize,
      topTitleFontSize: topTitleFontSize,
      topTitleHorizontalPadding: topTitleHorizontalPadding,
      hideSearch: hideSearch,
      hideAvatar: hideAvatar,
      bottomHeight: bottomHeight,
      bottomMarginHorizontal: bottomMarginHorizontal,
      bottomMarginBottom: bottomMarginBottom,
      bottomRadius: bottomRadius,
      bottomIconSize: bottomIconSize,
      centerButtonSize: centerButtonSize,
      centerButtonBorderWidth: centerButtonBorderWidth,
      contentPaddingTop: contentPaddingTop,
      contentPaddingBottom: contentPaddingBottom,
    );
  }
}

class _FloatingTopNavBar extends StatelessWidget {
  const _FloatingTopNavBar({
    required this.config,
    required this.metrics,
    required this.currentTab,
    required this.showBack,
    required this.unreadCount,
    required this.userInitials,
    required this.onBack,
    required this.onAction,
    required this.onMenu,
    this.menuLottieEnabled = false,
    this.menuLottieAsset = '',
    this.menuLottieAnimating = false,
    this.onMenuLottieCompleted,
    this.searchQuery = '',
    this.onSearchChanged,
    this.onSearchSubmitted,
    this.onSearchClear,
    this.onTitleTap,
  });

  final SduiMobileUiConfig config;
  final _ResponsiveNavMetrics metrics;
  final String currentTab;
  final bool showBack;
  final int unreadCount;
  final String userInitials;
  final VoidCallback onBack;
  final SduiActionCallback onAction;
  final VoidCallback onMenu;
  final bool menuLottieEnabled;
  final String menuLottieAsset;
  final bool menuLottieAnimating;
  final VoidCallback? onMenuLottieCompleted;
  final String searchQuery;
  final ValueChanged<String>? onSearchChanged;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final topNav = config.topNav;
    final bottomNav = config.bottomNav;
    final referenceStyle = _isReferenceFloatingTopNav(topNav);
    final title = config.titleForTab(currentTab);
    final placeholder = _asString(
      topNav['placeholder'] ?? topNav['searchPlaceholder'],
      fallback: referenceStyle ? config.text('topNav.searchPlaceholder', fallback: title) : title,
    );
    final cardColor = SduiMobileUiConfig.colorFromHex(
      _asString(topNav['background'], fallback: _asString(bottomNav['background'], fallback: '#FFFFFF')),
      config.cardColor(context),
    );
    final border = SduiMobileUiConfig.colorFromHex(
      _asString(topNav['border'], fallback: _asString(bottomNav['border'], fallback: '#0F140F')),
      config.borderColor(context),
    );
    final accent = SduiMobileUiConfig.colorFromHex(
      _asString(topNav['actionColor'] ?? topNav['primaryActionColor'] ?? bottomNav['activeItemBackground'] ?? bottomNav['centerActionColor'], fallback: '#6B8C5A'),
      const Color(0xFF6B8C5A),
    );
    final textColor = config.primaryTextColor(context);
    final muted = config.secondaryTextColor(context);
    final showSearch = _asBool(topNav['searchEnabled'], fallback: true) && !metrics.hideSearch;

    // v255: top nav now acts the same on Task Board as it does on all
    // other screens. The board-specific fix is content padding only, not
    // hiding the notification shortcut.
    final showInbox = _asBool(topNav['showInbox'], fallback: true);
    const showProjectAi = true;
    final showAvatar = _asBool(topNav['showAvatar'], fallback: true) && !metrics.hideAvatar;
    final actions = _stringList(topNav['actions']);
    final sideMenuConfig = _asMap(config.raw['sideMenuConfig']);
    final notificationAnimation = _asMap(
      topNav['notificationShortcutAnimation'] ??
          config.raw['notificationShortcutAnimation'] ??
          _asMap(config.raw['notificationAlertConfig'])['shortcutAnimation'],
    );
    // v190: restore old notification shortcut behavior.
    // The notification/inbox shortcut must open directly on tap; no app-opening
    // transform animation should run from stale Firestore JSON or hardcoded code.
    final notificationTransformEnabled = false;
    final notificationTransformDurationMs = _asInt(notificationAnimation['durationMs'], fallback: 460).clamp(180, 900).toInt();
    final notificationTransformLift = _asDouble(notificationAnimation['lift'] ?? notificationAnimation['translateY'], fallback: -3).clamp(-12, 12).toDouble();
    final notificationTransformRotationTurns = _asDouble(notificationAnimation['rotationTurns'], fallback: .035).clamp(-.20, .20).toDouble();
    final showMenu = !showBack && (
      _asBool(sideMenuConfig['enabled']) ||
      _asBool(topNav['hamburgerMenu']) ||
      actions.contains('hamburgerMenu') ||
      actions.contains('openSideMenu') ||
      actions.contains('sideMenu') ||
      actions.contains('menu')
    );
    final singleAction = _asBool(topNav['singleFloatingAction'], fallback: referenceStyle);
    final actionIcon = showInbox ? Icons.notifications_none_rounded : Icons.tune_rounded;
    final actionTap = showInbox ? () => onAction('inbox') : () => onAction('smartSearch');

    if (referenceStyle) {
      final hamburgerMode = _asString(topNav['hamburgerMode'], fallback: '').toLowerCase();
      final mergeHamburgerWithSearch = _asBool(topNav['mergeHamburgerWithSearch'], fallback: false) ||
          hamburgerMode == 'mergedleadingicon' ||
          hamburgerMode == 'merged' ||
          hamburgerMode == 'insidepill' ||
          _asString(topNav['hamburgerPosition'], fallback: '').toLowerCase() == 'insideSearch'.toLowerCase();
      final searchInteractive = _asBool(topNav['searchInteractive'], fallback: true);
      // v246: compact phones need the notification shortcut to sit beside the
      // merged search pill, not on top of it. Use a slightly smaller action
      // circle and tighter gap on compact widths while keeping the reference
      // look on normal phones/tablets.
      final referenceActionSize = metrics.isTiny
          ? _clampDouble(metrics.topHeight - 6, 46, 52)
          : metrics.isCompact
              ? _clampDouble(metrics.topHeight - 4, 50, 56)
              : _clampDouble(metrics.topHeight, 56, 64);
      final referenceActionGap = metrics.isTiny ? 7.0 : 10.0;
      final referenceActionIconSize = metrics.isTiny ? metrics.topIconSize - 1 : metrics.topIconSize;
      final compactPlaceholder = metrics.isTiny
          ? 'Search'
          : metrics.isCompact
              ? 'Search projects, tasks'
              : placeholder;

      final referenceOuterHorizontalPadding = _asDouble(
        topNav['referenceOuterHorizontalPadding'] ??
            topNav['navBarHorizontalPadding'] ??
            topNav['topNavHorizontalPadding'] ??
            topNav['outerHorizontalPadding'],
        fallback: metrics.topMarginHorizontal,
      ).clamp(metrics.isTiny ? 10.0 : 12.0, metrics.isCompact ? 18.0 : 26.0).toDouble();
      final referenceOuterTopPadding = _asDouble(
        topNav['referenceOuterTopPadding'] ??
            topNav['navBarTopPadding'] ??
            topNav['topNavTopPadding'] ??
            topNav['outerTopPadding'],
        fallback: metrics.topMarginTop,
      ).clamp(4.0, metrics.isCompact ? 9.0 : 12.0).toDouble();

      return AnimatedSlide(
        duration: config.mediumAnimationDuration,
        curve: config.defaultCurve,
        offset: Offset.zero,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            referenceOuterHorizontalPadding,
            referenceOuterTopPadding,
            referenceOuterHorizontalPadding,
            0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: metrics.topNavMaxWidth),
              child: SizedBox(
                height: metrics.topHeight,
                child: Row(
                  children: [
                    if (showMenu && !mergeHamburgerWithSearch) ...[
                      _WireframeCircleAction(
                        size: metrics.topHeight,
                        icon: Icons.menu_rounded,
                        iconSize: metrics.topIconSize,
                        background: cardColor,
                        foreground: textColor,
                        border: border,
                        lottieAsset: menuLottieEnabled ? menuLottieAsset : '',
                        lottieAnimate: menuLottieAnimating,
                        onLottieCompleted: onMenuLottieCompleted,
                        onTap: onMenu,
                      ),
                      const SizedBox(width: 10),
                    ],
                    if (showBack && !mergeHamburgerWithSearch) ...[
                      _WireframeCircleAction(
                        size: metrics.topHeight,
                        icon: Icons.arrow_back_rounded,
                        iconSize: metrics.topIconSize,
                        background: cardColor,
                        foreground: textColor,
                        border: border,
                        lottieAsset: menuLottieEnabled ? menuLottieAsset : '',
                        lottieAnimate: menuLottieAnimating,
                        onLottieCompleted: onMenuLottieCompleted,
                        onTap: onBack,
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: _MergedTopSearchPill(
                        height: metrics.topHeight,
                        compact: metrics.isCompact,
                        tiny: metrics.isTiny,
                        iconSize: metrics.topIconSize,
                        placeholder: showSearch ? compactPlaceholder : title,
                        query: searchQuery,
                        enabled: showSearch && searchInteractive,
                        background: cardColor,
                        border: border,
                        textColor: textColor,
                        mutedColor: muted,
                        showMenu: showMenu && mergeHamburgerWithSearch,
                        showBack: showBack && mergeHamburgerWithSearch,
                        menuLottieAsset: menuLottieEnabled ? menuLottieAsset : '',
                        menuLottieAnimate: menuLottieAnimating,
                        onMenuLottieCompleted: onMenuLottieCompleted,
                        onMenu: onMenu,
                        onBack: onBack,
                        onChanged: onSearchChanged,
                        onSubmitted: onSearchSubmitted,
                        onClear: onSearchClear,
                        showAi: showProjectAi,
                        onAi: () => onAction('openProjectAi'),
                        onTapWhenDisabled: () => onAction('smartSearch'),
                      ),
                    ),
                    SizedBox(width: referenceActionGap),
                    _WireframeCircleAction(
                        size: referenceActionSize,
                        icon: actionIcon,
                        iconSize: referenceActionIconSize,
                        background: accent,
                        foreground: Colors.white,
                        border: accent,
                        badgeCount: showInbox ? unreadCount : 0,
                        transformOnTap: showInbox && notificationTransformEnabled,
                        transformDurationMs: notificationTransformDurationMs,
                        transformLift: notificationTransformLift,
                        transformRotationTurns: notificationTransformRotationTurns,
                        onTap: actionTap,
                      ),
                    if (!singleAction && showAvatar) ...[
                      SizedBox(width: referenceActionGap),
                      _WireframeCircleAction(
                        size: referenceActionSize,
                        label: _avatarText(userInitials),
                        background: const Color(0xFF151515),
                        foreground: Colors.white,
                        border: const Color(0xFF151515),
                        onTap: () => onAction('openProfile'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSlide(
      duration: config.mediumAnimationDuration,
      curve: config.defaultCurve,
      offset: Offset.zero,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: metrics.topNavMaxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              metrics.topMarginHorizontal,
              metrics.topMarginTop,
              metrics.topMarginHorizontal,
              0,
            ),
            child: Container(
              height: metrics.topHeight,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(metrics.topRadius),
                border: Border.all(color: border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: metrics.isTiny ? 18 : 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  SizedBox(width: metrics.isTiny ? 4 : 6),
                  if (showMenu)
                    _RoundIconButton(
                      icon: Icons.menu_rounded,
                      size: metrics.topIconButtonSize,
                      iconSize: metrics.topIconSize,
                      lottieAsset: menuLottieEnabled ? menuLottieAsset : '',
                      lottieAnimate: menuLottieAnimating,
                      onLottieCompleted: onMenuLottieCompleted,
                      onTap: onMenu,
                    ),
                  if (showBack)
                    _RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      size: metrics.topIconButtonSize,
                      iconSize: metrics.topIconSize,
                      lottieAsset: menuLottieEnabled ? menuLottieAsset : '',
                      lottieAnimate: menuLottieAnimating,
                      onLottieCompleted: onMenuLottieCompleted,
                      onTap: onBack,
                    )
                  else
                    SizedBox(width: metrics.isTiny ? 8 : 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: onTitleTap,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: metrics.topTitleHorizontalPadding),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: metrics.topTitleFontSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showSearch)
                    _RoundIconButton(
                      icon: Icons.search_rounded,
                      size: metrics.topIconButtonSize,
                      iconSize: metrics.topIconSize,
                      onTap: () => onAction('smartSearch'),
                    ),
                  if (showInbox)
                    _InboxButton(
                      muted: muted,
                      unreadCount: unreadCount,
                      size: metrics.topIconButtonSize,
                      iconSize: metrics.topIconSize,
                      transformOnTap: notificationTransformEnabled,
                      transformDurationMs: notificationTransformDurationMs,
                      transformLift: notificationTransformLift,
                      transformRotationTurns: notificationTransformRotationTurns,
                      onTap: () => onAction('inbox'),
                    ),
                  if (showAvatar)
                    Padding(
                      padding: EdgeInsets.only(left: metrics.isTiny ? 2 : 4, right: metrics.isTiny ? 8 : 10),
                      child: CircleAvatar(
                        radius: metrics.isCompact ? 15 : 17,
                        backgroundColor: const Color(0xFF151515),
                        child: Text(
                          _avatarText(userInitials),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _MergedTopSearchPill extends StatefulWidget {
  const _MergedTopSearchPill({
    required this.height,
    required this.compact,
    required this.tiny,
    required this.iconSize,
    required this.placeholder,
    required this.query,
    required this.enabled,
    required this.background,
    required this.border,
    required this.textColor,
    required this.mutedColor,
    required this.showMenu,
    required this.showBack,
    this.menuLottieAsset = '',
    this.menuLottieAnimate = false,
    this.onMenuLottieCompleted,
    required this.onMenu,
    required this.onBack,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.showAi,
    required this.onAi,
    required this.onTapWhenDisabled,
  });

  final double height;
  final bool compact;
  final bool tiny;
  final double iconSize;
  final String placeholder;
  final String query;
  final bool enabled;
  final Color background;
  final Color border;
  final Color textColor;
  final Color mutedColor;
  final bool showMenu;
  final bool showBack;
  final String menuLottieAsset;
  final bool menuLottieAnimate;
  final VoidCallback? onMenuLottieCompleted;
  final VoidCallback onMenu;
  final VoidCallback onBack;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool showAi;
  final VoidCallback onAi;
  final VoidCallback onTapWhenDisabled;

  @override
  State<_MergedTopSearchPill> createState() => _MergedTopSearchPillState();
}

class _MergedTopSearchPillState extends State<_MergedTopSearchPill> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _MergedTopSearchPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasLeading = widget.showBack || widget.showMenu;
    final leadingIcon = widget.showBack ? Icons.arrow_back_rounded : Icons.menu_rounded;
    final leadingTap = widget.showBack ? widget.onBack : widget.onMenu;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.height / 2),
        onTap: widget.enabled ? null : widget.onTapWhenDisabled,
        child: Container(
          height: widget.height,
          padding: EdgeInsets.only(
            left: hasLeading ? (widget.tiny ? 8 : 10) : (widget.compact ? 14 : 18),
            right: widget.tiny ? 8 : (widget.compact ? 10 : 12),
          ),
          decoration: BoxDecoration(
            color: widget.background,
            borderRadius: BorderRadius.circular(widget.height / 2),
            border: Border.all(color: widget.border, width: 1.15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: widget.tiny ? 18 : 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              if (hasLeading) ...[
                InkResponse(
                  onTap: leadingTap,
                  radius: widget.height * .42,
                  child: SizedBox(
                    width: widget.height - 10,
                    height: widget.height - 10,
                    child: _OneShotMenuLottieIcon(
                      asset: widget.menuLottieAsset,
                      animate: widget.menuLottieAnimate,
                      fallbackIcon: leadingIcon,
                      color: widget.textColor,
                      size: widget.iconSize + 7,
                      iconSize: widget.iconSize + 1,
                      onCompleted: widget.onMenuLottieCompleted,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: widget.height * .38,
                  margin: EdgeInsets.only(right: widget.tiny ? 8 : 10),
                  color: widget.border.withOpacity(.18),
                ),
              ],
              Icon(Icons.search_rounded, color: widget.mutedColor, size: widget.iconSize),
              SizedBox(width: widget.tiny ? 8 : 10),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  enabled: widget.enabled,
                  onChanged: (value) {
                    widget.onChanged?.call(value);
                    setState(() {});
                  },
                  onSubmitted: widget.onSubmitted,
                  textInputAction: TextInputAction.search,
                  minLines: 1,
                  maxLines: 1,
                  style: TextStyle(
                    color: widget.textColor,
                    fontSize: widget.compact ? 14 : 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.placeholder,
                    hintStyle: TextStyle(
                      color: widget.mutedColor,
                      fontSize: widget.compact ? 14 : 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (widget.showAi)
                Tooltip(
                  message: 'Project AI',
                  child: InkResponse(
                    onTap: widget.onAi,
                    radius: 20,
                    child: Container(
                      width: widget.height - 14,
                      height: widget.height - 14,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.background,
                        shape: BoxShape.circle,
                        border: Border.all(color: widget.border.withOpacity(.55)),
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: widget.mutedColor, size: widget.iconSize - 1),
                    ),
                  ),
                ),
              if (_controller.text.trim().isNotEmpty)
                InkResponse(
                  onTap: _clear,
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: widget.mutedColor, size: widget.iconSize - 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


class _OneShotMenuLottieIcon extends StatefulWidget {
  const _OneShotMenuLottieIcon({
    required this.asset,
    required this.animate,
    required this.fallbackIcon,
    required this.color,
    required this.size,
    required this.iconSize,
    this.onCompleted,
  });

  final String asset;
  final bool animate;
  final IconData fallbackIcon;
  final Color color;
  final double size;
  final double iconSize;
  final VoidCallback? onCompleted;

  @override
  State<_OneShotMenuLottieIcon> createState() => _OneShotMenuLottieIconState();
}

class _OneShotMenuLottieIconState extends State<_OneShotMenuLottieIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _loaded = false;
  bool _completedThisRun = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_completedThisRun) {
          _completedThisRun = true;
          widget.onCompleted?.call();
          if (mounted) {
            _controller.value = 0;
            setState(() {});
          }
        }
      });
  }

  @override
  void didUpdateWidget(covariant _OneShotMenuLottieIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) _playOnce();
    if (!widget.animate && oldWidget.animate) {
      _completedThisRun = false;
      _controller.value = 0;
    }
  }

  void _playOnce() {
    if (widget.asset.trim().isEmpty || !_loaded) return;
    _completedThisRun = false;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asset.trim().isEmpty || !widget.animate) {
      return Icon(widget.fallbackIcon, color: widget.color, size: widget.iconSize);
    }
    return Lottie.asset(
      widget.asset,
      controller: _controller,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      repeat: false,
      frameRate: FrameRate.max,
      onLoaded: (composition) {
        _controller.duration = composition.duration;
        _loaded = true;
        if (widget.animate) _playOnce();
      },
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onCompleted?.call());
        return Icon(widget.fallbackIcon, color: widget.color, size: widget.iconSize);
      },
    );
  }
}

class _AdaptiveNavigationRail extends StatelessWidget {
  const _AdaptiveNavigationRail({
    required this.config,
    required this.metrics,
    required this.currentTab,
    required this.placeOnRight,
    required this.onTabTap,
    required this.onCenterTap,
  });

  final SduiMobileUiConfig config;
  final _ResponsiveNavMetrics metrics;
  final String currentTab;
  final bool placeOnRight;
  final ValueChanged<String> onTabTap;
  final VoidCallback onCenterTap;

  @override
  Widget build(BuildContext context) {
    final bottomNav = config.bottomNav;
    final tabs = config.bottomTabs.isEmpty ? const <String>['home', 'projects', 'board', 'profile'] : config.bottomTabs;
    final selectedIndex = tabs.indexOf(currentTab).clamp(0, tabs.length - 1).toInt();
    final background = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['background'], fallback: '#FFFFFF'),
      config.cardColor(context),
    );
    final border = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['border'], fallback: '#D8DED4'),
      config.borderColor(context),
    );
    final active = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['activeItemBackground'], fallback: _asString(bottomNav['indicatorColor'], fallback: '#6B8C5A')),
      const Color(0xFF6B8C5A),
    );
    final inactive = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['inactiveColor'], fallback: '#0F140F'),
      const Color(0xFF0F140F),
    );
    final displayMode = _asString(
      config.navigationConfig['displayMode'],
      fallback: 'expanded',
    ).toLowerCase().trim();
    final canExtend = metrics.screenWidth >= 720;
    final extended = displayMode == 'expanded'
        ? canExtend
        : displayMode == 'automatic'
            ? metrics.railExtended
            : false;
    final railWidth = extended
        ? (metrics.screenWidth < 900 ? 172.0 : metrics.railWidth)
        : displayMode == 'compact'
            ? 88.0
            : 76.0;

    return AnimatedContainer(
      duration: config.mediumAnimationDuration,
      curve: config.defaultCurve,
      width: railWidth,
      margin: placeOnRight
          ? EdgeInsets.fromLTRB(6, 8, metrics.isTablet ? 10 : 6, 8)
          : EdgeInsets.fromLTRB(metrics.isTablet ? 10 : 6, 8, 6, 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        extended: extended,
        minWidth: railWidth.clamp(72, 104).toDouble(),
        minExtendedWidth: railWidth,
        selectedIndex: selectedIndex,
        useIndicator: true,
        indicatorColor: active.withOpacity(0.14),
        selectedIconTheme: IconThemeData(color: active, size: 24),
        unselectedIconTheme: IconThemeData(color: inactive.withOpacity(0.72), size: 23),
        selectedLabelTextStyle: TextStyle(color: active, fontWeight: FontWeight.w900),
        unselectedLabelTextStyle: TextStyle(color: inactive.withOpacity(0.72), fontWeight: FontWeight.w800),
        leading: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 12),
          child: FloatingActionButton.small(
            heroTag: 'sdui_adaptive_nav_rail_fab',
            elevation: 0,
            backgroundColor: active,
            foregroundColor: Colors.white,
            onPressed: onCenterTap,
            child: const Icon(Icons.add_rounded),
          ),
        ),
        destinations: [
          for (final tab in tabs)
            NavigationRailDestination(
              icon: Icon(_iconForTabFromConfig(tab, bottomNav)),
              selectedIcon: Icon(_iconForTabFromConfig(tab, bottomNav)),
              label: Text(config.routeLabel(tab, fallback: _labelForTab(tab))),
            ),
        ],
        onDestinationSelected: (index) {
          if (index >= 0 && index < tabs.length) onTabTap(tabs[index]);
        },
      ),
    );
  }
}

class _FloatingBottomNavBar extends StatelessWidget {
  const _FloatingBottomNavBar({
    required this.config,
    required this.metrics,
    required this.currentTab,
    required this.onTabTap,
    required this.onCenterTap,
    this.atTop = false,
  });

  final SduiMobileUiConfig config;
  final _ResponsiveNavMetrics metrics;
  final String currentTab;
  final ValueChanged<String> onTabTap;
  final VoidCallback onCenterTap;
  final bool atTop;

  @override
  Widget build(BuildContext context) {
    final bottomNav = config.bottomNav;
    final cardColor = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['background'], fallback: '#FFFFFF'),
      config.cardColor(context),
    );
    final border = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['border'], fallback: '#0F140F'),
      config.borderColor(context),
    );
    final activeColor = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['activeColor'], fallback: '#FFFFFF'),
      Colors.white,
    );
    final inactiveColor = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['inactiveColor'], fallback: '#0F140F'),
      const Color(0xFF0F140F),
    );
    final activeItemBackground = SduiMobileUiConfig.colorFromHex(
      _asString(bottomNav['activeItemBackground'] ?? bottomNav['indicatorColor'] ?? bottomNav['centerActionColor'], fallback: '#6B8C5A'),
      const Color(0xFF6B8C5A),
    );
    final centerAction = _asBool(bottomNav['centerAction'], fallback: false);
    final tabs = config.bottomTabs.isEmpty ? const <String>['home', 'projects', 'board', 'profile'] : config.bottomTabs;
    final pillHeight = metrics.bottomHeight;
    final centerButtonSize = metrics.centerButtonSize;
    final totalHeight = centerAction ? pillHeight + (centerButtonSize * 0.32) : pillHeight;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: metrics.bottomNavMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            metrics.bottomMarginHorizontal,
            atTop ? metrics.bottomMarginBottom : 0,
            metrics.bottomMarginHorizontal,
            atTop ? 0 : metrics.bottomMarginBottom,
          ),
          child: SizedBox(
            height: totalHeight,
            child: Stack(
              alignment: atTop ? Alignment.topCenter : Alignment.bottomCenter,
              children: [
                Container(
                  height: pillHeight,
                  padding: EdgeInsets.symmetric(horizontal: metrics.isTiny ? 10 : 14),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(pillHeight / 2),
                    border: Border.all(color: border, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.16),
                        blurRadius: metrics.isTiny ? 20 : 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (var i = 0; i < tabs.length; i++) ...[
                        if (centerAction && i == (tabs.length / 2).ceil()) SizedBox(width: centerButtonSize * 0.86),
                        Expanded(
                          child: _BottomTabItem(
                            tab: tabs[i],
                            icon: _iconForTabFromConfig(tabs[i], bottomNav),
                            selected: tabs[i] == currentTab,
                            iconSize: metrics.bottomIconSize,
                            dense: metrics.isTiny,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                            activeItemBackground: activeItemBackground,
                            onTap: () => onTabTap(tabs[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (centerAction)
                  Positioned(
                    top: atTop ? null : 0,
                    bottom: atTop ? 0 : null,
                    child: GestureDetector(
                      onTap: onCenterTap,
                      child: AnimatedScale(
                        scale: 1,
                        duration: config.shortAnimationDuration,
                        curve: config.defaultCurve,
                        child: Container(
                          height: centerButtonSize,
                          width: centerButtonSize,
                          decoration: BoxDecoration(
                            color: activeItemBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: cardColor, width: metrics.centerButtonBorderWidth),
                            boxShadow: [
                              BoxShadow(
                                color: activeItemBackground.withOpacity(0.28),
                                blurRadius: metrics.isTiny ? 18 : 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomTabItem extends StatelessWidget {
  const _BottomTabItem({
    required this.tab,
    required this.icon,
    required this.selected,
    required this.iconSize,
    required this.dense,
    required this.activeColor,
    required this.inactiveColor,
    required this.activeItemBackground,
    required this.onTap,
  });

  final String tab;
  final IconData icon;
  final bool selected;
  final double iconSize;
  final bool dense;
  final Color activeColor;
  final Color inactiveColor;
  final Color activeItemBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? (dense ? 44.0 : 48.0) : (dense ? 38.0 : 42.0);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected ? activeItemBackground : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: activeItemBackground.withOpacity(0.24),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : const [],
          ),
          child: Icon(icon, color: selected ? activeColor : inactiveColor, size: iconSize),
        ),
      ),
    );
  }
}


bool _isReferenceFloatingTopNav(Map<String, dynamic> topNav) {
  final variant = _asString(topNav['variant'] ?? topNav['style'] ?? topNav['mode']).toLowerCase();
  return variant.contains('wireframereference') ||
      variant.contains('referencefloating') ||
      variant.contains('floatingsearch') ||
      variant.contains('wireframetopsearchbar');
}

class _WireframeCircleAction extends StatefulWidget {
  const _WireframeCircleAction({
    required this.size,
    required this.background,
    required this.foreground,
    required this.border,
    required this.onTap,
    this.icon,
    this.iconSize = 22,
    this.label,
    this.badgeCount = 0,
    this.lottieAsset = '',
    this.lottieAnimate = false,
    this.onLottieCompleted,
    this.transformOnTap = false,
    this.transformDurationMs = 460,
    this.transformLift = -3,
    this.transformRotationTurns = .035,
  });

  final double size;
  final IconData? icon;
  final double iconSize;
  final String? label;
  final Color background;
  final Color foreground;
  final Color border;
  final int badgeCount;
  final String lottieAsset;
  final bool lottieAnimate;
  final VoidCallback? onLottieCompleted;
  final VoidCallback onTap;
  final bool transformOnTap;
  final int transformDurationMs;
  final double transformLift;
  final double transformRotationTurns;

  @override
  State<_WireframeCircleAction> createState() => _WireframeCircleActionState();
}

class _WireframeCircleActionState extends State<_WireframeCircleAction> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _rotation;
  late Animation<double> _dy;
  late Animation<double> _launchScale;
  late Animation<double> _launchOpacity;
  late Animation<double> _contentOpacity;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: widget.transformDurationMs));
    _rebuildAnimations();
  }

  @override
  void didUpdateWidget(covariant _WireframeCircleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformDurationMs != widget.transformDurationMs) {
      _controller.duration = Duration(milliseconds: widget.transformDurationMs);
    }
    if (oldWidget.transformLift != widget.transformLift || oldWidget.transformRotationTurns != widget.transformRotationTurns) {
      _rebuildAnimations();
    }
  }

  void _rebuildAnimations() {
    // Legacy tap behavior is active in v190; these animations are kept inert for
    // backwards compatibility only and are not enabled for notification shortcuts.
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: .92), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: .92, end: 1.62), weight: 45),
      TweenSequenceItem(tween: Tween<double>(begin: 1.62, end: 1.00), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -widget.transformRotationTurns * .45), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: -widget.transformRotationTurns * .45, end: widget.transformRotationTurns * .30), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: widget.transformRotationTurns * .30, end: 0), weight: 52),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _dy = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: widget.transformLift - 3), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: widget.transformLift - 3, end: 0), weight: 66),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: .72, end: 1.00), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: 2.55), weight: 52),
      TweenSequenceItem(tween: Tween<double>(begin: 2.55, end: 2.90), weight: 38),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.00, end: .34), weight: 18),
      TweenSequenceItem(tween: Tween<double>(begin: .34, end: .18), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: .18, end: 0.00), weight: 48),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _contentOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: .88), weight: 22),
      TweenSequenceItem(tween: Tween<double>(begin: .88, end: .52), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: .52, end: 1.00), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  void _handleTap() {
    // v190 restores older behavior: tap opens the notification/inbox action directly.
    if (widget.transformOnTap) {
      _running = false;
      _controller.value = 0;
    }
    widget.onTap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: widget.background,
        shape: BoxShape.circle,
        border: Border.all(color: widget.border, width: 1.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.icon != null)
            _OneShotMenuLottieIcon(
              asset: widget.lottieAsset,
              animate: widget.lottieAnimate,
              fallbackIcon: widget.icon!,
              color: widget.foreground,
              size: widget.size * .68,
              iconSize: widget.iconSize,
              onCompleted: widget.onLottieCompleted,
            )
          else
            Text(
              (widget.label ?? '').isEmpty ? 'U' : widget.label!,
              style: TextStyle(color: widget.foreground, fontSize: 12, fontWeight: FontWeight.w900),
            ),
          if (widget.badgeCount > 0)
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE95D5D),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  widget.badgeCount > 9 ? '9+' : '${widget.badgeCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.size / 2),
        onTap: _handleTap,
        child: widget.transformOnTap
            ? AnimatedBuilder(
                animation: _controller,
                child: content,
                builder: (context, child) {
                  return SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: OverflowBox(
                      maxWidth: widget.size * 2.8,
                      maxHeight: widget.size * 2.8,
                      child: SizedBox(
                        width: widget.size * 2.8,
                        height: widget.size * 2.8,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                        Opacity(
                          opacity: _launchOpacity.value,
                          child: Transform.scale(
                            scale: _launchScale.value,
                            child: Container(
                              width: widget.size,
                              height: widget.size,
                              decoration: BoxDecoration(
                                color: widget.background,
                                borderRadius: BorderRadius.circular(widget.size * .50),
                                boxShadow: [BoxShadow(color: widget.background.withOpacity(.22), blurRadius: 28, spreadRadius: 3)],
                              ),
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(0, _dy.value),
                          child: Transform.rotate(
                            angle: _rotation.value * math.pi * 2,
                            child: Opacity(opacity: _contentOpacity.value, child: Transform.scale(scale: _scale.value, child: child)),
                          ),
                        ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            : content,
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 38,
    this.iconSize = 22,
    this.lottieAsset = '',
    this.lottieAnimate = false,
    this.onLottieCompleted,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final String lottieAsset;
  final bool lottieAnimate;
  final VoidCallback? onLottieCompleted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: SizedBox(
        height: size,
        width: size,
        child: _OneShotMenuLottieIcon(
          asset: lottieAsset,
          animate: lottieAnimate,
          fallbackIcon: icon,
          color: const Color(0xFF151515),
          size: size * .84,
          iconSize: iconSize,
          onCompleted: onLottieCompleted,
        ),
      ),
    );
  }
}


String _avatarText(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return 'U';
  final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (cleaned.isEmpty) return value[0].toUpperCase();
  return cleaned.substring(0, cleaned.length.clamp(1, 2).toInt()).toUpperCase();
}

class _InboxButton extends StatefulWidget {
  const _InboxButton({
    required this.muted,
    required this.unreadCount,
    required this.onTap,
    this.size = 38,
    this.iconSize = 22,
    this.transformOnTap = false,
    this.transformDurationMs = 460,
    this.transformLift = -3,
    this.transformRotationTurns = .035,
  });

  final Color muted;
  final int unreadCount;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final bool transformOnTap;
  final int transformDurationMs;
  final double transformLift;
  final double transformRotationTurns;

  @override
  State<_InboxButton> createState() => _InboxButtonState();
}

class _InboxButtonState extends State<_InboxButton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _rotation;
  late Animation<double> _dy;
  late Animation<double> _launchScale;
  late Animation<double> _launchOpacity;
  late Animation<double> _contentOpacity;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: widget.transformDurationMs));
    _rebuildAnimations();
  }

  @override
  void didUpdateWidget(covariant _InboxButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transformDurationMs != widget.transformDurationMs) {
      _controller.duration = Duration(milliseconds: widget.transformDurationMs);
    }
    if (oldWidget.transformLift != widget.transformLift || oldWidget.transformRotationTurns != widget.transformRotationTurns) {
      _rebuildAnimations();
    }
  }

  void _rebuildAnimations() {
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: .92), weight: 15),
      TweenSequenceItem(tween: Tween<double>(begin: .92, end: 1.58), weight: 45),
      TweenSequenceItem(tween: Tween<double>(begin: 1.58, end: 1.00), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _rotation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -widget.transformRotationTurns * .45), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: -widget.transformRotationTurns * .45, end: widget.transformRotationTurns * .30), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: widget.transformRotationTurns * .30, end: 0), weight: 52),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _dy = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: widget.transformLift - 3), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: widget.transformLift - 3, end: 0), weight: 66),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: .72, end: 1.00), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: 2.45), weight: 52),
      TweenSequenceItem(tween: Tween<double>(begin: 2.45, end: 2.80), weight: 38),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.00, end: .20), weight: 18),
      TweenSequenceItem(tween: Tween<double>(begin: .20, end: .12), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: .12, end: 0.00), weight: 48),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _contentOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: .88), weight: 22),
      TweenSequenceItem(tween: Tween<double>(begin: .88, end: .52), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: .52, end: 1.00), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  void _handleTap() {
    // v190 restores older behavior: tap opens the notification/inbox action directly.
    if (widget.transformOnTap) {
      _running = false;
      _controller.value = 0;
    }
    widget.onTap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      height: widget.size,
      width: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, size: widget.iconSize, color: widget.muted),
          if (widget.unreadCount > 0)
            Positioned(
              top: widget.size * 0.18,
              right: widget.size * 0.18,
              child: Container(
                height: 8,
                width: 8,
                decoration: const BoxDecoration(color: Color(0xFFD87465), shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(widget.size / 2),
      onTap: _handleTap,
      child: widget.transformOnTap
          ? AnimatedBuilder(
              animation: _controller,
              child: content,
              builder: (context, child) {
                return SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: OverflowBox(
                    maxWidth: widget.size * 2.5,
                    maxHeight: widget.size * 2.5,
                    child: SizedBox(
                      width: widget.size * 2.5,
                      height: widget.size * 2.5,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                      Opacity(
                        opacity: _launchOpacity.value,
                        child: Transform.scale(
                          scale: _launchScale.value,
                          child: Container(
                            width: widget.size,
                            height: widget.size,
                            decoration: BoxDecoration(
                              color: widget.muted,
                              borderRadius: BorderRadius.circular(widget.size * .50),
                            ),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, _dy.value),
                        child: Transform.rotate(
                          angle: _rotation.value * math.pi * 2,
                          child: Opacity(opacity: _contentOpacity.value, child: Transform.scale(scale: _scale.value, child: child)),
                        ),
                      ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            )
          : content,
    );
  }
}


class _SduiSideMenuItem {
  const _SduiSideMenuItem({
    required this.route,
    required this.label,
    required this.group,
    required this.icon,
  });

  final String route;
  final String label;
  final String group;
  final IconData icon;
}

List<_SduiSideMenuItem> _sideMenuItemsForConfig(SduiMobileUiConfig config) {
  final sideMenu = _asMap(config.raw['sideMenuConfig']);
  final registry = _asMap(config.raw['screenRegistry']);
  final navigation = config.navigationConfig;
  final screenConfigs = config.screenConfigs;
  final showNested = _asBool(sideMenu['showNestedScreens'], fallback: true);
  final configuredMain = _stringList(sideMenu['mainScreens']);
  final configuredMore = _stringList(sideMenu['moreScreens']);
  final activeBottomTabs = _stringList(registry['activeBottomTabs'], fallback: _stringList(config.bottomNav['tabs'], fallback: config.bottomTabs));
  final activeTabs = _stringList(registry['activeTabs'], fallback: _stringList(navigation['contentTabs']));
  final nestedScreens = showNested
      ? _stringList(registry['nestedScreens'], fallback: _stringList(navigation['nestedRoutes']))
      : const <String>[];

  final mainRoutes = <String>[
    ...(configuredMain.isNotEmpty ? configuredMain : activeBottomTabs),
  ];
  final moreRoutes = <String>[
    ...(configuredMore.isNotEmpty ? configuredMore : activeTabs),
    ...nestedScreens,
  ];

  const fallbackMain = <String>['home', 'projects', 'board', 'profile'];
  const fallbackMore = <String>['tasks', 'taskTimeline', 'meetings', 'notifications', 'taskMap', 'timeline', 'files', 'calendar', 'teamMembers'];
  if (mainRoutes.isEmpty) mainRoutes.addAll(fallbackMain);
  if (moreRoutes.isEmpty) moreRoutes.addAll(fallbackMore);

  final taskTimelineEnabled = _asBool(sideMenu['showTaskTimeline'], fallback: true);
  if (taskTimelineEnabled) {
    final allRoutes = <String>[...mainRoutes, ...moreRoutes].map(_canonicalSideMenuRoute).toSet();
    if (!allRoutes.contains('taskTimeline')) {
      final taskIndex = moreRoutes.indexWhere((route) => _canonicalSideMenuRoute(route) == 'tasks');
      moreRoutes.insert(taskIndex >= 0 ? taskIndex + 1 : 0, 'taskTimeline');
    }
  }

  final seen = <String>{};
  final result = <_SduiSideMenuItem>[];

  void addRoutes(Iterable<String> routes, String group) {
    for (final raw in routes) {
      final route = _canonicalSideMenuRoute(raw);
      if (route.isEmpty || !seen.add(route)) continue;
      final screen = _asMap(screenConfigs[route]);
      final labelMap = _asMap(sideMenu['labelMap'] ?? sideMenu['labels'] ?? sideMenu['screenLabels']);
      final title = _asString(labelMap[route] ?? screen['label'] ?? screen['title'], fallback: config.routeLabel(route, fallback: _labelForTab(route)));
      result.add(_SduiSideMenuItem(route: route, label: title, group: group, icon: _iconForSideMenuRoute(route, config.raw)));
    }
  }

  addRoutes(mainRoutes, _asString(sideMenu['mainGroupLabel'], fallback: config.text('sideMenu.groups.main', fallback: 'Main')));
  addRoutes(moreRoutes, _asString(sideMenu['moreGroupLabel'], fallback: config.text('sideMenu.groups.more', fallback: 'More')));
  return result;
}

List<Widget> _buildGroupedSideMenuTiles({
  required List<_SduiSideMenuItem> items,
  required String currentTab,
  required Color accent,
  required Color text,
  required Color muted,
  required Color surface,
  required ValueChanged<String> onTap,
}) {
  final widgets = <Widget>[];
  String? lastGroup;
  for (final item in items) {
    if (item.group != lastGroup) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Text(
          item.group,
          style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.2),
        ),
      ));
      lastGroup = item.group;
    }
    final selected = item.route == currentTab;
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? accent.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onTap(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, color: selected ? accent : muted, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? text : text.withOpacity(0.86),
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: muted.withOpacity(0.55), size: 20),
              ],
            ),
          ),
        ),
      ),
    ));
  }
  return widgets;
}

String _canonicalSideMenuRoute(String raw) {
  final value = raw.trim();
  final compact = value.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  return switch (compact) {
    'home' || 'dashboard' || 'employeehome' => 'home',
    'task' || 'tasks' || 'tasklist' || 'mytasks' => 'tasks',
    'project' || 'projects' || 'projectlist' => 'projects',
    'board' || 'kanban' || 'kanbanboard' => 'board',
    'meeting' || 'meetings' || 'meetinglist' => 'meetings',
    'notification' || 'notifications' || 'inbox' || 'notificationlist' => 'notifications',
    'profile' || 'account' || 'myprofile' => 'profile',
    'taskmap' || 'taskmapsiteview' || 'siteview' => 'taskMap',
    'tasktimeline' || 'taskprogresstimeline' || 'productivetasktimeline' || 'deliveryuikittimeline' || 'deliveryappuikittimeline' => 'taskTimeline',
    'timeline' || 'timelinemilestones' || 'milestones' => 'timeline',
    'files' || 'file' || 'filesdocuments' || 'documents' => 'files',
    'calendar' || 'calendarview' || 'calendardeadlines' => 'calendar',
    'teammembers' || 'teamprojectmembers' || 'members' => 'teamMembers',
    'taskdetail' || 'taskdetails' => 'taskDetail',
    'projectdetail' || 'projectdetails' => 'projectDetail',
    'meetingdetail' || 'meetingdetails' => 'meetingDetail',
    _ => value,
  };
}

IconData _iconForSideMenuRoute(String route, Map<String, dynamic> rawConfig) {
  final sideMenu = _asMap(rawConfig['sideMenuConfig']);
  final sideMenuIconMap = _asMap(sideMenu['iconMap'] ?? sideMenu['icons'] ?? sideMenu['screenIcons']);
  final bottomNav = _asMap(rawConfig['bottomNav']);
  final bottomIconMap = _asMap(bottomNav['iconMap']);
  final screenConfigs = _asMap(rawConfig['screenConfigs']);
  final screenConfig = _asMap(screenConfigs[route]);

  final explicitIcon = _iconFromName(
        sideMenuIconMap[route]?.toString() ??
        bottomIconMap[route]?.toString() ??
        screenConfig['icon']?.toString() ??
        screenConfig['iconName']?.toString() ??
        screenConfig['leadingIcon']?.toString(),
      );
  if (explicitIcon != null) return explicitIcon;

  switch (route) {
    case 'taskMap':
      return Icons.location_on_outlined;
    case 'timeline':
      return Icons.schedule_rounded;
    case 'taskTimeline':
      return Icons.view_timeline_rounded;
    case 'files':
      return Icons.folder_open_rounded;
    case 'calendar':
      return Icons.calendar_month_rounded;
    case 'teamMembers':
      return Icons.groups_rounded;
    case 'taskDetail':
      return Icons.assignment_rounded;
    case 'projectDetail':
      return Icons.folder_special_rounded;
    case 'meetingDetail':
      return Icons.video_camera_front_rounded;
    default:
      return _iconForTab(route);
  }
}

Future<void> showSduiQuickActionSheet({
  required BuildContext context,
  required SduiMobileUiConfig config,
  required SduiActionCallback onAction,
}) {
  final actions = _stringList(config.quickActionDock['actions'], fallback: const [
    'createTask',
    'createProject',
    'uploadFile',
    'openInbox',
  ]);

  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: config.cardColor(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              config.text('quickActions.title', fallback: 'Quick action'),
              style: TextStyle(
                color: config.primaryTextColor(context),
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            for (final action in actions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF4F0E8),
                  child: Icon(_iconForAction(action), color: const Color(0xFF151515)),
                ),
                title: Text(config.text('quickActions.$action', fallback: _labelForAction(action)), style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  Navigator.of(context).pop();
                  onAction(action);
                },
              ),
          ],
        ),
      );
    },
  );
}

IconData _iconForTabFromConfig(String tab, Map<String, dynamic> bottomNav) {
  final iconMapRaw = bottomNav['iconMap'];
  if (iconMapRaw is Map) {
    final value = iconMapRaw[tab]?.toString().trim();
    final mapped = _iconFromName(value);
    if (mapped != null) return mapped;
  }
  return _iconForTab(tab);
}

IconData? _iconFromName(String? name) {
  final key = name?.trim().replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  switch (key) {
    case null:
    case '':
      return null;
    case 'home':
    case 'homerounded':
    case 'dashboard':
      return Icons.home_rounded;
    case 'search':
    case 'searchrounded':
    case 'magnify':
      return Icons.search_rounded;
    case 'heart':
    case 'favorite':
    case 'favoriteborder':
      return Icons.favorite_border_rounded;
    case 'task':
    case 'tasks':
    case 'taskalt':
    case 'assignment':
    case 'checklist':
      return Icons.task_alt_rounded;
    case 'board':
    case 'kanban':
    case 'viewkanban':
    case 'grid':
      return Icons.view_kanban_rounded;
    case 'project':
    case 'projects':
    case 'folder':
    case 'foldercopy':
      return Icons.folder_copy_rounded;
    case 'projectdetail':
    case 'folderspecial':
      return Icons.folder_special_rounded;
    case 'profile':
    case 'person':
    case 'user':
    case 'account':
      return Icons.person_rounded;
    case 'notifications':
    case 'notification':
    case 'inbox':
    case 'bell':
      return Icons.notifications_none_rounded;
    case 'message':
    case 'messages':
    case 'chat':
      return Icons.chat_bubble_outline_rounded;
    case 'meetings':
    case 'meeting':
    case 'videocall':
    case 'video':
      return Icons.video_call_rounded;
    case 'meetingdetail':
    case 'videocamerafront':
      return Icons.video_camera_front_rounded;
    case 'taskmap':
    case 'map':
    case 'location':
    case 'locationon':
    case 'pin':
      return Icons.location_on_outlined;
    case 'tasktimeline':
    case 'taskprogresstimeline':
      return Icons.view_timeline_rounded;
    case 'timeline':
    case 'timelinemilestones':
    case 'milestone':
    case 'schedule':
    case 'clock':
      return Icons.schedule_rounded;
    case 'files':
    case 'file':
    case 'documents':
    case 'folderopen':
      return Icons.folder_open_rounded;
    case 'calendar':
    case 'calendarview':
    case 'calendarmonth':
    case 'event':
      return Icons.calendar_month_rounded;
    case 'teammembers':
    case 'team':
    case 'members':
    case 'group':
    case 'groups':
      return Icons.groups_rounded;
    case 'taskdetail':
    case 'taskdetails':
      return Icons.assignment_rounded;
    case 'menu':
    case 'hamburger':
    case 'hamburgermenu':
      return Icons.menu_rounded;
    case 'plus':
    case 'add':
    case 'create':
      return Icons.add_rounded;
    default:
      return null;
  }
}


String _labelForTab(String tab) {
  switch (tab) {
    case 'home':
      return 'Home';
    case 'tasks':
      return 'Tasks';
    case 'taskTimeline':
      return 'Task Timeline';
    case 'projects':
      return 'Projects';
    case 'board':
      return 'Board';
    case 'meetings':
      return 'Meetings';
    case 'notifications':
      return 'Inbox';
    case 'profile':
      return 'Profile';
    default:
      return tab.isEmpty ? '' : '${tab[0].toUpperCase()}${tab.substring(1)}';
  }
}

IconData _iconForTab(String tab) {
  switch (tab) {
    case 'home':
      return Icons.home_rounded;
    case 'tasks':
      return Icons.task_alt_rounded;
    case 'projects':
      return Icons.folder_copy_rounded;
    case 'board':
      return Icons.view_kanban_rounded;
    case 'meetings':
      return Icons.video_call_rounded;
    case 'notifications':
      return Icons.notifications_none_rounded;
    case 'profile':
      return Icons.person_rounded;
    case 'taskMap':
      return Icons.location_on_outlined;
    case 'timeline':
      return Icons.schedule_rounded;
    case 'taskTimeline':
      return Icons.view_timeline_rounded;
    case 'files':
      return Icons.folder_open_rounded;
    case 'calendar':
      return Icons.calendar_month_rounded;
    case 'teamMembers':
      return Icons.groups_rounded;
    case 'taskDetail':
      return Icons.assignment_rounded;
    case 'projectDetail':
      return Icons.folder_special_rounded;
    case 'meetingDetail':
      return Icons.video_camera_front_rounded;
    default:
      return Icons.circle_rounded;
  }
}

IconData _iconForAction(String action) {
  switch (action) {
    case 'createTask':
      return Icons.add_task_rounded;
    case 'createProject':
      return Icons.create_new_folder_rounded;
    case 'uploadFile':
      return Icons.upload_file_rounded;
    case 'openInbox':
      return Icons.notifications_rounded;
    default:
      return Icons.add_rounded;
  }
}

String _labelForAction(String action) {
  switch (action) {
    case 'createTask':
      return 'Create task';
    case 'createProject':
      return 'Create project';
    case 'uploadFile':
      return 'Upload file';
    case 'openInbox':
      return 'Open inbox';
    default:
      return action;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  return const <String, dynamic>{};
}

bool _isTaskBoardShellContext(SduiMobileUiConfig config, String currentTab) {
  final canonicalCurrentTab = _canonicalSideMenuRoute(currentTab);
  final screenOverrides = _asMap(config.raw['screenOverrides']);
  final activeOverride = _asMap(screenOverrides[canonicalCurrentTab]);
  final activeScreenConfig = _asMap(config.screenConfigs[canonicalCurrentTab]);

  String compactToken(Object? value) => (value?.toString() ?? '').replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  bool isTaskBoardToken(Object? value) {
    final token = compactToken(value);
    return token == 'board' ||
        token == 'kanban' ||
        token == 'kanbanboard' ||
        token == 'taskboard' ||
        token == 'taskboardphase' ||
        token == 'phaseprojectstackcarousel' ||
        token == 'cinematichorizontaltaskstack';
  }

  return isTaskBoardToken(canonicalCurrentTab) ||
      isTaskBoardToken(activeOverride['screen']) ||
      isTaskBoardToken(activeOverride['screenKey']) ||
      isTaskBoardToken(activeOverride['route']) ||
      isTaskBoardToken(activeOverride['type']) ||
      isTaskBoardToken(activeOverride['layout']) ||
      isTaskBoardToken(activeOverride['boardStyle']) ||
      isTaskBoardToken(activeScreenConfig['screen']) ||
      isTaskBoardToken(activeScreenConfig['screenKey']) ||
      isTaskBoardToken(activeScreenConfig['type']) ||
      _asBool(activeOverride['phaseProjectStackCarousel']) ||
      _asBool(activeOverride['carouselOnlyTaskBoard']) ||
      _asBool(activeOverride['exactDesignerTaskCarousel']);
}

double _taskBoardHardcodedTopPadding(_ResponsiveNavMetrics metrics) {
  if (metrics.useNavigationRail) return 0.0;
  if (metrics.isTiny) return 126.0;
  if (metrics.isCompact) return 136.0;
  if (metrics.isVeryTallPhone) return 146.0;
  if (metrics.isTallPhone) return 140.0;
  return 132.0;
}

bool _isScrollAwareTopPaddingEnabled(SduiMobileUiConfig config) {
  final scroll = _asMap(config.raw['scrollAwareTopPadding']);
  final behavior = _asString(config.layoutConfig['topPaddingBehavior']).toLowerCase();
  final mode = _asString(config.navigationConfig['initialTopPaddingMode']).toLowerCase();
  return _asBool(scroll['enabled']) ||
      _asBool(config.navigationConfig['scrollAwareTopPadding']) ||
      _asBool(config.layoutConfig['adaptiveTopPadding']) ||
      behavior.contains('scrollaware') ||
      mode.contains('autountilfirstscroll');
}

double _scrollAwareInitialTopPadding(SduiMobileUiConfig config, _ResponsiveNavMetrics metrics) {
  final scroll = _asMap(config.raw['scrollAwareTopPadding']);
  final edge = _asMap(config.raw['edgeToEdgeConfig']);
  final edgeTop = _asMap(edge['topProtection']);
  final responsive = _asMap(config.raw['responsiveNav']);
  final overlap = _asMap(responsive['overlapProtection']);
  final fallback = _asDouble(
    scroll['fallbackInitialPaddingTop'] ?? edgeTop['initialTopPadding'] ?? overlap['initialTopPadding'],
    fallback: metrics.contentPaddingTop,
  );
  final explicitConfiguredValue = config.layoutConfig['initialContentPaddingTop'] ??
      config.topNav['initialContentProtectionPadding'] ??
      config.floatingTopNav['initialContentProtectionPadding'] ??
      edgeTop['initialTopPadding'] ??
      edgeTop['initialContentPaddingTop'] ??
      overlap['initialTopPadding'] ??
      overlap['initialContentPaddingTop'] ??
      scroll['fallbackInitialPaddingTop'] ??
      scroll['initialTopPadding'] ??
      scroll['initialContentPaddingTop'];
  final hasExplicitConfiguredValue = explicitConfiguredValue != null;
  final configured = _asDouble(explicitConfiguredValue, fallback: fallback);
  final extra = _asDouble(
    config.layoutConfig['initialContentProtectionExtra'] ??
        config.topNav['initialContentProtectionExtra'] ??
        config.floatingTopNav['initialContentProtectionExtra'] ??
        edgeTop['initialContentProtectionExtra'] ??
        overlap['initialContentProtectionExtra'] ??
        scroll['initialContentProtectionExtra'],
    fallback: hasExplicitConfiguredValue ? 0 : 18,
  );

  // v167: when Firestore publishes an explicit initial top padding (for
  // example 82), treat it as the final visual reserve for the floating top
  // dock. The previous renderer always took max(configured, runtimeSafe), so
  // tall Android phones could ignore the server value and keep a large gap
  // above the first page title.
  final ratioExtra = hasExplicitConfiguredValue ? 0.0 : _ratioBasedInitialProtectionExtra(config, metrics);
  final runtimeSafePadding = metrics.contentPaddingTop + extra + ratioExtra;
  final effective = hasExplicitConfiguredValue ? configured + extra : _maxDouble(configured, runtimeSafePadding);
  final maxInitialPadding = _asDouble(
    _asMap(config.layoutConfig['ratioBasedLayout'] ?? config.raw['ratioBasedLayout'])['maxInitialTopPadding'],
    fallback: metrics.isVeryTallPhone ? 176 : 156,
  );
  return _clampDouble(effective, 0, maxInitialPadding);
}

double _ratioBasedInitialProtectionExtra(SduiMobileUiConfig config, _ResponsiveNavMetrics metrics) {
  final ratioLayout = _asMap(config.layoutConfig['ratioBasedLayout'] ?? config.raw['ratioBasedLayout']);
  final enabled = _asBool(ratioLayout['enabled'], fallback: true);
  if (!enabled || metrics.isLandscape || metrics.isTablet) return 0;
  final minExtra = _asDouble(ratioLayout['minInitialTopProtectionExtra'], fallback: 0);
  final maxExtra = _asDouble(ratioLayout['maxInitialTopProtectionExtra'], fallback: metrics.isVeryTallPhone ? 22 : 16);
  final startAspect = _asDouble(ratioLayout['startAspectRatio'], fallback: 1.78);
  final factor = _asDouble(ratioLayout['topProtectionAspectFactor'], fallback: 34);
  final computed = (metrics.deviceAspectRatio - startAspect) * factor;
  return _clampDouble(computed, minExtra, maxExtra);
}

double _scrollAwareScrolledTopPadding(SduiMobileUiConfig config) {
  final scroll = _asMap(config.raw['scrollAwareTopPadding']);
  final edge = _asMap(config.raw['edgeToEdgeConfig']);
  final edgeTop = _asMap(edge['topProtection']);
  final responsive = _asMap(config.raw['responsiveNav']);
  final overlap = _asMap(responsive['overlapProtection']);
  final configured = _asDouble(
    config.layoutConfig['scrolledContentPaddingTop'] ??
        config.topNav['scrolledContentProtectionPadding'] ??
        config.floatingTopNav['scrolledContentProtectionPadding'] ??
        edgeTop['scrolledTopPadding'] ??
        edgeTop['scrolledContentPaddingTop'] ??
        overlap['scrolledTopPadding'] ??
        overlap['scrolledContentPaddingTop'] ??
        scroll['scrolledPaddingTop'],
    fallback: 0,
  );
  return _clampDouble(configured, 0, 80);
}

double _scrollAwareCollapseTrigger(SduiMobileUiConfig config) {
  final scroll = _asMap(config.raw['scrollAwareTopPadding']);
  final edge = _asMap(config.raw['edgeToEdgeConfig']);
  final edgeTop = _asMap(edge['topProtection']);
  final responsive = _asMap(config.raw['responsiveNav']);
  final overlap = _asMap(responsive['overlapProtection']);
  return _asDouble(
    config.layoutConfig['topPaddingCollapseThresholdPx'] ??
        config.navigationConfig['topPaddingCollapseThresholdPx'] ??
        config.topNav['protectionCollapseThresholdPx'] ??
        config.floatingTopNav['protectionCollapseThresholdPx'] ??
        edgeTop['topDetectionThresholdPx'] ??
        overlap['topDetectionThresholdPx'] ??
        overlap['topPaddingCollapseThresholdPx'] ??
        scroll['collapseTriggerOffset'],
    fallback: 8,
  );
}

String _asString(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) {
    final lower = value.toLowerCase().trim();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return fallback;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double _clampDouble(double value, double min, double max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

double _maxDouble(double a, double b) => a >= b ? a : b;

List<String> _stringList(dynamic value, {List<String> fallback = const []}) {
  if (value is Iterable) {
    final result = value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    return result.isEmpty ? fallback : result;
  }
  return fallback;
}
