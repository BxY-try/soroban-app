import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';

/// Settings screen allowing the user to configure preferences
/// such as per-rod color palettes and view app information.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: SorobanTheme.frameColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            color: SorobanTheme.frameColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 620),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ListView(
              children: [
                // 1. Appearance Section
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tampilan Visual Sempoa',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: SorobanTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: const Text(
                            'Warna Manik Per-Tiang',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Memberikan warna palet kayu harmonis yang berbeda pada setiap tiang (rod) untuk memudahkan pembacaan posisi digit.',
                            style: TextStyle(fontSize: 12, color: SorobanTheme.textMuted),
                          ),
                          activeThumbColor: SorobanTheme.beadActiveColor,
                          value: controller.perRodColor,
                          onChanged: (_) => controller.togglePerRodColor(),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 2. About Section
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tentang Aplikasi Soroban',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: SorobanTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Aplikasi latihan sempoa Jepang (Soroban 1-4) dengan fitur:\n'
                          '• Hint aktif per digit penuh (Chained Animation dengan aksen pendar kuningan)\n'
                          '• Tombol Replay untuk demonstrasi ulang teknik kawan kecil dan kawan besar\n'
                          '• Mode Tantangan dengan akumulasi 1 timer total untuk 5 soal\n'
                          '• Desain manik bikonikal prosedural tanpa ketergantungan aset raster',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: SorobanTheme.textDark,
                          ),
                        ),
                        Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Versi Aplikasi', style: TextStyle(color: SorobanTheme.textMuted, fontSize: 13)),
                            Text('v1.0.0 (Refined)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
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
}
