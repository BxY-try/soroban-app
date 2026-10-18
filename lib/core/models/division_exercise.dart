/// Integer powers keep fixed-point division exact on native and web targets.
int decimalPower(int exponent) {
  if (exponent < 0 || exponent > 12) {
    throw ArgumentError.value(exponent, 'exponent');
  }
  var value = 1;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}

/// A physical board with a work area on the left, one unused rod, and a
/// quotient on the right. Capacities depend on the exercise level, never on
/// the length of the particular answer. Both areas use the SAME fixed scale;
/// no rod changes its meaning halfway through decimal division.
class DivisionLayout {
  final int dividendDigits;
  final int quotientIntegerDigits;
  final int decimalPlaces;

  const DivisionLayout({
    required this.dividendDigits,
    required this.quotientIntegerDigits,
    this.decimalPlaces = 0,
  });

  int get scale => decimalPower(decimalPlaces);
  int get resultRods => quotientIntegerDigits + decimalPlaces;
  int get spacerRod => resultRods;
  int get workOffset => resultRods + 1;
  int get workRods => dividendDigits + decimalPlaces;
  int get rodCount => workOffset + workRods;
  int get workMultiplier => decimalPower(workOffset);
  int get resultUnitsRod => decimalPlaces;
  int get workUnitsRod => workOffset + decimalPlaces;

  int encode({required int work, required int quotient}) {
    if (work < 0 ||
        work >= decimalPower(workRods) ||
        quotient < 0 ||
        quotient >= decimalPower(resultRods)) {
      throw ArgumentError('Division values do not fit their board areas');
    }
    return work * workMultiplier + quotient;
  }

  int workValue(int board) => board ~/ workMultiplier;
  int quotientValue(int board) => board % decimalPower(resultRods);

  String format(int scaledValue) {
    if (decimalPlaces == 0) return '$scaledValue';
    final digits = scaledValue.toString().padLeft(decimalPlaces + 1, '0');
    final split = digits.length - decimalPlaces;
    return '${digits.substring(0, split)},${digits.substring(split)}';
  }

  String resultPlace(int rod) {
    final power = rod - decimalPlaces;
    if (power >= 0) return '${decimalPower(power)}';
    return '0,${'0' * (-power - 1)}1';
  }

  /// External readout labels, not dividers painted inside the abacus.
  String rodLabel(int rod) {
    if (rod == spacerRod) return 'kosong';
    final local = rod >= workOffset ? rod - workOffset : rod;
    return resultPlace(local);
  }
}

class DivisionExercise {
  final DivisionLayout layout;
  final int dividend;
  final int divisor;

  const DivisionExercise({
    required this.layout,
    required this.dividend,
    required this.divisor,
  });

  int get initialValue => layout.encode(
        work: dividend * layout.scale,
        quotient: 0,
      );

  String get introduction => 'Soal/sisa di kiri, hasil di kanan. '
      'Sisakan satu tiang kosong di antaranya. '
      'Label 1 menunjukkan satuan tiap area.'
      '${layout.decimalPlaces > 0 ? ' Tiang 0,1 dan seterusnya sudah tersedia; nilai tempatnya tetap.' : ''}';
}
