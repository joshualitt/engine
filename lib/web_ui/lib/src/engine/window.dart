// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.10
part of engine;

/// When set to true, all platform messages will be printed to the console.
const bool _debugPrintPlatformMessages = false;

/// Requests that the browser schedule a frame.
///
/// This may be overridden in tests, for example, to pump fake frames.
ui.VoidCallback? scheduleFrameCallback;

typedef _JsSetUrlStrategy = void Function(JsUrlStrategy?);

/// A JavaScript hook to customize the URL strategy of a Flutter app.
//
// Keep this js name in sync with flutter_web_plugins. Find it at:
// https://github.com/flutter/flutter/blob/custom_location_strategy/packages/flutter_web_plugins/lib/src/navigation/js_url_strategy.dart
//
// TODO: Add integration test https://github.com/flutter/flutter/issues/66852
@JS('_flutter_web_set_location_strategy')
external set _jsSetUrlStrategy(_JsSetUrlStrategy? newJsSetUrlStrategy);

/// The Web implementation of [ui.Window].
class EngineWindow extends ui.Window {
  EngineWindow() {
    _addBrightnessMediaQueryListener();
    _addUrlStrategyListener();
  }

  @override
  double get devicePixelRatio =>
      _debugDevicePixelRatio ?? browserDevicePixelRatio;

  /// Returns device pixel ratio returned by browser.
  static double get browserDevicePixelRatio {
    double? ratio = html.window.devicePixelRatio as double?;
    // Guard against WebOS returning 0 and other browsers returning null.
    return (ratio == null || ratio == 0.0) ? 1.0 : ratio;
  }

  /// Overrides the default device pixel ratio.
  ///
  /// This is useful in tests to emulate screens of different dimensions.
  void debugOverrideDevicePixelRatio(double value) {
    _debugDevicePixelRatio = value;
  }

  double? _debugDevicePixelRatio;

  @override
  ui.Size get physicalSize {
    if (_physicalSize == null) {
      _computePhysicalSize();
    }
    assert(_physicalSize != null);
    return _physicalSize!;
  }

  /// Computes the physical size of the screen from [html.window].
  ///
  /// This function is expensive. It triggers browser layout if there are
  /// pending DOM writes.
  void _computePhysicalSize() {
    bool override = false;

    assert(() {
      if (webOnlyDebugPhysicalSizeOverride != null) {
        _physicalSize = webOnlyDebugPhysicalSizeOverride;
        override = true;
      }
      return true;
    }());

    if (!override) {
      double windowInnerWidth;
      double windowInnerHeight;
      final html.VisualViewport? viewport = html.window.visualViewport;
      if (viewport != null) {
        windowInnerWidth = viewport.width!.toDouble() * devicePixelRatio;
        windowInnerHeight = viewport.height!.toDouble() * devicePixelRatio;
      } else {
        windowInnerWidth = html.window.innerWidth! * devicePixelRatio;
        windowInnerHeight = html.window.innerHeight! * devicePixelRatio;
      }
      _physicalSize = ui.Size(
        windowInnerWidth,
        windowInnerHeight,
      );
    }
  }

  void computeOnScreenKeyboardInsets() {
    double windowInnerHeight;
    final html.VisualViewport? viewport = html.window.visualViewport;
    if (viewport != null) {
      windowInnerHeight = viewport.height!.toDouble() * devicePixelRatio;
    } else {
      windowInnerHeight = html.window.innerHeight! * devicePixelRatio;
    }
    final double bottomPadding = _physicalSize!.height - windowInnerHeight;
    _viewInsets =
        WindowPadding(bottom: bottomPadding, left: 0, right: 0, top: 0);
  }

