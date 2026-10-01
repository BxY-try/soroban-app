# soroban_app

Aplikasi latihan sempoa Jepang (Soroban 1-4) berbasis Flutter. Manik, bingkai, dan tekstur kayu digambar **prosedural** lewat `CustomPainter` — tanpa satu pun aset gambar raster. Seluruh antarmuka berbahasa Indonesia dan dikunci ke orientasi **landscape**.

Berdiri di atas `ChangeNotifier` + `provider`, dengan seluruh perhitungan mekanik sempoa dipisahkan ke engine murni yang tidak tahu apa-apa soal widget.

---

## Fitur Utama

| Fitur | Penjelasan |
|---|---|
| **Sempoa 7 tiang interaktif** | Setiap tiang punya 1 manik langit (nilai 5) dan 4 manik bumi (nilai 1). Tiap jari/pointer diklaim satu tiang sampai terangkat, sehingga beberapa tiang bisa digeser bersamaan (**multi-touch**). |
| **Dua jari pada satu tiang** | Sentuhan pada beam (14 px di tengah papan) tidak diabaikan: ia diarahkan ke tiang terdekat, ke sisi beam yang paling dekat, dan ke deck yang masih bebas bila deck terdekat sedang dipegang — persis teknik soroban asli (jari telunjuk di manik langit, jempol di manik bumi). Batas ini hanya berlaku di beam: menafsirkan ulang sentuhan pada manik akan membuat tap biasa membalik manik langit di mode Klik Manik. |
| **Manik mengikuti jari dari piksel pertama** | Ambang drag hanya **1 px** (bukan `kTouchSlop` 18 px yang itu ambang tap-vs-scroll). Di layar 800×360 seluruh perjalanan satu manik hanya ~16 px, jadi flick pendek lama tidak pernah terekam sama sekali. |
| **Fisika manik 1D rigid-body** | Saat digeser, manik yang "`mendorong`" manik di atas/bawahnya ikut terdorong, dengan jarak minimum sebesar `beadPitch` dan clamp di batas beam serta bingkai. |
| **Glosir saat dilepas** | Manik yang dilepas tidak lagi *pop* ke slot-nya, melainkan meluncur 130 ms dari posisi terakhir jari menuju hasil commit — drag yang belum cukup jauh akan memantul balik, bukan melompat. |
| **Sinyal "yang sedang dipegang"** | Ujung jari menutupi manik yang dicengkeramnya. Sejak pointer-down, deck yang dipegang mendapat pita soft (dibatasi lebar kolom tiang agar dua tiang bersebelahan tidak menyatu jadi strip gelap) dan manik yang dicengkeram membesar sedikit dengan outline gelap, disertai satu haptic tick. |
| **Checkpoint per digit penuh** | Setiap digit satu `DigitCheckpoint` yang menyimpan daftar `BeadMove` atomik — satu checkpoint boleh butuh banyak tiang dan banyak gestur. |
| **Hint berantai (Chained Animation)** | Tombol hint memutar satu checkpoint penuh, manik demi manik, dengan aksen pendar kuningan (brass glow) dan suara klak. |
| **Recovery "Nyasar"** | Kalau papan melenceng dari checkpoint terakhir, hint memulihkan tiang yang menyimpang satu per satu supaya user melihat persis tiang mana yang salah. |
| **Replay & Retri** | Replay memutar ulang animasi digit terakhir yang di-hint; Retri mundur satu checkpoint. Keduanya **hanya di Practice mode**. |
| **Papan bebas (Free Board)** | Papan adalah sumber kebenaran. Gestur bisa mendarat di tiang mana pun; progres hanya dibaca **saat diam** (`onGestureSettled`), lalu dicocokkan ke rantai checkpoint berdasarkan nilai. |
| **Mode Practice** | Tanpa timer, tanpa tekanan. Ganti kategori & tingkat kesulitan on-the-fly, tombol Soal Berikutnya, hint/replay/retri aktif. |
| **Mode Tantangan** | 5 soal beruntun dengan **satu timer akumulatif** untuk seluruh sesi, plus rekor waktu terbaik per kategori × kesulitan. |
| **Suara taktil** | 4 variasi klak kayu diputar round-robin (tanpa pengulangan beruntun) dengan jitter volume 0.80–0.88. Satu gestur = satu klak. Tiap variasi punya `AudioPool` yang sudah di-preload, jadi klak pertama sebuah sesi tidak ikut menanggung biaya salin aset, dan konteksnya `mixWithOthers` sehingga klak tidak merebut fokus audio aplikasi lain. |
| **Audio yang tidak bisu diam-diam** | Dua klak gagal berturut-turut memicu pembangunan ulang pool, dibatasi maksimal sekali per 3 detik. `init()` tidak lagi di-`await` saat startup; klak yang diminta sebelum pool selesai dimuat sengaja dilewati, bukan ditunda. |
| **Render terpisah, nol rebuild saat drag** | Lukisan dipecah dua: `SorobanFramePainter` menggambar bingkai, tiang, dan beam ke `RepaintBoundary`-nya sendiri dan di-raster sekali, sedangkan lapisan manik saja yang repaint — digerakkan `Listenable` yang di-ping oleh event pointer dan ticker. Tidak ada `setState` selama jari bergerak. Bayangan blur pada maksimal 35 manik per frame diganti salinan flat ber-offset. |
| **Jam tantangan tidak rebuild layar** | Tick 100 ms hanya mengisi `ValueNotifier<int> elapsedSeconds` tanpa `notifyListeners`; label `mm:ss` di `challenge_screen` adalah satu-satunya pendengarnya, sehingga layar tidak digambar ulang sepuluh kali per detik untuk label yang berubah sekali per detik. `elapsedMilliseconds` tetap ada dan terisi tepat saat sesi selesai. |
| **Multi-sentuh & lifecycle aman** | Gestur yang terputus saat app di-background tidak me-rollback papan; sesi pointer dibersihkan dan board diteruskan apa adanya. |

