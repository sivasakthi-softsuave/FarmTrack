import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmtrack/core/theme/app_theme.dart';
import 'package:farmtrack/features/scan/crop_picture.dart';

import 'support/harness.dart';

/// The picture of a crop is `assets/crops/<crop id in lower case>.<png|jpg|jpeg|webp>`: adding a file is all it takes.
void main() {
  test('the picture file of a crop is found by its id in any case, in any of the allowed kinds', () {
    const assets = {'assets/crops/apple.jpg', 'assets/crops/grape.webp', 'assets/crops/tomato.png'};
    expect(cropImagePath(assets, 'apple'), 'assets/crops/apple.jpg');
    expect(cropImagePath(assets, 'Apple'), 'assets/crops/apple.jpg', reason: 'the server writes ids with a capital');
    expect(cropImagePath(assets, 'Grape'), 'assets/crops/grape.webp');
    expect(cropImagePath(assets, 'tomato'), 'assets/crops/tomato.png');
    expect(cropImagePath(assets, 'pear'), isNull, reason: 'no file: the picture of its group is drawn');
  });

  test('every crop the real server lists (the meta fixture) has its real photo, and the files are small enough for a phone', () {
    final meta = jsonDecode(File('test/fixtures/api/meta.json').readAsStringSync()) as Map;
    final crops = [for (final c in (meta['body'] as Map)['supported_crops'] as List) c as String];
    expect(crops, isNotEmpty);
    final files = [
      for (final entity in Directory('assets/crops').listSync())
        if (entity is File) entity,
    ];
    for (final crop in crops) {
      final name = RegExp('^${crop.toLowerCase()}\\.(png|jpg|jpeg|webp)\$');
      final found = files.where((f) => name.hasMatch(f.uri.pathSegments.last)).toList();
      expect(found, hasLength(1), reason: 'assets/crops/${crop.toLowerCase()}.jpg is missing (or there are two)');
      expect(found.single.lengthSync(), lessThan(120 * 1024), reason: '$crop: keep the picture under 120 KB');
    }
  });

  testWidgets('a crop with a photo shows it; a crop without one shows the blue picture of its group', (tester) async {
    final env = await TestEnv.create(loggedIn: true, language: 'en');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          cropImageAssetsProvider.overrideWith((ref) async => {'assets/crops/apple.jpg'}),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                CropPicture(cropId: 'apple', size: 44),
                CropPicture(cropId: 'pear', size: 44),
                CropPicture(cropId: 'tomato', size: 44),
                CropPicture(cropId: 'maize', size: 44),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget, reason: 'only the apple has a file in this test');
    expect(find.byIcon(AppIcons.tree), findsOneWidget, reason: 'pear: fruit');
    expect(find.byIcon(AppIcons.leaf), findsOneWidget, reason: 'tomato: vegetable');
    expect(find.byIcon(AppIcons.grass), findsOneWidget, reason: 'maize: cereal');
  });
}
