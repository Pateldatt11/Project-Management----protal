import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_theme.dart';
import '../../../app/workspace_state.dart';
import '../../../core/config/app_config.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/brew_haven_chat_sheet.dart';
import '../../tasks/presentation/task_timeline_screen.dart';
import '../../../data/firebase/firebase_paths.dart';
import '../../../data/models/mobile_ui_config.dart';
import '../../../data/models/mobile_ui_design.dart';
import '../../../employee_app/server_driven/renderer/mobile_json_ui_renderer.dart';
import '../../../employee_app/server_driven/renderer/mobile_ui_support_registry.dart';



enum _PreviewDocTarget {
  release,
  test,
}

extension _PreviewDocTargetLabel on _PreviewDocTarget {
  String get label {
    return switch (this) {
      _PreviewDocTarget.release => 'Release',
      _PreviewDocTarget.test => 'Test',
    };
  }

  String get docId {
    return switch (this) {
      _PreviewDocTarget.release => 'mobileEmployee',
      _PreviewDocTarget.test => 'mobileEmployeeNext',
    };
  }

  String get description {
    return switch (this) {
      _PreviewDocTarget.release => 'Preview current production APK config.',
      _PreviewDocTarget.test => 'Preview next draft/test APK config.',
    };
  }

  String get designDocId {
    return switch (this) {
      _PreviewDocTarget.release => 'mobileEmployeeDesign',
      _PreviewDocTarget.test => 'mobileEmployeeNextDesign',
    };
  }

  String get draftDocId {
    return switch (this) {
      _PreviewDocTarget.release => 'mobileEmployeeDesignDraft',
      _PreviewDocTarget.test => 'mobileEmployeeNextDesignDraft',
    };
  }

  String get publishTitle {
    return switch (this) {
      _PreviewDocTarget.release => 'Release / current users',
      _PreviewDocTarget.test => 'Test / next APK only',
    };
  }
}

_PreviewDocTarget _previewTargetFromDocId(String docId) {
  return docId.trim() == 'mobileEmployeeNext' ? _PreviewDocTarget.test : _PreviewDocTarget.release;
}

enum _JsonImportMode {
  screenOnly,
  allUi,
  cosmeticOnly,
}

extension _JsonImportModeLabel on _JsonImportMode {
  String get label {
    return switch (this) {
      _JsonImportMode.screenOnly => 'Use imported JSON for screen UI only',
      _JsonImportMode.allUi => 'Apply imported JSON to all mobile UI',
      _JsonImportMode.cosmeticOnly => 'Apply cosmetic changes only',
    };
  }

  String get description {
    return switch (this) {
      _JsonImportMode.screenOnly => 'Keeps current bottom navigation/navbar and applies imported screen layout, card UI, and theme.',
      _JsonImportMode.allUi => 'Imports JSON into editable no-code controls for every mobile screen. Keeps the emulator editable instead of locking it to raw JSON preview.',
      _JsonImportMode.cosmeticOnly => 'Keeps navigation, section order, and visible fields. Applies only colors, spacing, radius, density, and card variants.',
    };
  }
}

enum _JsonImportTargetScreen {
  home,
  tasks,
  projects,
  board,
  notifications,
  calendar,
  profile,
}

extension _JsonImportTargetScreenLabel on _JsonImportTargetScreen {
  String get key {
    return switch (this) {
      _JsonImportTargetScreen.home => 'home',
      _JsonImportTargetScreen.tasks => 'tasks',
      _JsonImportTargetScreen.projects => 'projects',
      _JsonImportTargetScreen.board => 'board',
      _JsonImportTargetScreen.notifications => 'notifications',
      _JsonImportTargetScreen.calendar => 'calendar',
      _JsonImportTargetScreen.profile => 'profile',
    };
  }

  String get label => _label(key);
}

class MobileUiDesignerScreen extends ConsumerStatefulWidget {
  const MobileUiDesignerScreen({super.key});

  @override
  ConsumerState<MobileUiDesignerScreen> createState() => _MobileUiDesignerScreenState();
}

class _MobileUiDesignerScreenState extends ConsumerState<MobileUiDesignerScreen> {
  late MobileUiDesign _design;
  bool _advancedJsonOpen = false;
  bool _saving = false;
  bool _loadingPreviewConfig = false;
  String _previewTab = 'home';
  String _devicePreset = 'pixel8';
  String? _previewSourceStatus;
  Map<String, dynamic> _previewRuntimeConfig = const <String, dynamic>{};
  Map<String, dynamic>? _stagedRuntimeConfigForPublish;
  bool _stagedRuntimeConfigCameFromImport = false;
  _PreviewDocTarget _previewDocTarget = _previewTargetFromDocId(
    const String.fromEnvironment('SDUI_CONFIG_DOC', defaultValue: 'mobileEmployee'),
  );

  @override
  void initState() {
    super.initState();
    _design = MobileUiDesign.fromConfig(ref.read(workspaceProvider).mobileUiConfig);
    _loadPreviewConfigForTarget();
  }

  Map<String, dynamic> _extractSduiConfig(Map<String, dynamic> rawData) {
    // Supports both normal Firestore docs and patch-wrapper JSON files:
    // { version, patchName, applyTo, replaceDocument, config: { ...actual SDUI... } }
    final wrappedConfig = rawData['config'];
    if (wrappedConfig is Map) {
      return wrappedConfig.map((key, value) => MapEntry(key.toString(), value));
    }
    return rawData.map((key, value) => MapEntry(key.toString(), value));
  }


