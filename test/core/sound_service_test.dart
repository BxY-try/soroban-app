import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/services/sound_service.dart';

void main() {
  group('SoundService Tests', () {
    late SoundService soundService;

    setUp(() {
      soundService = SoundService();
      soundService.enabled = true;
    });

    test('soundAssetPaths contains 4 variants', () {
      expect(SoundService.soundAssetPaths.length, 4);
      expect(
        SoundService.soundAssetPaths,
        containsAll([
          'sounds/stapler_1.wav',
          'sounds/stapler_2.wav',
          'sounds/stapler_3.wav',
          'sounds/stapler_4.wav',
        ]),
      );
    });

    test('getNextSoundPath never repeats the same asset consecutively', () {
      String? previousPath;
      for (int i = 0; i < 50; i++) {
        final currentPath = soundService.getNextSoundPath();
        expect(SoundService.soundAssetPaths.contains(currentPath), isTrue);
        if (previousPath != null) {
          expect(
            currentPath,
            isNot(equals(previousPath)),
            reason: 'Audio sample must not repeat on consecutive clicks (iteration $i)',
          );
        }
        previousPath = currentPath;
      }
    });

    test('enabled flag can be toggled without issues', () {
      soundService.enabled = false;
      expect(soundService.enabled, isFalse);
      soundService.enabled = true;
      expect(soundService.enabled, isTrue);
    });
  });
}
