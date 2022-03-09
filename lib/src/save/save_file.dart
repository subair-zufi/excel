part of excel;

class _Save {
  final Excel _excel;
  Map<String, ArchiveFile> _archiveFiles = Map<String, ArchiveFile>();
  List<CellStyle?> _innerCellStyle = <CellStyle?>[];
  final Parser? parser;
  _Save._(this._excel, this.parser);

  List<int>? _save() {
    if (_excel._colorChanges) {
      _processStylesFile();
    }
    _setSheetElements();
    if (_excel._defaultSheet != null) {
      _setDefaultSheet(_excel._defaultSheet);
    }
    _setSharedStrings();

    if (_excel._mergeChanges) {
      _setMerge();
    }

    if (_excel._rtlChanges) {
      _setRTL();
    }

    for (var xmlFile in _excel._xmlFiles.keys) {
      var xml = _excel._xmlFiles[xmlFile].toString();
      var content = utf8.encode(xml);
      _archiveFiles[xmlFile] = ArchiveFile(xmlFile, content.length, content);
    }
    return ZipEncoder().encode(_cloneArchive(_excel._archive));
  }

  Archive _cloneArchive(Archive archive) {
    var clone = Archive();
    archive.files.forEach((file) {
      if (file.isFile) {
        ArchiveFile? copy;
        if (_archiveFiles.containsKey(file.name)) {
          copy = _archiveFiles[file.name];
        } else {
          var content = (file.content as Uint8List).toList();
          var compress = !_noCompression.contains(file.name);
          copy = ArchiveFile(file.name, content.length, content)
            ..compress = compress;
        }
        clone.addFile(copy!);
      }
    });
    return clone;
  }

  bool _setDefaultSheet(String? sheetName) {
    int position = -1;
    List<XmlElement> sheetList =
        _excel._xmlFiles['xl/workbook.xml']!.findAllElements('sheet').toList();
    late XmlElement elementFound;

    for (int i = 0; i < sheetList.length; i++) {
      var _sheetName = sheetList[i].getAttribute('name');
      if (_sheetName != null && _sheetName.toString() == sheetName) {
        elementFound = sheetList[i];
        position = i;
        break;
      }
    }

    if (position == -1) {
      return false;
    }
    if (position == 0) {
      return true;
    }

    _excel._xmlFiles['xl/workbook.xml']!.findAllElements('sheets').first.children
      ..removeAt(position)
      ..insert(0, elementFound);

    String? expectedSheet = _excel._getDefaultSheet();

    return expectedSheet == sheetName;
  }

  /// Writing cell contained text into the excel sheet files.
  _setSheetElements() {
    _excel._sharedStrings = _SharedStringsMaintainer.instance;
    _excel._sharedStrings.clear();

    _excel._sheetMap.forEach((sheet, value) {
      ///
      /// Create the sheet's xml file if it does not exist.
      if (_excel._sheets[sheet] == null) {
        parser!._createSheet(sheet);
      }

      /// Clear the previous contents of the sheet if it exists,
      /// in order to reduce the time to find and compare with the sheet rows
      /// and hence just do the work of putting the data only i.e. creating new rows
      if (_excel._sheets[sheet]?.children.isNotEmpty ?? false) {
        _excel._sheets[sheet]!.children.clear();
      }

      /// `Above function is important in order to wipe out the old contents of the sheet.`
      for (var rowIndex = 0; rowIndex < value!._maxRows; rowIndex++) {
        if (value._sheetData[rowIndex] != null) {
          var foundRow =
              _createNewRow(_excel._sheets[sheet] as XmlElement, rowIndex);
          for (var colIndex = 0; colIndex < value._maxCols; colIndex++) {
            var data = value._sheetData[rowIndex]![colIndex];
            if (data?.value != null) {
              _updateCell(sheet, foundRow, colIndex, rowIndex, data!.value);
            }
          }
        }
      }
    });
  }