  Map<String, dynamic> _runtimeConfigFromJsonText(String rawJson) {
    final decoded = jsonDecode(rawJson.trim());
    if (decoded is! Map) {
      throw const FormatException('Top-level JSON must be an object.');
    }

    return _extractSduiConfig(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  static Map<String, dynamic> _cloneRuntimeMap(Map<String, dynamic> source) {
    return source.map((key, value) {
      if (value is Map) {
        return MapEntry(key, _cloneRuntimeMap(value.map((k, v) => MapEntry(k.toString(), v))));
      }
      if (value is List) {
        return MapEntry(key, value.map((item) {
          if (item is Map) return _cloneRuntimeMap(item.map((k, v) => MapEntry(k.toString(), v)));
          if (item is List) return List<dynamic>.from(item);
          return item;
        }).toList());
      }
      return MapEntry(key, value);
    });
  }

  static Map<String, dynamic> _deepMergeRuntimeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final next = _cloneRuntimeMap(base);
    for (final entry in overlay.entries) {
      final overlayValue = entry.value;
      final baseValue = next[entry.key];
      if (overlayValue is Map && baseValue is Map) {
        next[entry.key] = _deepMergeRuntimeMaps(
          baseValue.map((key, value) => MapEntry(key.toString(), value)),
          overlayValue.map((key, value) => MapEntry(key.toString(), value)),
        );
      } else {
        next[entry.key] = overlayValue;
      }
    }
    return next;
  }

  Future<Map<String, dynamic>> _readOptionalUiConfigDoc(String companyId, String docId) async {
    final docPath = '${FirebasePaths.uiConfigs(companyId)}/$docId';
    final snapshot = await FirebaseFirestore.instance.doc(docPath).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return const <String, dynamic>{};
    return _extractSduiConfig(data);
  }

  Map<String, dynamic> _normalizeRuntimeConfigForPreview(
    Map<String, dynamic> config, {
    required _PreviewDocTarget target,
  }) {
    final next = _cloneRuntimeMap(config);
    next['targetDocId'] = target.docId;
    next['publishTarget'] = target.name;
    next['previewParityMode'] = 'pureMergedFirestoreJson';
    next['adminPreviewRenderer'] = 'v95PureRuntimePreview';

    final registry = _mapValue(next['screenRegistry']);
    final registryTabs = _jsonStringList(registry['activeBottomTabs'] ?? registry['activeTabs']);
    final bottomTabs = _jsonStringList(next['bottomTabs']);
    if (bottomTabs.isEmpty && registryTabs.isNotEmpty) {
      next['bottomTabs'] = registryTabs;
    }

    final bottomNav = _mapValue(next['bottomNav']);
    if (bottomNav.isNotEmpty && _jsonStringList(bottomNav['tabs']).isEmpty) {
      bottomNav['tabs'] = _jsonStringList(next['bottomTabs']);
      next['bottomNav'] = bottomNav;
    }

    final screenOverrides = _mapValue(next['screenOverrides']);
    if (screenOverrides.isEmpty) {
      next['screenOverrides'] = <String, dynamic>{};
    }
    return next;
  }

  Future<void> _loadPreviewConfigForTarget({_PreviewDocTarget? target}) async {
    final nextTarget = target ?? _previewDocTarget;
    final state = ref.read(workspaceProvider);

    setState(() {
      _previewDocTarget = nextTarget;
      _loadingPreviewConfig = true;
      _stagedRuntimeConfigForPublish = null;
      _stagedRuntimeConfigCameFromImport = false;
      _previewSourceStatus = 'Loading ${nextTarget.label} preview from ${nextTarget.docId}...';
    });

    try {
      if (!AppConfig.useFirebase || state.company.companyId.isEmpty || state.company.companyId == 'platform') {
        final localDesign = MobileUiDesign.fromConfig(state.mobileUiConfig);
        if (!mounted) return;
        setState(() {
          _design = localDesign;
          _previewRuntimeConfig = _normalizeRuntimeConfigForPreview(
            localDesign.toMobileConfig().toMap(updatedBy: state.user.uid),
            target: nextTarget,
          );
          _previewSourceStatus = '${nextTarget.label} preview loaded from local state.';
        });
        return;
      }

      final coreConfig = await _readOptionalUiConfigDoc(state.company.companyId, nextTarget.docId);
      if (!mounted) return;
      if (coreConfig.isEmpty) {
        setState(() {
          _previewRuntimeConfig = const <String, dynamic>{};
          _previewSourceStatus = '${nextTarget.label} doc not found: ${nextTarget.docId}';
        });
        return;
      }

      final designConfig = await _readOptionalUiConfigDoc(state.company.companyId, nextTarget.designDocId);
      final screensDocId = nextTarget == _PreviewDocTarget.test ? 'mobileEmployeeNextScreens' : 'mobileEmployeeScreens';
      final screensConfig = await _readOptionalUiConfigDoc(state.company.companyId, screensDocId);

      var mergedConfig = _deepMergeRuntimeMaps(coreConfig, designConfig);
      mergedConfig = _deepMergeRuntimeMaps(mergedConfig, screensConfig);
      mergedConfig = _normalizeRuntimeConfigForPreview(mergedConfig, target: nextTarget);

      final loadedDesign = MobileUiDesign.fromMap(mergedConfig);
      final version = mergedConfig['version']?.toString() ?? loadedDesign.version.toString();
      final mergedParts = <String>[
        nextTarget.docId,
        if (designConfig.isNotEmpty) nextTarget.designDocId,
        if (screensConfig.isNotEmpty) screensDocId,
      ].join(' + ');
      setState(() {
        _design = loadedDesign;
        _previewRuntimeConfig = mergedConfig;
        _previewSourceStatus = '${nextTarget.label} pure preview: $mergedParts · v$version';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _previewSourceStatus = '${nextTarget.label} preview load failed: $error';
      });
    } finally {
      if (mounted) setState(() => _loadingPreviewConfig = false);
    }
  }


  void _selectPublishTargetWithoutReload(_PreviewDocTarget target) {
    setState(() {
      _previewDocTarget = target;
      if (_stagedRuntimeConfigForPublish != null) {
        _stagedRuntimeConfigForPublish = _normalizeRuntimeConfigForPreview(
          _stagedRuntimeConfigForPublish!,
          target: target,
        );
      }
      _previewRuntimeConfig = _normalizeRuntimeConfigForPreview(
        _previewRuntimeConfig.isEmpty
            ? <String, dynamic>{
                ..._design.toMobileConfig().toMap(updatedBy: _design.updatedBy ?? 'admin_preview'),
                'screenOverrides': _design.screenOverrides,
              }
            : _previewRuntimeConfig,
        target: target,
      );
      _previewSourceStatus = 'Publish target selected: ${target.label} · ${target.docId}. Current imported preview is preserved.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceProvider);
    final canManage = PermissionService.canManageSettings(state.currentMember);
    final previewJson = _design.toPrettyJson(updatedBy: state.user.uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile UI Designer'),
        actions: [
          TextButton.icon(
            onPressed: canManage && !_saving ? _showImportJsonDialog : null,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Import JSON'),
          ),
          TextButton.icon(
            onPressed: () => _copyJson(previewJson),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy JSON'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: StatusBadge(label: 'v${_design.version}', color: Colors.indigo)),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1160;
          final controls = _DesignerControls(
            design: _design,
            canManage: canManage && !_saving,
            advancedJsonOpen: _advancedJsonOpen,
            previewJson: previewJson,
            onDesignChanged: _applyNoCodeDesignChange,
            onTemplateSelected: _applyTemplate,
            onToggleAdvanced: () => setState(() => _advancedJsonOpen = !_advancedJsonOpen),
            onCopyJson: () => _copyJson(previewJson),
            onImportJson: _showImportJsonDialog,
            onSaveDraft: canManage ? _saveDraft : null,
            onPublish: canManage ? _publish : null,
            publishTarget: _previewDocTarget,
            onPublishTargetChanged: _selectPublishTargetWithoutReload,
            saving: _saving,
            hasRawOverrides: _design.screenOverrides.isNotEmpty,
            onClearImportedScreens: _clearImportedJsonRenders,
          );
          final preview = _PhonePreviewPanel(
            design: _design,
            runtimeConfig: _previewRuntimeConfig,
            previewTab: _previewTab,
            devicePreset: _devicePreset,
            previewDocTarget: _previewDocTarget,
            loadingPreviewConfig: _loadingPreviewConfig,
            previewSourceStatus: _previewSourceStatus,
            onPreviewTabChanged: (tab) => setState(() => _previewTab = _canonicalPreviewRoute(tab)),
            onDeviceChanged: (device) => setState(() => _devicePreset = device),
            onPreviewDocTargetChanged: (target) => _loadPreviewConfigForTarget(target: target),
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: controls,
                  ),
                ),
                Container(width: 1, color: AppTheme.border),
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: preview,
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                controls,
                const SizedBox(height: 18),
                preview,
              ],
            ),
          );
        },
      ),
    );
  }

  void _setDesign(MobileUiDesign design) {
    final nextRuntimeConfig = _normalizeRuntimeConfigForPreview(
      <String, dynamic>{
        ...design.toMobileConfig().toMap(
              updatedBy: design.updatedBy ?? 'admin_preview',
            ),
        'screenOverrides': design.screenOverrides,
      },
      target: _previewDocTarget,
    );

    final tabs = _previewTabsForRuntimeConfig(nextRuntimeConfig, design);
    final currentPreviewRoute = _canonicalPreviewRoute(_previewTab);
    final nextPreviewTab = tabs.contains(currentPreviewRoute)
        ? currentPreviewRoute
        : (tabs.isEmpty ? 'home' : tabs.first);

    setState(() {
      _design = design;
      _previewRuntimeConfig = nextRuntimeConfig;
      _stagedRuntimeConfigForPublish = null;
      _stagedRuntimeConfigCameFromImport = false;
      _previewTab = nextPreviewTab;
    });
  }

  void _applyNoCodeDesignChange(MobileUiDesign design) {
    // If an imported raw JSON screen is active, normal no-code controls appear to do nothing
    // because the preview prioritizes the imported screen override. Any no-code edit now
    // returns the preview to the generated no-code renderer so every control visibly works.
    _setDesign(design.copyWith(screenOverrides: const <String, Map<String, dynamic>>{}));
  }

  void _clearImportedJsonRenders() {
    _setDesign(_design.copyWith(screenOverrides: const <String, Map<String, dynamic>>{}));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Imported JSON render cleared. No-code designer controls are active again.')),
    );
  }

  void _applyTemplate(String templateName) {
    final nextDesign = switch (templateName) {
      'compactEmployeeApp' => _templateCompact(_design),
      'modernCardUi' => _templateModern(_design),
      'progressFocusUi' => _templateProgress(_design),
      'minimalFieldUi' => _templateMinimal(_design),
      'editorialNativeUi' => _templateEditorialNative(_design),
      _ => _templateClean(_design),
    };
    _setDesign(nextDesign.copyWith(screenOverrides: const <String, Map<String, dynamic>>{}));
  }

  Future<void> _copyJson(String jsonText) async {
    await Clipboard.setData(ClipboardData(text: jsonText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied.')));
  }

  Future<void> _showImportJsonDialog() async {
    final controller = TextEditingController();
    var importMode = _JsonImportMode.screenOnly;
    var targetScreen = _JsonImportTargetScreen.home;
    var importDocTarget = _previewDocTarget;
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> importNow() async {
              try {
                final importedRuntimeConfig = _runtimeConfigFromJsonText(controller.text);
                final imported = _designFromJson(
                  controller.text,
                  mode: importMode,
                  targetScreen: targetScreen.key,
                );

                if (!mounted) return;

                this.setState(() {
                  _design = imported;

                  final baseRuntimeConfig = _previewRuntimeConfig.isEmpty
                      ? <String, dynamic>{
                          ...imported.toMobileConfig().toMap(
                                updatedBy: ref.read(workspaceProvider).user.uid,
                              ),
                          'screenOverrides': imported.screenOverrides,
                        }
                      : _previewRuntimeConfig;

                  final mergedRuntimeConfig = importMode == _JsonImportMode.screenOnly
                      ? _deepMergeRuntimeMaps(baseRuntimeConfig, importedRuntimeConfig)
                      : importedRuntimeConfig;

                  _previewRuntimeConfig = _normalizeRuntimeConfigForPreview(
                    mergedRuntimeConfig,
                    target: importDocTarget,
                  );
                  _stagedRuntimeConfigForPublish = _normalizeRuntimeConfigForPreview(
                    importMode == _JsonImportMode.screenOnly ? mergedRuntimeConfig : importedRuntimeConfig,
                    target: importDocTarget,
                  );
                  _stagedRuntimeConfigCameFromImport = true;
                  _previewDocTarget = importDocTarget;
                  _previewSourceStatus =
                      'Imported JSON staged for ${importDocTarget.label} · ${importDocTarget.docId}. Save/Publish will write this JSON to ${importDocTarget.designDocId}.';

                  final tabs = _previewTabsForRuntimeConfig(_previewRuntimeConfig, imported);
                  if (importMode == _JsonImportMode.allUi) {
                    final currentPreviewRoute = _canonicalPreviewRoute(_previewTab);
                    _previewTab = tabs.contains(currentPreviewRoute)
                        ? currentPreviewRoute
                        : (tabs.isEmpty ? 'home' : tabs.first);
                  } else {
                    _previewTab = _canonicalPreviewRoute(targetScreen.key);
                  }
                });

                // ---> UPDATED SAFE ASYNC CHECKS HERE <---
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('${importMode.label} applied to preview. Publish when ready.')),
                  );
                }
              } catch (error) {
                setState(() => errorText = 'Invalid UI JSON: $error');
              }
            }

            Future<void> pasteClipboard() async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text == null || data!.text!.trim().isEmpty) {
                setState(() => errorText = 'Clipboard has no JSON text.');
                return;
              }
              controller.text = data.text!;
              setState(() => errorText = null);
            }

            return AlertDialog(
              title: const Text('Import JSON UI'),
              content: SizedBox(
                width: 800,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paste a mobileEmployeeDesign JSON or the older mobileEmployee config JSON. Choose how much of the imported design should affect the preview before publishing.',
                        style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_PreviewDocTarget>(
                        key: ValueKey('import-doc-target-${importDocTarget.name}'),
                        initialValue: importDocTarget,
                        decoration: const InputDecoration(labelText: 'Import / publish target'),
                        items: _PreviewDocTarget.values
                            .map((target) => DropdownMenuItem<_PreviewDocTarget>(
                                  value: target,
                                  child: Text('${target.label} · ${target.docId}'),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() {
                          importDocTarget = value ?? _PreviewDocTarget.test;
                          errorText = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        importDocTarget == _PreviewDocTarget.release
                            ? 'Imported JSON will be staged for Release. Publishing writes mobileEmployee for current users.'
                            : 'Imported JSON will be staged for Test. Publishing writes mobileEmployeeNext only; current users stay on mobileEmployee.',
                        style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_JsonImportMode>(
                        key: ValueKey('import-mode-${importMode.name}'),
                        initialValue: importMode,
                        decoration: const InputDecoration(labelText: 'Import apply mode'),
                        items: _JsonImportMode.values
                            .map((mode) => DropdownMenuItem<_JsonImportMode>(
                                  value: mode,
                                  child: Text(mode.label),
                                ))
                            .toList(),
                        onChanged: (value) => setState(() {
                          importMode = value ?? _JsonImportMode.screenOnly;
                          errorText = null;
                        }),
                      ),
                      const SizedBox(height: 8),
                      Text(importMode.description, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<_JsonImportTargetScreen>(
                        key: ValueKey('import-target-${targetScreen.key}-${importMode.name}'),
                        initialValue: targetScreen,
                        decoration: const InputDecoration(labelText: 'Screen to change from imported JSON'),
                        items: _JsonImportTargetScreen.values
                            .map((screen) => DropdownMenuItem<_JsonImportTargetScreen>(
                                  value: screen,
                                  child: Text(screen.label),
                                ))
                            .toList(),
                        onChanged: importMode == _JsonImportMode.allUi
                            ? null
                            : (value) => setState(() {
                                  targetScreen = value ?? _JsonImportTargetScreen.home;
                                  errorText = null;
                                }),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        importMode == _JsonImportMode.allUi
                            ? 'All UI import can replace every preview screen. Screen selector is disabled for this mode.'
                            : 'Only ${targetScreen.label} will render from the imported JSON. The navbar and other screens stay unchanged unless you choose all UI.',
                        style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        minLines: 12,
                        maxLines: 18,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                        decoration: InputDecoration(
                          labelText: 'Paste JSON here',
                          alignLabelWithHint: true,
                          errorText: errorText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(onPressed: pasteClipboard, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste clipboard')),
                TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
                FilledButton.icon(onPressed: importNow, icon: const Icon(Icons.upload_rounded), label: const Text('Import to UI')),
              ],
            );
          },
        );
      },
    );
  }

  MobileUiDesign _designFromJson(String rawJson, {required _JsonImportMode mode, required String targetScreen}) {
    final decoded = jsonDecode(rawJson.trim());
    if (decoded is! Map) {
      throw const FormatException('Top-level JSON must be an object.');
    }
    final map = _extractSduiConfig(decoded.map((key, value) => MapEntry(key.toString(), value)));

    // Accept normal Firestore docs, patch-wrapper JSON files, full designer schema,
    // and the lightweight runtime config schema. Patch wrappers are unwrapped above
    // so admin can paste the generated JSON file directly.
    final looksLikeRuntimeConfig = map.containsKey('bottomTabs') || map.containsKey('homeCards') || map.containsKey('taskCardFields') || map.containsKey('projectCardFields');
    final imported = looksLikeRuntimeConfig ? MobileUiDesign.fromConfig(MobileUiConfig.fromMap(map)) : MobileUiDesign.fromMap(map);

    final normalized = imported.copyWith(
      version: imported.version <= 0 ? _design.version : imported.version,
      updatedAt: DateTime.now(),
      updatedBy: ref.read(workspaceProvider).user.uid,
    );
    return _mergeImportedDesign(normalized, mode: mode, rawJson: map, targetScreen: targetScreen);
  }

  MobileUiDesign _mergeImportedDesign(
    MobileUiDesign imported, {
    required _JsonImportMode mode,
    required Map<String, dynamic> rawJson,
    required String targetScreen,
  }) {
    final importedScreenPayload = MobileUiDesign.screenPayload(rawJson, targetScreen) ?? rawJson;
    final currentOverrides = MobileUiDesign.cloneScreenOverrides(_design.screenOverrides);

    if (mode == _JsonImportMode.allUi) {
      // All mobile UI import must stay editable. The previous all-UI importer
      // stored imported screens in screenOverrides, so the emulator switched to
      // strict raw JSON mode and the no-code controls looked deactivated. Now
      // all-UI import converts supported JSON keys into the normal no-code
      // design model and clears raw overrides. Strict imported-screen rendering
      // remains available only for the screen-only import mode.
      return _editableNoCodeDesignFromImported(imported, rawJson).copyWith(
        templateName: 'importedJson_allUiEditable',
        screenOverrides: const <String, Map<String, dynamic>>{},
        updatedAt: imported.updatedAt,
        updatedBy: imported.updatedBy,
      );
    }

    currentOverrides[targetScreen] = <String, dynamic>{
      'screen': targetScreen,
      '_strictJsonOnly': true,
      ...importedScreenPayload,
    };

    return switch (mode) {
      _JsonImportMode.screenOnly => _design.copyWith(
          version: imported.version,
          enabled: imported.enabled,
          templateName: 'importedJson_$targetScreen',
          theme: Map<String, dynamic>.from(imported.theme),
          sections: targetScreen == 'home' ? imported.sections.map(Map<String, dynamic>.from).toList() : _design.sections.map(Map<String, dynamic>.from).toList(),
          taskCard: targetScreen == 'tasks' ? Map<String, dynamic>.from(imported.taskCard) : Map<String, dynamic>.from(_design.taskCard),
          projectCard: targetScreen == 'projects' ? Map<String, dynamic>.from(imported.projectCard) : Map<String, dynamic>.from(_design.projectCard),
          screenOverrides: currentOverrides,
          updatedAt: imported.updatedAt,
          updatedBy: imported.updatedBy,
          // Keep existing bottomNav/navbar exactly as-is.
          bottomNav: Map<String, dynamic>.from(_design.bottomNav),
        ),
      _JsonImportMode.cosmeticOnly => _design.copyWith(
          version: imported.version,
          enabled: imported.enabled,
          templateName: 'importedCosmetic_$targetScreen',
          theme: Map<String, dynamic>.from(imported.theme),
          sections: _mergeSectionCosmetics(_design.sections, imported.sections),
          taskCard: _mergeCardCosmetics(_design.taskCard, imported.taskCard),
          projectCard: _mergeCardCosmetics(_design.projectCard, imported.projectCard),
          screenOverrides: currentOverrides,
          updatedAt: imported.updatedAt,
          updatedBy: imported.updatedBy,
          // Keep bottom navigation, visible fields, actions, and section order.
          bottomNav: Map<String, dynamic>.from(_design.bottomNav),
        ),
      _JsonImportMode.allUi => imported,
    };
  }

  MobileUiDesign _editableNoCodeDesignFromImported(MobileUiDesign imported, Map<String, dynamic> rawJson) {
    final homePayload = _screenPayloadForNoCode(rawJson, 'home');
    final taskPayload = _screenPayloadForNoCode(rawJson, 'tasks');
    final projectPayload = _screenPayloadForNoCode(rawJson, 'projects');
    final profilePayload = _screenPayloadForNoCode(rawJson, 'profile');

    final theme = _mergeMap(imported.theme, _mapValue(rawJson['theme']));
    final bottomNav = _mergeBottomNav(imported.bottomNav, rawJson);
    final topNav = _mergeMap(imported.topNav, _mapValue(rawJson['topNav']));
    final sections = _sectionsForNoCode(imported.sections, rawJson, homePayload);
    final taskCard = _cardForNoCode(imported.taskCard, rawJson, taskPayload, 'taskCard');
    final projectCard = _cardForNoCode(imported.projectCard, rawJson, projectPayload, 'projectCard');
    final taskListConfig = _mergeMap(imported.taskListConfig, _mapValue(taskPayload['taskListConfig'] ?? rawJson['taskListConfig']));
    final profileActions = _mergeMap(imported.profileActions, _mapValue(profilePayload['profileActions'] ?? rawJson['profileActions']));

    return imported.copyWith(
      theme: theme,
      bottomNav: bottomNav,
      topNav: topNav,
      sections: sections,
      taskCard: taskCard,
      projectCard: projectCard,
      taskListConfig: taskListConfig,
      profileActions: profileActions,
      screenOverrides: const <String, Map<String, dynamic>>{},
    );
  }

  static Map<String, dynamic> _screenPayloadForNoCode(Map<String, dynamic> rawJson, String screen) {
    final payload = MobileUiDesign.screenPayload(rawJson, screen);
    if (payload == null) return const <String, dynamic>{};
    return Map<String, dynamic>.from(payload);
  }

  static Map<String, dynamic> _mapValue(dynamic value) {
    if (value is! Map) return const <String, dynamic>{};
    return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  }

  static Map<String, dynamic> _mergeMap(Map<String, dynamic> base, Map<String, dynamic> imported) {
    if (imported.isEmpty) return Map<String, dynamic>.from(base);
    return <String, dynamic>{...base, ...imported};
  }

  static Map<String, dynamic> _mergeBottomNav(Map<String, dynamic> base, Map<String, dynamic> rawJson) {
    final importedBottomNav = _mapValue(rawJson['bottomNav']);
    final next = <String, dynamic>{...base, ...importedBottomNav};
    final tabs = _jsonStringList(rawJson['bottomTabs']);
    if (tabs.isNotEmpty) {
      next['tabs'] = tabs.where(MobileUiConfig.allowedBottomTabs.contains).toSet().toList();
    }
    return next;
  }

  static List<Map<String, dynamic>> _sectionsForNoCode(
    List<Map<String, dynamic>> importedSections,
    Map<String, dynamic> rawJson,
    Map<String, dynamic> homePayload,
  ) {
    final rawSections = homePayload['sections'] ?? rawJson['sections'];
    if (rawSections is List) {
      final result = rawSections.whereType<Map>().map((item) => item.map((key, value) => MapEntry(key.toString(), value))).toList();
      if (result.isNotEmpty) return result;
    }
    final homeCards = _jsonStringList(rawJson['homeCards']);
    if (homeCards.isNotEmpty) {
      return homeCards
          .where(MobileUiConfig.allowedHomeCards.contains)
          .map((id) => <String, dynamic>{
                'id': id,
                'type': MobileUiDesign.sectionTypes[id] ?? id,
                'title': MobileUiDesign.sectionLabels[id] ?? _label(id),
                'style': id == 'deadlineTimer' ? 'compact' : 'modern',
                'visible': true,
              })
          .toList();
    }
    return importedSections.map(Map<String, dynamic>.from).toList();
  }

  static Map<String, dynamic> _cardForNoCode(
    Map<String, dynamic> importedCard,
    Map<String, dynamic> rawJson,
    Map<String, dynamic> screenPayload,
    String cardKey,
  ) {
    final rootCard = _mapValue(rawJson[cardKey]);
    final screenCard = _mapValue(screenPayload[cardKey]);
    final next = <String, dynamic>{...importedCard, ...rootCard, ...screenCard};

    final rootFieldsKey = cardKey == 'taskCard' ? 'taskCardFields' : 'projectCardFields';
    final rootVariantKey = cardKey == 'taskCard' ? 'taskCardVariant' : 'projectCardVariant';
    final allowedFields = cardKey == 'taskCard' ? MobileUiConfig.allowedTaskCardFields : MobileUiConfig.allowedProjectCardFields;

    final fields = <String>{
      ..._jsonStringList(next['showFields']).where(allowedFields.contains),
      ..._jsonStringList(rawJson[rootFieldsKey]).where(allowedFields.contains),
      ..._jsonStringList(screenPayload['showFields']).where(allowedFields.contains),
    }.toList();
    if (fields.isNotEmpty) next['showFields'] = fields;

    final variant = (rawJson[rootVariantKey] ?? screenPayload['variant'] ?? next['variant'])?.toString();
    if (variant != null && MobileUiConfig.allowedCardVariants.contains(variant)) {
      next['variant'] = variant;
    }
    return next;
  }

  Map<String, Map<String, dynamic>> _allUiScreenOverridesFromJson(
    Map<String, dynamic> rawJson, {
    required MobileUiDesign imported,
    required String fallbackTargetScreen,
  }) {
    final result = <String, Map<String, dynamic>>{};

    void addScreen(String rawKey, dynamic rawValue) {
      final screenKey = rawKey.trim();
      if (!_allMobileScreenKeys.contains(screenKey) || rawValue is! Map) return;
      final payload = rawValue.map((key, value) => MapEntry(key.toString(), value));
      result[screenKey] = <String, dynamic>{
        'screen': screenKey,
        '_strictJsonOnly': true,
        ...payload,
      };
    }

    void addFromContainer(dynamic container) {
      if (container is! Map) return;
      for (final entry in container.entries) {
        addScreen(entry.key.toString(), entry.value);
      }
    }

    addFromContainer(rawJson['screens']);
    addFromContainer(rawJson['screenLayouts']);
    addFromContainer(rawJson['routes']);
    addFromContainer(rawJson['pages']);

    for (final entry in imported.screenOverrides.entries) {
      addScreen(entry.key, entry.value);
    }

    for (final screenKey in _allMobileScreenKeys) {
      final maybePayload = rawJson[screenKey];
      if (maybePayload is Map) addScreen(screenKey, maybePayload);
    }

    if (result.isNotEmpty) return result;

    // Full runtime/design JSON already carries bottom nav, top nav, sections,
    // task/project card config, profile actions, etc. Keeping overrides empty
    // lets every emulator tab render from the imported design instead of
    // forcing Home-only strict JSON.
    if (_looksLikeFullMobileUiSchema(rawJson)) {
      return const <String, Map<String, dynamic>>{};
    }

    // Single-screen JSON fallback. Since the admin chose all mobile UI and the
    // screen selector is disabled, apply the same imported shell to every active
    // mobile tab so the emulator/published APK does not restrict it to Home.
    final importedScreen = rawJson['screen']?.toString().trim();
    if (importedScreen != null && _allMobileScreenKeys.contains(importedScreen)) {
      addScreen(importedScreen, rawJson);
      return result;
    }

    final tabs = <String>{
      ..._design.bottomTabs.where(_allMobileScreenKeys.contains),
      ...imported.bottomTabs.where(_allMobileScreenKeys.contains),
      fallbackTargetScreen,
    }.where(_allMobileScreenKeys.contains).toList();
    final safeTabs = tabs.isEmpty ? _defaultAllUiTabs : tabs;
    for (final screenKey in safeTabs) {
      addScreen(screenKey, <String, dynamic>{...rawJson, 'screen': screenKey});
    }
    return result;
  }

  static const List<String> _defaultAllUiTabs = <String>['home', 'tasks', 'projects', 'notifications', 'profile'];

  static const Set<String> _allMobileScreenKeys = <String>{
    'home',
    'tasks',
    'projects',
    'board',
    'notifications',
    'calendar',
    'meetings',
    'profile',
  };

  static bool _looksLikeFullMobileUiSchema(Map<String, dynamic> rawJson) {
    return rawJson.containsKey('bottomTabs') ||
        rawJson.containsKey('homeCards') ||
        rawJson.containsKey('taskCardFields') ||
        rawJson.containsKey('projectCardFields') ||
        rawJson.containsKey('bottomNav') ||
        rawJson.containsKey('topNav') ||
        rawJson.containsKey('sections') ||
        rawJson.containsKey('taskCard') ||
        rawJson.containsKey('projectCard') ||
        rawJson.containsKey('taskListConfig') ||
        rawJson.containsKey('profileActions') ||
        rawJson.containsKey('screenOverrides') ||
        rawJson.containsKey('designSystem') ||
        rawJson.containsKey('animationConfig') ||
        rawJson.containsKey('layoutConfig') ||
        rawJson.containsKey('navigationConfig') ||
        rawJson.containsKey('floatingTopNav') ||
        rawJson.containsKey('floatingBottomNav') ||
        rawJson.containsKey('quickActionDock') ||
        rawJson.containsKey('screenConfigs') ||
        rawJson.containsKey('rendererCompatibility');
  }

  static Map<String, dynamic> _mergeCardCosmetics(Map<String, dynamic> current, Map<String, dynamic> imported) {
    final next = Map<String, dynamic>.from(current);
    for (final key in <String>['variant', 'style', 'radius', 'padding', 'density']) {
      if (imported.containsKey(key)) next[key] = imported[key];
    }
    return next;
  }

  static List<Map<String, dynamic>> _mergeSectionCosmetics(List<Map<String, dynamic>> current, List<Map<String, dynamic>> imported) {
    final importedById = <String, Map<String, dynamic>>{
      for (final section in imported) if ((section['id']?.toString() ?? '').isNotEmpty) section['id'].toString(): section,
    };
    return current.map((section) {
      final next = Map<String, dynamic>.from(section);
      final importedSection = importedById[next['id']?.toString() ?? ''];
      if (importedSection != null && importedSection.containsKey('style')) {
        next['style'] = importedSection['style'];
      }
      return next;
    }).toList();
  }

  void _validateImportedDesign(MobileUiDesign design) {
    // Imported UI JSON can be a screen-specific payload that is rendered by the raw JSON previewer.
    // Do not reject it just because it does not contain the no-code designer's default sections.
  }


  Future<void> _saveDraft() async {
    await _writeDesign(docId: _previewDocTarget.draftDocId, publish: false, target: _previewDocTarget);
  }

  Future<void> _publish() async {
    await _writeDesign(docId: _previewDocTarget.designDocId, publish: true, target: _previewDocTarget);
  }

  int _readVersion(Map<String, dynamic>? data, int fallback) {
    final raw = data == null ? null : data['version'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  Map<String, dynamic> _runtimePayloadForDesignDoc({
    required MobileUiDesign design,
    required _PreviewDocTarget target,
    required int version,
    required String updatedBy,
    required String companyId,
    required DateTime now,
  }) {
    final runtimeSource = _stagedRuntimeConfigForPublish ??
        (_previewRuntimeConfig.isNotEmpty
            ? _previewRuntimeConfig
            : <String, dynamic>{
                ...design.toMobileConfig(versionOverride: version).toMap(updatedBy: updatedBy),
                'screenOverrides': design.screenOverrides,
              });

    final payload = _normalizeRuntimeConfigForPreview(runtimeSource, target: target);
    payload['version'] = version;
    payload['enabled'] = payload['enabled'] ?? true;
    payload['updatedAt'] = now.toIso8601String();
    payload['updatedBy'] = updatedBy;
    payload['targetDocId'] = target.docId;
    payload['publishTarget'] = target.name;
    payload['configDocPath'] = '${FirebasePaths.uiConfigs(companyId)}/${target.docId}';
    payload['sourceDesignDocId'] = target.designDocId;
    payload['publishedFrom'] = _stagedRuntimeConfigCameFromImport
        ? 'mobile_ui_designer_imported_runtime_json'
        : 'mobile_ui_designer_no_code_runtime_json';
    payload['previewParityMode'] = 'pureMergedFirestoreJson';
    payload['adminPreviewRenderer'] = 'v98PublishRuntimeJson';
    return payload;
  }

  Future<MobileUiDesign> _publishDesignToFirestoreTarget(
    MobileUiDesign design, {
    required _PreviewDocTarget target,
    required String companyId,
    required String updatedBy,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final configRef = firestore.doc('${FirebasePaths.uiConfigs(companyId)}/${target.docId}');
    final designRef = firestore.doc('${FirebasePaths.uiConfigs(companyId)}/${target.designDocId}');
    final now = DateTime.now();

    return firestore.runTransaction<MobileUiDesign>((transaction) async {
      final configSnapshot = await transaction.get(configRef);
      final designSnapshot = await transaction.get(designRef);
      final configData = configSnapshot.data();
      final designData = designSnapshot.data();
      final configVersion = _readVersion(configData, design.version);
      final designVersion = _readVersion(designData, design.version);
      final currentVersion = configVersion > designVersion ? configVersion : designVersion;
      final nextVersion = (currentVersion > design.version ? currentVersion : design.version) + 1;
      final nextDesign = design.copyWith(version: nextVersion, updatedAt: now, updatedBy: updatedBy);
      final designPayload = _runtimePayloadForDesignDoc(
        design: nextDesign,
        target: target,
        version: nextVersion,
        updatedBy: updatedBy,
        companyId: companyId,
        now: now,
      );

      if (designData != null) {
        transaction.set(designRef.collection('versions').doc('v$designVersion'), <String, dynamic>{
          ...designData,
          'backupCreatedAt': now.toIso8601String(),
          'backupReason': 'before_${target.designDocId}_publish_from_mobile_ui_designer',
          'targetDocId': target.docId,
          'publishTarget': target.name,
        }, SetOptions(merge: true));
      }

      // Important: publish imported/Test UI into the Design doc, not by rebuilding
      // mobileEmployeeNext from the no-code model. Rebuilding the core doc caused
      // the real preview to fall back to old cards after publish.
      transaction.set(designRef, designPayload);
      transaction.set(designRef.collection('versions').doc('v$nextVersion'), <String, dynamic>{
        ...designPayload,
        'savedAsRollbackVersion': true,
      }, SetOptions(merge: true));

      // Keep the core doc as structure-only. Only bump safe metadata so preview/APK
      // caches know a newer UI layer exists.
      transaction.set(configRef, <String, dynamic>{
        'enabled': configData?['enabled'] ?? true,
        'version': nextVersion,
        'updatedAt': now.toIso8601String(),
        'updatedBy': updatedBy,
        'targetDocId': target.docId,
        'publishTarget': target.name,
        'sourceDesignDocId': target.designDocId,
        'latestDesignVersion': nextVersion,
        'latestDesignUpdatedAt': now.toIso8601String(),
        'previewParityMode': 'corePlusDesignMerged',
      }, SetOptions(merge: true));

      return nextDesign;
    });
  }

  Future<void> _writeDesign({required String docId, required bool publish, required _PreviewDocTarget target}) async {
    final state = ref.read(workspaceProvider);
    final nextDesign = _design.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: state.user.uid,
    );
    setState(() {
      _saving = true;
      _design = nextDesign;
    });

    try {
      if (publish) {
        final publishedDesign = AppConfig.useFirebase && state.company.companyId != 'platform'
            ? await _publishDesignToFirestoreTarget(
                nextDesign,
                target: target,
                companyId: state.company.companyId,
                updatedBy: state.user.uid,
              )
            : nextDesign.copyWith(
                version: nextDesign.version + 1,
                updatedAt: DateTime.now(),
                updatedBy: state.user.uid,
              );

        if (!mounted) return;
        setState(() {
          _design = publishedDesign;
          _previewDocTarget = target;
          _previewSourceStatus = '${target.label} UI published to ${target.designDocId}. Reloading real preview...';
        });

        // Force the emulator to read back the real Firestore documents after publish.
        // This prevents the preview from showing the old in-memory/no-code fallback.
        if (AppConfig.useFirebase && state.company.companyId != 'platform') {
          await _loadPreviewConfigForTarget(target: target);
        } else {
          final runtime = _normalizeRuntimeConfigForPreview(
            _runtimePayloadForDesignDoc(
              design: publishedDesign,
              target: target,
              version: publishedDesign.version,
              updatedBy: state.user.uid,
              companyId: state.company.companyId,
              now: DateTime.now(),
            ),
            target: target,
          );
          setState(() => _previewRuntimeConfig = runtime);
        }
      } else if (AppConfig.useFirebase && state.company.companyId != 'platform') {
        final now = DateTime.now();
        final draftPayload = _runtimePayloadForDesignDoc(
          design: nextDesign,
          target: target,
          version: nextDesign.version,
          updatedBy: state.user.uid,
          companyId: state.company.companyId,
          now: now,
        );
        await FirebaseFirestore.instance.doc('${FirebasePaths.uiConfigs(state.company.companyId)}/$docId').set(<String, dynamic>{
          ...draftPayload,
          'draft': true,
          'configDocPath': '${FirebasePaths.uiConfigs(state.company.companyId)}/${target.docId}',
        });
      }

      if (!mounted) return;
      final versionLabel = _design.version.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            publish
                ? '${target.label} UI published to ${target.designDocId} as v$versionLabel. ${target == _PreviewDocTarget.test ? 'Current users are unchanged.' : 'Release design layer updated.'}'
                : '${target.label} design draft saved to $docId. Config target remains ${target.docId}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mobile UI design save failed: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static MobileUiDesign _templateEditorialNative(MobileUiDesign current) {
    final config = MobileUiConfig.defaults().copyWith(
      version: current.version,
      enabled: current.enabled,
      updatedBy: current.updatedBy,
      updatedAt: current.updatedAt,
    );
    return MobileUiDesign.fromConfig(config, templateName: 'editorialNativeUi').copyWith(
      screenOverrides: const <String, Map<String, dynamic>>{},
    );
  }

  static MobileUiDesign _templateClean(MobileUiDesign current) {
    return current.copyWith(
      templateName: 'cleanWorkApp',
      theme: <String, dynamic>{
        ...current.theme,
        'accent': '#2563EB',
        'background': '#F6F8FB',
        'surface': '#FFFFFF',
        'cardRadius': 24,
        'cardPadding': 16,
        'density': 'comfortable',
      },
      bottomNav: <String, dynamic>{'style': 'floating', 'tabs': <String>['home', 'tasks', 'projects', 'notifications', 'profile']},
      topNav: <String, dynamic>{'enabled': true, 'style': 'glassAdvanced', 'density': 'comfortable', 'showInbox': true, 'showCompanyName': true, 'showUserRole': true, 'showOnlineStatus': true, 'showLogout': false, 'inboxBadge': true, 'showAvatar': true, 'showPresenceGlow': true},
      sections: <Map<String, dynamic>>[
        _section('workSummary', style: 'soft'),
        _section('deadlineTimer', style: 'compact'),
        _section('myOpenTasks', style: 'modern'),
        _section('projectProgress', style: 'ring'),
        _section('onlineStatus', style: 'pill'),
      ],
      taskCard: <String, dynamic>{'variant': 'modernCard', 'showFields': <String>['taskTitle', 'projectName', 'status', 'deadlineTimer', 'priority'], 'actions': <String>['changeStatus', 'comment']},
      projectCard: <String, dynamic>{'variant': 'progressCard', 'showFields': <String>['projectName', 'taskCount', 'progress', 'deadline'], 'actions': <String>['openDetails']},
    );
  }

  static MobileUiDesign _templateCompact(MobileUiDesign current) {
    return current.copyWith(
      templateName: 'compactEmployeeApp',
      theme: <String, dynamic>{
        ...current.theme,
        'accent': '#0F766E',
        'background': '#F8FAFC',
        'surface': '#FFFFFF',
        'cardRadius': 16,
        'cardPadding': 12,
        'density': 'compact',
      },
      bottomNav: <String, dynamic>{'style': 'standard', 'tabs': <String>['home', 'tasks', 'projects', 'profile']},
      topNav: <String, dynamic>{'enabled': true, 'style': 'compact', 'density': 'compact', 'showInbox': true, 'showCompanyName': true, 'showUserRole': true, 'showOnlineStatus': true, 'showLogout': false, 'inboxBadge': true, 'showAvatar': false, 'showPresenceGlow': false},
      sections: <Map<String, dynamic>>[
        _section('deadlineTimer', style: 'compact'),
        _section('myOpenTasks', style: 'minimal'),
        _section('onlineStatus', style: 'pill'),
      ],
      taskCard: <String, dynamic>{'variant': 'compactCard', 'showFields': <String>['taskTitle', 'status', 'deadlineTimer'], 'actions': <String>['changeStatus']},
      projectCard: <String, dynamic>{'variant': 'minimalCard', 'showFields': <String>['projectName', 'progress'], 'actions': <String>['openDetails']},
    );
  }

  static MobileUiDesign _templateModern(MobileUiDesign current) {
    return current.copyWith(
      templateName: 'modernCardUi',
      theme: <String, dynamic>{
        ...current.theme,
        'accent': '#7C3AED',
        'background': '#F5F3FF',
        'surface': '#FFFFFF',
        'cardRadius': 28,
        'cardPadding': 18,
        'density': 'comfortable',
      },
      bottomNav: <String, dynamic>{'style': 'floating', 'tabs': <String>['home', 'tasks', 'projects', 'board', 'notifications', 'profile']},
      topNav: <String, dynamic>{'enabled': true, 'style': 'premium', 'density': 'comfortable', 'showInbox': true, 'showCompanyName': true, 'showUserRole': true, 'showOnlineStatus': true, 'showLogout': false, 'inboxBadge': true, 'showAvatar': true, 'showPresenceGlow': true},
      sections: <Map<String, dynamic>>[
        _section('workSummary', style: 'gradient'),
        _section('deadlineTimer', style: 'modern'),
        _section('todayTasks', style: 'modern'),
        _section('myOpenTasks', style: 'modern'),
        _section('projectProgress', style: 'ring'),
      ],
      taskCard: <String, dynamic>{'variant': 'modernCard', 'showFields': <String>['taskTitle', 'projectName', 'priority', 'status', 'deadlineTimer', 'progress'], 'actions': <String>['changeStatus', 'comment', 'uploadFile']},
      projectCard: <String, dynamic>{'variant': 'progressCard', 'showFields': <String>['projectName', 'taskCount', 'progress', 'deadline', 'status'], 'actions': <String>['openDetails']},
    );
  }

  static MobileUiDesign _templateProgress(MobileUiDesign current) {
    return current.copyWith(
      templateName: 'progressFocusUi',
      theme: <String, dynamic>{
        ...current.theme,
        'accent': '#2563EB',
        'background': '#EFF6FF',
        'surface': '#FFFFFF',
        'cardRadius': 22,
        'cardPadding': 16,
        'density': 'comfortable',
      },
      bottomNav: <String, dynamic>{'style': 'floating', 'tabs': <String>['home', 'projects', 'tasks', 'profile']},
      topNav: <String, dynamic>{'enabled': true, 'style': 'glassAdvanced', 'density': 'comfortable', 'showInbox': true, 'showCompanyName': true, 'showUserRole': true, 'showOnlineStatus': true, 'showLogout': false, 'inboxBadge': true, 'showAvatar': true, 'showPresenceGlow': true},
      sections: <Map<String, dynamic>>[
        _section('workSummary', style: 'progressHero'),
        _section('projectProgress', style: 'ring'),
        _section('deadlineTimer', style: 'compact'),
        _section('myOpenTasks', style: 'progressList'),
      ],
      taskCard: <String, dynamic>{'variant': 'progressCard', 'showFields': <String>['taskTitle', 'status', 'deadlineTimer', 'progress'], 'actions': <String>['changeStatus', 'comment']},
      projectCard: <String, dynamic>{'variant': 'progressCard', 'showFields': <String>['projectName', 'taskCount', 'progress', 'deadline', 'team'], 'actions': <String>['openDetails']},
    );
  }

  static MobileUiDesign _templateMinimal(MobileUiDesign current) {
    return current.copyWith(
      templateName: 'minimalFieldUi',
      theme: <String, dynamic>{
        ...current.theme,
        'accent': '#111827',
        'background': '#FAFAFA',
        'surface': '#FFFFFF',
        'cardRadius': 18,
        'cardPadding': 14,
        'density': 'comfortable',
      },
      bottomNav: <String, dynamic>{'style': 'standard', 'tabs': <String>['home', 'tasks', 'projects', 'profile']},
      topNav: <String, dynamic>{'enabled': true, 'style': 'floating', 'density': 'comfortable', 'showInbox': true, 'showCompanyName': true, 'showUserRole': true, 'showOnlineStatus': true, 'showLogout': false, 'inboxBadge': false, 'showAvatar': false, 'showPresenceGlow': false},
      sections: <Map<String, dynamic>>[
        _section('workSummary', style: 'plain'),
        _section('myOpenTasks', style: 'minimal'),
        _section('deadlineTimer', style: 'plain'),
      ],
      taskCard: <String, dynamic>{'variant': 'minimalCard', 'showFields': <String>['taskTitle', 'status'], 'actions': <String>['changeStatus']},
      projectCard: <String, dynamic>{'variant': 'minimalCard', 'showFields': <String>['projectName', 'progress'], 'actions': <String>['openDetails']},
    );
  }

  static Map<String, dynamic> _section(String id, {String style = 'modern', bool visible = true}) {
    return <String, dynamic>{
      'id': id,
      'type': MobileUiDesign.sectionTypes[id] ?? id,
      'title': MobileUiDesign.sectionLabels[id] ?? id,
      'style': style,
      'visible': visible,
    };
  }
}

class _DesignerControls extends StatelessWidget {
  const _DesignerControls({
    required this.design,
    required this.canManage,
    required this.advancedJsonOpen,
    required this.previewJson,
    required this.onDesignChanged,
    required this.onTemplateSelected,
    required this.onToggleAdvanced,
    required this.onCopyJson,
    required this.onImportJson,
    required this.onSaveDraft,
    required this.onPublish,
    required this.publishTarget,
    required this.onPublishTargetChanged,
    required this.saving,
    required this.hasRawOverrides,
    required this.onClearImportedScreens,
  });

  final MobileUiDesign design;
  final bool canManage;
  final bool advancedJsonOpen;
  final String previewJson;
  final ValueChanged<MobileUiDesign> onDesignChanged;
  final ValueChanged<String> onTemplateSelected;
  final VoidCallback onToggleAdvanced;
  final VoidCallback onCopyJson;
  final VoidCallback onImportJson;
  final VoidCallback? onSaveDraft;
  final VoidCallback? onPublish;
  final _PreviewDocTarget publishTarget;
  final ValueChanged<_PreviewDocTarget> onPublishTargetChanged;
  final bool saving;
  final bool hasRawOverrides;
  final VoidCallback onClearImportedScreens;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'No-code Mobile UI Designer',
          subtitle: 'Use templates or imported JSON. Import can apply to screen UI only, all UI, or cosmetic changes only before publish.',
          trailing: StatusBadge(label: MobileUiDesign.templateLabels[design.templateName] ?? design.templateName, color: Colors.indigo),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('template-${design.templateName}-${hasRawOverrides ? 'raw' : 'nocode'}'),
                initialValue: MobileUiDesign.templateNames.contains(design.templateName) ? design.templateName : 'cleanWorkApp',
                decoration: const InputDecoration(labelText: 'Start from template / import'),
                items: [
                  ...MobileUiDesign.templateNames.map((name) => DropdownMenuItem(value: name, child: Text(MobileUiDesign.templateLabels[name] ?? name))),
                  const DropdownMenuItem(value: 'useImportedJson', child: Text('Use imported JSON file')),
                ],
                onChanged: canManage
                    ? (value) {
                        if (value == 'useImportedJson') {
                          onImportJson();
                          return;
                        }
                        onTemplateSelected(value ?? 'cleanWorkApp');
                      }
                    : null,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(onPressed: canManage ? onImportJson : null, icon: const Icon(Icons.upload_file_rounded), label: const Text('Import JSON UI')),
                  OutlinedButton.icon(onPressed: onCopyJson, icon: const Icon(Icons.copy_rounded), label: const Text('Copy generated JSON')),
                  StatusBadge(label: design.compactMode ? 'Compact density' : 'Comfortable density', color: Colors.blueGrey),
                  StatusBadge(label: '${design.bottomTabs.length} mobile tabs', color: Colors.blue),
                  StatusBadge(label: hasRawOverrides ? 'Imported JSON render active' : 'No-code render active', color: hasRawOverrides ? Colors.orange : Colors.green),
                  if (hasRawOverrides)
                    OutlinedButton.icon(
                      onPressed: canManage ? onClearImportedScreens : null,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: const Text('Return to no-code render'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _ApkSupportPanel(design: design),
        const SizedBox(height: 18),
        _ProductionParityPanel(design: design),
        const SizedBox(height: 18),
        _ThemeEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _TopNavEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _BottomNavEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _TaskListEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _ProfileActionsEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _SectionOrderEditor(design: design, canManage: canManage, onChanged: onDesignChanged),
        const SizedBox(height: 18),
        _CardEditor(
          title: 'Task card design',
          subtitle: 'Pick mobile task card variant and fields. The emulator renders the exact selected field behavior.',
          design: design,
          canManage: canManage,
          cardKey: 'taskCard',
          fields: MobileUiConfig.allowedTaskCardFields,
          selectedFields: design.taskFields.toSet(),
          onChanged: onDesignChanged,
        ),
        const SizedBox(height: 18),
        _CardEditor(
          title: 'Project card design',
          subtitle: 'Pick mobile project card variant and fields. The emulator renders the exact selected field behavior.',
          design: design,
          canManage: canManage,
          cardKey: 'projectCard',
          fields: MobileUiConfig.allowedProjectCardFields,
          selectedFields: design.projectFields.toSet(),
          onChanged: onDesignChanged,
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: 'Advanced JSON',
          subtitle: 'This JSON is generated from the designer controls. Imported JSON can be merged safely without changing the navbar unless you choose all UI.',
          trailing: TextButton.icon(onPressed: onToggleAdvanced, icon: Icon(advancedJsonOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded), label: Text(advancedJsonOpen ? 'Hide JSON' : 'Show JSON')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge(label: '${design.visibleHomeCardIds.length} visible home cards', color: Colors.indigo),
                  StatusBadge(label: design.taskCard['variant']?.toString() ?? 'modernCard', color: Colors.deepPurple),
                  StatusBadge(label: 'Preview-safe schema', color: Colors.green),
                ],
              ),
              if (advancedJsonOpen) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 360),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1220),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      previewJson,
                      style: const TextStyle(color: Color(0xFFCBD5E1), fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(onPressed: onCopyJson, icon: const Icon(Icons.copy_rounded), label: const Text('Copy JSON')),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionCard(
          title: 'Draft and publish',
          subtitle: 'Save Draft and Publish now use the selected target. Release writes mobileEmployee. Test writes mobileEmployeeNext, keeping current users safe.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<_PreviewDocTarget>(
                key: ValueKey('publish-target-${publishTarget.name}'),
                initialValue: publishTarget,
                decoration: const InputDecoration(labelText: 'Save / publish target'),
                items: _PreviewDocTarget.values
                    .map((target) => DropdownMenuItem<_PreviewDocTarget>(
                          value: target,
                          child: Text('${target.publishTitle} · ${target.docId}'),
                        ))
                    .toList(),
                onChanged: canManage && !saving ? (value) => onPublishTargetChanged(value ?? _PreviewDocTarget.test) : null,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge(label: 'Config: ${publishTarget.docId}', color: publishTarget == _PreviewDocTarget.test ? Colors.orange : Colors.green),
                  StatusBadge(label: 'Design: ${publishTarget.designDocId}', color: Colors.indigo),
                  StatusBadge(label: 'Draft: ${publishTarget.draftDocId}', color: Colors.blueGrey),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                publishTarget == _PreviewDocTarget.test
                    ? 'Test publish updates only mobileEmployeeNext. Build/install the test APK with --dart-define=SDUI_CONFIG_DOC=mobileEmployeeNext to see it.'
                    : 'Release publish updates mobileEmployee. Current employee APKs will sync this production UI.',
                style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(onPressed: canManage && !saving ? onSaveDraft : null, icon: const Icon(Icons.save_outlined), label: Text('Save ${publishTarget.label} Draft')),
                  FilledButton.icon(
                    onPressed: canManage && !saving ? onPublish : null,
                    icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.publish_rounded),
                    label: Text(saving ? 'Saving...' : 'Publish to ${publishTarget.label}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}


enum _ApkSupportViewMode { current, detailed }

class _ApkSupportPanel extends StatefulWidget {
  const _ApkSupportPanel({required this.design});

  final MobileUiDesign design;

  @override
  State<_ApkSupportPanel> createState() => _ApkSupportPanelState();
}

class _ApkSupportPanelState extends State<_ApkSupportPanel> {
  _ApkSupportViewMode _viewMode = _ApkSupportViewMode.current;

  Future<void> _copyReport(BuildContext context, SupportReport report) async {
    final text = _apkSupportReportText(widget.design, report);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(report.isFullySupported ? 'APK support report copied.' : 'Detailed APK support errors copied for developer.')),
    );
  }

  Future<void> _copyIssue(BuildContext context, SupportIssue issue, int index) async {
    await Clipboard.setData(ClipboardData(text: _apkSupportIssueText(issue, index)));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support issue copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final report = MobileUiSupportRegistry.analyzeDesign(widget.design);
    final ok = report.isFullySupported;
    final detailed = _viewMode == _ApkSupportViewMode.detailed;
    return SectionCard(
      title: 'Employee APK support checker',
      subtitle: detailed
          ? 'Developer mode: exact JSON path, bad value, reason, and fix hint for every issue. Built for copy/paste debugging.'
          : 'Current mode: clean APK readiness summary for this SDUI design, including floating nav, screen overrides, widgets, actions, fields, and variants.',
      trailing: StatusBadge(
        label: ok ? 'APK supported' : '${report.issues.length} unsupported',
        color: ok ? Colors.green : Colors.deepOrange,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ok ? const Color(0xFFEAFBF0) : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: (ok ? Colors.green : Colors.deepOrange).withOpacity(.22)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(label: MobileUiSupportRegistry.apkRendererVersion, color: Colors.indigo),
                StatusBadge(label: '${MobileUiSupportRegistry.supportedWidgetTypes.length} widget types', color: Colors.blue),
                StatusBadge(label: '${MobileUiSupportRegistry.supportedTabs.length} tabs', color: Colors.blueGrey),
                StatusBadge(label: '${MobileUiSupportRegistry.supportedCardVariants.length} variants', color: Colors.purple),
                StatusBadge(label: '${MobileUiSupportRegistry.supportedActions.length} actions', color: Colors.teal),
                StatusBadge(label: 'floating nav + scroll padding', color: Colors.green),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SegmentedButton<_ApkSupportViewMode>(
                segments: const [
                  ButtonSegment(
                    value: _ApkSupportViewMode.current,
                    icon: Icon(Icons.visibility_rounded, size: 18),
                    label: Text('Current view'),
                  ),
                  ButtonSegment(
                    value: _ApkSupportViewMode.detailed,
                    icon: Icon(Icons.bug_report_rounded, size: 18),
                    label: Text('Detailed view'),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (values) => setState(() => _viewMode = values.first),
              ),
              OutlinedButton.icon(
                onPressed: () => _copyReport(context, report),
                icon: const Icon(Icons.copy_rounded),
                label: Text(ok ? 'Copy report' : 'Copy error details'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (ok)
            const Text(
              'This design is fully supported by the current employee APK code. Publishing it will update installed employee APKs through Firestore + SQLite sync.',
              style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
            )
          else if (!detailed)
            _ApkSupportCurrentView(report: report)
          else
            _ApkSupportDetailedView(
              report: report,
              onCopyIssue: (issue, index) => _copyIssue(context, issue, index),
            ),
        ],
      ),
    );
  }
}

class _ApkSupportCurrentView extends StatelessWidget {
  const _ApkSupportCurrentView({required this.report});

  final SupportReport report;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Unsupported JSON was found. These items will not render in the employee APK until we add the matching widget/type/field/action to the mobile renderer code, or change the JSON to a supported value.',
          style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...report.issues.take(8).map((issue) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${issue.path}: ${issue.value} — ${issue.message}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            )),
        if (report.issues.length > 8)
          Text(
            '+${report.issues.length - 8} more unsupported items. Switch to Detailed view or tap Copy error details for the full developer report.',
            style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
          ),
      ],
    );
  }
}

class _ApkSupportDetailedView extends StatelessWidget {
  const _ApkSupportDetailedView({required this.report, required this.onCopyIssue});

  final SupportReport report;
  final void Function(SupportIssue issue, int index) onCopyIssue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${report.issues.length} issue(s) found. Each row tells the developer exactly where the bad config is and what needs to change.',
          style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        ...report.issues.asMap().entries.map((entry) {
          final index = entry.key;
          final issue = entry.value;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.deepOrange.withOpacity(.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.deepOrange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Issue ${index + 1}: ${_apkSupportIssueTitle(issue)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy this issue',
                      onPressed: () => onCopyIssue(issue, index),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ApkSupportDetailLine(label: 'Where', value: issue.path),
                _ApkSupportDetailLine(label: 'Bad value', value: issue.value),
                _ApkSupportDetailLine(label: 'Problem', value: issue.message),
                _ApkSupportDetailLine(label: 'Fix', value: _apkSupportFixHint(issue)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ApkSupportDetailLine extends StatelessWidget {
  const _ApkSupportDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.navy)),
            TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.navy)),
          ],
        ),
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

String _apkSupportReportText(MobileUiDesign design, SupportReport report) {
  final buffer = StringBuffer()
    ..writeln('Employee APK Support Checker Report')
    ..writeln('===================================')
    ..writeln('Renderer: ${MobileUiSupportRegistry.apkRendererVersion}')
    ..writeln('Design enabled: ${design.enabled}')
    ..writeln('Design version: ${design.version}')
    ..writeln('Template: ${design.templateName}')
    ..writeln('Status: ${report.isFullySupported ? 'SUPPORTED' : 'UNSUPPORTED'}')
    ..writeln('Issue count: ${report.issues.length}')
    ..writeln();

  if (report.issues.isEmpty) {
    buffer.writeln('No unsupported widgets, tabs, fields, variants, or actions were found.');
    return buffer.toString();
  }

  for (var i = 0; i < report.issues.length; i++) {
    buffer.writeln(_apkSupportIssueText(report.issues[i], i));
  }
  return buffer.toString();
}

String _apkSupportIssueText(SupportIssue issue, int index) {
  return '''Issue ${index + 1}: ${_apkSupportIssueTitle(issue)}
Where: ${issue.path}
Bad value: ${issue.value}
Problem: ${issue.message}
Fix: ${_apkSupportFixHint(issue)}
''';
}

String _apkSupportIssueTitle(SupportIssue issue) {
  if (issue.path.endsWith('.type') || issue.path.endsWith('sections.type')) return 'Unsupported widget type';
  if (issue.path.endsWith('.screen')) return 'Unsupported screen route';
  if (issue.path.endsWith('.variant')) return 'Unsupported card variant';
  if (issue.path.contains('actions')) return 'Unsupported production action';
  if (issue.path.contains('showFields') || issue.path.contains('fields')) return 'Unsupported field';
  if (issue.path.contains('bottomNav.tabs')) return 'Unsupported bottom tab';
  if (issue.path.contains('topNav.style')) return 'Unsupported top navigation style';
  if (issue.path.contains('bottomNav.style')) return 'Unsupported bottom navigation style';
  return 'Unsupported APK config';
}

String _apkSupportFixHint(SupportIssue issue) {
  final path = issue.path;
  if (path.endsWith('.type') || path.endsWith('sections.type')) {
    return 'Either change this JSON type to one of the APK supported widget types, or add a renderer case for `${issue.value}` in mobile_json_ui_renderer.dart and register it in MobileUiSupportRegistry.supportedWidgetTypes.';
  }
  if (path.endsWith('.screen')) {
    return 'Use an existing APK screen route or add the new screen to MobileUiSupportRegistry.supportedScreens, EmployeeMobileShell tab routing, and the mobile JSON renderer.';
  }
  if (path.endsWith('.variant')) {
    return 'Change the variant to a supported card variant or add `${issue.value}` to supportedCardVariants and implement the visual style in _VariantSurface/_cardVariant.';
  }
  if (path.contains('actions')) {
    return 'Use a supported action name or add `${issue.value}` to MobileUiSupportRegistry.supportedActions and map it in the renderer/action handler.';
  }
  if (path.contains('showFields') || path.contains('fields')) {
    return 'Remove this field from the JSON or add the field to the matching allowed field list and render it in the relevant APK card widget.';
  }
  if (path.contains('bottomNav.tabs')) {
    return 'Use one of the supported APK tabs, or add the tab to allowedBottomTabs, EmployeeMobileShell routing, and the renderer screen map.';
  }
  if (path.contains('topNav.style') || path.contains('bottomNav.style')) {
    return 'Change the nav style to a supported style or add this style to MobileUiSupportRegistry and the floating shell implementation.';
  }
  return 'Update the Firestore JSON to a supported value or add support for this value in the APK renderer and support registry.';
}


class _ProductionParityPanel extends StatelessWidget {
  const _ProductionParityPanel({required this.design});

  final MobileUiDesign design;

  @override
  Widget build(BuildContext context) {
    final taskActions = _stringList(design.taskCard['actions']);
    final profileReady = design.bottomTabs.contains('profile');
    return SectionCard(
      title: 'Production parity and APK edit permissions',
      subtitle: 'The admin emulator uses the same mobile JSON renderer as the employee APK. Preview actions are safe; the APK persists them to Firestore so admin progress stays accurate.',
      trailing: StatusBadge(label: 'Same renderer', color: Colors.green),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          StatusBadge(label: 'Theme editable', color: Colors.indigo),
          StatusBadge(label: 'Screen layout editable', color: Colors.blue),
          StatusBadge(label: 'Navbar editable', color: Colors.blueGrey),
          StatusBadge(label: taskActions.contains('changeStatus') ? 'Task status updatable' : 'Task status hidden', color: taskActions.contains('changeStatus') ? Colors.green : Colors.orange),
          StatusBadge(label: profileReady ? 'Profile updatable in APK' : 'Profile tab hidden', color: profileReady ? Colors.green : Colors.orange),
          StatusBadge(label: 'SQLite + Firestore sync', color: Colors.teal),
        ],
      ),
    );
  }
}

class _ThemeEditor extends StatelessWidget {
  const _ThemeEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Map<String, dynamic>.from(design.theme);
    return SectionCard(
      title: 'Theme and spacing',
      subtitle: 'Control the visual skin used by the emulator and the published employee UI config.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <String>['#2563EB', '#7C3AED', '#0F766E', '#111827', '#F97316', '#DC2626'].map((color) {
              final active = design.accent.toUpperCase() == color.toUpperCase();
              return ChoiceChip(
                selected: active,
                label: Text(color),
                avatar: CircleAvatar(backgroundColor: _hexColor(color), radius: 9),
                onSelected: canManage
                    ? (_) {
                        theme['accent'] = color;
                        onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme)));
                      }
                    : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 760 ? (constraints.maxWidth - 30) / 3 : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Background', value: design.background, enabled: canManage, onChanged: (value) { theme['background'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Surface / card', value: design.surface, enabled: canManage, onChanged: (value) { theme['surface'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Text primary', value: theme['textPrimary']?.toString() ?? '#111827', enabled: canManage, onChanged: (value) { theme['textPrimary'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Text secondary', value: theme['textSecondary']?.toString() ?? '#64748B', enabled: canManage, onChanged: (value) { theme['textSecondary'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Border', value: theme['border']?.toString() ?? '#E2E8F0', enabled: canManage, onChanged: (value) { theme['border'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                  SizedBox(width: fieldWidth, child: _ThemeHexField(label: 'Accent', value: design.accent, enabled: canManage, onChanged: (value) { theme['accent'] = value; onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme))); })),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text('Card radius: ${design.cardRadius}', style: const TextStyle(fontWeight: FontWeight.w900)),
          Slider(
            min: 8,
            max: 36,
            divisions: 14,
            value: design.cardRadius.toDouble(),
            onChanged: canManage
                ? (value) {
                    theme['cardRadius'] = value.round();
                    onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme)));
                  }
                : null,
          ),
          Text('Card padding: ${design.cardPadding}', style: const TextStyle(fontWeight: FontWeight.w900)),
          Slider(
            min: 8,
            max: 28,
            divisions: 10,
            value: design.cardPadding.toDouble(),
            onChanged: canManage
                ? (value) {
                    theme['cardPadding'] = value.round();
                    onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme)));
                  }
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: design.compactMode,
            onChanged: canManage
                ? (value) {
                    theme['density'] = value ? 'compact' : 'comfortable';
                    theme['cardPadding'] = value ? 12 : 16;
                    theme['cardRadius'] = value ? 16 : 24;
                    onChanged(design.copyWith(theme: Map<String, dynamic>.from(theme)));
                  }
                : null,
            title: const Text('Compact density'),
            subtitle: const Text('Makes the employee app tighter for small phones.'),
          ),
        ],
      ),
    );
  }
}


