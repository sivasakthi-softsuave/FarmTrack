import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

/// The kinds of picture file a crop can have in `assets/crops/`.
const cropImageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

/// Crop pictures that exist as assets (`assets/crops/<crop_id>.png`, `.jpg`, `.jpeg` or `.webp`). Add a file there and it
/// is used.
final cropImageAssetsProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest.listAssets().where((a) => a.startsWith('assets/crops/') && !a.endsWith('.gitkeep')).toSet();
  } catch (_) {
    return const {};
  }
});

/// The picture file of [cropId] among the crop [assets], or null when it has none (then the group's picture is drawn).
String? cropImagePath(Set<String> assets, String cropId) {
  for (final extension in cropImageExtensions) {
    final path = 'assets/crops/${cropId.toLowerCase()}.$extension';
    if (assets.contains(path)) return path;
  }
  return null;
}

/// A round picture of a crop: its real photo when `assets/crops/` has one (apple, cherry), else the generic picture of
/// its group (tree for fruit, leaf for vegetables, grass for cereals). The generic one is always blue (information):
/// green, red and yellow are kept for done, stop and warning.
class CropPicture extends ConsumerWidget {
  const CropPicture({super.key, required this.cropId, this.size = 120});

  final String cropId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(resourcesProvider).cropGroup(cropId);
    final assets = ref.watch(cropImageAssetsProvider).value ?? const <String>{};
    final path = cropImagePath(assets, cropId);
    final icon = switch (group) {
      'vegetable' => AppIcons.leaf,
      'cereal' => AppIcons.grass,
      _ => AppIcons.tree,
    };
    const color = AppColors.blue;
    const soft = AppColors.blueSoft;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: soft,
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null ? Image.asset(path, fit: BoxFit.cover) : Icon(icon, size: size * 0.55, color: color),
    );
  }
}