  _setRTL() {
    _excel._rtlChangeLook.keys.forEach((s) {
      var sheetObject = _excel._sheetMap[s];
      if (sheetObject != null &&
          _excel._xmlSheetId.containsKey(s) &&
          _excel._xmlFiles.containsKey(_excel._xmlSheetId[s])) {
        var itrSheetViewsRTLElement = _excel._xmlFiles[_excel._xmlSheetId[s]!]!
            .findAllElements('sheetViews');

        if (itrSheetViewsRTLElement.isNotEmpty) {
          var itrSheetViewRTLElement = _excel._xmlFiles[_excel._xmlSheetId[s]!]!
              .findAllElements('sheetView');

          if (itrSheetViewRTLElement.isNotEmpty) {
            /// clear all the children of the sheetViews here
            _excel._xmlFiles[_excel._xmlSheetId[s]!]!
                .findAllElements('sheetViews')
                .first
                .children
                .clear();
          }
          _excel._xmlFiles[_excel._xmlSheetId[s]!]!
              .findAllElements('sheetViews')
              .first
              .children
              .add(XmlElement(
                XmlName('sheetView'),
                [
                  if (sheetObject.isRTL!)
                    XmlAttribute(XmlName('rightToLeft'), '1'),
                  XmlAttribute(XmlName('workbookViewId'), '0'),
                ],
              ));
        } else {
          _excel._xmlFiles[_excel._xmlSheetId[s]!]!
              .findAllElements('worksheet')
              .first
              .children
              .add(XmlElement(XmlName('sheetViews'), [], [
                XmlElement(
                  XmlName('sheetView'),
                  [
                    if (sheetObject.isRTL!)
                      XmlAttribute(XmlName('rightToLeft'), '1'),
                    XmlAttribute(XmlName('workbookViewId'), '0'),
                  ],
                )
              ]));
        }
      }
    });
  }

  /// Writing the merged cells information into the excel properties files.
  _setMerge() {
    _selfCorrectSpanMap(_excel);
    _excel._mergeChangeLook.forEach((s) {
      if (_excel._sheetMap[s] != null &&
          _excel._sheetMap[s]!._spanList != null &&
          _excel._sheetMap[s]!._spanList.isNotEmpty &&
          _excel._xmlSheetId.containsKey(s) &&
          _excel._xmlFiles.containsKey(_excel._xmlSheetId[s])) {
        Iterable<XmlElement> iterMergeElement = _excel
            ._xmlFiles[_excel._xmlSheetId[s]!]!
            .findAllElements('mergeCells');
        late XmlElement mergeElement;
        if (iterMergeElement.isNotEmpty) {
          mergeElement = iterMergeElement.first;
        } else {
          if (_excel._xmlFiles[_excel._xmlSheetId[s]!]!
                  .findAllElements('worksheet')
                  .length >
              0) {
            int index = _excel._xmlFiles[_excel._xmlSheetId[s]!]!
                .findAllElements('worksheet')
                .first
                .children
                .indexOf(_excel._xmlFiles[_excel._xmlSheetId[s]!]!
                    .findAllElements("sheetData")
                    .first);
            if (index == -1) {
              _damagedExcel();
            }
            _excel._xmlFiles[_excel._xmlSheetId[s]!]!
                .findAllElements('worksheet')
                .first
                .children
                .insert(
                    index + 1,
                    XmlElement(XmlName('mergeCells'),
                        [XmlAttribute(XmlName('count'), '0')]));

            mergeElement = _excel._xmlFiles[_excel._xmlSheetId[s]!]!
                .findAllElements('mergeCells')
                .first;
          } else {
            _damagedExcel();
          }
        }

        List<String> _spannedItems =
            List<String>.from(_excel._sheetMap[s]!.spannedItems);

        [
          ['count', _spannedItems.length.toString()],
        ].forEach((value) {
          if (mergeElement.getAttributeNode(value[0]) == null) {
            mergeElement.attributes
                .add(XmlAttribute(XmlName(value[0]), value[1]));
          } else {
            mergeElement.getAttributeNode(value[0])!.value = value[1];
          }
        });

        mergeElement.children.clear();

        _spannedItems.forEach((value) {
          mergeElement.children.add(XmlElement(XmlName('mergeCell'),
              [XmlAttribute(XmlName('ref'), '$value')], []));
        });
      }
    });
  }

  /// Writing Font Color in [xl/styles.xml] from the Cells of the sheets.