class _ThemeHexField extends StatelessWidget {
  const _ThemeHexField({required this.label, required this.value, required this.enabled, required this.onChanged});

  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: CircleAvatar(radius: 8, backgroundColor: _hexColor(value)),
        ),
        helperText: 'Hex color',
      ),
      onChanged: (raw) {
        final value = raw.trim();
        final normalized = value.startsWith('#') ? value : '#$value';
        final hex = normalized.replaceAll('#', '');
        if (hex.length == 6 || hex.length == 8) onChanged(normalized);
      },
    );
  }
}


class _TopNavEditor extends StatelessWidget {
  const _TopNavEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  bool _flag(Map<String, dynamic> nav, String key, {bool fallback = true}) {
    final value = nav[key];
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final topNav = Map<String, dynamic>.from(design.topNav);
    void update(String key, Object value) {
      final next = Map<String, dynamic>.from(topNav)..[key] = value;
      onChanged(design.copyWith(topNav: next));
    }

    return SectionCard(
      title: 'Advanced top navigation',
      subtitle: 'Server-driven upper navbar: Inbox, workspace identity, role text and live presence capsule are controlled from this JSON.',
      trailing: StatusBadge(label: topNav['style']?.toString() ?? 'glassAdvanced', color: Colors.indigo),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('topNavStyle-${topNav['style']?.toString() ?? 'glassAdvanced'}'),
            initialValue: const ['glassAdvanced', 'premium', 'glass', 'floating', 'compact', 'standard'].contains(topNav['style']?.toString()) ? topNav['style']?.toString() : 'glassAdvanced',
            decoration: const InputDecoration(labelText: 'Top nav style'),
            items: const [
              DropdownMenuItem(value: 'glassAdvanced', child: Text('Glass advanced capsule')),
              DropdownMenuItem(value: 'premium', child: Text('Premium glass capsule')),
              DropdownMenuItem(value: 'glass', child: Text('Simple glass capsule')),
              DropdownMenuItem(value: 'floating', child: Text('Floating clean capsule')),
              DropdownMenuItem(value: 'compact', child: Text('Compact capsule')),
              DropdownMenuItem(value: 'standard', child: Text('Standard')),
            ],
            onChanged: canManage ? (value) => update('style', value ?? 'glassAdvanced') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('topNavDensity-${topNav['density']?.toString() ?? 'comfortable'}'),
            initialValue: topNav['density']?.toString() == 'compact' ? 'compact' : 'comfortable',
            decoration: const InputDecoration(labelText: 'Top nav density'),
            items: const [
              DropdownMenuItem(value: 'comfortable', child: Text('Comfortable')),
              DropdownMenuItem(value: 'compact', child: Text('Compact')),
            ],
            onChanged: canManage ? (value) => update('density', value ?? 'comfortable') : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilterChip(label: const Text('Inbox'), selected: _flag(topNav, 'showInbox'), onSelected: canManage ? (value) => update('showInbox', value) : null),
              FilterChip(label: const Text('Badge'), selected: _flag(topNav, 'inboxBadge'), onSelected: canManage ? (value) => update('inboxBadge', value) : null),
              FilterChip(label: const Text('Company name'), selected: _flag(topNav, 'showCompanyName'), onSelected: canManage ? (value) => update('showCompanyName', value) : null),
              FilterChip(label: const Text('User role'), selected: _flag(topNav, 'showUserRole'), onSelected: canManage ? (value) => update('showUserRole', value) : null),
              FilterChip(label: const Text('Presence'), selected: _flag(topNav, 'showOnlineStatus'), onSelected: canManage ? (value) => update('showOnlineStatus', value) : null),
              FilterChip(label: const Text('Avatar'), selected: _flag(topNav, 'showAvatar'), onSelected: canManage ? (value) => update('showAvatar', value) : null),
              FilterChip(label: const Text('Presence glow'), selected: _flag(topNav, 'showPresenceGlow'), onSelected: canManage ? (value) => update('showPresenceGlow', value) : null),
              FilterChip(label: const Text('Logout in top nav'), selected: _flag(topNav, 'showLogout', fallback: false), onSelected: canManage ? (value) => update('showLogout', value) : null),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'For your current APK flow keep “Logout in top nav” off, because Logout is now inside Profile.',
            style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BottomNavEditor extends StatelessWidget {
  const _BottomNavEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  @override
  Widget build(BuildContext context) {
    final bottomNav = Map<String, dynamic>.from(design.bottomNav);
    final selected = design.bottomTabs.toSet();
    return SectionCard(
      title: 'Bottom navigation',
      subtitle: 'Choose mobile tab order and style. The emulator uses the same tab list.',
      trailing: StatusBadge(label: bottomNav['style']?.toString() ?? 'floating', color: Colors.blueGrey),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('bottomNavStyle-${bottomNav['style']?.toString() ?? 'floating'}'),
            initialValue: const ['floating', 'standard', 'compact'].contains(bottomNav['style']?.toString()) ? bottomNav['style']?.toString() : 'floating',
            decoration: const InputDecoration(labelText: 'Bottom nav style'),
            items: const [
              DropdownMenuItem(value: 'floating', child: Text('Floating rounded nav')),
              DropdownMenuItem(value: 'compact', child: Text('Compact floating nav')),
              DropdownMenuItem(value: 'standard', child: Text('Standard bottom nav')),
            ],
            onChanged: canManage
                ? (value) {
                    bottomNav['style'] = value ?? 'floating';
                    onChanged(design.copyWith(bottomNav: Map<String, dynamic>.from(bottomNav)));
                  }
                : null,
          ),
          const SizedBox(height: 14),
          Text('Active tab order', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...List.generate(design.bottomTabs.length, (index) {
            final tab = design.bottomTabs[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(_tabIcon(tab), size: 18, color: _hexColor(design.accent)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_label(tab), style: const TextStyle(fontWeight: FontWeight.w900))),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: canManage && index > 0
                        ? () {
                            final tabs = design.bottomTabs.toList();
                            final item = tabs.removeAt(index);
                            tabs.insert(index - 1, item);
                            bottomNav['tabs'] = tabs;
                            onChanged(design.copyWith(bottomNav: Map<String, dynamic>.from(bottomNav)));
                          }
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: canManage && index < design.bottomTabs.length - 1
                        ? () {
                            final tabs = design.bottomTabs.toList();
                            final item = tabs.removeAt(index);
                            tabs.insert(index + 1, item);
                            bottomNav['tabs'] = tabs;
                            onChanged(design.copyWith(bottomNav: Map<String, dynamic>.from(bottomNav)));
                          }
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  IconButton(
                    tooltip: 'Remove tab',
                    onPressed: canManage && design.bottomTabs.length > 1
                        ? () {
                            final tabs = design.bottomTabs.where((item) => item != tab).toList();
                            bottomNav['tabs'] = tabs;
                            onChanged(design.copyWith(bottomNav: Map<String, dynamic>.from(bottomNav)));
                          }
                        : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MobileUiConfig.allowedBottomTabs.where((tab) => !selected.contains(tab)).map((tab) {
                return ActionChip(
                  avatar: Icon(_tabIcon(tab), size: 18),
                  label: Text('Add ${_label(tab)}'),
                  onPressed: canManage
                      ? () {
                          final tabs = design.bottomTabs.toList()..add(tab);
                          bottomNav['tabs'] = tabs;
                          onChanged(design.copyWith(bottomNav: Map<String, dynamic>.from(bottomNav)));
                        }
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}


class _TaskListEditor extends StatelessWidget {
  const _TaskListEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  bool _flag(Map<String, dynamic> config, String key, {bool fallback = true}) {
    final value = config[key];
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final config = Map<String, dynamic>.from(design.taskListConfig);
    void update(String key, Object value) {
      final next = Map<String, dynamic>.from(config)..[key] = value;
      onChanged(design.copyWith(taskListConfig: next));
    }

    return SectionCard(
      title: 'Task menu behavior',
      subtitle: 'Every dropdown here is written to Firestore and used by the employee APK task menu.',
      trailing: StatusBadge(label: _flag(config, 'showFloatingTabs') ? 'Floating tabs' : 'Single list', color: Colors.deepPurple),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey("taskDefaultTab-${config['defaultTab']?.toString() ?? 'newArrival'}"),
            initialValue: const ['newArrival', 'completed'].contains(config['defaultTab']?.toString()) ? config['defaultTab']?.toString() : 'newArrival',
            decoration: const InputDecoration(labelText: 'Default task tab'),
            items: const [
              DropdownMenuItem(value: 'newArrival', child: Text('New arrival')),
              DropdownMenuItem(value: 'completed', child: Text('Completed')),
            ],
            onChanged: canManage ? (value) => update('defaultTab', value ?? 'newArrival') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey("completedSort-${config['completedSort']?.toString() ?? 'completedAtDesc'}"),
            initialValue: const ['completedAtDesc', 'updatedAtDesc'].contains(config['completedSort']?.toString()) ? config['completedSort']?.toString() : 'completedAtDesc',
            decoration: const InputDecoration(labelText: 'Completed task sort'),
            items: const [
              DropdownMenuItem(value: 'completedAtDesc', child: Text('Completed date newest first')),
              DropdownMenuItem(value: 'updatedAtDesc', child: Text('Last updated newest first')),
            ],
            onChanged: canManage ? (value) => update('completedSort', value ?? 'completedAtDesc') : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilterChip(label: const Text('Show floating tabs'), selected: _flag(config, 'showFloatingTabs'), onSelected: canManage ? (value) => update('showFloatingTabs', value) : null),
              FilterChip(label: const Text('New arrivals first'), selected: _flag(config, 'newArrivalFirst'), onSelected: canManage ? (value) => update('newArrivalFirst', value) : null),
              FilterChip(label: const Text('Completed tab'), selected: _flag(config, 'showCompletedTab'), onSelected: canManage ? (value) => update('showCompletedTab', value) : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileActionsEditor extends StatelessWidget {
  const _ProfileActionsEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  bool _flag(Map<String, dynamic> config, String key, {bool fallback = true}) {
    final value = config[key];
    if (value is bool) return value;
    if (value is String) return value.trim().toLowerCase() == 'true';
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final actions = Map<String, dynamic>.from(design.profileActions);
    void update(String key, Object value) {
      final next = Map<String, dynamic>.from(actions)..[key] = value;
      onChanged(design.copyWith(profileActions: next));
    }

    return SectionCard(
      title: 'Profile page actions',
      subtitle: 'Control the production Profile logout button from SDUI config.',
      trailing: StatusBadge(label: _flag(actions, 'showLogout') ? 'Logout visible' : 'Logout hidden', color: Colors.redAccent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey("logoutStyle-${actions['logoutStyle']?.toString() ?? 'filledIcon'}"),
            initialValue: const ['filledIcon', 'capsule', 'outlined', 'text'].contains(actions['logoutStyle']?.toString()) ? actions['logoutStyle']?.toString() : 'filledIcon',
            decoration: const InputDecoration(labelText: 'Logout button style'),
            items: const [
              DropdownMenuItem(value: 'filledIcon', child: Text('Same as Edit Profile')),
              DropdownMenuItem(value: 'capsule', child: Text('Capsule')),
              DropdownMenuItem(value: 'outlined', child: Text('Outlined')),
              DropdownMenuItem(value: 'text', child: Text('Text button')),
            ],
            onChanged: canManage ? (value) => update('logoutStyle', value ?? 'filledIcon') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey("logoutPosition-${actions['logoutPosition']?.toString() ?? 'bottom'}"),
            initialValue: const ['bottom', 'profileHeader', 'actionsRow'].contains(actions['logoutPosition']?.toString()) ? actions['logoutPosition']?.toString() : 'bottom',
            decoration: const InputDecoration(labelText: 'Logout position'),
            items: const [
              DropdownMenuItem(value: 'bottom', child: Text('Bottom of Profile')),
              DropdownMenuItem(value: 'profileHeader', child: Text('Profile header')),
              DropdownMenuItem(value: 'actionsRow', child: Text('Action row')),
            ],
            onChanged: canManage ? (value) => update('logoutPosition', value ?? 'bottom') : null,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilterChip(label: const Text('Show logout'), selected: _flag(actions, 'showLogout'), onSelected: canManage ? (value) => update('showLogout', value) : null),
              FilterChip(label: const Text('Set offline before logout'), selected: _flag(actions, 'setOfflineBeforeLogout'), onSelected: canManage ? (value) => update('setOfflineBeforeLogout', value) : null),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionOrderEditor extends StatelessWidget {
  const _SectionOrderEditor({required this.design, required this.canManage, required this.onChanged});

  final MobileUiDesign design;
  final bool canManage;
  final ValueChanged<MobileUiDesign> onChanged;

  @override
  Widget build(BuildContext context) {
    final sections = design.sections.map(Map<String, dynamic>.from).toList();
    final existingIds = sections.map((section) => section['id']?.toString()).toSet();
    return SectionCard(
      title: 'Home sections',
      subtitle: 'Show, hide, and reorder employee Home. The emulator renders this list immediately.',
      trailing: StatusBadge(label: '${design.visibleHomeCardIds.length} active', color: Colors.indigo),
      child: Column(
        children: [
          ...List.generate(sections.length, (index) {
            final section = sections[index];
            final id = section['id']?.toString() ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppTheme.cardAlt, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(_sectionIcon(id), color: _hexColor(design.accent)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(MobileUiDesign.sectionLabels[id] ?? id, style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text('${section['type']} • ${section['style'] ?? 'modern'}', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: section['visible'] != false,
                    onChanged: canManage
                        ? (value) {
                            sections[index] = <String, dynamic>{...section, 'visible': value};
                            onChanged(design.copyWith(sections: sections));
                          }
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: canManage && index > 0
                        ? () {
                            final item = sections.removeAt(index);
                            sections.insert(index - 1, item);
                            onChanged(design.copyWith(sections: sections));
                          }
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: canManage && index < sections.length - 1
                        ? () {
                            final item = sections.removeAt(index);
                            sections.insert(index + 1, item);
                            onChanged(design.copyWith(sections: sections));
                          }
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MobileUiDesign.sectionIds.where((id) => !existingIds.contains(id)).map((id) {
                return ActionChip(
                  avatar: Icon(_sectionIcon(id), size: 18),
                  label: Text('Add ${MobileUiDesign.sectionLabels[id] ?? id}'),
                  onPressed: canManage
                      ? () {
                          final next = sections.toList()..add(_MobileUiDesignerScreenState._section(id));
                          onChanged(design.copyWith(sections: next));
                        }
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardEditor extends StatelessWidget {
  const _CardEditor({
    required this.title,
    required this.subtitle,
    required this.design,
    required this.canManage,
    required this.cardKey,
    required this.fields,
    required this.selectedFields,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final MobileUiDesign design;
  final bool canManage;
  final String cardKey;
  final List<String> fields;
  final Set<String> selectedFields;
  final ValueChanged<MobileUiDesign> onChanged;

  @override
  Widget build(BuildContext context) {
    final card = Map<String, dynamic>.from(cardKey == 'taskCard' ? design.taskCard : design.projectCard);
    return SectionCard(
      title: title,
      subtitle: subtitle,
      trailing: StatusBadge(label: card['variant']?.toString() ?? 'modernCard', color: Colors.deepPurple),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('$cardKey-${card['variant']?.toString() ?? 'modernCard'}'),
            initialValue: MobileUiDesign.cardVariants.contains(card['variant']?.toString()) ? card['variant']!.toString() : 'modernCard',
            decoration: const InputDecoration(labelText: 'Card variant'),
            items: MobileUiDesign.cardVariants.map((variant) => DropdownMenuItem(value: variant, child: Text(_variantLabel(variant)))).toList(),
            onChanged: canManage
                ? (value) {
                    card['variant'] = value ?? 'modernCard';
                    _emit(card);
                  }
                : null,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: fields.map((field) {
              return FilterChip(
                selected: selectedFields.contains(field),
                label: Text(_label(field)),
                onSelected: canManage
                    ? (value) {
                        final copy = selectedFields.toSet();
                        value ? copy.add(field) : copy.remove(field);
                        card['showFields'] = fields.where(copy.contains).toList();
                        _emit(card);
                      }
                    : null,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text('Production actions', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _actionOptions(cardKey).map((action) {
              final selected = _stringList(card['actions']).contains(action);
              return FilterChip(
                selected: selected,
                label: Text(_label(action)),
                onSelected: canManage
                    ? (value) {
                        final current = _stringList(card['actions']).toSet();
                        value ? current.add(action) : current.remove(action);
                        card['actions'] = _actionOptions(cardKey).where(current.contains).toList();
                        _emit(card);
                      }
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _emit(Map<String, dynamic> card) {
    if (cardKey == 'taskCard') {
      onChanged(design.copyWith(taskCard: Map<String, dynamic>.from(card)));
    } else {
      onChanged(design.copyWith(projectCard: Map<String, dynamic>.from(card)));
    }
  }
}

class _PhonePreviewPanel extends StatelessWidget {
  const _PhonePreviewPanel({
    required this.design,
    required this.runtimeConfig,
    required this.previewTab,
    required this.devicePreset,
    required this.previewDocTarget,
    required this.loadingPreviewConfig,
    required this.previewSourceStatus,
    required this.onPreviewTabChanged,
    required this.onDeviceChanged,
    required this.onPreviewDocTargetChanged,
  });

  final MobileUiDesign design;
  final Map<String, dynamic> runtimeConfig;
  final String previewTab;
  final String devicePreset;
  final _PreviewDocTarget previewDocTarget;
  final bool loadingPreviewConfig;
  final String? previewSourceStatus;
  final ValueChanged<String> onPreviewTabChanged;
  final ValueChanged<String> onDeviceChanged;
  final ValueChanged<_PreviewDocTarget> onPreviewDocTargetChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = _previewTabsForRuntimeConfig(runtimeConfig, design);
    final canonicalPreviewTab = _canonicalPreviewRoute(previewTab);
    final safePreviewTab = tabs.contains(canonicalPreviewTab) ? canonicalPreviewTab : (tabs.isEmpty ? 'home' : tabs.first);
    return SectionCard(
      title: 'Real-use emulator preview',
      subtitle: 'Switch between Release and Test docs. The preview reloads from Firestore and renders the selected document.',
      trailing: StatusBadge(label: '${previewDocTarget.label} · ${previewDocTarget.docId}', color: previewDocTarget == _PreviewDocTarget.test ? Colors.deepPurple : Colors.green),
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _PreviewDocTarget.values.map((target) {
              return ChoiceChip(
                selected: previewDocTarget == target,
                label: Text('${target.label} preview'),
                avatar: Icon(target == _PreviewDocTarget.test ? Icons.science_rounded : Icons.verified_rounded, size: 16),
                onSelected: loadingPreviewConfig ? null : (_) => onPreviewDocTargetChanged(target),
              );
            }).toList(),
          ),
          if (previewSourceStatus != null) ...[
            const SizedBox(height: 8),
            Text(
              previewSourceStatus!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
            ),
          ],
          if (loadingPreviewConfig) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _DevicePreset.values.map((preset) {
              return ChoiceChip(
                selected: devicePreset == preset.key,
                label: Text(preset.label),
                onSelected: (_) => onDeviceChanged(preset.key),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs.map((tab) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: safePreviewTab == tab,
                    label: Text(_label(tab)),
                    avatar: Icon(_tabIcon(tab), size: 16),
                    onSelected: (_) => onPreviewTabChanged(tab),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final preset = _DevicePreset.byKey(devicePreset);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Center(
                    child: _PhoneFrame(
                      design: design,
                      runtimeConfig: runtimeConfig,
                      previewTab: safePreviewTab,
                      devicePreset: preset,
                      onPreviewTabChanged: onPreviewTabChanged,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}


class _PreviewRuntimeLogOverlay extends StatelessWidget {
  const _PreviewRuntimeLogOverlay({required this.logs, required this.onClear});

  final List<String> logs;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final visibleLogs = logs.reversed.take(5).toList().reversed.toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal_rounded, color: Colors.white, size: 15),
                const SizedBox(width: 6),
                const Expanded(child: Text('Preview live logs', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900))),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Clear', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            for (final log in visibleLogs)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(log, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }
}

class _DevicePreset {
  const _DevicePreset({required this.key, required this.label, required this.width, required this.height, required this.radius});

  final String key;
  final String label;
  final double width;
  final double height;
  final double radius;

  static const values = <_DevicePreset>[
    _DevicePreset(key: 'compactAndroid', label: 'Compact Android', width: 360, height: 640, radius: 30),
    _DevicePreset(key: 'motoG', label: 'Moto G / Budget', width: 360, height: 760, radius: 32),
    _DevicePreset(key: 'galaxyS24', label: 'Galaxy S24', width: 360, height: 780, radius: 36),
    _DevicePreset(key: 'pixel8', label: 'Pixel 8', width: 390, height: 760, radius: 38),
    _DevicePreset(key: 'pixel8Pro', label: 'Pixel 8 Pro', width: 430, height: 860, radius: 42),
    _DevicePreset(key: 's24Ultra', label: 'S24 Ultra', width: 412, height: 915, radius: 44),
    _DevicePreset(key: 'iphoneSE', label: 'iPhone SE', width: 375, height: 667, radius: 30),
    _DevicePreset(key: 'iphone15', label: 'iPhone 15', width: 393, height: 852, radius: 44),
    _DevicePreset(key: 'iphone15ProMax', label: '15 Pro Max', width: 430, height: 932, radius: 48),
    _DevicePreset(key: 'pixelFold', label: 'Pixel Fold', width: 673, height: 841, radius: 34),
    _DevicePreset(key: 'ipadMini', label: 'iPad Mini', width: 744, height: 1024, radius: 28),
    _DevicePreset(key: 'androidTablet', label: 'Android Tablet', width: 800, height: 1100, radius: 26),
  ];

  static _DevicePreset byKey(String key) {
    return values.firstWhere((preset) => preset.key == key, orElse: () => values.first);
  }
}

class _PhoneFrame extends StatefulWidget {
  const _PhoneFrame({
    required this.design,
    required this.runtimeConfig,
    required this.previewTab,
    required this.devicePreset,
    required this.onPreviewTabChanged,
  });

  final MobileUiDesign design;
  final Map<String, dynamic> runtimeConfig;
  final String previewTab;
  final _DevicePreset devicePreset;
  final ValueChanged<String> onPreviewTabChanged;

  @override
  State<_PhoneFrame> createState() => _PhoneFrameState();
}

class _PhoneFrameState extends State<_PhoneFrame> {
  bool _topPaddingCollapsed = false;
  bool _sideMenuOpen = false;
  String _previewSearchQuery = '';
  final List<String> _previewLogs = <String>[];

  @override
  void initState() {
    super.initState();
    _previewLogs.add('[session] preview_started route=${_canonicalPreviewRoute(widget.previewTab)}');
  }

  void _appendPreviewLog(String message) {
    if (!mounted) return;
    final now = DateTime.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _previewLogs.add('[$stamp] $message');
      if (_previewLogs.length > 80) _previewLogs.removeRange(0, _previewLogs.length - 80);
    });
  }

  void _resetPreviewLogs(String reason, {bool updateState = true}) {
    if (!mounted) return;
    
    if (updateState) {
      setState(() {
        _previewLogs
          ..clear()
          ..add('[session] $reason');
      });
    } else {
      _previewLogs
        ..clear()
        ..add('[session] $reason');
    }
  }

  @override
  void didUpdateWidget(covariant _PhoneFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewTab != widget.previewTab ||
        oldWidget.devicePreset.key != widget.devicePreset.key ||
        oldWidget.runtimeConfig['version'] != widget.runtimeConfig['version'] ||
        oldWidget.runtimeConfig['configId'] != widget.runtimeConfig['configId']) {
      
      _topPaddingCollapsed = false;
      _sideMenuOpen = false;
      _previewSearchQuery = '';
      
      _resetPreviewLogs('preview_reset route=${_canonicalPreviewRoute(widget.previewTab)}', updateState: false);
    }
  }

  @override
  void dispose() {
    _previewLogs.clear();
    super.dispose();
  }

  bool _handlePreviewScroll(ScrollNotification notification, double trigger) {
    final shouldCollapse = notification.metrics.pixels > trigger;
    if (shouldCollapse != _topPaddingCollapsed && mounted) {
      setState(() => _topPaddingCollapsed = shouldCollapse);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final design = widget.design;
    final runtimeConfig = widget.runtimeConfig;
    final previewTab = _canonicalPreviewRoute(widget.previewTab);
    final devicePreset = widget.devicePreset;
    void onPreviewTabChanged(String tab) {
      final route = _canonicalPreviewRoute(tab);
      _appendPreviewLog('route_tap raw=$tab canonical=$route');
      widget.onPreviewTabChanged(route);
    }
    final runtime = runtimeConfig.isEmpty
        ? <String, dynamic>{
            ...design.toMobileConfig().toMap(updatedBy: design.updatedBy ?? 'admin_preview'),
            'screenOverrides': design.screenOverrides,
          }
        : runtimeConfig;
    final theme = _previewThemeFromRuntimeConfig(runtime, design);
    final accent = _hexColor(theme['accent']?.toString() ?? design.accent);
    final background = _hexColor(theme['background']?.toString() ?? design.background);
    final surface = _hexColor(theme['surface']?.toString() ?? design.surface);
    final json = _previewJsonForTab(design, previewTab, runtimeConfig: runtime);
    final layout = _jsonMap(runtime['layoutConfig']) ?? const <String, dynamic>{};
    final designSystem = _jsonMap(runtime['designSystem']) ?? const <String, dynamic>{};
    final edgeConfig = _jsonMap(runtime['edgeToEdgeConfig']) ?? const <String, dynamic>{};
    final topNav = _jsonMap(runtime['topNav']) ?? _jsonMap(runtime['floatingTopNav']) ?? const <String, dynamic>{};
    final bottomNav = _jsonMap(runtime['bottomNav']) ?? _jsonMap(runtime['floatingBottomNav']) ?? const <String, dynamic>{};
    final navigation = _jsonMap(runtime['navigationConfig']) ?? const <String, dynamic>{};
    final edgeToEdgePreview =
        (_jsonBool(edgeConfig['enabled']) ?? false) ||
        (_jsonBool(layout['edgeToEdge']) ?? false) ||
        (_jsonBool(layout['systemBarsTransparent']) ?? false) ||
        (_jsonBool(layout['drawBehindSystemBars']) ?? false) ||
        (_jsonBool(layout['contentDrawsBehindSystemBars']) ?? false) ||
        (_jsonBool(navigation['edgeToEdge']) ?? false) ||
        (_jsonBool(navigation['transparentSystemBars']) ?? false) ||
        (_jsonBool(navigation['drawBehindSystemBars']) ?? false) ||
        (_jsonBool(designSystem['contentUnderSystemBars']) ?? false) ||
        (designSystem['systemBarPolicy']?.toString().toLowerCase().contains('transparent') == true) ||
        (layout['edgeToEdgeMode']?.toString().isNotEmpty == true) ||
        (navigation['edgeToEdgeMode']?.toString().isNotEmpty == true) ||
        (layout['systemBarMode']?.toString() == 'edgeToEdgeTransparent') ||
        (navigation['systemBarMode']?.toString() == 'edgeToEdgeTransparent');
    final showStatusBar = !edgeToEdgePreview && (_jsonBool(layout['nativeStatusBar']) ?? _jsonBool(layout['safeAreaTop']) ?? true);
    final showSystemIconsOverlay = edgeToEdgePreview && (_jsonBool(layout['showSystemBarIcons']) ?? true);
    final showTopNav = _jsonBool(topNav['enabled']) ?? true;
    final showBottomNav = _jsonBool(bottomNav['enabled']) ?? true;
    final isLandscapePreview = devicePreset.width > devicePreset.height;
    final forceFloatingReferenceNav = (_jsonBool(navigation['forceFloatingReferenceNav']) ?? true) ||
        (bottomNav['variant']?.toString().contains('wireframeReference') == true) ||
        (topNav['variant']?.toString().contains('wireframeReference') == true);
    final useAdaptiveRail = !forceFloatingReferenceNav &&
        ((_jsonBool(navigation['adaptiveNavigation']) ?? false) &&
            (_jsonBool(navigation['adaptiveNavRail']) ?? false) &&
            (devicePreset.width >= 600 || (isLandscapePreview && devicePreset.width >= 520)));
    final showBottomDock = showBottomNav && !useAdaptiveRail;
    final railWidth = devicePreset.width >= 840 ? 184.0 : 80.0;
    final topInsetMode = (topNav['contentInset'] ?? '').toString().toLowerCase().trim();
    final bottomInsetMode = (bottomNav['contentInset'] ?? '').toString().toLowerCase().trim();
    final contentPassUnderTopNav = (_jsonBool(layout['contentPassUnderTopNav']) ?? false) ||
        (_jsonBool(topNav['overlayContent']) ?? false) ||
        topInsetMode == 'passunder' ||
        topInsetMode == 'pass_under' ||
        topInsetMode == 'passthrough';
    final contentPassUnderBottomNav = (_jsonBool(layout['contentPassUnderBottomNav']) ?? false) ||
        (_jsonBool(bottomNav['overlayContent']) ?? false) ||
        bottomInsetMode == 'passunder' ||
        bottomInsetMode == 'pass_under' ||
        bottomInsetMode == 'passthrough';
    final previewTopNavHeight = _jsonDouble(topNav, const ['height'], fallback: 56).clamp(46, 72).toDouble();
    final ratioLayout = _jsonMap(layout['ratioBasedLayout']) ?? _jsonMap(runtime['ratioBasedLayout']) ?? const <String, dynamic>{};
    final previewShortestSide = devicePreset.width < devicePreset.height ? devicePreset.width : devicePreset.height;
    final previewLongestSide = devicePreset.width > devicePreset.height ? devicePreset.width : devicePreset.height;
    final previewAspectRatio = previewShortestSide <= 0 ? 1.0 : previewLongestSide / previewShortestSide;
    final previewIsLandscape = devicePreset.width > devicePreset.height;
    final previewIsTablet = devicePreset.width >= 600;
    final previewIsVeryTallPhone = !previewIsLandscape && !previewIsTablet && previewAspectRatio >= 2.12;
    final previewIsTallPhone = !previewIsLandscape && !previewIsTablet && previewAspectRatio >= 1.95;
    final previewIsShortPhone = !previewIsLandscape && !previewIsTablet && previewAspectRatio < 1.78;
    final previewRatioLayout = _jsonBool(ratioLayout['enabled']) ?? true;
    final basePreviewTopMargin = _jsonDouble(topNav, const ['marginTop'], fallback: 8);
    final previewTopNavMarginTop = (previewRatioLayout && !previewIsLandscape && !previewIsTablet
            ? (devicePreset.height * (previewIsShortPhone ? 0.006 : previewIsVeryTallPhone ? 0.010 : 0.008))
            : basePreviewTopMargin)
        .clamp(5, 12)
        .toDouble();
    final systemTopInset = edgeToEdgePreview ? 24.0 : (showStatusBar ? 32.0 : 0.0);
    final ratioTopProtectionGap = (previewRatioLayout && !previewIsLandscape && !previewIsTablet
            ? (devicePreset.height * (previewIsShortPhone ? 0.016 : previewIsVeryTallPhone ? 0.030 : previewIsTallPhone ? 0.026 : 0.022))
            : 12.0)
        .clamp(12, previewIsVeryTallPhone ? 34 : 28)
        .toDouble();
    final topOverlayReserve = showTopNav ? systemTopInset + previewTopNavHeight + previewTopNavMarginTop + ratioTopProtectionGap : 0.0;
    final protectedTopGap = _jsonDouble(layout, const ['topOverlaySafeGap'], fallback: 0).clamp(0, 40).toDouble();
    final protectedBottomGap = _jsonDouble(layout, const ['bottomOverlaySafeGap'], fallback: 0).clamp(0, 60).toDouble();
    final scrollAware = _jsonMap(runtime['scrollAwareTopPadding']) ?? const <String, dynamic>{};
    final edgeTopProtection = _jsonMap(edgeConfig['topProtection']) ?? const <String, dynamic>{};
    final responsiveNav = _jsonMap(runtime['responsiveNav']) ?? const <String, dynamic>{};
    final overlapProtection = _jsonMap(responsiveNav['overlapProtection']) ?? const <String, dynamic>{};
    final scrollAwareTopPadding = (_jsonBool(scrollAware['enabled']) ?? false) ||
        (_jsonBool(edgeTopProtection['enabled']) ?? false) ||
        (_jsonBool(navigation['scrollAwareTopPadding']) ?? false) ||
        (_jsonBool(layout['adaptiveTopPadding']) ?? false) ||
        (layout['topPaddingBehavior']?.toString().toLowerCase().contains('scrollaware') == true) ||
        (navigation['initialTopPaddingMode']?.toString().toLowerCase().contains('autountilfirstscroll') == true);
    final explicitInitialTopPaddingValue = layout['initialContentPaddingTop'] ??
        edgeTopProtection['initialTopPadding'] ??
        edgeTopProtection['initialContentPaddingTop'] ??
        topNav['initialContentProtectionPadding'] ??
        overlapProtection['initialTopPadding'] ??
        overlapProtection['initialContentPaddingTop'] ??
        scrollAware['fallbackInitialPaddingTop'] ??
        scrollAware['initialTopPadding'] ??
        scrollAware['initialContentPaddingTop'];
    final hasExplicitInitialTopPadding = explicitInitialTopPaddingValue != null;
    final configuredInitialTopPadding = _jsonValueDouble(explicitInitialTopPaddingValue, fallback: topOverlayReserve);
    final initialProtectionExtra = _jsonDouble(
      layout,
      const ['initialContentProtectionExtra'],
      fallback: _jsonDouble(
        edgeTopProtection,
        const ['initialContentProtectionExtra'],
        fallback: _jsonDouble(
          topNav,
          const ['initialContentProtectionExtra'],
          fallback: _jsonDouble(
            overlapProtection,
            const ['initialContentProtectionExtra'],
            fallback: _jsonDouble(scrollAware, const ['initialContentProtectionExtra'], fallback: hasExplicitInitialTopPadding ? 0 : 18),
          ),
        ),
      ),
    );
    final ratioInitialExtra = hasExplicitInitialTopPadding
        ? 0.0
        : ((previewRatioLayout && !previewIsLandscape && !previewIsTablet)
            ? ((previewAspectRatio - (_jsonDouble(ratioLayout, const ['startAspectRatio'], fallback: 1.78))) *
                    _jsonDouble(ratioLayout, const ['topProtectionAspectFactor'], fallback: 34))
                .clamp(
                  _jsonDouble(ratioLayout, const ['minInitialTopProtectionExtra'], fallback: 0),
                  _jsonDouble(ratioLayout, const ['maxInitialTopProtectionExtra'], fallback: previewIsVeryTallPhone ? 22 : 16),
                )
                .toDouble()
            : 0.0);
    final runtimeSafeInitialTopPadding = topOverlayReserve + initialProtectionExtra + ratioInitialExtra;
    final maxInitialTopPadding = _jsonDouble(ratioLayout, const ['maxInitialTopPadding'], fallback: previewIsVeryTallPhone ? 176 : 156);
    final initialTopPadding = (hasExplicitInitialTopPadding
            ? configuredInitialTopPadding + initialProtectionExtra
            : (configuredInitialTopPadding >= runtimeSafeInitialTopPadding ? configuredInitialTopPadding : runtimeSafeInitialTopPadding))
        .clamp(0, maxInitialTopPadding)
        .toDouble();
    final scrolledTopPadding = _jsonDouble(
      layout,
      const ['scrolledContentPaddingTop'],
      fallback: _jsonDouble(
        edgeTopProtection,
        const ['scrolledTopPadding', 'scrolledContentPaddingTop'],
        fallback: _jsonDouble(
          topNav,
          const ['scrolledContentProtectionPadding'],
          fallback: _jsonDouble(overlapProtection, const ['scrolledTopPadding', 'scrolledContentPaddingTop'], fallback: _jsonDouble(scrollAware, const ['scrolledPaddingTop'], fallback: 0)),
        ),
      ),
    ).clamp(0, 80).toDouble();
    final collapseTrigger = _jsonDouble(
      layout,
      const ['topPaddingCollapseThresholdPx'],
      fallback: _jsonDouble(
        edgeTopProtection,
        const ['topDetectionThresholdPx'],
        fallback: _jsonDouble(
          topNav,
          const ['protectionCollapseThresholdPx'],
          fallback: _jsonDouble(overlapProtection, const ['topDetectionThresholdPx', 'topPaddingCollapseThresholdPx'], fallback: _jsonDouble(scrollAware, const ['collapseTriggerOffset'], fallback: 8)),
        ),
      ),
    ).clamp(0, 80).toDouble();
    final previewTopPadding = contentPassUnderTopNav && showTopNav
        ? (scrollAwareTopPadding ? (_topPaddingCollapsed ? scrolledTopPadding : initialTopPadding) : protectedTopGap)
        : topOverlayReserve;

    return Container(
      width: devicePreset.width,
      height: devicePreset.height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(devicePreset.radius + 10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 40, offset: const Offset(0, 22))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(devicePreset.radius),
        child: Container(
          color: background,
          child: Stack(
            children: [
              Positioned.fill(
                left: useAdaptiveRail ? railWidth : 0,
                child: Column(
                  children: [
                    if (showStatusBar) _PreviewStatusBar(accent: accent),
                    Expanded(
                      child: AnimatedPadding(
                        duration: Duration(milliseconds: _jsonDouble(layout, const ['topPaddingAnimationMs'], fallback: 180).round().clamp(0, 800)),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.only(
                          top: previewTopPadding,
                          bottom: contentPassUnderBottomNav && showBottomDock ? protectedBottomGap : (showBottomDock ? 78 : 0),
                        ),
                        child: NotificationListener<ScrollNotification>(
                          onNotification: scrollAwareTopPadding ? (notification) => _handlePreviewScroll(notification, collapseTrigger) : null,
                          child: previewTab == 'taskTimeline'
                              ? TaskTimelineScreen(
                                  key: const ValueKey<String>('admin-preview-hardcoded-taskTimeline'),
                                  onPreviewLog: _appendPreviewLog,
                                )
                              : MobileJsonUiRenderer(
                                  key: ValueKey<String>('admin-preview-$previewTab'),
                                  json: json,
                                  previewMode: true,
                                  runtimeSearchQuery: '',
                                  suppressPageSearchBars: false,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (showSystemIconsOverlay)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(child: _PreviewStatusBar(accent: accent)),
                ),
              if (useAdaptiveRail)
                Positioned(
                  left: 0,
                  top: systemTopInset,
                  bottom: 0,
                  child: _RuntimePreviewNavigationRail(
                    config: bottomNav,
                    runtimeConfig: runtime,
                    activeTab: previewTab,
                    accent: accent,
                    surface: surface,
                    width: railWidth,
                    onTabChanged: onPreviewTabChanged,
                  ),
                ),
              if (showTopNav)
                Positioned(
                  left: useAdaptiveRail ? railWidth : 0,
                  right: 0,
                  top: systemTopInset,
                  child: _RuntimePreviewTopNav(
                    config: topNav,
                    runtimeConfig: runtime,
                    activeTab: previewTab,
                    accent: accent,
                    surface: surface,
                    searchQuery: _previewSearchQuery,
                    onSearchChanged: (value) => setState(() => _previewSearchQuery = value),
                    onSearchSubmitted: (_) {},
                    onSearchClear: () => setState(() => _previewSearchQuery = ''),
                    onInbox: () => onPreviewTabChanged('notifications'),
                    onMenu: () {
                      _appendPreviewLog('side_menu_open route=$previewTab');
                      setState(() => _sideMenuOpen = true);
                    },
                    drawerOpen: _sideMenuOpen,
                  ),
                ),
              if (_previewSearchQuery.trim().isNotEmpty)
                Positioned(
                  left: (useAdaptiveRail ? railWidth : 0) + 18,
                  right: 18,
                  top: systemTopInset + previewTopPadding + 8,
                  child: _RuntimePreviewUniversalSearchResults(
                    query: _previewSearchQuery,
                    accent: accent,
                    onClose: () => setState(() => _previewSearchQuery = ''),
                    onTabChanged: (tab) {
                      setState(() => _previewSearchQuery = '');
                      onPreviewTabChanged(tab);
                    },
                  ),
                ),
              if (showBottomDock)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _RuntimePreviewBottomNav(
                    config: bottomNav,
                    runtimeConfig: runtime,
                    activeTab: previewTab,
                    accent: accent,
                    surface: surface,
                    onTabChanged: onPreviewTabChanged,
                  ),
                ),
              if (_previewLogs.isNotEmpty)
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: showBottomDock ? 88 : 14,
                  child: _PreviewRuntimeLogOverlay(
                    logs: _previewLogs,
                    onClear: () => setState(_previewLogs.clear),
                  ),
                ),
              if (_sideMenuOpen)
                Positioned.fill(
                  child: _RuntimePreviewSideMenuOverlay(
                    runtimeConfig: runtime,
                    activeTab: previewTab,
                    accent: accent,
                    surface: surface,
                    activeScreenJson: json,
                    onClose: () {
                      _appendPreviewLog('side_menu_close route=$previewTab');
                      setState(() => _sideMenuOpen = false);
                    },
                    onTabChanged: (tab) {
                      final route = _canonicalPreviewRoute(tab);
                      _appendPreviewLog('side_menu_route_tap raw=$tab canonical=$route');
                      setState(() => _sideMenuOpen = false);
                      onPreviewTabChanged(route);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _canonicalPreviewRoute(String raw) {
  return MobileUiSupportRegistry.canonicalScreen(raw);
}

List<String> _previewTabsForRuntimeConfig(Map<String, dynamic> runtimeConfig, MobileUiDesign design) {
  final bottomNav = _jsonMap(runtimeConfig['bottomNav']) ?? const <String, dynamic>{};
  final registry = _jsonMap(runtimeConfig['screenRegistry']) ?? const <String, dynamic>{};
  final screenOverrides = _jsonMap(runtimeConfig['screenOverrides']) ?? const <String, dynamic>{};
  final screenConfigs = _jsonMap(runtimeConfig['screenConfigs']) ?? const <String, dynamic>{};
  final candidates = <String>[
    ..._jsonStringList(bottomNav['tabs']),
    ..._jsonStringList(runtimeConfig['bottomTabs']),
    ..._jsonStringList(registry['activeBottomTabs']),
    ..._jsonStringList(registry['activeTabs']),
    ..._jsonStringList(registry['screenOrder']),
    ..._jsonStringList(registry['nestedScreens']),
    ...design.bottomTabs,
    ...screenConfigs.keys,
    ...screenOverrides.keys,
  ];
  final seen = <String>{};
  final tabs = candidates
      .map((tab) => MobileUiSupportRegistry.canonicalScreen(tab))
      .where((tab) => MobileUiSupportRegistry.supportedScreens.contains(tab))
      .where(seen.add)
      .toList();
  if (tabs.isEmpty) return const <String>['home', 'tasks', 'taskTimeline', 'projects', 'board', 'profile'];
  if (!tabs.contains('home')) tabs.insert(0, 'home');
  if (!tabs.contains('taskTimeline')) {
    final taskIndex = tabs.indexOf('tasks');
    tabs.insert(taskIndex >= 0 ? taskIndex + 1 : tabs.length, 'taskTimeline');
  }
  return tabs;
}

Map<String, dynamic> _previewThemeFromRuntimeConfig(Map<String, dynamic> runtimeConfig, MobileUiDesign design) {
  final designSystem = _jsonMap(runtimeConfig['designSystem']) ?? const <String, dynamic>{};
  final theme = _jsonMap(runtimeConfig['theme']) ?? const <String, dynamic>{};
  final layout = _jsonMap(runtimeConfig['layoutConfig']) ?? const <String, dynamic>{};
  return <String, dynamic>{
    ...theme,
    'mode': theme['mode'] ?? 'light',
    'background': layout['background'] ?? designSystem['surface'] ?? theme['background'] ?? design.background,
    'surface': designSystem['card'] ?? theme['surface'] ?? design.surface,
    'surfaceAlt': designSystem['cardAlt'] ?? theme['surfaceAlt'] ?? '#EEF2EA',
    'accent': designSystem['accent'] ?? theme['accent'] ?? design.accent,
    'accentDark': designSystem['accentDark'] ?? theme['accentDark'] ?? designSystem['accent'] ?? design.accent,
    'textPrimary': designSystem['textPrimary'] ?? theme['textPrimary'] ?? '#0F140F',
    'textSecondary': designSystem['textSecondary'] ?? theme['textSecondary'] ?? '#5F675E',
    'textMuted': designSystem['textMuted'] ?? theme['textMuted'] ?? '#8B9288',
    'border': designSystem['border'] ?? theme['border'] ?? '#D8DED4',
    'cardRadius': designSystem['radiusLarge'] ?? theme['cardRadius'] ?? 24,
    'cardPadding': layout['horizontalPadding'] ?? theme['cardPadding'] ?? 16,
    'density': theme['density'] ?? (design.compactMode ? 'compact' : 'comfortable'),
  };
}

Map<String, dynamic> _runtimeScreenJsonForTab(Map<String, dynamic> runtimeConfig, MobileUiDesign design, String tab) {
  final screenOverrides = _jsonMap(runtimeConfig['screenOverrides']) ?? const <String, dynamic>{};
  final screenConfigs = _jsonMap(runtimeConfig['screenConfigs']) ?? const <String, dynamic>{};
  final override = _jsonMap(screenOverrides[tab]);
  final screenConfig = _jsonMap(screenConfigs[tab]) ?? const <String, dynamic>{};
  final theme = _previewThemeFromRuntimeConfig(runtimeConfig, design);

  if (override != null && override.isNotEmpty) {
    final localTheme = _jsonMap(override['theme']) ?? const <String, dynamic>{};
    final type = override['type']?.toString().trim().isNotEmpty == true
        ? override['type'].toString()
        : _runtimeTypeFromLayout(override['layout'] ?? screenConfig['layout'] ?? tab);
    return <String, dynamic>{
      ...override,
      'screen': tab,
      'type': type,
      'theme': <String, dynamic>{...theme, ...localTheme},
      'layoutConfig': runtimeConfig['layoutConfig'],
      'rendererCompatibility': runtimeConfig['rendererCompatibility'],
      'hideTitle': override['hideTitle'] ?? false,
    };
  }

  final runtimeScreen = MobileUiSupportRegistry.canonicalScreen(runtimeConfig['screen']);
  final isDirectScreen = runtimeScreen == tab &&
      (runtimeConfig.containsKey('type') || runtimeConfig.containsKey('sections') || runtimeConfig.containsKey('items') || runtimeConfig.containsKey('children'));
  if (isDirectScreen) {
    return <String, dynamic>{
      ...runtimeConfig,
      'screen': tab,
      'theme': theme,
      'hideTitle': runtimeConfig['hideTitle'] ?? false,
    };
  }

  if (tab == 'taskTimeline') {
    return <String, dynamic>{
      'screen': 'taskTimeline',
      'type': 'taskProgressTimeline',
      'variant': 'deliveryAppUIKitTimeline',
      'taskTimelineStyle': 'deliveryAppUIKitTimeline',
      'deliveryUIKitTimeline': true,
      'useDeliveryUIKitTimeline': true,
      'exactReferenceTimeline': false,
      'forceReferenceTimeline': false,
      'forceReferenceDeliveryUIKit': false,
      'liveDataMode': true,
      'title': 'Task Timeline',
      'appTitle': 'Task Timeline',
      'subtitle': '',
      'showScreenHeader': true,
      'theme': theme,
      'layoutConfig': runtimeConfig['layoutConfig'],
      'rendererCompatibility': runtimeConfig['rendererCompatibility'],
      'showReferenceFallbackWhenEmpty': false,
      'referenceFallbackWhenEmpty': false,
      'timelineTaskLimit': 6,
      'showTaskProgressCard': true,
      'showTaskTimelineBars': true,
      'showAgendaList': false,
      'showDateStrip': false,
      'axisStartDay': 0,
      'todayAxisIndex': 4,
      'referenceProgress': 0,
      'timelineVisualConfig': <String, dynamic>{
        'enabled': true,
        'variant': 'deliveryAppUIKitTimeline',
        'taskTimelineStyle': 'deliveryAppUIKitTimeline',
        'deliveryUIKitTimeline': true,
        'useDeliveryUIKitTimeline': true,
        'exactReferenceTimeline': false,
        'forceReferenceTimeline': false,
        'forceReferenceDeliveryUIKit': false,
        'liveDataMode': true,
        'taskTimelineActive': true,
        'showTaskProgressCard': true,
        'showTaskTimelineBars': true,
        'showAgendaList': false,
        'showDateStrip': false,
        'axisStartDay': 0,
        'todayAxisIndex': 4,
        'referenceProgress': 0,
        'timelineTaskLimit': 6,
        'showReferenceFallbackWhenEmpty': false,
      },
    };
  }

  return const <String, dynamic>{};
}

String _runtimeTypeFromLayout(dynamic rawLayout) {
  final value = rawLayout?.toString().trim() ?? '';
  final compact = value.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  return switch (compact) {
    'dashboard' || 'dashboardprojectfeedwireframe' || 'projectmanagementdashboard' => 'sectionList',
    'projectlist' || 'projectfeedwireframe' || 'searchableprojectlist' => 'projectPage',
    'tasklist' || 'taskfeedwireframe' || 'statustimelinelist' => 'taskPage',
    'kanbanboard' => 'kanbanBoard',
    'notificationlist' => 'notificationList',
    'profile' || 'profilesettings' => 'profileSummary',
    'meetinglist' => 'meetingPage',
    'taskdetail' || 'taskdetailwireframe' => 'taskDetails',
    'projectdetail' => 'projectDetails',
    'tasktimeline' || 'taskprogresstimeline' || 'productivetasktimeline' => 'taskProgressTimeline',
    'timeline' || 'timelinemilestones' => 'progressTimeline',
    'files' || 'filesdocuments' => 'filesDocuments',
    'calendar' || 'calendardeadlines' || 'calendarlabelsections' || 'calendarfiltersections' || 'calendarlabelfiltersections' || 'calendarthinsquirclelabels' || 'deadlinefirstthinsquirclelabeledcalendar' => 'calendarView',
    _ => MobileUiSupportRegistry.canonicalScreen(value),
  };
}

Map<String, dynamic> _previewJsonForTab(
  MobileUiDesign design,
  String tab, {
  Map<String, dynamic>? runtimeConfig,
}) {
  final runtime = runtimeConfig ?? const <String, dynamic>{};
  if (runtime.isNotEmpty) {
    final runtimeScreen = _runtimeScreenJsonForTab(runtime, design, tab);
    if (runtimeScreen.isNotEmpty) return runtimeScreen;
  }

  final override = design.screenOverrides[tab];
  if (override != null) {
    return <String, dynamic>{
      'screen': tab,
      '_strictJsonOnly': true,
      if (!override.containsKey('theme')) 'theme': _themeFromDesignForPreview(design),
      ...override,
    };
  }

  final taskCard = <String, dynamic>{
    ...design.taskCard,
    'variant': design.taskCard['variant']?.toString() ?? 'modernCard',
    'showFields': design.taskFields,
  };
  final projectCard = <String, dynamic>{
    ...design.projectCard,
    'variant': design.projectCard['variant']?.toString() ?? 'progressCard',
    'showFields': design.projectFields,
  };
  final base = <String, dynamic>{
    'screen': tab,
    'theme': _themeFromDesignForPreview(design),
    'title': _label(tab),
    'templateName': design.templateName,
    'templateRendererMode': 'sduiJsonRenderer',
    'designSystem': design.designSystem,
    'layoutConfig': design.layoutConfig,
    'rendererCompatibility': <String, dynamic>{
      ...design.rendererCompatibility,
      'hardcodedBodyRenderer': false,
      'apkPreviewParityMode': 'sharedSduiJson',
    },
  };
  return switch (tab) {
    'home' => <String, dynamic>{...base, 'type': 'sectionList', 'sections': _previewHomeSectionsFromDesign(design, taskCard: taskCard, projectCard: projectCard)},
    'tasks' => <String, dynamic>{...base, 'type': 'taskPage', ...design.taskListConfig, 'taskCard': taskCard, ...taskCard},
    'projects' => <String, dynamic>{...base, 'type': 'projectPage', ...design.projectListConfig, 'projectCard': projectCard, ...projectCard},
    'board' => <String, dynamic>{...base, 'type': 'kanbanBoard'},
    'taskTimeline' => <String, dynamic>{
        ...base,
        'type': 'taskProgressTimeline',
        'variant': 'deliveryAppUIKitTimeline',
        'taskTimelineStyle': 'deliveryAppUIKitTimeline',
        'deliveryUIKitTimeline': true,
        'title': 'Task Timeline',
        'subtitle': 'Task progress chart and timeline bars',
        'showReferenceFallbackWhenEmpty': false,
        'referenceFallbackWhenEmpty': false,
        'timelineTaskLimit': 6,
        'showTaskProgressCard': true,
        'showTaskTimelineBars': true,
        'showAgendaList': false,
        'showDateStrip': false,
        'axisStartDay': 0,
        'todayAxisIndex': 4,
        'referenceProgress': 0,
        'timelineVisualConfig': <String, dynamic>{
          'enabled': true,
          'variant': 'deliveryAppUIKitTimeline',
          'taskTimelineStyle': 'deliveryAppUIKitTimeline',
          'deliveryUIKitTimeline': true,
          'taskTimelineActive': true,
          'showTaskProgressCard': true,
          'showTaskTimelineBars': true,
          'showAgendaList': false,
          'showDateStrip': false,
          'axisStartDay': 0,
          'todayAxisIndex': 4,
          'referenceProgress': 0,
          'timelineTaskLimit': 6,
          'showReferenceFallbackWhenEmpty': false,
        },
      },
    'notifications' => <String, dynamic>{...base, 'type': 'notificationList'},
    'profile' => <String, dynamic>{...base, 'type': 'profileSummary', 'profileActions': design.profileActions, 'profileFields': design.profileFields, 'profileCardConfig': design.profileCardConfig},
    _ => base,
  };
}

Map<String, dynamic> _themeFromDesignForPreview(MobileUiDesign design) {
  return <String, dynamic>{
    ...design.theme,
    'mode': 'light',
    'background': design.designSystem['surface'] ?? design.background,
    'surface': design.designSystem['card'] ?? design.surface,
    'accent': design.designSystem['accent'] ?? design.accent,
    'textPrimary': design.designSystem['textPrimary'] ?? '#151515',
    'textSecondary': design.designSystem['textSecondary'] ?? '#76736D',
    'border': design.designSystem['border'] ?? '#ECE7DA',
    'cardRadius': design.designSystem['radiusLarge'] ?? design.theme['cardRadius'] ?? 24,
    'cardPadding': design.layoutConfig['horizontalPadding'] ?? design.theme['cardPadding'] ?? 16,
    'density': design.compactMode ? 'compact' : (design.theme['density'] ?? 'comfortable'),
  };
}

List<Map<String, dynamic>> _previewHomeSectionsFromDesign(
  MobileUiDesign design, {
  required Map<String, dynamic> taskCard,
  required Map<String, dynamic> projectCard,
}) {
  final rawSections = _jsonStringList(design.homeLayout['sections']);
  final ids = rawSections.isNotEmpty
      ? rawSections
      : (design.visibleHomeCardIds.isNotEmpty ? design.visibleHomeCardIds : const <String>['deadlineTimer', 'todayTasks', 'myOpenTasks', 'projectProgress']);
  return ids.map((id) {
    final normalized = id == 'deadlineTimer' ? 'deadlineHero' : id;
    final configKey = normalized == 'deadlineHero' ? 'deadlineTimer' : normalized;
    final cardConfig = _jsonMap(design.homeCardConfig[configKey]) ?? const <String, dynamic>{};
    switch (normalized) {
      case 'deadlineHero':
        return <String, dynamic>{'id': 'deadlineTimer', 'type': 'deadlineHero', 'title': 'Next deadline', 'variant': cardConfig['variant'] ?? 'darkEditorialHero', 'visible': true};
      case 'activeProjectsGrid':
        return <String, dynamic>{'id': 'activeProjectsGrid', 'type': 'activeProjectsGrid', 'title': 'Current work', 'projectCard': projectCard, 'visible': true};
      case 'todayTasks':
        return <String, dynamic>{'id': 'todayTasks', 'type': 'todayTaskList', 'title': 'Today', 'limit': 3, 'taskCard': taskCard, 'visible': true};
      case 'myOpenTasks':
        return <String, dynamic>{'id': 'myOpenTasks', 'type': 'taskList', 'title': 'My open tasks', 'limit': 4, 'taskCard': taskCard, 'visible': true};
      case 'projectProgress':
        return <String, dynamic>{'id': 'projectProgress', 'type': 'projectProgressCard', 'title': 'Project progress', 'projectCard': projectCard, 'visible': true};
      case 'onlineStatus':
        return <String, dynamic>{'id': 'onlineStatus', 'type': 'onlineStatusCard', 'title': 'Status', 'visible': true};
      default:
        return <String, dynamic>{'id': normalized, 'type': normalized, 'title': normalized, 'visible': true};
    }
  }).toList();
}

List<String> _jsonStringList(dynamic value) {
  if (value is Iterable) return value.map((item) => item.toString()).where((item) => item.trim().isNotEmpty).toList();
  return const <String>[];
}

class _StrictJsonPhonePreview extends StatelessWidget {
  const _StrictJsonPhonePreview({
    required this.screenJson,
    required this.design,
    required this.previewTab,
    required this.accent,
    required this.surface,
  });

  final Map<String, dynamic> screenJson;
  final MobileUiDesign design;
  final String previewTab;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final jsonTheme = _jsonMap(screenJson['theme']) ?? _jsonMap(screenJson['style']);
    final background = _jsonColor(jsonTheme, const ['background', 'backgroundColor', 'scaffoldBackgroundColor'], fallback: _hexColor(design.background));
    final padding = _jsonInsets(screenJson['padding'], fallback: const EdgeInsets.all(16));
    final showStatusBar = _jsonBool(screenJson['showStatusBar']) ?? _jsonBool(screenJson['statusBar']) ?? false;

    return Container(
      color: background,
      child: Column(
        children: [
          if (showStatusBar) _PreviewStatusBar(accent: accent),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: padding,
              child: _StrictJsonRenderer(
                data: screenJson,
                design: design,
                previewTab: previewTab,
                accent: accent,
                surface: surface,
                isRoot: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



class _RuntimePreviewNavigationRail extends StatelessWidget {
  const _RuntimePreviewNavigationRail({
    required this.config,
    required this.runtimeConfig,
    required this.activeTab,
    required this.accent,
    required this.surface,
    required this.width,
    required this.onTabChanged,
  });

  final Map<String, dynamic> config;
  final Map<String, dynamic> runtimeConfig;
  final String activeTab;
  final Color accent;
  final Color surface;
  final double width;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = _previewTabsForRuntimeConfig(runtimeConfig, MobileUiDesign.defaults())
        .where((tab) => tab != 'notifications' && tab != 'meetings')
        .take(6)
        .toList();
    final background = _jsonColor(config, const ['background'], fallback: surface);
    final border = _jsonColor(config, const ['border'], fallback: AppTheme.border);
    final activeBg = _jsonColor(config, const ['activeItemBackground', 'indicatorColor', 'centerActionColor'], fallback: accent);
    final inactiveColor = _jsonColor(config, const ['inactiveColor'], fallback: _hexColor('#0F140F'));
    final extended = width >= 160;

    return Container(
      width: width,
      margin: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: border, width: 1.1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.10), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: activeBg, shape: BoxShape.circle),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: tabs.map((tab) {
                final active = tab == activeTab;
                return InkWell(
                  onTap: () => onTabChanged(tab),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 0, vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? activeBg.withOpacity(.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                      children: [
                        Icon(_tabIcon(tab), color: active ? activeBg : inactiveColor.withOpacity(.72), size: 23),
                        if (extended) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _label(tab),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active ? activeBg : inactiveColor.withOpacity(.72),
                                fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}



class _RuntimePreviewSideMenuOverlay extends StatelessWidget {
  const _RuntimePreviewSideMenuOverlay({
    required this.runtimeConfig,
    required this.activeTab,
    required this.accent,
    required this.surface,
    required this.activeScreenJson,
    required this.onClose,
    required this.onTabChanged,
  });

  final Map<String, dynamic> runtimeConfig;
  final String activeTab;
  final Color accent;
  final Color surface;
  final Map<String, dynamic> activeScreenJson;
  final VoidCallback onClose;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final menuConfig = _jsonMap(runtimeConfig['sideMenuConfig']) ?? const <String, dynamic>{};
    final presentation = (menuConfig['presentation'] ?? menuConfig['variant'] ?? '').toString().toLowerCase();
    final animation = (menuConfig['animation'] ?? '').toString().toLowerCase();
    final useCalendarReveal = presentation.contains('calendar') || animation.contains('slidereveal');

    if (!useCalendarReveal) {
      return _buildLegacyPreviewDrawer(menuConfig);
    }

    final items = _previewSideMenuItems(runtimeConfig);
    final drawerColor = _hexColor((menuConfig['background'] ?? menuConfig['drawerBackground'] ?? '#4E8064').toString());
    final drawerText = _hexColor((menuConfig['textColor'] ?? '#FFFFFF').toString());
    final selectedText = _hexColor((menuConfig['selectedTextColor'] ?? '#FFFFFF').toString());
    final radius = _jsonDouble(menuConfig, const ['cornerRadius'], fallback: 30).clamp(22, 42).toDouble();
    final animationMs = _jsonDouble(menuConfig, const ['animationMs'], fallback: 380).round().clamp(120, 700).toInt();
    final translateRatio = _jsonDouble(menuConfig, const ['translateXRatio'], fallback: .96).clamp(.76, .98).toDouble();
    final mainRadius = _jsonDouble(menuConfig, const ['mainPanelBorderRadius'], fallback: 28).clamp(16, 36).toDouble();
    final showDepthShadow = _jsonBool(menuConfig['depthShadow']) ?? true;
    final showFooter = _jsonBool(menuConfig['showFooter']) ?? true;
    final welcomeLabel = (menuConfig['welcomeLabel'] ?? 'Welcome Back,').toString();
    final welcomeName = (menuConfig['welcomeName'] ?? 'Project Hub').toString();

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth <= 0 ? 390.0 : constraints.maxWidth;
        final drawerWidth = _jsonDouble(menuConfig, const ['width'], fallback: maxWidth * .70).clamp(maxWidth * .58, maxWidth * .78).toDouble();
        final mainLeft = (drawerWidth * translateRatio).clamp(maxWidth * .58, maxWidth * .80).toDouble();
        final panelTop = _jsonDouble(menuConfig, const ['mainPanelTopInset'], fallback: 16).clamp(0, 44).toDouble();
        final panelBottom = _jsonDouble(menuConfig, const ['mainPanelBottomInset'], fallback: 20).clamp(0, 48).toDouble();
        final verticalShrinkEnabled = _jsonBool(menuConfig['verticalShrinkEnabled']) ??
            _jsonBool(menuConfig['mainPanelVerticalShrinkEnabled']) ??
            true;
        final verticalShrinkScale = verticalShrinkEnabled
            ? _jsonDouble(
                menuConfig,
                const ['verticalShrinkScale', 'mainPanelVerticalShrinkScale', 'activePanelVerticalScale'],
                fallback: .965,
              ).clamp(.90, 1.0).toDouble()
            : 1.0;
        final mainPanelWidth = _jsonDouble(menuConfig, const ['mainPanelWidth'], fallback: maxWidth).clamp(maxWidth * .96, maxWidth * 1.08).toDouble();
        final cutShadow = showDepthShadow
            ? <BoxShadow>[
                BoxShadow(color: Colors.black.withOpacity(.20), blurRadius: 32, offset: const Offset(-8, 20)),
                BoxShadow(color: drawerColor.withOpacity(.18), blurRadius: 26, offset: const Offset(-10, 8)),
              ]
            : <BoxShadow>[];

        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onClose,
                child: Container(color: Colors.black.withOpacity(.06)),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: drawerColor,
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [BoxShadow(color: drawerColor.withOpacity(.18), blurRadius: 36, offset: const Offset(0, 16))],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: Duration(milliseconds: animationMs),
              curve: Curves.easeOutCubic,
              left: mainLeft,
              top: panelTop,
              bottom: panelBottom,
              width: mainPanelWidth,
              child: IgnorePointer(
                ignoring: true,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 1.0, end: verticalShrinkScale),
                  duration: Duration(milliseconds: animationMs),
                  curve: Curves.easeOutCubic,
                  builder: (context, scaleY, scaledChild) {
                    return Transform.scale(
                      scaleX: 1.0,
                      scaleY: scaleY,
                      alignment: Alignment.centerLeft,
                      child: scaledChild,
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(mainRadius),
                      boxShadow: cutShadow,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(mainRadius),
                      child: _PreviewCutSideMenuMainPanel(
                        accent: accent,
                        surface: surface,
                        runtimeConfig: runtimeConfig,
                        activeTab: activeTab,
                        activeScreenJson: activeScreenJson,
                        onClose: onClose,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: drawerWidth,
              child: SafeArea(
                right: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    _jsonDouble(menuConfig, const ['drawerContentLeft'], fallback: 38).clamp(14, 56).toDouble(),
                    _jsonDouble(menuConfig, const ['drawerContentTop'], fallback: 50).clamp(14, 72).toDouble(),
                    _jsonDouble(menuConfig, const ['drawerContentRight'], fallback: 28).clamp(12, 48).toDouble(),
                    _jsonDouble(menuConfig, const ['drawerContentBottom'], fallback: 34).clamp(12, 56).toDouble(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: _jsonDouble(menuConfig, const ['avatarRadius'], fallback: 34).clamp(24, 42).toDouble(),
                        backgroundColor: Colors.white.withOpacity(.20),
                        child: Text('PM', style: TextStyle(color: drawerText, fontWeight: FontWeight.w900, fontSize: 18)),
                      ),
                      const SizedBox(height: 24),
                      Text(welcomeLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: drawerText.withOpacity(.72), fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(welcomeName, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: drawerText, fontSize: 27, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -.8)),
                      const SizedBox(height: 28),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            for (final item in items)
                              _PreviewRevealDrawerTile(
                                item: item,
                                active: item.route == activeTab,
                                textColor: drawerText,
                                selectedText: selectedText,
                                selectedBackground: Colors.white.withOpacity(.15),
                                onTap: () => onTabChanged(_canonicalPreviewRoute(item.route)),
                              ),
                          ],
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
                              Expanded(child: Text((menuConfig['footerLabel'] ?? 'Project workspace').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: drawerText.withOpacity(.84), fontSize: 12.5, fontWeight: FontWeight.w800))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegacyPreviewDrawer(Map<String, dynamic> menuConfig) {
    final items = _previewSideMenuItems(runtimeConfig);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black.withOpacity(.26)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Container(
              width: _jsonDouble(menuConfig, const ['width'], fallback: 320).clamp(270, 390).toDouble(),
              constraints: const BoxConstraints(maxHeight: 720),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(_jsonDouble(menuConfig, const ['cornerRadius'], fallback: 30).clamp(18, 40).toDouble()),
                border: Border.all(color: _hexColor('#D8DED4'), width: 1.1),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.20), blurRadius: 32, offset: const Offset(0, 18))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_jsonDouble(menuConfig, const ['cornerRadius'], fallback: 30).clamp(18, 40).toDouble()),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                      child: Row(
                        children: [
                          Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withOpacity(.14), shape: BoxShape.circle), child: Icon(Icons.menu_rounded, color: accent)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text((menuConfig['title'] ?? 'All Screens').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF0F140F), letterSpacing: -.3)),
                                const SizedBox(height: 2),
                                Text((menuConfig['subtitle'] ?? 'Open any workspace screen').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _hexColor('#5F675E'))),
                              ],
                            ),
                          ),
                          IconButton(visualDensity: VisualDensity.compact, onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: _hexColor('#D8DED4')),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
                        children: _previewSideMenuTiles(items: items, activeTab: activeTab, accent: accent, onTap: (tab) => onTabChanged(_canonicalPreviewRoute(tab))),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewRevealDrawerTile extends StatelessWidget {
  const _PreviewRevealDrawerTile({
    required this.item,
    required this.active,
    required this.textColor,
    required this.selectedText,
    required this.selectedBackground,
    required this.onTap,
  });

  final _PreviewSideMenuItem item;
  final bool active;
  final Color textColor;
  final Color selectedText;
  final Color selectedBackground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: active ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, color: active ? selectedText : textColor.withOpacity(.88), size: 22),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: active ? selectedText : textColor.withOpacity(.92), fontSize: 15.5, fontWeight: active ? FontWeight.w900 : FontWeight.w800, letterSpacing: -.08),
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

class _PreviewCutSideMenuMainPanel extends StatelessWidget {
  const _PreviewCutSideMenuMainPanel({
    required this.accent,
    required this.surface,
    required this.runtimeConfig,
    required this.activeTab,
    required this.activeScreenJson,
    required this.onClose,
  });
  final Color accent;
  final Color surface;
  final Map<String, dynamic> runtimeConfig;
  final String activeTab;
  final Map<String, dynamic> activeScreenJson;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final topNav = _jsonMap(runtimeConfig['topNav']) ?? const <String, dynamic>{};
    final bottomNav = _jsonMap(runtimeConfig['bottomNav']) ?? const <String, dynamic>{};
    final layout = _jsonMap(runtimeConfig['layoutConfig']) ?? const <String, dynamic>{};
    final sideMenu = _jsonMap(runtimeConfig['sideMenuConfig']) ?? const <String, dynamic>{};
    final showTopNav = _jsonBool(topNav['enabled']) ?? true;
    final showBottomNav = _jsonBool(bottomNav['enabled']) ?? true;
    final useLiveActivePanel = (_jsonBool(sideMenu['useActiveScreenForCutPanel']) ?? true) && activeScreenJson.isNotEmpty;
    if (useLiveActivePanel) {
      final panelContentPadding = EdgeInsets.fromLTRB(
        _jsonDouble(sideMenu, const ['activePanelContentPaddingLeft', 'mainPanelContentPaddingLeft'], fallback: 18).clamp(0, 56).toDouble(),
        _jsonDouble(sideMenu, const ['activePanelContentPaddingTop', 'mainPanelContentPaddingTop'], fallback: 10).clamp(0, 40).toDouble(),
        _jsonDouble(sideMenu, const ['activePanelContentPaddingRight', 'mainPanelContentPaddingRight'], fallback: 18).clamp(0, 56).toDouble(),
        _jsonDouble(sideMenu, const ['activePanelContentPaddingBottom', 'mainPanelContentPaddingBottom'], fallback: 10).clamp(0, 40).toDouble(),
      );
      final topPadding = showTopNav ? _jsonDouble(layout, const ['previewCutPanelTopContentPadding'], fallback: 86).clamp(60, 128).toDouble() : 0.0;
      final bottomPadding = showBottomNav ? _jsonDouble(layout, const ['previewCutPanelBottomContentPadding'], fallback: 88).clamp(64, 128).toDouble() : 0.0;
      return Container(
        color: surface,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  panelContentPadding.left,
                  topPadding + panelContentPadding.top,
                  panelContentPadding.right,
                  bottomPadding + panelContentPadding.bottom,
                ),
                child: MobileJsonUiRenderer(
                  key: ValueKey<String>('admin-cut-panel-$activeTab'),
                  json: activeScreenJson,
                  previewMode: true,
                  runtimeSearchQuery: '',
                  suppressPageSearchBars: false,
                ),
              ),
            ),
            if (showTopNav)
              Positioned(
                left: panelContentPadding.left,
                right: panelContentPadding.right,
                top: 22 + panelContentPadding.top,
                child: _RuntimePreviewTopNav(
                  config: topNav,
                  runtimeConfig: runtimeConfig,
                  activeTab: activeTab,
                  accent: accent,
                  surface: surface,
                  searchQuery: '',
                  onSearchChanged: (_) {},
                  onSearchSubmitted: (_) {},
                  onSearchClear: () {},
                  onInbox: () {},
                  onMenu: onClose,
                  drawerOpen: true,
                ),
              ),
            if (showBottomNav)
              Positioned(
                left: panelContentPadding.left,
                right: panelContentPadding.right,
                bottom: panelContentPadding.bottom,
                child: _RuntimePreviewBottomNav(
                  config: bottomNav,
                  runtimeConfig: runtimeConfig,
                  activeTab: activeTab,
                  accent: accent,
                  surface: surface,
                  onTabChanged: (_) {},
                ),
              ),
          ],
        ),
      );
    }

    final muted = _hexColor('#6C756C');
    final title = switch (activeTab) {
      'projects' => 'Projects Timeline',
      'tasks' => 'Task Timeline',
      'calendar' => 'Calendar Timeline',
      'notifications' => 'Inbox Activity',
      'profile' => 'My Profile',
      'meetings' => 'Meetings Timeline',
      'board' => 'Task Board',
      'taskTimeline' => 'Task Timeline',
      'timeline' => 'Project Milestones',
      _ => 'Today\'s Timeline',
    };
    final List<Widget> rows;
    if (activeTab == 'projects') {
      rows = const [
        _PreviewCutTimelineRow(time: '9:00', title: 'Project Kickoff', subtitle: 'Design System'),
        _PreviewCutTimelineRow(time: '11:30', title: 'API Review', subtitle: 'Backend Team'),
        _PreviewCutTimelineRow(time: '2:00', title: 'Milestone Check', subtitle: 'Mobile App'),
        _PreviewCutTimelineRow(time: '4:30', title: 'Sprint Planning', subtitle: 'Q2 Sprint'),
      ];
    } else if (activeTab == 'tasks' || activeTab == 'taskTimeline') {
      rows = const [
        _PreviewCutTimelineRow(time: '9:00', title: 'Wireframe Review', subtitle: 'UI/UX Task'),
        _PreviewCutTimelineRow(time: '11:30', title: 'Implement Login Flow', subtitle: 'High Priority'),
        _PreviewCutTimelineRow(time: '2:00', title: 'Fix Project Stats', subtitle: 'In Progress'),
        _PreviewCutTimelineRow(time: '4:30', title: 'QA Handoff', subtitle: 'Review'),
      ];
    } else if (activeTab == 'notifications') {
      rows = const [
        _PreviewCutTimelineRow(time: '9:00', title: 'Task assigned', subtitle: 'Mobile App'),
        _PreviewCutTimelineRow(time: '11:30', title: 'Meeting invite', subtitle: 'Product Team'),
        _PreviewCutTimelineRow(time: '2:00', title: 'Deadline reminder', subtitle: 'Today'),
        _PreviewCutTimelineRow(time: '4:30', title: 'Comment mention', subtitle: 'Design Review'),
      ];
    } else {
      rows = const [
        _PreviewCutTimelineRow(time: '9:00', title: 'Design System Update', subtitle: 'UI/UX Redesign'),
        _PreviewCutTimelineRow(time: '11:30', title: 'Implement Login Flow', subtitle: 'Website Revamp'),
        _PreviewCutTimelineRow(time: '2:00', title: 'Project Status Review', subtitle: 'Mobile App'),
        _PreviewCutTimelineRow(time: '4:30', title: 'Sprint Planning', subtitle: 'Q2 Sprint'),
      ];
    }
    return Container(
      color: surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _jsonDouble(sideMenu, const ['activePanelContentPaddingLeft', 'mainPanelContentPaddingLeft'], fallback: 22).clamp(0, 56).toDouble() + 4,
            _jsonDouble(sideMenu, const ['activePanelContentPaddingTop', 'mainPanelContentPaddingTop'], fallback: 20).clamp(0, 40).toDouble() + 6,
            _jsonDouble(sideMenu, const ['activePanelContentPaddingRight', 'mainPanelContentPaddingRight'], fallback: 22).clamp(0, 56).toDouble() + 4,
            _jsonDouble(sideMenu, const ['activePanelContentPaddingBottom', 'mainPanelContentPaddingBottom'], fallback: 18).clamp(0, 40).toDouble() + 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_rounded, color: _hexColor('#193126'), size: 23),
                  const Spacer(),
                  Text(_label(activeTab), style: TextStyle(color: _hexColor('#193126'), fontWeight: FontWeight.w900, fontSize: 14)),
                  const SizedBox(width: 5),
                  Icon(Icons.keyboard_arrow_down_rounded, color: _hexColor('#193126'), size: 18),
                ],
              ),
              const SizedBox(height: 26),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: _hexColor('#193126'), fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -.5)),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final day in const ['M', 'T', 'W', 'T'])
                    Container(
                      width: 38,
                      height: 42,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(color: day == 'W' ? accent : _hexColor('#F4F6F2'), borderRadius: BorderRadius.circular(12), boxShadow: day == 'W' ? [BoxShadow(color: accent.withOpacity(.22), blurRadius: 12, offset: const Offset(0, 6))] : null),
                      child: Center(child: Text(day, style: TextStyle(color: day == 'W' ? Colors.white : muted, fontWeight: FontWeight.w900, fontSize: 12))),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Stack(
                  children: [
                    Positioned(left: 9, top: 8, bottom: 0, child: Container(width: 2, color: accent.withOpacity(.65))),
                    ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      children: rows,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewCutTimelineRow extends StatelessWidget {
  const _PreviewCutTimelineRow({required this.time, required this.title, required this.subtitle});
  final String time;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = _hexColor('#4E8064');
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: accent, width: 2), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: _hexColor('#F8FAF7'), borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.06), blurRadius: 14, offset: const Offset(0, 8))]),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: TextStyle(color: _hexColor('#6C756C'), fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _hexColor('#17251D'), fontSize: 12.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: _hexColor('#6C756C'), fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewSideMenuItem {
  const _PreviewSideMenuItem({required this.route, required this.label, required this.group, required this.icon});
  final String route;
  final String label;
  final String group;
  final IconData icon;
}

List<_PreviewSideMenuItem> _previewSideMenuItems(Map<String, dynamic> runtimeConfig) {
  final menuConfig = _jsonMap(runtimeConfig['sideMenuConfig']) ?? const <String, dynamic>{};
  final registry = _jsonMap(runtimeConfig['screenRegistry']) ?? const <String, dynamic>{};
  final navigation = _jsonMap(runtimeConfig['navigationConfig']) ?? const <String, dynamic>{};
  final screenConfigs = _jsonMap(runtimeConfig['screenConfigs']) ?? const <String, dynamic>{};
  final showNested = _jsonBool(menuConfig['showNestedScreens']) ?? true;
  final main = _jsonStringList(menuConfig['mainScreens']).isNotEmpty
      ? _jsonStringList(menuConfig['mainScreens'])
      : (_jsonStringList(registry['activeBottomTabs']).isNotEmpty ? _jsonStringList(registry['activeBottomTabs']) : _jsonStringList(runtimeConfig['bottomTabs']));
  final more = _jsonStringList(menuConfig['moreScreens']).isNotEmpty
      ? _jsonStringList(menuConfig['moreScreens'])
      : <String>[
          ..._jsonStringList(registry['activeTabs']).ifEmpty(_jsonStringList(navigation['contentTabs'])),
          if (showNested) ..._jsonStringList(registry['nestedScreens']).ifEmpty(_jsonStringList(navigation['nestedRoutes'])),
        ];
  final seen = <String>{};
  final result = <_PreviewSideMenuItem>[];
  void add(Iterable<String> routes, String group) {
    for (final raw in routes) {
      final route = MobileUiSupportRegistry.canonicalScreen(raw);
      if (route.isEmpty || !MobileUiSupportRegistry.supportedScreens.contains(route) || !seen.add(route)) continue;
      final cfg = _jsonMap(screenConfigs[route]) ?? const <String, dynamic>{};
      final labels = _jsonMap(menuConfig['labelMap']) ?? _jsonMap(menuConfig['labels']) ?? _jsonMap(menuConfig['screenLabels']) ?? const <String, dynamic>{};
      final label = (labels[route] ?? cfg['title'] ?? _label(route)).toString();
      result.add(_PreviewSideMenuItem(route: route, label: label, group: group, icon: _previewIconForRoute(runtimeConfig, route)));
    }
  }
  final effectiveMore = <String>[...(more.isEmpty ? const <String>['tasks', 'taskTimeline', 'meetings', 'notifications', 'taskMap', 'timeline', 'files', 'calendar', 'teamMembers'] : more)];
  if (!effectiveMore.map(MobileUiSupportRegistry.canonicalScreen).contains('taskTimeline') &&
      !_jsonStringList(main).map(MobileUiSupportRegistry.canonicalScreen).contains('taskTimeline')) {
    final taskIndex = effectiveMore.indexWhere((route) => MobileUiSupportRegistry.canonicalScreen(route) == 'tasks');
    effectiveMore.insert(taskIndex >= 0 ? taskIndex + 1 : 0, 'taskTimeline');
  }
  add(main.isEmpty ? const <String>['home', 'projects', 'board', 'profile'] : main, (menuConfig['mainGroupLabel'] ?? 'Main').toString());
  add(effectiveMore, (menuConfig['moreGroupLabel'] ?? 'More').toString());
  return result;
}

extension _PreviewListFallback on List<String> {
  List<String> ifEmpty(List<String> fallback) => isEmpty ? fallback : this;
}

IconData _previewIconForRoute(Map<String, dynamic> runtimeConfig, String route) {
  final sideMenu = _jsonMap(runtimeConfig['sideMenuConfig']) ?? const <String, dynamic>{};
  final bottomNav = _jsonMap(runtimeConfig['bottomNav']) ?? const <String, dynamic>{};
  final screenConfigs = _jsonMap(runtimeConfig['screenConfigs']) ?? const <String, dynamic>{};
  final screenConfig = _jsonMap(screenConfigs[route]) ?? const <String, dynamic>{};
  final sideIconMap = _jsonMap(sideMenu['iconMap']) ?? _jsonMap(sideMenu['icons']) ?? _jsonMap(sideMenu['screenIcons']) ?? const <String, dynamic>{};
  final bottomIconMap = _jsonMap(bottomNav['iconMap']) ?? const <String, dynamic>{};
  final explicit = _iconNameToData(
    sideIconMap[route]?.toString() ??
    bottomIconMap[route]?.toString() ??
    screenConfig['icon']?.toString() ??
    screenConfig['iconName']?.toString() ??
    screenConfig['leadingIcon']?.toString(),
  );
  return explicit ?? _tabIcon(route);
}

IconData? _iconNameToData(String? value) {
  final key = value?.trim().replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  return switch (key) {
    null || '' => null,
    'home' || 'homerounded' || 'dashboard' => Icons.home_rounded,
    'search' || 'searchrounded' || 'magnify' => Icons.search_rounded,
    'projects' || 'project' || 'folder' || 'foldercopy' => Icons.folder_rounded,
    'projectdetail' || 'folderspecial' => Icons.folder_special_rounded,
    'tasks' || 'task' || 'taskalt' || 'assignment' || 'checklist' => Icons.task_alt_rounded,
    'board' || 'kanban' || 'viewkanban' || 'grid' => Icons.view_kanban_rounded,
    'profile' || 'person' || 'user' || 'account' => Icons.person_rounded,
    'notifications' || 'notification' || 'inbox' || 'bell' => Icons.notifications_rounded,
    'meetings' || 'meeting' || 'videocall' || 'video' => Icons.video_call_rounded,
    'meetingdetail' || 'videocamerafront' => Icons.video_camera_front_rounded,
    'taskmap' || 'map' || 'location' || 'locationon' || 'pin' => Icons.location_on_outlined,
    'tasktimeline' || 'taskprogresstimeline' || 'productivetasktimeline' => Icons.view_timeline_rounded,
    'timeline' || 'timelinemilestones' || 'milestone' || 'schedule' || 'clock' => Icons.schedule_rounded,
    'files' || 'file' || 'documents' || 'folderopen' => Icons.folder_open_rounded,
    'calendar' || 'calendarview' || 'calendarmonth' || 'event' => Icons.calendar_month_rounded,
    'teammembers' || 'team' || 'members' || 'group' || 'groups' => Icons.groups_rounded,
    'taskdetail' || 'taskdetails' => Icons.assignment_rounded,
    'menu' || 'hamburger' || 'hamburgermenu' => Icons.menu_rounded,
    _ => null,
  };
}

List<Widget> _previewSideMenuTiles({
  required List<_PreviewSideMenuItem> items,
  required String activeTab,
  required Color accent,
  required ValueChanged<String> onTap,
}) {
  final widgets = <Widget>[];
  String? lastGroup;
  for (final item in items) {
    if (item.group != lastGroup) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 10));
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Text(item.group, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w900)),
      ));
      lastGroup = item.group;
    }
    final active = item.route == activeTab;
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? accent.withOpacity(.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onTap(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(item.icon, color: active ? accent : _hexColor('#5F675E'), size: 22),
                const SizedBox(width: 12),
                Expanded(child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: active ? FontWeight.w900 : FontWeight.w700, color: const Color(0xFF0F140F)))),
                if (active)
                  Container(width: 22, height: 22, decoration: BoxDecoration(color: accent, shape: BoxShape.circle), child: const Icon(Icons.check_rounded, color: Colors.white, size: 15))
                else
                  Icon(Icons.chevron_right_rounded, color: _hexColor('#8B9288'), size: 20),
              ],
            ),
          ),
        ),
      ),
    ));
  }
  return widgets;
}


class _RuntimePreviewUniversalSearchResults extends StatelessWidget {
  const _RuntimePreviewUniversalSearchResults({
    required this.query,
    required this.accent,
    required this.onClose,
    required this.onTabChanged,
  });

  final String query;
  final Color accent;
  final VoidCallback onClose;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final items = <_PreviewSearchResult>[
      _PreviewSearchResult(Icons.folder_rounded, 'Projects', 'Match project name, details, status, team', 'projects'),
      _PreviewSearchResult(Icons.task_alt_rounded, 'Tasks', 'Match task title, project, priority, status', 'tasks'),
      _PreviewSearchResult(Icons.notifications_active_rounded, 'Inbox / Notifications', 'Match notification title, body, sender', 'notifications'),
      _PreviewSearchResult(Icons.video_call_rounded, 'Meetings', 'Match meeting title, link, creator', 'meetings'),
    ].where((item) => '${item.title} ${item.subtitle}'.toLowerCase().contains(q.toLowerCase()) || q.length <= 2).toList();

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 310),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.98),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.black.withOpacity(.10)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 30, offset: const Offset(0, 16))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.manage_search_rounded, color: accent, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Global search: “$q”', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded), onPressed: onClose),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                itemCount: items.isEmpty ? 1 : items.length,
                itemBuilder: (context, index) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(8, 10, 8, 20),
                      child: Center(child: Text('No preview result', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54))),
                    );
                  }
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF7F8F4),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => onTabChanged(_canonicalPreviewRoute(item.route)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(radius: 17, backgroundColor: accent.withOpacity(.14), child: Icon(item.icon, color: accent, size: 19)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                                    Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.black.withOpacity(.55), fontWeight: FontWeight.w600, fontSize: 11)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, size: 13),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSearchResult {
  const _PreviewSearchResult(this.icon, this.title, this.subtitle, this.route);
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
}

class _RuntimePreviewTopNav extends StatelessWidget {
  const _RuntimePreviewTopNav({
    required this.config,
    required this.runtimeConfig,
    required this.activeTab,
    required this.accent,
    required this.surface,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSearchClear,
    required this.onInbox,
    required this.onMenu,
    this.drawerOpen = false,
  });

  final Map<String, dynamic> config;
  final Map<String, dynamic> runtimeConfig;
  final String activeTab;
  final Color accent;
  final Color surface;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onSearchClear;
  final VoidCallback onInbox;
  final VoidCallback onMenu;
  final bool drawerOpen;

  @override
  Widget build(BuildContext context) {
    final bottomNav = _jsonMap(runtimeConfig['bottomNav']) ?? const <String, dynamic>{};
    final referenceStyle = _previewReferenceTopNav(config);
    final height = _jsonDouble(config, const ['height'], fallback: 56).clamp(48, 72).toDouble();
    final marginHorizontal = _jsonDouble(config, const ['marginHorizontal'], fallback: 18).clamp(8, 28).toDouble();
    final marginTop = _jsonDouble(config, const ['marginTop'], fallback: 8).clamp(0, 22).toDouble();
    final background = _jsonColor(config, const ['background', 'surface'], fallback: _jsonColor(bottomNav, const ['background'], fallback: surface));
    final border = _jsonColor(config, const ['border'], fallback: _jsonColor(bottomNav, const ['border'], fallback: _hexColor('#0F140F')));
    final actionColor = _jsonColor(config, const ['actionColor', 'primaryActionColor'], fallback: _jsonColor(bottomNav, const ['activeItemBackground', 'indicatorColor', 'centerActionColor'], fallback: accent));
    final placeholder = (config['placeholder'] ?? config['searchPlaceholder'] ?? 'Search...').toString();
    final showInbox = _jsonBool(config['showInbox']) ?? true;
    final actions = _jsonStringList(config['actions']);
    final sideMenuConfig = _jsonMap(runtimeConfig['sideMenuConfig']) ?? const <String, dynamic>{};
    final showMenu = (_jsonBool(sideMenuConfig['enabled']) ?? false) ||
        (_jsonBool(config['hamburgerMenu']) ?? false) ||
        actions.contains('hamburgerMenu') ||
        actions.contains('openSideMenu') ||
        actions.contains('sideMenu') ||
        actions.contains('menu');
    final hamburgerMode = (config['hamburgerMode'] ?? '').toString().toLowerCase();
    final mergeHamburgerWithSearch = (_jsonBool(config['mergeHamburgerWithSearch']) ?? false) ||
        hamburgerMode == 'mergedleadingicon' ||
        hamburgerMode == 'merged' ||
        hamburgerMode == 'insidepill' ||
        (config['hamburgerPosition'] ?? '').toString().toLowerCase() == 'insidesearch';
    final maxWidth = _jsonDouble(config, const ['maxWidth'], fallback: referenceStyle ? (showMenu ? 470 : 420) : 620).clamp(260, 620).toDouble();
    final notificationAnimation = _jsonMap(config['notificationShortcutAnimation']) ??
        _jsonMap(runtimeConfig['notificationShortcutAnimation']) ??
        _jsonMap((_jsonMap(runtimeConfig['notificationAlertConfig']) ?? const <String, dynamic>{})['shortcutAnimation']) ??
        const <String, dynamic>{};
    // v190: preview matches APK legacy notification shortcut behavior.
    // Tap opens inbox directly; no transform/app-opening animation.
    final notificationTransformEnabled = false;
    final notificationTransformDurationMs = _jsonDouble(notificationAnimation, const ['durationMs'], fallback: 460).round().clamp(180, 900).toInt();
    final notificationTransformLift = _jsonDouble(notificationAnimation, const ['lift', 'translateY'], fallback: -3).clamp(-12, 12).toDouble();
    final notificationTransformRotationTurns = _jsonDouble(notificationAnimation, const ['rotationTurns'], fallback: .035).clamp(-.20, .20).toDouble();

    if (referenceStyle) {
      return Padding(
        padding: EdgeInsets.fromLTRB(marginHorizontal, marginTop, marginHorizontal, 8),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  if (showMenu && !mergeHamburgerWithSearch) ...[
                    InkWell(
                      onTap: onMenu,
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: height,
                        height: height,
                        decoration: BoxDecoration(
                          color: background,
                          shape: BoxShape.circle,
                          border: Border.all(color: border, width: 1.15),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 22, offset: const Offset(0, 12))],
                        ),
                        child: Icon(drawerOpen ? Icons.arrow_back_rounded : Icons.menu_rounded, color: _hexColor('#0F140F'), size: 23),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _RuntimePreviewMergedSearchPill(
                      height: height,
                      background: background,
                      border: border,
                      placeholder: placeholder,
                      query: searchQuery,
                      showMenu: showMenu && mergeHamburgerWithSearch,
                      drawerOpen: drawerOpen,
                      onMenu: onMenu,
                      onChanged: onSearchChanged,
                      onSubmitted: onSearchSubmitted,
                      onClear: onSearchClear,
                      showAi: true,
                      onAi: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (sheetContext) => const BrewHavenChatSheet(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _PreviewTransformingNotificationShortcut(
                    enabled: showInbox && notificationTransformEnabled,
                    durationMs: notificationTransformDurationMs,
                    lift: notificationTransformLift,
                    rotationTurns: notificationTransformRotationTurns,
                    onTap: showInbox ? onInbox : () {},
                    child: Container(
                      width: height,
                      height: height,
                      decoration: BoxDecoration(
                        color: actionColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: actionColor, width: 1.15),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 22, offset: const Offset(0, 12))],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Icon(showInbox ? Icons.notifications_none_rounded : Icons.tune_rounded, color: Colors.white, size: 23),
                          if (showInbox)
                            Positioned(
                              right: 3,
                              top: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFFE95D5D), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white, width: 1.2)),
                                child: const Text('9+', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                              ),
                            ),
                        ],
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

    final routeTitleMap = _jsonMap(config['routeTitleMap']) ?? const <String, dynamic>{};
    final title = config['routeAwareTitle'] == true || routeTitleMap.isNotEmpty
        ? (routeTitleMap[activeTab]?.toString() ?? _label(activeTab))
        : (config['title']?.toString() ?? _label(activeTab));
    final radius = _jsonDouble(config, const ['cornerRadius', 'radius'], fallback: 26).clamp(10, 36).toDouble();
    final showAvatar = _jsonBool(config['showAvatar']) ?? true;
    final searchEnabled = _jsonBool(config['searchEnabled']) ?? _jsonBool(config['showSearchOnListPages']) ?? true;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(marginHorizontal, marginTop, marginHorizontal, 8),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: border, width: 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 22, offset: const Offset(0, 12))],
            ),
            child: Row(
              children: [
                if (showMenu) ...[
                  InkWell(onTap: onMenu, borderRadius: BorderRadius.circular(999), child: Icon(drawerOpen ? Icons.arrow_back_rounded : Icons.menu_rounded, color: _hexColor('#0F140F'), size: 24)),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0F140F)),
                  ),
                ),
                if (searchEnabled) Icon(Icons.search_rounded, color: _hexColor('#0F140F'), size: 23),
                if (showInbox) ...[
                  const SizedBox(width: 14),
                  _PreviewTransformingNotificationShortcut(
                    enabled: notificationTransformEnabled,
                    durationMs: notificationTransformDurationMs,
                    lift: notificationTransformLift,
                    rotationTurns: notificationTransformRotationTurns,
                    onTap: onInbox,
                    child: Icon(Icons.notifications_none_rounded, color: _hexColor('#0F140F'), size: 24),
                  ),
                ],
                if (showAvatar) ...[
                  const SizedBox(width: 14),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Color.lerp(accent, Colors.black, .2),
                    child: const Text('D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _previewReferenceTopNav(Map<String, dynamic> config) {
  final raw = (config['variant'] ?? config['style'] ?? config['mode'] ?? '').toString().toLowerCase();
  return raw.contains('wireframereference') || raw.contains('referencefloating') || raw.contains('floatingsearch') || raw.contains('wireframetopsearchbar');
}



class _PreviewTransformingNotificationShortcut extends StatefulWidget {
  const _PreviewTransformingNotificationShortcut({
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.durationMs = 460,
    this.lift = -3,
    this.rotationTurns = .035,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  final int durationMs;
  final double lift;
  final double rotationTurns;

  @override
  State<_PreviewTransformingNotificationShortcut> createState() => _PreviewTransformingNotificationShortcutState();
}

class _PreviewTransformingNotificationShortcutState extends State<_PreviewTransformingNotificationShortcut> with SingleTickerProviderStateMixin {
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
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: widget.durationMs));
    _rebuildAnimations();
  }

  @override
  void didUpdateWidget(covariant _PreviewTransformingNotificationShortcut oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.durationMs != widget.durationMs) {
      _controller.duration = Duration(milliseconds: widget.durationMs);
    }
    if (oldWidget.lift != widget.lift || oldWidget.rotationTurns != widget.rotationTurns) {
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
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -widget.rotationTurns * .45), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: -widget.rotationTurns * .45, end: widget.rotationTurns * .30), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: widget.rotationTurns * .30, end: 0), weight: 52),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _dy = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: widget.lift - 3), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: widget.lift - 3, end: 0), weight: 66),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: .72, end: 1.00), weight: 10),
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: 2.55), weight: 52),
      TweenSequenceItem(tween: Tween<double>(begin: 2.55, end: 2.90), weight: 38),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _launchOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.00, end: .24), weight: 18),
      TweenSequenceItem(tween: Tween<double>(begin: .24, end: .12), weight: 34),
      TweenSequenceItem(tween: Tween<double>(begin: .12, end: 0.00), weight: 48),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _contentOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.00, end: .88), weight: 22),
      TweenSequenceItem(tween: Tween<double>(begin: .88, end: .52), weight: 28),
      TweenSequenceItem(tween: Tween<double>(begin: .52, end: 1.00), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  void _handleTap() {
    // v190 legacy preview behavior: open directly on tap.
    if (widget.enabled) {
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
    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          if (!widget.enabled) return child ?? const SizedBox.shrink();
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: _launchOpacity.value,
                  child: Transform.scale(
                    scale: _launchScale.value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: const Color(0xFF6B8C5A), borderRadius: BorderRadius.circular(999)),
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
          );
        },
      ),
    );
  }
}

class _RuntimePreviewMergedSearchPill extends StatefulWidget {
  const _RuntimePreviewMergedSearchPill({
    required this.height,
    required this.background,
    required this.border,
    required this.placeholder,
    required this.query,
    required this.showMenu,
    this.drawerOpen = false,
    required this.onMenu,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.showAi,
    required this.onAi,
  });

  final double height;
  final Color background;
  final Color border;
  final String placeholder;
  final String query;
  final bool showMenu;
  final bool drawerOpen;
  final VoidCallback onMenu;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final bool showAi;
  final VoidCallback onAi;

  @override
  State<_RuntimePreviewMergedSearchPill> createState() => _RuntimePreviewMergedSearchPillState();
}

class _RuntimePreviewMergedSearchPillState extends State<_RuntimePreviewMergedSearchPill> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _RuntimePreviewMergedSearchPill oldWidget) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _hexColor('#0F140F');
    final muted = _hexColor('#5F675E');
    return Container(
      height: widget.height,
      padding: EdgeInsets.only(left: widget.showMenu ? 6 : 16, right: 10),
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(widget.height / 2),
        border: Border.all(color: widget.border, width: 1.15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Row(
        children: [
          if (widget.showMenu) ...[
            InkResponse(
              onTap: widget.onMenu,
              radius: widget.height * .42,
              child: SizedBox(
                width: widget.height - 10,
                height: widget.height - 10,
                child: Icon(widget.drawerOpen ? Icons.arrow_back_rounded : Icons.menu_rounded, color: text, size: 23),
              ),
            ),
            Container(width: 1, height: widget.height * .38, margin: const EdgeInsets.only(right: 12), color: widget.border.withOpacity(.18)),
          ],
          Icon(Icons.search_rounded, color: muted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (value) {
                widget.onChanged(value);
                setState(() {});
              },
              onSubmitted: widget.onSubmitted,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: text, fontWeight: FontWeight.w800, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.placeholder,
                hintStyle: TextStyle(color: muted, fontWeight: FontWeight.w700, fontSize: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
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
                  child: Icon(Icons.auto_awesome_rounded, color: muted, size: 20),
                ),
              ),
            ),
          if (_controller.text.trim().isNotEmpty)
            InkResponse(
              onTap: () {
                _controller.clear();
                widget.onChanged('');
                widget.onClear();
                setState(() {});
              },
              radius: 18,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, color: muted, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}

class _RuntimePreviewBottomNav extends StatelessWidget {
  const _RuntimePreviewBottomNav({
    required this.config,
    required this.runtimeConfig,
    required this.activeTab,
    required this.accent,
    required this.surface,
    required this.onTabChanged,
  });

  final Map<String, dynamic> config;
  final Map<String, dynamic> runtimeConfig;
  final String activeTab;
  final Color accent;
  final Color surface;
  final ValueChanged<String> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = _previewTabsForRuntimeConfig(runtimeConfig, MobileUiDesign.defaults())
        .where((tab) => tab != 'notifications' && tab != 'meetings')
        .take(4)
        .toList();
    final height = _jsonDouble(config, const ['height'], fallback: 64).clamp(54, 78).toDouble();
    final marginHorizontal = _jsonDouble(config, const ['marginHorizontal'], fallback: 48).clamp(8, 80).toDouble();
    final marginBottom = _jsonDouble(config, const ['marginBottom'], fallback: 16).clamp(6, 28).toDouble();
    final background = _jsonColor(config, const ['background'], fallback: surface);
    final border = _jsonColor(config, const ['border'], fallback: _hexColor('#0F140F'));
    final activeBg = _jsonColor(config, const ['activeItemBackground', 'indicatorColor', 'centerActionColor'], fallback: accent);
    final activeColor = _jsonColor(config, const ['activeColor'], fallback: Colors.white);
    final inactiveColor = _jsonColor(config, const ['inactiveColor'], fallback: _hexColor('#0F140F'));
    final centerAction = _jsonBool(config['centerAction']) ?? false;
    final maxWidth = _jsonDouble(config, const ['maxWidth'], fallback: 340).clamp(260, 620).toDouble();

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(marginHorizontal, 8, marginHorizontal, marginBottom),
          child: SizedBox(
            height: height + (centerAction ? 14 : 0),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: height,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(height / 2),
                    border: Border.all(color: border, width: 1.2),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.16), blurRadius: 24, offset: const Offset(0, 12))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (var i = 0; i < tabs.length; i++) ...[
                        if (centerAction && i == (tabs.length / 2).ceil()) SizedBox(width: height * .72),
                        Expanded(
                          child: _RuntimeBottomNavItem(
                            tab: tabs[i],
                            active: tabs[i] == activeTab,
                            activeBg: activeBg,
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                            onTap: () => onTabChanged(tabs[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (centerAction)
                  Positioned(
                    top: 0,
                    child: InkWell(
                      onTap: () {},
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: height * .86,
                        height: height * .86,
                        decoration: BoxDecoration(
                          color: activeBg,
                          shape: BoxShape.circle,
                          border: Border.all(color: background, width: 5),
                          boxShadow: [BoxShadow(color: activeBg.withOpacity(.26), blurRadius: 18, offset: const Offset(0, 10))],
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
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

class _RuntimeBottomNavItem extends StatelessWidget {
  const _RuntimeBottomNavItem({
    required this.tab,
    required this.active,
    required this.activeBg,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final String tab;
  final bool active;
  final Color activeBg;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: active ? 46 : 40,
          height: active ? 46 : 40,
          decoration: BoxDecoration(
            color: active ? activeBg : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: active ? [BoxShadow(color: activeBg.withOpacity(.22), blurRadius: 16, offset: const Offset(0, 8))] : const [],
          ),
          child: Icon(_tabIcon(tab), color: active ? activeColor : inactiveColor, size: 22),
        ),
      ),
    );
  }
}

class _PreviewStatusBar extends StatelessWidget {
  const _PreviewStatusBar({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          const Text('9:41', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
          const Spacer(),
          Container(width: 62, height: 18, decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(999))),
        ],
      ),
    );
  }
}


class _PreviewTopNav extends StatelessWidget {
  const _PreviewTopNav({required this.design, required this.accent, required this.surface, required this.onInbox});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;
  final VoidCallback onInbox;

  bool _flag(String key, {bool fallback = true}) {
    final value = design.topNav[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes' || normalized == '1') return true;
      if (normalized == 'false' || normalized == 'no' || normalized == '0') return false;
    }
    return fallback;
  }

  String _text(String key, {String fallback = ''}) {
    final value = design.topNav[key];
    final raw = value?.toString().trim() ?? '';
    return raw.isEmpty ? fallback : raw;
  }

  @override
  Widget build(BuildContext context) {
    if (!_flag('enabled')) return const SizedBox.shrink();

    final style = _text('style', fallback: 'glassAdvanced');
    final compact = _text('density', fallback: 'comfortable') == 'compact';
    final useGlass = style == 'glassAdvanced' || style == 'glass' || style == 'premium';
    final navSurface = useGlass ? Colors.white.withOpacity(.88) : surface;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, compact ? 8 : 10, 12, compact ? 7 : 8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 7 : 9),
        decoration: BoxDecoration(
          color: navSurface,
          gradient: useGlass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white.withOpacity(.96), Color.lerp(surface, accent, .035)!.withOpacity(.92)],
                )
              : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: useGlass ? Colors.white.withOpacity(.72) : AppTheme.border),
          boxShadow: [
            BoxShadow(color: accent.withOpacity(.12), blurRadius: 22, offset: const Offset(0, 10)),
            BoxShadow(color: Colors.white.withOpacity(.58), blurRadius: 10, offset: const Offset(-5, -5)),
          ],
        ),
        child: Row(
          children: [
            if (_flag('showInbox')) ...[
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onInbox,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 7 : 8),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withOpacity(.22)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(Icons.notifications_rounded, color: accent, size: compact ? 17 : 18),
                          if (_flag('inboxBadge'))
                            Positioned(
                              right: -7,
                              top: -7,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                ),
                                child: const Text('9+', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                              ),
                            ),
                        ],
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 7),
                        const Text('Inbox', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
            ],
            if (_flag('showAvatar')) ...[
              Container(
                width: compact ? 34 : 38,
                height: compact ? 34 : 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [accent, Color.lerp(accent, Colors.black, .18)!]),
                  boxShadow: [BoxShadow(color: accent.withOpacity(.26), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Text('D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: compact ? 13 : 15)),
              ),
              SizedBox(width: compact ? 8 : 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_flag('showCompanyName'))
                    Text('Decode Derivatives', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13 : 15, letterSpacing: -.2)),
                  if (_flag('showUserRole')) ...[
                    const SizedBox(height: 2),
                    Text('Developer', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: compact ? 10 : 11)),
                  ],
                ],
              ),
            ),
            if (_flag('showOnlineStatus')) ...[
              SizedBox(width: compact ? 6 : 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: compact ? 7 : 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.green.withOpacity(.24)),
                  boxShadow: _flag('showPresenceGlow') ? [BoxShadow(color: Colors.green.withOpacity(.16), blurRadius: 12, offset: const Offset(0, 6))] : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: compact ? 9 : 10, height: compact ? 9 : 10, decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.green.withOpacity(.35), blurRadius: 8)])),
                    const SizedBox(width: 7),
                    Text('Online', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: compact ? 11 : 12)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewScreenContent extends StatelessWidget {
  const _PreviewScreenContent({required this.design, required this.previewTab, required this.accent, required this.surface});

  final MobileUiDesign design;
  final String previewTab;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final title = switch (previewTab) {
      'tasks' => 'My Tasks',
      'projects' => 'Projects',
      'board' => 'Board',
      'notifications' => 'Inbox',
      'calendar' => 'Calendar',
      'meetings' => 'Meetings',
      'profile' => 'Profile',
      _ => 'My Work',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Preview as employee • ${_label(previewTab)}', style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 14),
        if (design.screenOverrides.containsKey(previewTab))
          _ImportedJsonScreenPreview(
            screenJson: design.screenOverrides[previewTab]!,
            design: design,
            previewTab: previewTab,
            accent: accent,
            surface: surface,
          )
        else
          (switch (previewTab) {
            'tasks' => _TasksPreview(design: design, accent: accent, surface: surface),
            'projects' => _ProjectsPreview(design: design, accent: accent, surface: surface),
            'board' => _BoardPreview(design: design, accent: accent, surface: surface),
            'notifications' => _NotificationsPreview(design: design, accent: accent, surface: surface),
            'calendar' => _CalendarDesignerPreview(design: design, accent: accent, surface: surface),
            'profile' => _ProfilePreview(design: design, accent: accent, surface: surface),
            _ => _HomePreview(design: design, accent: accent, surface: surface),
          }),
      ],
    );
  }
}

class _HomePreview extends StatelessWidget {
  const _HomePreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    final visibleSections = design.sections.where((section) => section['visible'] != false).toList();
    return Column(
      children: visibleSections.map((section) {
        final id = section['id']?.toString() ?? '';
        return switch (id) {
          'workSummary' => _HeroPreviewCard(section: section, accent: accent, radius: radius, padding: padding),
          'myOpenTasks' || 'todayTasks' => _TaskListPreviewCard(section: section, accent: accent, surface: surface, radius: radius, padding: padding, fields: design.taskFields, variant: _cardVariant(design.taskCard, 'modernCard'), actions: _stringList(design.taskCard['actions'])),
          'projectProgress' => _ProjectProgressPreviewCard(section: section, accent: accent, surface: surface, radius: radius, padding: padding, fields: design.projectFields, variant: _cardVariant(design.projectCard, 'progressCard')),
          'onlineStatus' => _BasePreviewCard(title: section['title']?.toString() ?? 'Online Status', subtitle: 'Available for work now', trailing: 'Online', accent: Colors.green, surface: surface, radius: radius, padding: padding),
          'deadlineTimer' => _BasePreviewCard(title: section['title']?.toString() ?? 'Next Deadline', subtitle: 'Design review handoff', trailing: '4h 20m', accent: Colors.orange, surface: surface, radius: radius, padding: padding),
          _ => const SizedBox.shrink(),
        };
      }).toList(),
    );
  }
}

class _TasksPreview extends StatelessWidget {
  const _TasksPreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    return Column(
      children: [
        _TaskListPreviewCard(section: const {'title': 'Assigned today'}, accent: accent, surface: surface, radius: radius, padding: padding, fields: design.taskFields, variant: _cardVariant(design.taskCard, 'modernCard'), actions: _stringList(design.taskCard['actions'])),
        _TaskListPreviewCard(section: const {'title': 'Upcoming work'}, accent: Colors.indigo, surface: surface, radius: radius, padding: padding, fields: design.taskFields, variant: _cardVariant(design.taskCard, 'modernCard'), actions: _stringList(design.taskCard['actions'])),
      ],
    );
  }
}

class _ProjectsPreview extends StatelessWidget {
  const _ProjectsPreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    return Column(
      children: [
        _ProjectProgressPreviewCard(section: const {'title': 'Employee Workspace'}, accent: accent, surface: surface, radius: radius, padding: padding, fields: design.projectFields, variant: _cardVariant(design.projectCard, 'progressCard')),
        _ProjectProgressPreviewCard(section: const {'title': 'Client Portal'}, accent: Colors.purple, surface: surface, radius: radius, padding: padding, fields: design.projectFields, variant: _cardVariant(design.projectCard, 'progressCard')),
      ],
    );
  }
}

class _BoardPreview extends StatelessWidget {
  const _BoardPreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(radius + 8),
            border: Border.all(color: AppTheme.border),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: accent.withOpacity(.12), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.dashboard_customize_rounded, color: accent, size: 20)),
              const SizedBox(width: 10),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Task board cockpit', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)), SizedBox(height: 3), Text('Pinterest-style live lanes', style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.muted, fontSize: 11))])),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(999)), child: Text('Live', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 11))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _BoardColumn(title: 'Backlog', count: 3, accent: AppTheme.muted, surface: surface, radius: radius),
              const SizedBox(width: 10),
              _BoardColumn(title: 'In Progress', count: 4, accent: accent, surface: surface, radius: radius),
              const SizedBox(width: 10),
              _BoardColumn(title: 'Review', count: 2, accent: Colors.purple, surface: surface, radius: radius),
              const SizedBox(width: 10),
              _BoardColumn(title: 'Done', count: 8, accent: Colors.green, surface: surface, radius: radius),
            ],
          ),
        ),
      ],
    );
  }
}

class _BoardColumn extends StatelessWidget {
  const _BoardColumn({required this.title, required this.count, required this.accent, required this.surface, required this.radius});

  final String title;
  final int count;
  final Color accent;
  final Color surface;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Color.lerp(surface, accent, .04), borderRadius: BorderRadius.circular(radius + 6), border: Border.all(color: accent.withOpacity(.16))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)), const SizedBox(width: 7), Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))), Text('$count', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 11))]),
          const SizedBox(height: 10),
          _PreviewBoardTask(title: 'Mobile UI polish', accent: accent, tall: true),
          const SizedBox(height: 8),
          _PreviewBoardTask(title: 'Firebase sync', accent: accent),
        ],
      ),
    );
  }
}

