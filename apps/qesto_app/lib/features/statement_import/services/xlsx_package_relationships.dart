import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../domain/bank_statement_models.dart';

const _relationshipsNamespace =
    'http://schemas.openxmlformats.org/package/2006/relationships';
const _officeRelationshipPrefix =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships/';
const _officeRelationshipsNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _spreadsheetNamespace =
    'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _workbookRels = 'xl/_rels/workbook.xml.rels';

/// OPC targets are package URIs, not filesystem paths. excel_community 2.2.1
/// prefixes workbook targets with `xl/` even for `/xl/...` absolute targets.
/// Validate all relationships, then adapt ONLY those decoder-facing targets.
/// No files are extracted, URLs fetched, macros loaded or source IDs changed.
/// Must be called AFTER the existing bounded ZIP validation/decompression.
Uint8List? prepareXlsxRelationships(Archive archive) {
  final parts = <String, ArchiveFile>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    _validatePartName(file.name);
    parts[file.name] = file;
  }
  if (!parts.containsKey(_workbookRels) ||
      !parts.containsKey('xl/workbook.xml')) {
    _invalid('не найдены связи книги');
  }

  var changed = false;
  final worksheetIds = <String>{};
  final decoderParts = <String>{'xl/workbook.xml'};
  final removedHyperlinks = <String, Set<String>>{};
  var hasStyles = false;
  for (final file in parts.values.where(
    (part) => part.name.endsWith('.rels'),
  )) {
    final document = _parseXml(file);
    final root = document.rootElement;
    if (root.name.local != 'Relationships' ||
        root.namespaceUri != _relationshipsNamespace) {
      _invalid('неверная структура связей');
    }
    final source = _sourcePart(file.name);
    final ids = <String>{};
    var fileChanged = false;
    for (final relation in root.childElements.toList()) {
      if (relation.name.local != 'Relationship' ||
          relation.namespaceUri != _relationshipsNamespace) {
        _invalid('неверная связь');
      }
      final id = relation.getAttribute('Id');
      final type = relation.getAttribute('Type');
      final target = relation.getAttribute('Target');
      final mode = relation.getAttribute('TargetMode');
      if (id == null ||
          id.isEmpty ||
          !ids.add(id) ||
          type == null ||
          type.isEmpty ||
          target == null ||
          target.isEmpty) {
        _invalid('неполная или повторяющаяся связь');
      }
      if (mode != null && mode != 'Internal') {
        // Ordinary worksheets may contain links to shops unrelated to their
        // financial cells. Do not resolve or pass these external relationships
        // to the decoder: strip the inert hyperlink and its sheet reference in
        // the in-memory copy. Required/unknown external parts remain rejected.
        if (mode == 'External' &&
            type == '${_officeRelationshipPrefix}hyperlink' &&
            source.startsWith('xl/worksheets/')) {
          removedHyperlinks.putIfAbsent(source, () => <String>{}).add(id);
          relation.remove();
          fileChanged = true;
          continue;
        }
        _invalid('внешние связи запрещены');
      }
      final resolved = _resolveTarget(source, target);
      if (!parts.containsKey(resolved)) {
        _invalid('связь указывает на отсутствующую часть книги');
      }
      if (file.name != _workbookRels ||
          !type.startsWith(_officeRelationshipPrefix)) {
        continue;
      }
      final kind = type.substring(_officeRelationshipPrefix.length);
      if (kind != 'styles' && kind != 'sharedStrings' && kind != 'worksheet') {
        continue;
      }
      if (!resolved.startsWith('xl/')) {
        _invalid('неподдерживаемое расположение части книги');
      }
      if (kind == 'styles') hasStyles = true;
      if (kind == 'worksheet') worksheetIds.add(id);
      decoderParts.add(resolved);
      final decoderTarget = resolved.substring(3);
      if (target != decoderTarget) {
        relation.setAttribute('Target', decoderTarget);
        fileChanged = true;
      }
    }
    if (fileChanged) {
      archive.add(
        ArchiveFile.bytes(file.name, utf8.encode(document.toXmlString())),
      );
      changed = true;
    }
  }
  if (!hasStyles || worksheetIds.isEmpty) _invalid('неполные связи книги');
  final workbook = _parseXml(parts['xl/workbook.xml']!);
  for (final sheet in workbook.descendants.whereType<XmlElement>().where(
    (node) => node.name.local == 'sheet',
  )) {
    final id = sheet.getAttribute(
      'id',
      namespaceUri: _officeRelationshipsNamespace,
    );
    if (!worksheetIds.contains(id)) _invalid('не найдена связь листа');
  }
  // The same upstream decoder matches literal unprefixed SpreadsheetML names
  // and `r:id`, although XML allows equivalent prefixes (`x:sheet`, etc.).
  // Preserve namespace URIs/values, normalize only known decoder-facing parts.
  for (final name in decoderParts) {
    final document = name == 'xl/workbook.xml'
        ? workbook
        : _parseXml(parts[name]!);
    if (document.rootElement.namespaceUri != _spreadsheetNamespace) {
      _invalid('неверное пространство имён части книги');
    }
    var partChanged = false;
    var decoderDocument = document;
    final removedIds = removedHyperlinks[name];
    if (removedIds != null) {
      for (final link
          in document.descendants
              .whereType<XmlElement>()
              .where(
                (node) =>
                    node.namespaceUri == _spreadsheetNamespace &&
                    node.name.local == 'hyperlink' &&
                    removedIds.contains(
                      node.getAttribute(
                        'id',
                        namespaceUri: _officeRelationshipsNamespace,
                      ),
                    ),
              )
              .toList()) {
        link.remove();
        partChanged = true;
      }
    }
    if (document.descendants.whereType<XmlElement>().any(
      (node) =>
          (node.namespaceUri == _spreadsheetNamespace &&
              node.name.prefix != null) ||
          node.attributes.any(
            (attribute) =>
                attribute.namespaceUri == _officeRelationshipsNamespace &&
                attribute.name.prefix != 'r',
          ),
    )) {
      final root = _decoderElement(document.rootElement)
        ..setAttribute('xmlns', _spreadsheetNamespace)
        ..setAttribute('xmlns:r', _officeRelationshipsNamespace);
      decoderDocument = XmlDocument([root]);
      partChanged = true;
    }
    // Some valid producers use t="str" without a formula for literal text.
    // Upstream calls these FormulaCellValue, hiding headers from the adapter's
    // numeric-only formula handling. Convert ONLY formula-free literal values
    // to equivalent inline text; never execute formulas or change cell data.
    for (final cell
        in decoderDocument.descendants
            .whereType<XmlElement>()
            .where(
              (node) =>
                  node.namespaceUri == _spreadsheetNamespace &&
                  node.name.local == 'c' &&
                  node.getAttribute('t') == 'str',
            )
            .toList()) {
      if (cell.childElements.any((node) => node.name.local == 'f')) continue;
      final value = cell.childElements
          .where((node) => node.name.local == 'v')
          .firstOrNull;
      if (value == null) continue;
      final text = value.innerText;
      value.remove();
      cell.setAttribute('t', 'inlineStr');
      cell.children.add(
        XmlElement(
          const XmlName.parts('is', namespaceUri: _spreadsheetNamespace),
          [],
          [
            XmlElement(
              const XmlName.parts('t', namespaceUri: _spreadsheetNamespace),
              [
                XmlAttribute(
                  const XmlName.parts(
                    'space',
                    prefix: 'xml',
                    namespaceUri: 'http://www.w3.org/XML/1998/namespace',
                  ),
                  'preserve',
                ),
              ],
              [XmlText(text)],
            ),
          ],
        ),
      );
      partChanged = true;
    }
    if (partChanged) {
      archive.add(
        ArchiveFile.bytes(name, utf8.encode(decoderDocument.toXmlString())),
      );
      changed = true;
    }
  }
  if (!changed) return null;
  // archive 4.x's encoder reads rawContent; XML inspection may already have
  // cached decompressed content on an originally compressed entry. Rebuild
  // byte-backed entries so it cannot accidentally deflate compressed bytes
  // again. The original bounded archive validation still runs first.
  final decoderArchive = Archive();
  for (final file in archive.where((entry) => entry.isFile)) {
    decoderArchive.add(ArchiveFile.bytes(file.name, file.content));
  }
  return ZipEncoder().encodeBytes(decoderArchive);
}