  _processStylesFile() {
    _innerCellStyle = <CellStyle?>[];
    List<String?> innerPatternFill = <String?>[];
    List<_FontStyle> innerFontStyle = <_FontStyle>[];

    _excel._sheetMap.forEach((sheetName, sheetObject) {
      sheetObject!._sheetData.forEach((_, colMap) {
        colMap.forEach((_, dataObject) {
          if (dataObject != null && dataObject.cellStyle != null) {
            int pos = _checkPosition(_innerCellStyle, dataObject.cellStyle);
            if (pos == -1) {
              _innerCellStyle.add(dataObject.cellStyle);
            }
          }
        });
      });
    });

    _innerCellStyle.forEach((cellStyle) {
      _FontStyle _fs = _FontStyle(
          bold: cellStyle!.isBold,
          italic: cellStyle.isItalic,
          fontColorHex: cellStyle.fontColor,
          underline: cellStyle.underline,
          fontSize: cellStyle.fontSize,
          fontFamily: cellStyle.fontFamily);

      /// If `-1` is returned then it indicates that `_fontStyle` is not present in the `_fs`
      if (_fontStyleIndex(_excel._fontStyleList, _fs) == -1 &&
          _fontStyleIndex(innerFontStyle, _fs) == -1) {
        innerFontStyle.add(_fs);
      }

      /// Filling the inner usable extra list of backgroung color
      String? backgroundColor = cellStyle.backgroundColor;
      if (!_excel._patternFill.contains(backgroundColor) &&
          !innerPatternFill.contains(backgroundColor)) {
        innerPatternFill.add(backgroundColor);
      }
    });

    XmlElement fonts =
        _excel._xmlFiles['xl/styles.xml']!.findAllElements('fonts').first;

    var fontAttribute = fonts.getAttributeNode('count');
    if (fontAttribute != null) {
      fontAttribute.value =
          '${_excel._fontStyleList.length + innerFontStyle.length}';
    } else {
      fonts.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._fontStyleList.length + innerFontStyle.length}'));
    }

    innerFontStyle.forEach((fontStyleElement) {
      fonts.children.add(XmlElement(XmlName('font'), [], [
        /// putting color
        if (fontStyleElement._fontColorHex != null &&
            fontStyleElement._fontColorHex != "FF000000")
          XmlElement(
              XmlName('color'),
              [XmlAttribute(XmlName('rgb'), fontStyleElement._fontColorHex!)],
              []),

        /// putting bold
        if (fontStyleElement.isBold != null && fontStyleElement.isBold!)
          XmlElement(XmlName('b'), [], []),

        /// putting italic
        if (fontStyleElement.isItalic != null && fontStyleElement.isItalic!)
          XmlElement(XmlName('i'), [], []),

        /// putting single underline
        if (fontStyleElement.underline != null &&
            fontStyleElement.underline != Underline.None &&
            fontStyleElement.underline == Underline.Single)
          XmlElement(XmlName('u'), [], []),

        /// putting double underline
        if (fontStyleElement.underline != null &&
            fontStyleElement.underline != Underline.None &&
            fontStyleElement.underline != Underline.Single &&
            fontStyleElement.underline == Underline.Double)
          XmlElement(
              XmlName('u'), [XmlAttribute(XmlName('val'), 'double')], []),

        /// putting fontFamily
        if (fontStyleElement.fontFamily != null &&
            fontStyleElement.fontFamily!.toLowerCase().toString() != "null" &&
            fontStyleElement.fontFamily != "" &&
            fontStyleElement.fontFamily!.isNotEmpty)
          XmlElement(XmlName('name'), [
            XmlAttribute(XmlName('val'), fontStyleElement.fontFamily.toString())
          ], []),

        /// putting fontSize
        if (fontStyleElement.fontSize != null &&
            fontStyleElement.fontSize.toString().isNotEmpty)
          XmlElement(XmlName('sz'), [
            XmlAttribute(XmlName('val'), fontStyleElement.fontSize.toString())
          ], []),
      ]));
    });

    XmlElement fills =
        _excel._xmlFiles['xl/styles.xml']!.findAllElements('fills').first;

    var fillAttribute = fills.getAttributeNode('count');