class _PreviewBoardTask extends StatelessWidget {
  const _PreviewBoardTask({required this.title, required this.accent, this.tall = false});
  final String title;
  final Color accent;
  final bool tall;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: tall ? 76 : 58),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.025), blurRadius: 12, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: tall ? .64 : .38, minHeight: 5, color: accent, backgroundColor: accent.withOpacity(.10))),
      ]),
    );
  }
}

class _NotificationsPreview extends StatelessWidget {
  const _NotificationsPreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    return Column(
      children: [
        _BasePreviewCard(title: 'New task assigned', subtitle: 'API integration was assigned to you.', trailing: 'Now', accent: accent, surface: surface, radius: radius, padding: padding),
        _BasePreviewCard(title: 'Deadline reminder', subtitle: 'QA checklist is due today.', trailing: '2h', accent: Colors.orange, surface: surface, radius: radius, padding: padding),
      ],
    );
  }
}




class _DesignerProfileActionButton extends StatelessWidget {
  const _DesignerProfileActionButton({required this.label, required this.color, this.filled = false});

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: filled ? color : color.withOpacity(.28)),
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: filled ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _DesignerSettingsPreview extends StatelessWidget {
  const _DesignerSettingsPreview({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: AppTheme.cardAlt, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppTheme.border)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                _DesignerTextBadge(label: 'SET', color: accent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Settings', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                      SizedBox(height: 2),
                      Text('Notification alert controls', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 10.5)),
                    ],
                  ),
                ),
                Text('⌃', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 300;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _DesignerTextBadge(label: 'AL', color: accent),
                        const SizedBox(width: 9),
                        const Expanded(child: Text('Notification alert settings', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(color: accent.withOpacity(.09), borderRadius: BorderRadius.circular(99), border: Border.all(color: accent.withOpacity(.16))),
                                child: Text('Emergency alarm', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 9.5)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (compact) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(color: accent.withOpacity(.09), borderRadius: BorderRadius.circular(99), border: Border.all(color: accent.withOpacity(.16))),
                        child: Text('Emergency alarm', style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 9.5)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _DesignerMiniSettingsLine(accent: accent, title: 'Enable Android notifications', value: 'Enable'),
                    const SizedBox(height: 8),
                    _DesignerMiniSettingsLine(accent: accent, title: 'Preferred alert sound', value: 'Emergency alarm'),
                    const SizedBox(height: 8),
                    _DesignerMiniSettingsLine(accent: accent, title: 'Assistant voice', value: 'On'),
                    const SizedBox(height: 8),
                    _DesignerMiniSettingsLine(accent: accent, title: 'Display window', value: 'Current month'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DesignerMiniSettingsLine extends StatelessWidget {
  const _DesignerMiniSettingsLine({required this.accent, required this.title, required this.value});

  final Color accent;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 10.5))),
        const SizedBox(width: 8),
        Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 10.5)))),
      ],
    );
  }
}