XmlElement _decoderElement(XmlElement node) => XmlElement(
  node.namespaceUri == _spreadsheetNamespace
      ? XmlName.parts(node.name.local, namespaceUri: _spreadsheetNamespace)
      : node.name,
  node.attributes.map(
    (attribute) => attribute.namespaceUri == _officeRelationshipsNamespace
        ? XmlAttribute(
            XmlName.parts(
              attribute.name.local,
              prefix: 'r',
              namespaceUri: _officeRelationshipsNamespace,
            ),
            attribute.value,
            attribute.attributeType,
          )
        : attribute.copy(),
  ),
  node.children.map(
    (child) => child is XmlElement ? _decoderElement(child) : child.copy(),
  ),
  node.isSelfClosing,
);

XmlDocument _parseXml(ArchiveFile file) {
  try {
    final text = utf8.decode(file.content);
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text)) {
      _invalid('DTD и внешние сущности запрещены');
    }
    return XmlDocument.parse(text);
  } on UnsupportedBankStatementException {
    rethrow;
  } on Object {
    _invalid('повреждён XML связей книги');
  }
}

String _sourcePart(String relationshipPart) {
  if (relationshipPart == '_rels/.rels') return '';
  final marker = relationshipPart.lastIndexOf('/_rels/');
  if (marker < 0) _invalid('неверное расположение связей');
  return '${relationshipPart.substring(0, marker + 1)}'
      '${relationshipPart.substring(marker + 7, relationshipPart.length - 5)}';
}

String _resolveTarget(String source, String target) {
  late final String decoded;
  try {
    decoded = Uri.decodeComponent(target);
  } on FormatException {
    _invalid('неверный URI части книги');
  }
  if (decoded.contains(RegExp(r'[\\\x00-\x1f:#?]')) ||
      decoded.startsWith('//')) {
    _invalid('сетевые и файловые пути запрещены');
  }
  final directory = source.contains('/')
      ? source.substring(0, source.lastIndexOf('/') + 1)
      : '';
  final path = decoded.startsWith('/')
      ? decoded.substring(1)
      : '$directory$decoded';
  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty) _invalid('неверный путь части книги');
    if (segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) _invalid('выход за пределы пакета запрещён');
      segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  if (segments.isEmpty) _invalid('пустой путь части книги');
  return segments.join('/');
}

void _validatePartName(String name) {
  if (name.startsWith('/') ||
      name.contains(RegExp(r'[\\\x00-\x1f:#?]')) ||
      name
          .split('/')
          .any(
            (segment) => segment.isEmpty || segment == '.' || segment == '..',
          )) {
    _invalid('небезопасное имя архивной части');
  }
}

Never _invalid(String reason) =>
    throw UnsupportedBankStatementException('Excel-файл: $reason');