---

## Kategori Soal & Tingkat Kesulitan

Soal dibangkitkan dengan **rejection sampling** sehingga dijamin muat di 7 tiang (≤ 9,999,999) dan running total tidak pernah negatif.

| Kategori | Easy | Medium | Hard |
|---|---|---|---|
| **Penjumlahan** | 3 suku × 2 digit | 3 suku × 3 digit | 4 suku × 4 digit |
| **Campuran (+/−)** | 3 suku × 2 digit | 3 suku × 3 digit | 4 suku × 4 digit (acak simpan/pinjam) |
| **Perkalian I** | 3 digit × 1 digit | 4 digit × 1 digit | 5 digit × 1 digit |
| **Perkalian II** | 4 digit × 2 digit | 5 digit × 2 digit | 5 digit × 2 digit (carry-heavy, digit 6–9) |

Perkalian dipecah menjadi partial product, lalu **100% didelegasikan** move maniknya ke `AdditionEngine` — tidak ada logika manik terpisah di engine perkalian.

---

## Konsep Inti

**Model data.** `SorobanState` adalah daftar 7 `Rod` (indeks 0 = satuan/kanan). Karena `SorobanState.value` meng-encode seluruh tiang, kecocokan nilai_board == nilai_target berarti papan persis posisi yang dimaksud checkpoint itu — tidak ada yang perlu diverifikasi ulang.

**Kawan kecil / kawan besar.** `AdditionEngine` menghitung gerakan atomik `BeadMove` untuk satu digit memakai teknik asli sempoa: gerakan langsung, komplemen 5 (kawan kecil), dan komplemen 10 (kawan besar) dengan carry/borrow — termasuk ripple beruntun lintas tiang seperti `999 + 1 = 1000`.

**Rekonsiliasi di titik diam.** Progres checkpoint tidak pernah naik per-commit. Satu gestur fisik boleh melibatkan berapa pun jumlah jari, tiang, dan commit; baru saat jari terakhir terangkat `reconcileCheckpoints()` berjalan sekali. Yang diambil adalah checkpoint **pertama pada atau setelah posisi aktif** yang nilainya cocok — sehingga `12 + 7 − 7` (target `10, 12, 19, 12`) tidak salah resolve, dan user yang mendarat langsung di nilai akhir tetap dihitung sudah melewati checkpoint di antaranya.

**Tidak ada match = tidak ada aksi.** Papan dibiarkan persis seperti yang ditinggalkan user; memperbaiki board yang salah tetap keputusan mereka lewat Retri.

**Mode Retri.** Satu kali tekan: kalau board ≠ snapshot checkpoint aktif, kembalikan ke snapshot itu. Kalau board sudah pas, mundur satu checkpoint ("retri") dan buang jejak hint.

---

## Gestur & Render

**Tiga ambang, tiga alasan.** Gestur punya ambang yang saling berbeda dan semuanya disengaja: **1 px** (`_followSlop`) untuk mulai menggerakkan manik, **8 px** (`_tapSlop`) agar press pendek tetap terhitung tap saat Klik Manik aktif, dan **400 ms** (`_tapWindow`) sebagai batas tekan terpanjang yang masih boleh dianggap tap — jari yang ditahan lalu diangkat hanya "tidak terjadi apa-apa", tidak membalik manik. Versi lama memakai `kTouchSlop` (18 px) untuk semuanya, yaitu ambang tap-vs-scroll yang sama sekali tidak sesuai untuk manik.