  /// Uses the previous physical size and current innerHeight/innerWidth
  /// values to decide if a device is rotating.
  ///
  /// During a rotation the height and width values will (almost) swap place.
  /// Values can slightly differ due to space occupied by the browser header.
  /// For example the following values are collected for Pixel 3 rotation:
  ///
  /// height: 658 width: 393
  /// new height: 313 new width: 738
  ///
  /// The following values are from a changed caused by virtual keyboard.
  ///
  /// height: 658 width: 393
  /// height: 368 width: 393
  bool isRotation() {
    double height = 0;
    double width = 0;
    if (html.window.visualViewport != null) {
      height =
          html.window.visualViewport!.height!.toDouble() * devicePixelRatio;
      width = html.window.visualViewport!.width!.toDouble() * devicePixelRatio;
    } else {
      height = html.window.innerHeight! * devicePixelRatio;
      width = html.window.innerWidth! * devicePixelRatio;
    }

    // This method compares the new dimensions with the previous ones.
    // Return false if the previous dimensions are not set.
    if (_physicalSize != null) {
      // First confirm both height and width are effected.
      if (_physicalSize!.height != height && _physicalSize!.width != width) {
        // If prior to rotation height is bigger than width it should be the
        // opposite after the rotation and vice versa.
        if ((_physicalSize!.height > _physicalSize!.width && height < width) ||
            (_physicalSize!.width > _physicalSize!.height && width < height)) {
          // Rotation detected
          return true;
        }
      }
    }
    return false;
  }

  @override
  WindowPadding get viewInsets => _viewInsets;
  WindowPadding _viewInsets = ui.WindowPadding.zero as WindowPadding;

  /// Lazily populated and cleared at the end of the frame.
  ui.Size? _physicalSize;

  /// Overrides the value of [physicalSize] in tests.
  ui.Size? webOnlyDebugPhysicalSizeOverride;

  /// Handles the browser history integration to allow users to use the back
  /// button, etc.
  @visibleForTesting
  BrowserHistory get browserHistory {
    return _browserHistory ??=
        MultiEntriesBrowserHistory(urlStrategy: const HashUrlStrategy());
  }

  BrowserHistory? _browserHistory;

  Future<void> _useSingleEntryBrowserHistory() async {
    if (_browserHistory is SingleEntryBrowserHistory) {
      return;
    }
    final UrlStrategy? strategy = _browserHistory?.urlStrategy;
    await _browserHistory?.tearDown();
    _browserHistory = SingleEntryBrowserHistory(urlStrategy: strategy);
  }

  /// Lazily initialized when the `defaultRouteName` getter is invoked.
  ///
  /// The reason for the lazy initialization is to give enough time for the app to set [urlStrategy]
  /// in `lib/src/ui/initialization.dart`.
  String? _defaultRouteName;

  @override
  String get defaultRouteName {
    return _defaultRouteName ??= browserHistory.currentPath;
  }

  @override
  void scheduleFrame() {
    if (scheduleFrameCallback == null) {
      throw new Exception('scheduleFrameCallback must be initialized first.');
    }
    scheduleFrameCallback!();
  }