class _DesignerSettingsRow extends StatelessWidget {
  const _DesignerSettingsRow({required this.label, required this.title, required this.color});

  final String label;
  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [
        _DesignerTextBadge(label: label, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12))),
        Text('›', style: TextStyle(color: color.withOpacity(.70), fontWeight: FontWeight.w900, fontSize: 16)),
      ]),
    );
  }
}

class _DesignerTextBadge extends StatelessWidget {
  const _DesignerTextBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      constraints: const BoxConstraints(minWidth: 24),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(.22))),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 9, height: 1)),
    );
  }
}

class _CalendarDesignerPreview extends StatelessWidget {
  const _CalendarDesignerPreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    const deadline = Color(0xFFB98226);
    const assigned = Color(0xFF4B73A6);
    const meeting = Color(0xFF7455A3);
    final labelDays = <int, List<_CalendarPreviewLabel>>{};
    final markedDays = <int>{16, 17, 18, 19, 22, 23, 24, 25, 26, 29};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(radius), border: Border.all(color: AppTheme.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text('June 2026', style: TextStyle(color: AppTheme.navy, fontWeight: FontWeight.w900, fontSize: 16))),
                _MiniTag(text: 'clean dates', color: accent),
              ]),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1,
                children: [
                  for (final day in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Center(child: Text(day, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w900, fontSize: 10))),
                  for (var day = 8; day <= 30; day++) _CalendarPreviewDay(day: day, selected: day == 24, today: day == 18, marked: markedDays.contains(day), accent: accent, labels: labelDays[day] ?? const []),
                ],
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MiniTag(text: 'All 6', color: accent),
            const _MiniTag(text: 'Deadlines 2', color: deadline),
            const _MiniTag(text: 'Assigned 3', color: assigned),
            const _MiniTag(text: 'Meetings 1', color: meeting),
          ],
        ),
        const SizedBox(height: 12),
        _BasePreviewCard(title: 'Deadlines', subtitle: 'Submit UI sprint review • due first', trailing: '2', accent: deadline, surface: surface, radius: radius, padding: padding),
        _BasePreviewCard(title: 'Assigned tasks', subtitle: 'Fix task card responsive layout', trailing: '3', accent: assigned, surface: surface, radius: radius, padding: padding),
      ],
    );
  }
}