    if (fillAttribute != null) {
      fillAttribute.value =
          '${_excel._patternFill.length + innerPatternFill.length}';
    } else {
      fills.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._patternFill.length + innerPatternFill.length}'));
    }

    innerPatternFill.forEach((color) {
      if (color!.length >= 2) {
        if (color.substring(0, 2).toUpperCase() == 'FF') {
          fills.children.add(XmlElement(XmlName('fill'), [], [
            XmlElement(XmlName('patternFill'), [
              XmlAttribute(XmlName('patternType'), 'solid')
            ], [
              XmlElement(XmlName('fgColor'),
                  [XmlAttribute(XmlName('rgb'), color)], []),
              XmlElement(
                  XmlName('bgColor'), [XmlAttribute(XmlName('rgb'), color)], [])
            ])
          ]));
        } else if (color == "none" ||
            color == "gray125" ||
            color == "lightGray") {
          fills.children.add(XmlElement(XmlName('fill'), [], [
            XmlElement(XmlName('patternFill'),
                [XmlAttribute(XmlName('patternType'), color)], [])
          ]));
        }
      } else {
        _damagedExcel(
            text:
                "Corrupted Styles Found. Can't process further, Open up issue in github.");
      }
    });

    XmlElement celx =
        _excel._xmlFiles['xl/styles.xml']!.findAllElements('cellXfs').first;
    var cellAttribute = celx.getAttributeNode('count');

    if (cellAttribute != null) {
      cellAttribute.value =
          '${_excel._cellStyleList.length + _innerCellStyle.length}';
    } else {
      celx.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._cellStyleList.length + _innerCellStyle.length}'));
    }

    _innerCellStyle.forEach((cellStyle) {
      String? backgroundColor = cellStyle!.backgroundColor;

      _FontStyle _fs = _FontStyle(
          bold: cellStyle.isBold,
          italic: cellStyle.isItalic,
          fontColorHex: cellStyle.fontColor,
          underline: cellStyle.underline,
          fontSize: cellStyle.fontSize,
          fontFamily: cellStyle.fontFamily);

      HorizontalAlign? horizontalALign = cellStyle.horizontalAlignment;
      VerticalAlign? verticalAlign = cellStyle.verticalAlignment;
      int rotation = cellStyle.rotation;
      TextWrapping? textWrapping = cellStyle.wrap;
      int backgroundIndex = innerPatternFill.indexOf(backgroundColor),
          fontIndex = _fontStyleIndex(innerFontStyle, _fs);

      var attributes = <XmlAttribute>[
        XmlAttribute(XmlName('borderId'), '0'),
        XmlAttribute(XmlName('fillId'),
            '${backgroundIndex == -1 ? 0 : (backgroundIndex + _excel._patternFill.length)}'),
        XmlAttribute(XmlName('fontId'),
            '${fontIndex == -1 ? 0 : (fontIndex + _excel._fontStyleList.length)}'),
        XmlAttribute(XmlName('numFmtId'), '0'),
        XmlAttribute(XmlName('xfId'), '0'),
      ];

      if ((_excel._patternFill.contains(backgroundColor) ||
              innerPatternFill.contains(backgroundColor)) &&
          backgroundColor != "none" &&
          backgroundColor != "gray125" &&
          backgroundColor!.toLowerCase() != "lightgray") {
        attributes.add(XmlAttribute(XmlName('applyFill'), '1'));
      }

      if (_fontStyleIndex(_excel._fontStyleList, _fs) != -1 &&
          _fontStyleIndex(innerFontStyle, _fs) != -1) {
        attributes.add(XmlAttribute(XmlName('applyFont'), '1'));
      }

      var children = <XmlElement>[];

      if (horizontalALign != HorizontalAlign.Left ||
          textWrapping != null ||
          verticalAlign != VerticalAlign.Bottom ||
          rotation != null ||
          rotation != 0) {
        attributes.add(XmlAttribute(XmlName('applyAlignment'), '1'));
        var childAttributes = <XmlAttribute>[];

        if (textWrapping != null) {
          childAttributes.add(XmlAttribute(
              XmlName(textWrapping == TextWrapping.Clip
                  ? 'shrinkToFit'
                  : 'wrapText'),
              '1'));
        }

        if (verticalAlign != VerticalAlign.Bottom) {
          String ver = verticalAlign == VerticalAlign.Top ? 'top' : 'center';
          childAttributes.add(XmlAttribute(XmlName('vertical'), '$ver'));
        }

        if (horizontalALign != HorizontalAlign.Left) {
          String hor =
              horizontalALign == HorizontalAlign.Right ? 'right' : 'center';
          childAttributes.add(XmlAttribute(XmlName('horizontal'), '$hor'));
        }
        if (rotation != null && rotation != 0) {
          childAttributes
              .add(XmlAttribute(XmlName('textRotation'), '$rotation'));
        }

        children.add(XmlElement(XmlName('alignment'), childAttributes, []));
      }

      celx.children.add(XmlElement(XmlName('xf'), attributes, children));
    });
  }

  /// Writing the value of excel cells into the separate
  /// sharedStrings file so as to minimize the size of excel files.
  _setSharedStrings() {
    var uniqueCount = 0;
    var count = 0;

    XmlElement shareString = _excel
        ._xmlFiles['xl/${_excel._sharedStringsTarget}']!
        .findAllElements('sst')
        .first;

    shareString.children.clear();

    _excel._sharedStrings._map.forEach((string, ss) {
      uniqueCount += 1;
      count += ss.count as int;

      shareString.children.add(XmlElement(XmlName('si'), [], [
        XmlElement(XmlName('t'), [], [XmlText(string)])
      ]));
    });

    [
      ['count', '$count'],
      ['uniqueCount', '$uniqueCount']
    ].forEach((value) {
      if (shareString.getAttributeNode(value[0]) == null) {
        shareString.attributes.add(XmlAttribute(XmlName(value[0]), value[1]));
      } else {
        shareString.getAttributeNode(value[0])!.value = value[1];
      }
    });
  }

  ///
  XmlElement _createNewRow(XmlElement table, int rowIndex) {
    var row = XmlElement(XmlName('row'),
        [XmlAttribute(XmlName('r'), (rowIndex + 1).toString())], []);
    table.children.add(row);
    return row;
  }

  // Manage value's type
  XmlElement _createCell(
      String? sheet, int columnIndex, int rowIndex, dynamic value) {
    if (value.runtimeType == String) {
      _excel._sharedStrings.add(value);
    }

    String rC = getCellId(columnIndex, rowIndex);

    var attributes = <XmlAttribute>[
      XmlAttribute(XmlName('r'), rC),
      if (value.runtimeType == String) XmlAttribute(XmlName('t'), 's'),
    ];

    if (_excel._colorChanges &&
        (_excel._sheetMap[sheet]?._sheetData != null) &&
        _excel._sheetMap[sheet]!._sheetData[rowIndex] != null &&
        _excel._sheetMap[sheet]!._sheetData[rowIndex]![columnIndex]?.cellStyle !=
            null) {
      CellStyle? cellStyle =
          _excel._sheetMap[sheet]!._sheetData[rowIndex]![columnIndex]!.cellStyle;
      int upperLevelPos = _checkPosition(_excel._cellStyleList, cellStyle);
      if (upperLevelPos == -1) {
        int lowerLevelPos = _checkPosition(_innerCellStyle, cellStyle);
        if (lowerLevelPos != -1) {
          upperLevelPos = lowerLevelPos + _excel._cellStyleList.length;
        } else {
          upperLevelPos = 0;
        }
      }
      attributes.insert(
        1,
        XmlAttribute(XmlName('s'), '$upperLevelPos'),
      );
    } else if (_excel._cellStyleReferenced.containsKey(sheet) &&
        _excel._cellStyleReferenced[sheet]!.containsKey(rC)) {
      attributes.insert(
        1,
        XmlAttribute(XmlName('s'), '${_excel._cellStyleReferenced[sheet]![rC]}'),
      );
    }

    var children = value == null
        ? <XmlElement>[]
        : <XmlElement>[
            if (value is Formula)
              XmlElement(XmlName('f'), [], [XmlText(value.formula.toString())]),
            XmlElement(XmlName('v'), [], [
              XmlText(value is String
                  ? _excel._sharedStrings.indexOf(value).toString()
                  : value is Formula
                      ? ''
                      : value.toString())
            ]),
          ];
    return XmlElement(XmlName('c'), attributes, children);
  }

  XmlElement _updateCell(String? sheet, XmlElement row, int columnIndex,
      int rowIndex, dynamic value) {
    var cell = _createCell(sheet, columnIndex, rowIndex, value);
    row.children.add(cell);
    return cell;
  }
}