**Klaim deck terjadi di pointer-down, bukan setelah ambang terlampaui.** `RodTouch` mencatat sejak sentuhan pertama deck mana yang diklaim jari, sehingga painter bisa menampilkan pita deck dan manik yang terangkat pada frame pertama — bahkan sebelum jarinya bergerak.

**Pakai posisi pointer-up juga.** Event move terakhir bisa tertinggal satu langkah di belakang pelepasan, jadi koordinat `onPointerUp` ikut dipakai saat menghitung hasil drag.

**Sinyal vs papan.** `SorobanView` punya dua `Listenable` yang sengaja dipisah: yang satu berarti "lapisan manik berubah" (di-ping oleh pointer, ticker glosir, dan animasi), yang lain "readout berubah" (hanya saat board atau setelan visual berganti). Drag karena itu tidak pernah membangun ulang readout digital.

**Tidak ada yang dijadwalkan sia-sia.** Ticker glosir berhenti sendiri begitu manik terakhir tiba, sehingga tidak ada frame yang terus terjadwal setelah papan diam.

---

## Struktur Proyek

```text
lib/
├── main.dart                        # Lock landscape + immersive, provider bootstrap
├── core/
│   ├── models/                      # Murni data, tanpa Flutter
│   │   ├── rod.dart                 # 1 heaven (5) + 4 earth (1..4) => nilai 0..9
│   │   ├── soroban_state.dart       # List<Rod>, .value, .fromValue(), .clone()
│   │   ├── problem.dart             # ProblemCategory, Difficulty, DigitCheckpoint, Problem
│   │   └── bead_move.dart           # 1 gerakan atomik = 1 sentuhan jari
│   ├── engine/                      # Kalkulasi mekanik, tanpa widget & tanpa I/O
│   │   ├── addition_engine.dart     # Apply move, calculateDigitMoves (kawan kecil/besar)
│   │   ├── multiplication_engine.dart# Partial product -> AdditionEngine
│   │   ├── problem_generator.dart   # Rejection sampling per kategori & kesulitan
│   │   └── hint_engine.dart         # getNextHint, getReplay, deteksi divergensi
│   ├── services/
│   │   └── sound_service.dart       # 4 AudioPool (mediaPlayer) per variasi, mixWithOthers
│   └── state/
│       └── soroban_controller.dart  # ChangeNotifier + ValueNotifier elapsedSeconds
├── features/
│   ├── soroban_widget/              # Sempoa sebagai widget
│   │   ├── soroban_view.dart        # Sesi pointer per tiang, hit-test beam, pemisahan repaint
│   │   ├── soroban_painter.dart     # SorobanFramePainter (bingkai) + SorobanPainter (manik)
│   │   ├── soroban_layout.dart      # Geometri, hit-test, fisika 1D, gutter kiri/kanan
│   │   └── bead_drag_state.dart     # Posisi manik mengambang + RodTouch (deck yang dipegang)
│   ├── practice/practice_screen.dart
│   ├── challenge/                   # mode_select, difficulty_select, challenge, result
│   └── settings/settings_screen.dart
├── shared/
│   └── theme.dart                   # Palet kayu natural, tipografi Outfit, palet per-tiang
└── ...
```

Aturan arsitektur yang dipegang: `core/` tidak pernah bergantung pada `features/` atau `shared/`; `shared/` tidak pernah bergantung pada `core/`. Modifikasi tampilan tidak boleh menyentuh engine.

---

## Teknologi

| Paket | Versi | Peran |
|---|---|---|
| Flutter | `>=3.27.0` | Framework |
| Dart SDK | `>=3.6.0 <4.0.0` | Bahasa |
| `provider` | `^6.1.5` | DI pada `SorobanController` |
| `shared_preferences` | `^2.5.0` | Setelan + rekor waktu |
| `google_fonts` | `^8.2.1` | Font Outfit untuk persamaan soal |
| `audioplayers` | `^6.2.0` | Efek suara klak manik (pakai `AudioPool`, bukan mode `lowLatency`) |
| `flutter_lints` | `^5.0.0` | Lint (dev) |

Aset: hanya `assets/sounds/*.wav` (5 file klak, 4 dipakai round-robin saat runtime). Tidak ada aset gambar.

---

## Menjalankan Proyek

Prasyarat: Flutter 3.27+ (stable) sudah terinstall dan `flutter` ada di `PATH`.