class _CalendarPreviewLabel {
  const _CalendarPreviewLabel(this.label, this.background, this.textColor, this.borderColor);
  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;
}

class _CalendarPreviewDay extends StatelessWidget {
  const _CalendarPreviewDay({required this.day, required this.selected, required this.today, required this.marked, required this.accent, required this.labels});

  final int day;
  final bool selected;
  final bool today;
  final bool marked;
  final Color accent;
  final List<_CalendarPreviewLabel> labels;

  @override
  Widget build(BuildContext context) {
    final eventMarked = marked || labels.isNotEmpty;
    final fill = selected ? accent : eventMarked ? accent.withOpacity(.12) : today ? accent.withOpacity(.10) : Colors.transparent;
    final textColor = selected ? Colors.white : AppTheme.navy;
    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: selected ? accent : today || eventMarked ? accent.withOpacity(.24) : Colors.transparent, width: selected ? 1.6 : 1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: labels.isEmpty ? Alignment.center : const Alignment(0, -.28),
            child: Text('$day', style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 10)),
          ),
          if (labels.isNotEmpty)
            Align(
              alignment: const Alignment(0, .62),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < labels.take(3).length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      _CalendarPreviewChip(data: labels[i]),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarPreviewChip extends StatelessWidget {
  const _CalendarPreviewChip({required this.data});
  final _CalendarPreviewLabel data;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      constraints: const BoxConstraints(minWidth: 14),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(color: data.background, borderRadius: BorderRadius.circular(4), border: Border.all(color: data.borderColor, width: .7)),
      child: Text(data.label, style: TextStyle(color: data.textColor, fontWeight: FontWeight.w900, fontSize: 7, height: 1)),
    );
  }
}