  @override
  ui.VoidCallback? get onTextScaleFactorChanged => _onTextScaleFactorChanged;
  ui.VoidCallback? _onTextScaleFactorChanged;
  Zone? _onTextScaleFactorChangedZone;
  @override
  set onTextScaleFactorChanged(ui.VoidCallback? callback) {
    _onTextScaleFactorChanged = callback;
    _onTextScaleFactorChangedZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnTextScaleFactorChanged() {
    _invoke(_onTextScaleFactorChanged, _onTextScaleFactorChangedZone);
  }

  @override
  ui.VoidCallback? get onPlatformBrightnessChanged =>
      _onPlatformBrightnessChanged;
  ui.VoidCallback? _onPlatformBrightnessChanged;
  Zone? _onPlatformBrightnessChangedZone;
  @override
  set onPlatformBrightnessChanged(ui.VoidCallback? callback) {
    _onPlatformBrightnessChanged = callback;
    _onPlatformBrightnessChangedZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnPlatformBrightnessChanged() {
    _invoke(_onPlatformBrightnessChanged, _onPlatformBrightnessChangedZone);
  }

  @override
  ui.VoidCallback? get onMetricsChanged => _onMetricsChanged;
  ui.VoidCallback? _onMetricsChanged;
  Zone _onMetricsChangedZone = Zone.root;
  @override
  set onMetricsChanged(ui.VoidCallback? callback) {
    _onMetricsChanged = callback;
    _onMetricsChangedZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnMetricsChanged() {
    if (window._onMetricsChanged != null) {
      _invoke(_onMetricsChanged, _onMetricsChangedZone);
    }
  }

  @override
  ui.VoidCallback? get onLocaleChanged => _onLocaleChanged;
  ui.VoidCallback? _onLocaleChanged;
  Zone? _onLocaleChangedZone;
  @override
  set onLocaleChanged(ui.VoidCallback? callback) {
    _onLocaleChanged = callback;
    _onLocaleChangedZone = Zone.current;
  }

  /// The locale used when we fail to get the list from the browser.
  static const _defaultLocale = const ui.Locale('en', 'US');

  /// We use the first locale in the [locales] list instead of the browser's
  /// built-in `navigator.language` because browsers do not agree on the
  /// implementation.
  ///
  /// See also:
  ///
  /// * https://developer.mozilla.org/en-US/docs/Web/API/NavigatorLanguage/languages,
  ///   which explains browser quirks in the implementation notes.
  @override
  ui.Locale get locale => _locales!.first;

  @override
  List<ui.Locale>? get locales => _locales;
  List<ui.Locale>? _locales = parseBrowserLanguages();

  /// Sets locales to `null`.
  ///
  /// `null` is not a valid value for locales. This is only used for testing
  /// locale update logic.
  void debugResetLocales() {
    _locales = null;
  }

  // Called by DomRenderer when browser languages change.
  void _updateLocales() {
    _locales = parseBrowserLanguages();
  }

  static List<ui.Locale> parseBrowserLanguages() {
    // TODO(yjbanov): find a solution for IE
    var languages = html.window.navigator.languages;
    if (languages == null || languages.isEmpty) {
      // To make it easier for the app code, let's not leave the locales list
      // empty. This way there's fewer corner cases for apps to handle.
      return const [_defaultLocale];
    }

    final List<ui.Locale> locales = <ui.Locale>[];
    for (final String language in languages) {
      final List<String> parts = language.split('-');
      if (parts.length > 1) {
        locales.add(ui.Locale(parts.first, parts.last));
      } else {
        locales.add(ui.Locale(language));
      }
    }

    assert(locales.isNotEmpty);
    return locales;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnLocaleChanged() {
    _invoke(_onLocaleChanged, _onLocaleChangedZone);
  }

  @override
  ui.FrameCallback? get onBeginFrame => _onBeginFrame;
  ui.FrameCallback? _onBeginFrame;
  Zone? _onBeginFrameZone;
  @override
  set onBeginFrame(ui.FrameCallback? callback) {
    _onBeginFrame = callback;
    _onBeginFrameZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnBeginFrame(Duration duration) {
    _invoke1<Duration>(_onBeginFrame, _onBeginFrameZone, duration);
  }

  @override
  ui.TimingsCallback? get onReportTimings => _onReportTimings;
  ui.TimingsCallback? _onReportTimings;
  Zone? _onReportTimingsZone;
  @override
  set onReportTimings(ui.TimingsCallback? callback) {
    _onReportTimings = callback;
    _onReportTimingsZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnReportTimings(List<ui.FrameTiming> timings) {
    _invoke1<List<ui.FrameTiming>>(
        _onReportTimings, _onReportTimingsZone, timings);
  }

  @override
  ui.VoidCallback? get onDrawFrame => _onDrawFrame;
  ui.VoidCallback? _onDrawFrame;
  Zone? _onDrawFrameZone;
  @override
  set onDrawFrame(ui.VoidCallback? callback) {
    _onDrawFrame = callback;
    _onDrawFrameZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnDrawFrame() {
    _invoke(_onDrawFrame, _onDrawFrameZone);
  }

  @override
  ui.PointerDataPacketCallback? get onPointerDataPacket => _onPointerDataPacket;
  ui.PointerDataPacketCallback? _onPointerDataPacket;
  Zone? _onPointerDataPacketZone;
  @override
  set onPointerDataPacket(ui.PointerDataPacketCallback? callback) {
    _onPointerDataPacket = callback;
    _onPointerDataPacketZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnPointerDataPacket(ui.PointerDataPacket packet) {
    _invoke1<ui.PointerDataPacket>(
        _onPointerDataPacket, _onPointerDataPacketZone, packet);
  }

  @override
  ui.VoidCallback? get onSemanticsEnabledChanged => _onSemanticsEnabledChanged;
  ui.VoidCallback? _onSemanticsEnabledChanged;
  Zone? _onSemanticsEnabledChangedZone;
  @override
  set onSemanticsEnabledChanged(ui.VoidCallback? callback) {
    _onSemanticsEnabledChanged = callback;
    _onSemanticsEnabledChangedZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnSemanticsEnabledChanged() {
    _invoke(_onSemanticsEnabledChanged, _onSemanticsEnabledChangedZone);
  }

  @override
  ui.SemanticsActionCallback? get onSemanticsAction => _onSemanticsAction;
  ui.SemanticsActionCallback? _onSemanticsAction;
  Zone? _onSemanticsActionZone;
  @override
  set onSemanticsAction(ui.SemanticsActionCallback? callback) {
    _onSemanticsAction = callback;
    _onSemanticsActionZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnSemanticsAction(
      int id, ui.SemanticsAction action, ByteData? args) {
    _invoke3<int, ui.SemanticsAction, ByteData?>(
        _onSemanticsAction, _onSemanticsActionZone, id, action, args);
  }

  @override
  ui.VoidCallback? get onAccessibilityFeaturesChanged =>
      _onAccessibilityFeaturesChanged;
  ui.VoidCallback? _onAccessibilityFeaturesChanged;
  Zone? _onAccessibilityFeaturesChangedZone;
  @override
  set onAccessibilityFeaturesChanged(ui.VoidCallback? callback) {
    _onAccessibilityFeaturesChanged = callback;
    _onAccessibilityFeaturesChangedZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnAccessibilityFeaturesChanged() {
    _invoke(
        _onAccessibilityFeaturesChanged, _onAccessibilityFeaturesChangedZone);
  }

  @override
  ui.PlatformMessageCallback? get onPlatformMessage => _onPlatformMessage;
  ui.PlatformMessageCallback? _onPlatformMessage;
  Zone? _onPlatformMessageZone;
  @override
  set onPlatformMessage(ui.PlatformMessageCallback? callback) {
    _onPlatformMessage = callback;
    _onPlatformMessageZone = Zone.current;
  }

  /// Engine code should use this method instead of the callback directly.
  /// Otherwise zones won't work properly.
  void invokeOnPlatformMessage(String name, ByteData? data,
      ui.PlatformMessageResponseCallback callback) {
    _invoke3<String, ByteData?, ui.PlatformMessageResponseCallback>(
      _onPlatformMessage,
      _onPlatformMessageZone,
      name,
      data,
      callback,
    );
  }

  @override
  void sendPlatformMessage(
    String name,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) {
    _sendPlatformMessage(
        name, data, _zonedPlatformMessageResponseCallback(callback));
  }

  /// Wraps the given [callback] in another callback that ensures that the
  /// original callback is called in the zone it was registered in.
  static ui.PlatformMessageResponseCallback?
      _zonedPlatformMessageResponseCallback(
          ui.PlatformMessageResponseCallback? callback) {
    if (callback == null) {
      return null;
    }

    // Store the zone in which the callback is being registered.
    final Zone registrationZone = Zone.current;

    return (ByteData? data) {
      registrationZone.runUnaryGuarded(callback, data);
    };
  }

  void _sendPlatformMessage(
    String name,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) {
    // In widget tests we want to bypass processing of platform messages.
    if (assertionsEnabled && ui.debugEmulateFlutterTesterEnvironment) {
      return;
    }

    if (_debugPrintPlatformMessages) {
      print('Sent platform message on channel: "$name"');
    }

    if (assertionsEnabled && name == 'flutter/debug-echo') {
      // Echoes back the data unchanged. Used for testing purpopses.
      _replyToPlatformMessage(callback, data);
      return;
    }

    switch (name) {
      /// This should be in sync with shell/common/shell.cc
      case 'flutter/skia':
        const MethodCodec codec = JSONMethodCodec();
        final MethodCall decoded = codec.decodeMethodCall(data);
        switch (decoded.method) {
          case 'Skia.setResourceCacheMaxBytes':
            if (decoded.arguments is int) {
              rasterizer?.setSkiaResourceCacheMaxBytes(decoded.arguments);
            }
            break;
        }

        return;
      case 'flutter/assets':
        assert(ui.webOnlyAssetManager != null); // ignore: unnecessary_null_comparison
        final String url = utf8.decode(data!.buffer.asUint8List());
        ui.webOnlyAssetManager.load(url).then((ByteData assetData) {
          _replyToPlatformMessage(callback, assetData);
        }, onError: (dynamic error) {
          html.window.console
              .warn('Error while trying to load an asset: $error');
          _replyToPlatformMessage(callback, null);
        });
        return;

      case 'flutter/platform':
        const MethodCodec codec = JSONMethodCodec();
        final MethodCall decoded = codec.decodeMethodCall(data);
        switch (decoded.method) {
          case 'SystemNavigator.pop':
            browserHistory.exit().then((_) {
              _replyToPlatformMessage(
                  callback, codec.encodeSuccessEnvelope(true));
            });
            return;
          case 'HapticFeedback.vibrate':
            final String? type = decoded.arguments;
            domRenderer.vibrate(_getHapticFeedbackDuration(type));
            _replyToPlatformMessage(
                callback, codec.encodeSuccessEnvelope(true));
            return;
          case 'SystemChrome.setApplicationSwitcherDescription':
            final Map<String, dynamic> arguments = decoded.arguments;
            domRenderer.setTitle(arguments['label']);
            domRenderer.setThemeColor(ui.Color(arguments['primaryColor']));
            _replyToPlatformMessage(
                callback, codec.encodeSuccessEnvelope(true));
            return;
          case 'SystemChrome.setPreferredOrientations':
            final List<dynamic>? arguments = decoded.arguments;
            domRenderer.setPreferredOrientation(arguments).then((bool success) {
              _replyToPlatformMessage(
                  callback, codec.encodeSuccessEnvelope(success));
            });
            return;
          case 'SystemSound.play':
            // There are no default system sounds on web.
            _replyToPlatformMessage(
                callback, codec.encodeSuccessEnvelope(true));
            return;
          case 'Clipboard.setData':
            ClipboardMessageHandler().setDataMethodCall(decoded, callback);
            return;
          case 'Clipboard.getData':
            ClipboardMessageHandler().getDataMethodCall(callback);
            return;
        }
        break;

      // Dispatched by the bindings to delay service worker initialization.
      case 'flutter/service_worker':
        html.window.dispatchEvent(html.Event('flutter-first-frame'));
        return;

      case 'flutter/textinput':
        textEditing.channel.handleTextInput(data, callback);
        return;

      case 'flutter/mousecursor':
        const MethodCodec codec = StandardMethodCodec();
        final MethodCall decoded = codec.decodeMethodCall(data);
        final Map<dynamic, dynamic>? arguments = decoded.arguments;
        switch (decoded.method) {
          case 'activateSystemCursor':
            MouseCursor.instance!.activateSystemCursor(arguments!['kind']);
        }
        return;

      case 'flutter/web_test_e2e':
        const MethodCodec codec = JSONMethodCodec();
        _replyToPlatformMessage(
            callback,
            codec.encodeSuccessEnvelope(
                _handleWebTestEnd2EndMessage(codec, data)));
        return;

      case 'flutter/platform_views':
        if (experimentalUseSkia) {
          rasterizer!.surface.viewEmbedder
              .handlePlatformViewCall(data, callback);
        } else {
          ui.handlePlatformViewCall(data!, callback!);
        }
        return;

      case 'flutter/accessibility':
        // In widget tests we want to bypass processing of platform messages.
        final StandardMessageCodec codec = StandardMessageCodec();
        accessibilityAnnouncements.handleMessage(codec, data);
        _replyToPlatformMessage(callback, codec.encodeMessage(true));
        return;

      case 'flutter/navigation':
        _handleNavigationMessage(data, callback).then((handled) {
          if (!handled && callback != null) {
            callback(null);
          }
        });
        // As soon as Flutter starts taking control of the app navigation, we
        // should reset [_defaultRouteName] to "/" so it doesn't have any
        // further effect after this point.
        _defaultRouteName = '/';
        return;
    }

    if (pluginMessageCallHandler != null) {
      pluginMessageCallHandler!(name, data, callback);
      return;
    }

    // Passing [null] to [callback] indicates that the platform message isn't
    // implemented. Look at [MethodChannel.invokeMethod] to see how [null] is
    // handled.
    _replyToPlatformMessage(callback, null);
  }

  @visibleForTesting
  Future<void> debugInitializeHistory(
    UrlStrategy? strategy, {
    required bool useSingle,
  }) async {
    await _browserHistory?.tearDown();
    if (useSingle) {
      _browserHistory = SingleEntryBrowserHistory(urlStrategy: strategy);
    } else {
      _browserHistory = MultiEntriesBrowserHistory(urlStrategy: strategy);
    }
  }

  @visibleForTesting
  Future<void> debugResetHistory() async {
    await _browserHistory?.tearDown();
    _browserHistory = null;
  }

  Future<bool> _handleNavigationMessage(
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {
    const MethodCodec codec = JSONMethodCodec();
    final MethodCall decoded = codec.decodeMethodCall(data);
    final Map<String, dynamic> arguments = decoded.arguments;

    switch (decoded.method) {
      case 'routeUpdated':
        await _useSingleEntryBrowserHistory();
        browserHistory.setRouteName(arguments['routeName']);
        _replyToPlatformMessage(callback, codec.encodeSuccessEnvelope(true));
        return true;
      case 'routeInformationUpdated':
        assert(browserHistory is MultiEntriesBrowserHistory);
        browserHistory.setRouteName(
          arguments['location'],
          state: arguments['state'],
        );
        _replyToPlatformMessage(callback, codec.encodeSuccessEnvelope(true));
        return true;
    }
    return false;
  }

  int _getHapticFeedbackDuration(String? type) {
    switch (type) {
      case 'HapticFeedbackType.lightImpact':
        return DomRenderer.vibrateLightImpact;
      case 'HapticFeedbackType.mediumImpact':
        return DomRenderer.vibrateMediumImpact;
      case 'HapticFeedbackType.heavyImpact':
        return DomRenderer.vibrateHeavyImpact;
      case 'HapticFeedbackType.selectionClick':
        return DomRenderer.vibrateSelectionClick;
      default:
        return DomRenderer.vibrateLongPress;
    }
  }

  /// In Flutter, platform messages are exchanged between threads so the
  /// messages and responses have to be exchanged asynchronously. We simulate
  /// that by adding a zero-length delay to the reply.
  void _replyToPlatformMessage(
    ui.PlatformMessageResponseCallback? callback,
    ByteData? data,
  ) {
    Future<void>.delayed(Duration.zero).then((_) {
      if (callback != null) {
        callback(data);
      }
    });
  }

  @override
  ui.Brightness get platformBrightness => _platformBrightness;
  ui.Brightness _platformBrightness = ui.Brightness.light;

  /// Updates [_platformBrightness] and invokes [onPlatformBrightnessChanged]
  /// callback if [_platformBrightness] changed.
  void _updatePlatformBrightness(ui.Brightness newPlatformBrightness) {
    ui.Brightness previousPlatformBrightness = _platformBrightness;
    _platformBrightness = newPlatformBrightness;

    if (previousPlatformBrightness != _platformBrightness &&
        onPlatformBrightnessChanged != null) {
      invokeOnPlatformBrightnessChanged();
    }
  }

  /// Reference to css media query that indicates the user theme preference on the web.
  final html.MediaQueryList _brightnessMediaQuery =
      html.window.matchMedia('(prefers-color-scheme: dark)');

  /// A callback that is invoked whenever [_brightnessMediaQuery] changes value.
  ///
  /// Updates the [_platformBrightness] with the new user preference.
  html.EventListener? _brightnessMediaQueryListener;

  /// Set the callback function for listening changes in [_brightnessMediaQuery] value.
  void _addBrightnessMediaQueryListener() {
    _updatePlatformBrightness(_brightnessMediaQuery.matches
        ? ui.Brightness.dark
        : ui.Brightness.light);

    _brightnessMediaQueryListener = (html.Event event) {
      final html.MediaQueryListEvent mqEvent =
          event as html.MediaQueryListEvent;
      _updatePlatformBrightness(
          mqEvent.matches! ? ui.Brightness.dark : ui.Brightness.light);
    };
    _brightnessMediaQuery.addListener(_brightnessMediaQueryListener);
    registerHotRestartListener(() {
      _removeBrightnessMediaQueryListener();
    });
  }

  void _addUrlStrategyListener() {
    _jsSetUrlStrategy = allowInterop((JsUrlStrategy? jsStrategy) {
      assert(
        _browserHistory == null,
        'Cannot set URL strategy more than once.',
      );
      final UrlStrategy? strategy =
          jsStrategy == null ? null : CustomUrlStrategy.fromJs(jsStrategy);
      _browserHistory = MultiEntriesBrowserHistory(urlStrategy: strategy);
    });
    registerHotRestartListener(() {
      _jsSetUrlStrategy = null;
    });
  }

  /// Remove the callback function for listening changes in [_brightnessMediaQuery] value.
  void _removeBrightnessMediaQueryListener() {
    _brightnessMediaQuery.removeListener(_brightnessMediaQueryListener);
    _brightnessMediaQueryListener = null;
  }

  @override
  void render(ui.Scene scene) {
    if (experimentalUseSkia) {
      // "Build finish" and "raster start" happen back-to-back because we
      // render on the same thread, so there's no overhead from hopping to
      // another thread.
      //
      // CanvasKit works differently from the HTML renderer in that in HTML
      // we update the DOM in SceneBuilder.build, which is these function calls
      // here are CanvasKit-only.
      _frameTimingsOnBuildFinish();
      _frameTimingsOnRasterStart();

      final LayerScene layerScene = scene as LayerScene;
      rasterizer!.draw(layerScene.layerTree);
    } else {
      final SurfaceScene surfaceScene = scene as SurfaceScene;
      domRenderer.renderScene(surfaceScene.webOnlyRootElement);
    }
    _frameTimingsOnRasterFinish();
  }

  @visibleForTesting
  late Rasterizer? rasterizer =
      experimentalUseSkia ? Rasterizer(Surface(HtmlViewEmbedder())) : null;
}

bool _handleWebTestEnd2EndMessage(MethodCodec codec, ByteData? data) {
  final MethodCall decoded = codec.decodeMethodCall(data);
  double ratio = double.parse(decoded.arguments);
  switch (decoded.method) {
    case 'setDevicePixelRatio':
      window.debugOverrideDevicePixelRatio(ratio);
      window.onMetricsChanged!();
      return true;
  }
  return false;
}

/// Invokes [callback] inside the given [zone].
void _invoke(void callback()?, Zone? zone) {
  if (callback == null) {
    return;
  }

  assert(zone != null);

  if (identical(zone, Zone.current)) {
    callback();
  } else {
    zone!.runGuarded(callback);
  }
}

/// Invokes [callback] inside the given [zone] passing it [arg].
void _invoke1<A>(void callback(A a)?, Zone? zone, A arg) {
  if (callback == null) {
    return;
  }

  assert(zone != null);

  if (identical(zone, Zone.current)) {
    callback(arg);
  } else {
    zone!.runUnaryGuarded<A>(callback, arg);
  }
}

/// Invokes [callback] inside the given [zone] passing it [arg1], [arg2], and [arg3].
void _invoke3<A1, A2, A3>(void callback(A1 a1, A2 a2, A3 a3)?, Zone? zone,
    A1 arg1, A2 arg2, A3 arg3) {
  if (callback == null) {
    return;
  }

  assert(zone != null);

  if (identical(zone, Zone.current)) {
    callback(arg1, arg2, arg3);
  } else {
    zone!.runGuarded(() {
      callback(arg1, arg2, arg3);
    });
  }
}

/// The window singleton.
///
/// `dart:ui` window delegates to this value. However, this value has a wider
/// API surface, providing Web-specific functionality that the standard
/// `dart:ui` version does not.
final EngineWindow window = EngineWindow();

/// The Web implementation of [ui.WindowPadding].
class WindowPadding implements ui.WindowPadding {
  const WindowPadding({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}
