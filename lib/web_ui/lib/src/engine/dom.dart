// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:js/js.dart';
import 'package:js/js_util.dart' as js_util;

@JS()
@staticInterop
class DomWindow {}

extension DomWindowExtension on DomWindow {
  external DomDocument get document;
  external DomNavigator get navigator;
}

@JS('window')
external DomWindow get domWindow;

@JS()
@staticInterop
class DomNavigator {}

extension DomNavigatorExtension on DomNavigator {
  external int? get maxTouchPoints;
  external String get vendor;
  external String? get platform;
  external String get userAgent;
}

@JS()
@staticInterop
class DomDocument {}

extension DomDocumentExtension on DomDocument {
  external /* List<Node> */ List<Object?> querySelectorAll(String selectors);
  external DomHTMLElement createElement(String name, [dynamic options]);
}

@JS()
@staticInterop
class DomEventTarget {}

@JS()
@staticInterop
class DomNode extends DomEventTarget {}

@JS()
@staticInterop
class DomHTMLElement extends DomNode {}

@JS()
@staticInterop
class DomHTMLMetaElement {}

extension DomHTMLMetaElementExtension on DomHTMLMetaElement {
  external String get name;
  external set name(String value);
  external String get content;
}

@JS()
@staticInterop
class DomCanvasElement extends DomHTMLElement {
  factory DomCanvasElement({int? width, int? height}) {
    final DomCanvasElement canvas =
        domWindow.document.createElement('canvas') as DomCanvasElement;
    if (width != null) {
      canvas.width = width;
    }
    if (height != null) {
      canvas.height = height;
    }
    return canvas;
  }
}

extension DomCanvasElementExtension on DomCanvasElement {
  external int? get width;
  external set width(int? value);
  external int? get height;
  external set height(int? value);

  Object? getContext(String contextType, [Map<dynamic, dynamic>? attributes]) {
    return js_util.callMethod(this, 'getContext', <Object?>[
      contextType,
      if (attributes != null) js_util.jsify(attributes)
    ]);
  }
}

Object? domGetConstructor(String constructorName) =>
    js_util.getProperty(domWindow, constructorName);

bool domInstanceOfString(Object? element, String objectType) =>
    js_util.instanceof(element, domGetConstructor(objectType)!);