class _CalendarPreviewLegend extends StatelessWidget {
  const _CalendarPreviewLegend({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        height: 16,
        constraints: const BoxConstraints(minWidth: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(5), border: Border.all(color: color.withOpacity(.28))),
        child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 9, height: 1)),
      ),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 10)),
    ]);
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({required this.design, required this.accent, required this.surface});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final radius = design.cardRadius.toDouble();
    final padding = design.cardPadding.toDouble();
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(radius), border: Border.all(color: AppTheme.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 30, backgroundColor: accent.withOpacity(.12), child: Icon(Icons.person_rounded, color: accent, size: 31)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Darshan Employee', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900)),
                        SizedBox(height: 4),
                        Text('Developer • Web Development', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _BasePreviewCard(title: 'Online status', subtitle: 'Managers can see active status.', trailing: 'On', accent: accent, surface: surface, radius: 18, padding: 10),
              const SizedBox(height: 8),
              _BasePreviewCard(title: 'Availability', subtitle: 'Available for new work.', trailing: 'On', accent: accent, surface: surface, radius: 18, padding: 10),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (context, constraints) {
                final buttonWidth = constraints.maxWidth > 330 ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: buttonWidth, child: _DesignerProfileActionButton(label: 'Edit profile', color: accent, filled: true)),
                    SizedBox(width: buttonWidth, child: _DesignerProfileActionButton(label: 'Copy log', color: accent)),
                    SizedBox(width: buttonWidth, child: _DesignerProfileActionButton(label: 'Crashlytics Test', color: accent)),
                    SizedBox(width: buttonWidth, child: _DesignerProfileActionButton(label: 'Logout', color: accent, filled: true)),
                  ],
                );
              }),
              const SizedBox(height: 12),
              _DesignerSettingsPreview(accent: accent),
            ],
          ),
        ),
        _BasePreviewCard(title: 'Assigned scope', subtitle: '4 projects • 14 tasks • scoped access', trailing: 'Open', accent: accent, surface: surface, radius: radius, padding: padding),
        _BasePreviewCard(title: 'Role', subtitle: 'Developer • Web Development', trailing: 'Team', accent: accent, surface: surface, radius: radius, padding: padding),
        _BasePreviewCard(title: 'Company', subtitle: 'Company Workspace • Remote team', trailing: 'Active', accent: accent, surface: surface, radius: radius, padding: padding),
      ],
    );
  }
}

class _HeroPreviewCard extends StatelessWidget {
  const _HeroPreviewCard({required this.section, required this.accent, required this.radius, required this.padding});

  final Map<String, dynamic> section;
  final Color accent;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding + 2),
      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(radius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section['title']?.toString() ?? 'My Work', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(section['subtitle']?.toString() ?? 'Today overview', style: TextStyle(color: Colors.white.withOpacity(.82), fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: const [_WhitePill(text: '7 open tasks'), _WhitePill(text: '82% sprint')]),
        ],
      ),
    );
  }
}

class _BasePreviewCard extends StatelessWidget {
  const _BasePreviewCard({required this.title, required this.subtitle, required this.trailing, required this.accent, required this.surface, required this.radius, required this.padding});