```bash
# 1. Ambil dependensi
flutter pub get

# 2. Jalankan di perangkat / emulator / chrome
flutter run

# 3. Build APK release (butuh Android SDK + JDK 17)
flutter build apk --release --split-per-abi
```

Target platform yang dikonfigurasi: `android/`, `web/`, `windows/`. Karena app mengunci orientasi landscape dan memakai multi-touch, **tablet landscape** adalah pengalaman yang dimaksud; desktop/web cocok untuk mode tantangan, sementara drag manik dengan mouse hanya satu jari pada satu waktu.

---

## Pengujian

```bash
flutter analyze   # harus 0 issue
flutter test
```

116 test case tersebar di 9 file test:

| File | Test | Cakupan |
|---|---|---|
| `test/core/addition_engine_test.dart` | 8 | Model `Rod`/`SorobanState`, gerakan langsung, kawan kecil, kawan besar, ripple carry, peminjaman |
| `test/core/multiplication_engine_test.dart` | 2 | Perkalian 1-digit & 2-digit via partial product |
| `test/core/problem_generator_test.dart` | 5 | Konvensi digit/suku, batas 7 tiang, running total anti-negatif |
| `test/core/hint_engine_test.dart` | 3 | Pemilihan checkpoint, rollback replay, recovery divergensi |
| `test/core/soroban_controller_test.dart` | 17 | Gestur manual, checkpoint, reset/retry, setelan, timer |
| `test/core/checkpoint_progression_test.dart` | 22 | Papan bebas, rekonsiliasi di titik diam, skip checkpoint, target berulang, rantai snapshot tanpa lubang |
| `test/core/sound_service_test.dart` | 3 | Variasi klak, penghitung request, urutan asset |
| `test/features/soroban_widget/soroban_layout_test.dart` | 39 | Geometri, fisika dorong-tarik, threshold, gutter kiri/kanan, lantai pitch |
| `test/widget_test.dart` | 17 | Navigasi layar, posisi tombol, layout landscape, multi-touch, interruption, toggle Klik Manik |

Test klak menghitung **permintaan** suara, bukan suara itu sendiri: speaker yang benar-benar bersuara tidak bisa diamati dari unit test. Yang dipin adalah kebijakan milik kita — tidak ada suara selama jari ditekan, satu per gestur baik itu menyentuh satu tiang atau dua, tidak ada untuk gestur yang tidak mengubah apa pun, satu per gestur beruntun, dan satu per move untuk animasi hint; test widget menjalankan dua pointer sungguhan dan memastikan hanya satu permintaan.

---

## CI/CD

`.github/workflows/build.yml` berjalan otomatis pada push/PR ke `main` atau `master`:

1. **Job `analyze-test`** — `flutter pub get` → `flutter analyze` → `flutter test` pada Flutter 3.x stable.
2. **Job `build-apk`** — bergantung pada job pertama, memakai JDK 17 (Temurin), membangun `flutter build apk --release --split-per-abi`, lalu mengunggah `app-*-release.apk` sebagai artifact.

---

## Pengaturan

| Setelan | Default | Efek |
|---|---|---|
| Warna Manik Per-Tiang | Mati | Memberi tiap tiang palet kayu harmonis berbeda agar posisi digit lebih mudah dibaca |
| Efek Suara Manik | Aktif | Memutar klak kayu pada gerakan manual maupun animasi hint |
| Klik Manik (Tap to Toggle) | **Mati** | Secara default manik hanya bisa digeser seperti sempoa asli. Aktifkan untuk satu ketukan langsung memindahkan manik yang disentuh. Drag tetap tersedia di kedua mode. |

Rekor waktu terbaik disimpan per kombinasi `kategori_kesulitan` dan ditampilkan di layar pemilihan kesulitan.

Haptic tick saat menahan manik **belum** tersedia sebagai setelan — ia selalu aktif di platform yang mendukung `HapticFeedback`.

---

## Dokumentasi & Aturan Workspace

- `GEMINI.md` — aturan pengembangan workspace yang wajib dipatuhi: riset dokumentasi resmi terbaru, best practice Dart/Flutter modern, konsistensi arsitektur, dan validasi `flutter analyze` bersih + `flutter test` 100% lolos.
- Alur gestur, ambang drag/tap, pemisahan repaint, dan kebijakan audio tidak dijelaskan di dokumen terpisah; semuanya hidup di doc comment pada file yang mengimplementasikannya — `soroban_view.dart` (sesi pointer, ambang, glosir), `soroban_painter.dart` (sorotan & geometri manik), `sound_service.dart` (kebijakan pool), dan `soroban_controller.dart` (jam, checkpoint). Baca doc comment di sana sebelum mengubah perilaku yang sama.