  final String title;
  final String subtitle;
  final String trailing;
  final Color accent;
  final Color surface;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(radius), border: Border.all(color: AppTheme.border)),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: accent.withOpacity(.10), borderRadius: BorderRadius.circular(999)),
            child: Text(trailing, style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _TaskListPreviewCard extends StatelessWidget {
  const _TaskListPreviewCard({required this.section, required this.accent, required this.surface, required this.radius, required this.padding, required this.fields, required this.variant, required this.actions});

  final Map<String, dynamic> section;
  final Color accent;
  final Color surface;
  final double radius;
  final double padding;
  final List<String> fields;
  final String variant;
  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    final compact = variant == 'compactCard';
    final minimal = variant == 'minimalCard';
    final advanced = variant == 'advancedProgressCard';
    final borderColor = variant == 'timelineCard' ? accent.withOpacity(.42) : AppTheme.border;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? (padding - 2).clamp(8, 32).toDouble() : padding),
      decoration: BoxDecoration(
        color: minimal ? Colors.transparent : surface,
        borderRadius: BorderRadius.circular(compact ? (radius - 4).clamp(10, 40).toDouble() : radius),
        border: Border.all(color: borderColor),
        boxShadow: minimal ? null : [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: advanced ? 22 : 12, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (variant == 'timelineCard') Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: accent.withOpacity(.28), blurRadius: 10)])),
          Expanded(child: Text(section['title']?.toString() ?? 'My Tasks', style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 12 : 14))),
          _MiniTag(text: _variantLabel(variant), color: accent),
        ]),
        const SizedBox(height: 10),
        _TaskRowPreview(title: 'API integration', status: 'Active', accent: accent, fields: fields, variant: variant, actions: actions),
        SizedBox(height: compact ? 6 : 8),
        _TaskRowPreview(title: 'QA checklist', status: 'Review', accent: Colors.orange, fields: fields, variant: variant, actions: actions),
      ]),
    );
  }
}

class _TaskRowPreview extends StatelessWidget {
  const _TaskRowPreview({required this.title, required this.status, required this.accent, required this.fields, required this.variant, required this.actions});

  final String title;
  final String status;
  final Color accent;
  final List<String> fields;
  final String variant;
  final List<String> actions;

  @override
  Widget build(BuildContext context) {
    final compact = variant == 'compactCard';
    final minimal = variant == 'minimalCard';
    final timeline = variant == 'timelineCard';
    final progress = variant == 'progressCard' || variant == 'advancedProgressCard';
    final advanced = variant == 'advancedProgressCard';
    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        color: minimal ? Colors.transparent : AppTheme.cardAlt,
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(color: timeline ? accent.withOpacity(.30) : AppTheme.border.withOpacity(minimal ? 1 : .0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (timeline) ...[
            Column(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              Container(width: 2, height: 42, margin: const EdgeInsets.only(top: 4), color: accent.withOpacity(.22)),
            ]),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (fields.contains('taskTitle')) Text(title, style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 11 : 12)),
              if (fields.contains('taskTitle')) const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (fields.contains('projectName')) const _MiniTag(text: 'Mobile App'),
                if (fields.contains('status') || fields.contains('statusTag')) _MiniTag(text: status, color: accent),
                if (fields.contains('priority')) const _MiniTag(text: 'High', color: Colors.redAccent),
                if (fields.contains('deadlineTimer')) const _MiniTag(text: '4h 20m', color: Colors.orange),
                if (fields.contains('commentsCount')) const _MiniTag(text: '3 comments'),
                if (fields.contains('filesCount') || fields.contains('attachmentsCount')) const _MiniTag(text: '2 files'),
                if (fields.contains('progress')) const _MiniTag(text: '64%'),
              ]),
              if (progress) ...[
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: .64, minHeight: compact ? 6 : 8, color: accent, backgroundColor: accent.withOpacity(.12))),
              ],
              if (advanced && actions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: actions.take(3).map((action) => _MiniTag(text: _label(action), color: accent)).toList()),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}


class _ProjectProgressPreviewCard extends StatelessWidget {
  const _ProjectProgressPreviewCard({required this.section, required this.accent, required this.surface, required this.radius, required this.padding, required this.fields, required this.variant});

  final Map<String, dynamic> section;
  final Color accent;
  final Color surface;
  final double radius;
  final double padding;
  final List<String> fields;
  final String variant;

  @override
  Widget build(BuildContext context) {
    final compact = variant == 'compactCard';
    final minimal = variant == 'minimalCard';
    final timeline = variant == 'timelineCard';
    final advanced = variant == 'advancedProgressCard';
    final showProgress = variant == 'progressCard' || variant == 'advancedProgressCard' || fields.contains('progress');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? (padding - 2).clamp(8, 32).toDouble() : padding),
      decoration: BoxDecoration(
        color: minimal ? Colors.transparent : surface,
        borderRadius: BorderRadius.circular(compact ? (radius - 4).clamp(10, 40).toDouble() : radius),
        border: Border.all(color: timeline ? accent.withOpacity(.42) : AppTheme.border),
        boxShadow: minimal ? null : [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: advanced ? 24 : 14, offset: const Offset(0, 8))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (timeline) ...[
          Container(width: 4, height: 92, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(section['title']?.toString() ?? 'Project Progress', style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 13 : 14))),
              _MiniTag(text: _variantLabel(variant), color: accent),
            ]),
            const SizedBox(height: 10),
            if (fields.contains('projectName')) const Text('Employee Workspace', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            if (advanced && fields.contains('description')) const Padding(padding: EdgeInsets.only(top: 5), child: Text('SDUI production-ready employee workspace.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11))),
            if (showProgress) ...[
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: .82, minHeight: compact ? 7 : 9, color: accent, backgroundColor: accent.withOpacity(.12))),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (fields.contains('taskCount')) const _MiniTag(text: '12 tasks'),
              if (fields.contains('completedTaskCount')) const _MiniTag(text: '8 done', color: Colors.green),
              if (fields.contains('progress')) const _MiniTag(text: '82%'),
              if (fields.contains('deadline')) const _MiniTag(text: 'Due Fri', color: Colors.orange),
              if (fields.contains('status') || fields.contains('statusTag')) _MiniTag(text: 'Active', color: accent),
              if (fields.contains('priority')) const _MiniTag(text: 'High', color: Colors.redAccent),
              if (fields.contains('team') || fields.contains('teamCount')) const _MiniTag(text: '3 teams'),
            ]),
          ]),
        ),
      ]),
    );
  }
}



class _ImportedJsonScreenPreview extends StatelessWidget {
  const _ImportedJsonScreenPreview({
    required this.screenJson,
    required this.design,
    required this.previewTab,
    required this.accent,
    required this.surface,
  });

  final Map<String, dynamic> screenJson;
  final MobileUiDesign design;
  final String previewTab;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return _StrictJsonRenderer(
      data: screenJson,
      design: design,
      previewTab: previewTab,
      accent: accent,
      surface: surface,
      isRoot: true,
    );
  }
}

class _StrictJsonRenderer extends StatelessWidget {
  const _StrictJsonRenderer({
    required this.data,
    required this.design,
    required this.previewTab,
    required this.accent,
    required this.surface,
    this.isRoot = false,
  });

  final dynamic data;
  final MobileUiDesign design;
  final String previewTab;
  final Color accent;
  final Color surface;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    if (data is List) {
      final items = (data as List).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items
            .map((item) => _StrictJsonRenderer(data: item, design: design, previewTab: previewTab, accent: accent, surface: surface))
            .toList(),
      );
    }
    if (data is Map) {
      return _StrictJsonObjectRenderer(
        data: (data as Map).map((key, value) => MapEntry(key.toString(), value)),
        design: design,
        previewTab: previewTab,
        accent: accent,
        surface: surface,
        isRoot: isRoot,
      );
    }
    if (data == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(data.toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _StrictJsonObjectRenderer extends StatelessWidget {
  const _StrictJsonObjectRenderer({
    required this.data,
    required this.design,
    required this.previewTab,
    required this.accent,
    required this.surface,
    required this.isRoot,
  });

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final String previewTab;
  final Color accent;
  final Color surface;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final rootPayload = isRoot ? _rootPayload(data, previewTab) : data;
    final type = _componentType(rootPayload);
    final rootChildren = _orderedChildren(rootPayload, isRoot: isRoot);

    if (isRoot) {
      if (rootChildren.isNotEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rootChildren
              .map((child) => _StrictJsonRenderer(data: child, design: design, previewTab: previewTab, accent: accent, surface: surface))
              .toList(),
        );
      }
      return _StrictJsonComponentCard(data: rootPayload, type: type, design: design, accent: accent, surface: surface);
    }

    if (_isTextType(type)) {
      return _StrictTextBlock(data: rootPayload, accent: accent);
    }
    if (_isSpacerType(type)) {
      return SizedBox(height: _jsonDouble(rootPayload, const ['height', 'size'], fallback: 12));
    }
    if (_isDividerType(type)) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1));
    }
    if (_isProgressType(type)) {
      return _StrictProgressCard(data: rootPayload, design: design, accent: accent, surface: surface);
    }
    if (_isNavType(type)) {
      return _StrictNavCard(data: rootPayload, design: design, accent: accent, surface: surface);
    }
    if (_isCalendarType(type)) {
      return _CalendarDesignerPreview(design: design, accent: accent, surface: surface);
    }
    if (_isListType(type)) {
      return _StrictListCard(data: rootPayload, design: design, accent: accent, surface: surface);
    }
    if (_isHeroType(type)) {
      return _StrictHeroCard(data: rootPayload, design: design, accent: accent);
    }
    return _StrictJsonComponentCard(data: rootPayload, type: type, design: design, accent: accent, surface: surface);
  }

  static Map<String, dynamic> _rootPayload(Map<String, dynamic> json, String previewTab) {
    final screens = _jsonMap(json['screens']);
    if (screens != null) {
      final exact = _jsonMap(screens[previewTab]);
      if (exact != null) return exact;
    }
    final screenLayouts = _jsonMap(json['screenLayouts']);
    if (screenLayouts != null) {
      final exact = _jsonMap(screenLayouts[previewTab]);
      if (exact != null) return exact;
    }
    final body = _jsonMap(json['body']);
    if (body != null && (json.length <= 3 || json.containsKey('screen'))) return body;
    return json;
  }
}

class _StrictHeroCard extends StatelessWidget {
  const _StrictHeroCard({required this.data, required this.design, required this.accent});

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final style = _jsonMap(data['style']);
    final background = _jsonColor(data, const ['background', 'backgroundColor', 'color'], fallback: _jsonColor(style, const ['background', 'backgroundColor', 'color'], fallback: accent));
    final radius = _jsonDouble(data, const ['radius', 'borderRadius', 'cardRadius'], fallback: design.cardRadius.toDouble());
    final padding = _jsonDouble(data, const ['padding', 'cardPadding'], fallback: design.cardPadding.toDouble() + 2);
    final title = _jsonTitle(data, fallback: '');
    final subtitle = _jsonSubtitle(data);
    final children = _orderedChildren(data);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(.86), fontWeight: FontWeight.w700, fontSize: 12)),
        ],
        if (children.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...children.map((child) => _StrictJsonRenderer(data: child, design: design, previewTab: '', accent: Colors.white, surface: Colors.white.withOpacity(.14))),
        ] else ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: _primitiveLabels(data).map((pill) => _WhitePill(text: pill)).toList()),
        ],
      ]),
    );
  }
}

class _StrictProgressCard extends StatelessWidget {
  const _StrictProgressCard({required this.data, required this.design, required this.accent, required this.surface});

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final value = (_jsonDouble(data, const ['value', 'progress', 'percent', 'percentage'], fallback: 0) / (_jsonDouble(data, const ['percent', 'percentage'], fallback: -1) > 1 ? 100 : 1)).clamp(0.0, 1.0).toDouble();
    final title = _jsonTitle(data, fallback: 'Progress');
    final subtitle = _jsonSubtitle(data);
    final color = _jsonColor(data, const ['accent', 'color', 'progressColor'], fallback: accent);
    return _StrictShellCard(
      data: data,
      design: design,
      surface: surface,
      accent: color,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: value, minHeight: 9, color: color)),
        const SizedBox(height: 8),
        Text('${(value * 100).round()}%', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 12)),
      ]),
    );
  }
}

class _StrictNavCard extends StatelessWidget {
  const _StrictNavCard({required this.data, required this.design, required this.accent, required this.surface});

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final rawTabs = _jsonList(data['tabs']) ?? _jsonList(data['items']) ?? const <dynamic>[];
    final tabs = rawTabs.map((item) {
      if (item is Map) return (item['label'] ?? item['title'] ?? item['id'] ?? item['key'] ?? '').toString();
      return item.toString();
    }).where((item) => item.trim().isNotEmpty).toList();

    return _StrictShellCard(
      data: data,
      design: design,
      surface: surface,
      accent: accent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: tabs.take(5).map((tab) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_tabIcon(tab), color: accent, size: 18),
            const SizedBox(height: 3),
            Text(_label(tab), style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 10)),
          ]);
        }).toList(),
      ),
    );
  }
}

class _StrictListCard extends StatelessWidget {
  const _StrictListCard({required this.data, required this.design, required this.accent, required this.surface});

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final title = _jsonTitle(data, fallback: '');
    final subtitle = _jsonSubtitle(data);
    final items = _jsonItemMaps(data);
    return _StrictShellCard(
      data: data,
      design: design,
      surface: surface,
      accent: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
        if (items.isNotEmpty) const SizedBox(height: 10),
        ...items.take(8).map((item) => _StrictJsonRow(data: item, accent: accent)),
        if (items.isEmpty) Wrap(spacing: 6, runSpacing: 6, children: _primitiveLabels(data).map((pill) => _MiniTag(text: pill, color: accent)).toList()),
      ]),
    );
  }
}

class _StrictJsonComponentCard extends StatelessWidget {
  const _StrictJsonComponentCard({required this.data, required this.type, required this.design, required this.accent, required this.surface});

  final Map<String, dynamic> data;
  final String type;
  final MobileUiDesign design;
  final Color accent;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final title = _jsonTitle(data, fallback: type.isEmpty ? 'JSON block' : _label(type));
    final subtitle = _jsonSubtitle(data);
    final children = _orderedChildren(data);
    return _StrictShellCard(
      data: data,
      design: design,
      surface: surface,
      accent: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
        if (children.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...children.map((child) => _StrictJsonRenderer(data: child, design: design, previewTab: '', accent: accent, surface: surface)),
        ] else ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: _primitiveLabels(data).map((pill) => _MiniTag(text: pill, color: accent)).toList()),
        ],
      ]),
    );
  }
}

class _StrictShellCard extends StatelessWidget {
  const _StrictShellCard({required this.data, required this.design, required this.surface, required this.accent, required this.child});

  final Map<String, dynamic> data;
  final MobileUiDesign design;
  final Color surface;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = _jsonMap(data['style']);
    final background = _jsonColor(data, const ['background', 'backgroundColor', 'color'], fallback: _jsonColor(style, const ['background', 'backgroundColor', 'color'], fallback: surface));
    final radius = _jsonDouble(data, const ['radius', 'borderRadius', 'cardRadius'], fallback: design.cardRadius.toDouble());
    final padding = _jsonDouble(data, const ['padding', 'cardPadding'], fallback: design.cardPadding.toDouble());
    final borderColor = _jsonColor(data, const ['borderColor'], fallback: AppTheme.border);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius), border: Border.all(color: borderColor)),
      child: child,
    );
  }
}

class _StrictTextBlock extends StatelessWidget {
  const _StrictTextBlock({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final value = (data['text'] ?? data['title'] ?? data['label'] ?? data['value'] ?? '').toString();
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final size = _jsonDouble(data, const ['fontSize', 'size'], fallback: 14);
    final color = _jsonColor(data, const ['color', 'textColor'], fallback: const Color(0xFF111827));
    final weight = (data['fontWeight']?.toString() ?? data['weight']?.toString() ?? '').toLowerCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        value,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight.contains('bold') || weight.contains('w700') || weight.contains('900') ? FontWeight.w900 : FontWeight.w700),
      ),
    );
  }
}

class _StrictJsonRow extends StatelessWidget {
  const _StrictJsonRow({required this.data, required this.accent});

  final Map<String, dynamic> data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final title = _jsonTitle(data, fallback: '');
    final subtitle = _jsonSubtitle(data);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.cardAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty) Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _primitiveLabels(data).map((pill) => _MiniTag(text: pill, color: accent)).toList()),
      ]),
    );
  }
}

String _componentType(Map<String, dynamic> data) => (data['type'] ?? data['widget'] ?? data['component'] ?? data['kind'] ?? data['id'] ?? '').toString();
bool _isHeroType(String type) => type.toLowerCase().contains('hero') || type.toLowerCase().contains('summary');
bool _isTextType(String type) => type.toLowerCase() == 'text' || type.toLowerCase() == 'label' || type.toLowerCase() == 'title';
bool _isSpacerType(String type) => type.toLowerCase() == 'spacer' || type.toLowerCase() == 'gap';
bool _isDividerType(String type) => type.toLowerCase() == 'divider' || type.toLowerCase() == 'line';
bool _isProgressType(String type) => type.toLowerCase().contains('progress') || type.toLowerCase().contains('meter');
bool _isNavType(String type) => type.toLowerCase().contains('nav') || type.toLowerCase().contains('tabbar') || type.toLowerCase().contains('tabs');
bool _isListType(String type) => type.toLowerCase().contains('list') || type.toLowerCase().contains('tasks') || type.toLowerCase().contains('projects');
bool _isCalendarType(String type) {
  final compact = type.replaceAll(RegExp(r'[_\s-]+'), '').toLowerCase();
  return compact == 'calendar' ||
      compact == 'calendarview' ||
      compact == 'calendardeadlines' ||
      compact == 'calendarfiltersections' ||
      compact == 'calendarlabelfiltersections' ||
      compact == 'calendarthinsquirclelabels' ||
      compact == 'deadlinefirstthinsquirclelabeledcalendar';
}

List<dynamic> _orderedChildren(Map<String, dynamic> data, {bool isRoot = false}) {
  final result = <dynamic>[];
  for (final key in <String>['header', 'hero', 'body', 'content', 'layout']) {
    final value = data[key];
    if (value is Map) {
      final childMap = value.map((k, v) => MapEntry(k.toString(), v));
      final nested = _orderedChildren(childMap);
      if (nested.isNotEmpty && (key == 'layout' || key == 'body' || key == 'content')) {
        result.addAll(nested);
      } else if (!_isMetadataOnly(childMap)) {
        result.add(childMap);
      }
    } else if (value is List) {
      result.addAll(value);
    }
  }
  for (final key in <String>['sections', 'components', 'widgets', 'blocks', 'cards', 'children', 'rows']) {
    final value = data[key];
    if (value is List) result.addAll(value);
  }
  if (isRoot) {
    final bottomNav = _jsonMap(data['bottomNav']) ?? _jsonMap(data['navigation']);
    if (bottomNav != null) result.add(bottomNav.containsKey('type') ? bottomNav : <String, dynamic>{'type': 'bottomNav', ...bottomNav});
  }
  return result.map((item) {
    if (item is Map) return item.map((k, v) => MapEntry(k.toString(), v));
    return item;
  }).where((item) {
    if (item is Map<String, dynamic>) return !_isMetadataOnly(item);
    return item != null;
  }).toList();
}

bool _isMetadataOnly(Map<String, dynamic> value) {
  final renderKeys = value.keys.where((key) => !<String>{'version', 'enabled', 'theme', 'style', 'updatedAt', 'updatedBy', 'templateName', 'screen', 'screens', 'screenLayouts'}.contains(key)).toList();
  return renderKeys.isEmpty;
}

List<Map<String, dynamic>> _jsonItemMaps(Map<String, dynamic> data) {
  for (final key in <String>['items', 'tasks', 'projects', 'rows', 'data', 'children']) {
    final value = data[key];
    if (value is List) {
      return value.map((item) {
        if (item is Map) return item.map((k, v) => MapEntry(k.toString(), v));
        return <String, dynamic>{'title': item.toString()};
      }).toList();
    }
  }
  return const <Map<String, dynamic>>[];
}

String _jsonTitle(Map<String, dynamic> data, {required String fallback}) {
  return (data['title'] ?? data['name'] ?? data['label'] ?? data['taskTitle'] ?? data['projectName'] ?? data['heading'] ?? fallback).toString();
}

String _jsonSubtitle(Map<String, dynamic> data) {
  return (data['subtitle'] ?? data['description'] ?? data['caption'] ?? data['status'] ?? '').toString();
}

List<String> _primitiveLabels(Map<String, dynamic> data) {
  final blocked = <String>{
    'children',
    'sections',
    'components',
    'widgets',
    'blocks',
    'cards',
    'items',
    'tasks',
    'projects',
    'rows',
    'data',
    'layout',
    'body',
    'content',
    'style',
    'theme',
    'type',
    'widget',
    'component',
    'kind',
    'id',
    'title',
    'name',
    'label',
    'subtitle',
    'description',
  };
  final pills = <String>[];
  for (final entry in data.entries) {
    if (blocked.contains(entry.key)) continue;
    final value = entry.value;
    if (value is Map || value is List || value == null) continue;
    final raw = value.toString();
    final text = '${_label(entry.key)}: $raw';
    pills.add(text.length <= 34 ? text : '${_label(entry.key)}: ${raw.substring(0, raw.length < 22 ? raw.length : 22)}…');
    if (pills.length >= 6) break;
  }
  return pills;
}

Map<String, dynamic>? _jsonMap(dynamic value) {
  if (value is Map) return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
  return null;
}

List<dynamic>? _jsonList(dynamic value) {
  if (value is List) return value;
  return null;
}

bool? _jsonBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
  }
  return null;
}

double _jsonValueDouble(dynamic value, {required double fallback}) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value.replaceAll('px', '').trim());
    if (parsed != null) return parsed;
  }
  return fallback;
}

double _jsonDouble(Map<String, dynamic>? data, List<String> keys, {required double fallback}) {
  if (data == null) return fallback;
  for (final key in keys) {
    final value = data[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll('px', '').trim());
      if (parsed != null) return parsed;
    }
  }
  return fallback;
}

Color _jsonColor(Map<String, dynamic>? data, List<String> keys, {required Color fallback}) {
  if (data == null) return fallback;
  for (final key in keys) {
    final value = data[key];
    if (value is int) return Color(value);
    if (value is String && value.trim().isNotEmpty) return _hexColor(value, fallback: fallback);
  }
  return fallback;
}

EdgeInsets _jsonInsets(dynamic value, {required EdgeInsets fallback}) {
  if (value is num) return EdgeInsets.all(value.toDouble());
  if (value is String) {
    final parsed = double.tryParse(value.replaceAll('px', '').trim());
    if (parsed != null) return EdgeInsets.all(parsed);
  }
  if (value is Map) {
    double read(String key, double fallbackValue) {
      final item = value[key];
      if (item is num) return item.toDouble();
      if (item is String) return double.tryParse(item.replaceAll('px', '').trim()) ?? fallbackValue;
      return fallbackValue;
    }
    final all = read('all', double.nan);
    if (!all.isNaN) return EdgeInsets.all(all);
    return EdgeInsets.fromLTRB(
      read('left', read('horizontal', fallback.left)),
      read('top', read('vertical', fallback.top)),
      read('right', read('horizontal', fallback.right)),
      read('bottom', read('vertical', fallback.bottom)),
    );
  }
  return fallback;
}

class _PreviewBottomNav extends StatelessWidget {
  const _PreviewBottomNav({required this.design, required this.accent, required this.surface, required this.activeTab});

  final MobileUiDesign design;
  final Color accent;
  final Color surface;
  final String activeTab;

  @override
  Widget build(BuildContext context) {
    final floating = design.bottomNav['style']?.toString() != 'standard';
    final tabs = design.bottomTabs.where((tab) => tab != 'notifications').take(5).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(floating ? 18 : 0, 8, floating ? 18 : 0, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(floating ? 26 : 0), border: Border.all(color: AppTheme.border)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: tabs.map((tab) {
            final active = tab == activeTab;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(_tabIcon(tab), color: active ? accent : AppTheme.muted, size: 19),
              const SizedBox(height: 2),
              Text(_label(tab), style: TextStyle(color: active ? accent : AppTheme.muted, fontWeight: FontWeight.w800, fontSize: 10)),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: chipColor.withOpacity(.09), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: TextStyle(color: chipColor, fontSize: 10, fontWeight: FontWeight.w900)),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

String _label(String value) {
  return switch (value) {
    'home' => 'Home',
    'tasks' => 'Tasks',
    'taskTimeline' => 'Task Timeline',
    'projects' => 'Projects',
    'board' => 'Board',
    'notifications' => 'Inbox',
    'calendar' => 'Calendar',
    'meetings' => 'Meetings',
    'profile' => 'Profile',
    'deadlineTimer' => 'Deadline timer',
    'myOpenTasks' => 'My open tasks',
    'todayTasks' => 'Today tasks',
    'projectProgress' => 'Project progress',
    'onlineStatus' => 'Online status',
    'workSummary' => 'Work summary',
    'projectName' => 'Project name',
    'taskTitle' => 'Task title',
    'status' => 'Status',
    'priority' => 'Priority',
    'progress' => 'Progress',
    'taskCount' => 'Task count',
    'deadline' => 'Deadline',
    'team' => 'Team',
    'teamCount' => 'Team count',
    'completedTaskCount' => 'Completed task count',
    'statusTag' => 'Status tag',
    'description' => 'Description',
    'assignedBy' => 'Assigned by',
    'commentsCount' => 'Comments count',
    'filesCount' => 'Files count',
    'attachmentsCount' => 'Attachments count',
    'assigneeCount' => 'Assignee count',
    'changeStatus' => 'Change status',
    'comment' => 'Comment',
    'uploadFile' => 'Upload file',
    'openDetails' => 'Open details',
    'updateProfile' => 'Update profile',
    'setAvailability' => 'Availability',
    'setPresence' => 'Online presence',
    _ => value,
  };
}

List<String> _stringList(dynamic value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const <String>[];
}

List<String> _actionOptions(String cardKey) {
  return cardKey == 'taskCard'
      ? const <String>['changeStatus', 'comment', 'uploadFile']
      : const <String>['openDetails'];
}

String _cardVariant(Map<String, dynamic> card, String fallback) {
  final raw = card['variant']?.toString().trim() ?? '';
  return MobileUiDesign.cardVariants.contains(raw) ? raw : fallback;
}

String _variantLabel(String value) {
  return switch (value) {
    'modernCard' => 'Modern Card',
    'minimalCard' => 'Minimal Card',
    'compactCard' => 'Compact Card',
    'timelineCard' => 'Timeline Card',
    'progressCard' => 'Progress Card',
    'advancedProgressCard' => 'Advanced Progress Card',
    'nativeListRow' => 'Native List Row',
    'editorialProgressCard' => 'Editorial Progress Card',
    'editorialStatusCard' => 'Editorial Status Card',
    'editorialProjectRow' => 'Editorial Project Row',
    'darkEditorialHero' => 'Dark Editorial Hero',
    'smallMetricTile' => 'Small Metric Tile',
    'softProgressCard' => 'Soft Progress Card',
    _ => value,
  };
}

IconData _tabIcon(String value) {
  return switch (MobileUiSupportRegistry.canonicalScreen(value)) {
    'home' => Icons.home_rounded,
    'tasks' => Icons.task_alt_rounded,
    'projects' => Icons.folder_rounded,
    'board' => Icons.view_kanban_rounded,
    'meetings' => Icons.video_call_rounded,
    'notifications' => Icons.notifications_rounded,
    'profile' => Icons.person_rounded,
    'taskMap' => Icons.location_on_outlined,
    'timeline' => Icons.schedule_rounded,
    'files' => Icons.folder_open_rounded,
    'calendar' => Icons.calendar_month_rounded,
    'teamMembers' => Icons.groups_rounded,
    'taskDetail' => Icons.assignment_rounded,
    'projectDetail' => Icons.folder_special_rounded,
    'meetingDetail' => Icons.video_camera_front_rounded,
    _ => Icons.circle_rounded,
  };
}

IconData _sectionIcon(String value) {
  return switch (value) {
    'workSummary' => Icons.dashboard_customize_rounded,
    'deadlineTimer' => Icons.timer_rounded,
    'myOpenTasks' => Icons.task_alt_rounded,
    'todayTasks' => Icons.today_rounded,
    'projectProgress' => Icons.donut_large_rounded,
    'onlineStatus' => Icons.circle_rounded,
    _ => Icons.widgets_rounded,
  };
}

Color _hexColor(String raw, {Color fallback = AppTheme.blue}) {
  try {
    var value = raw.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    return Color(int.parse(value, radix: 16));
  } catch (_) {
    return fallback;
  }
}
