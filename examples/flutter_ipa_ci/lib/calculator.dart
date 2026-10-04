enum CalculatorOperation {
  add('+'),
  subtract('-'),
  multiply('*'),
  divide('/');

  const CalculatorOperation(this.symbol);

  final String symbol;
}

class CalculatorEngine {
  const CalculatorEngine();

  double calculate(
    double left,
    double right,
    CalculatorOperation operation,
  ) {
    return switch (operation) {
      CalculatorOperation.add => left + right,
      CalculatorOperation.subtract => left - right,
      CalculatorOperation.multiply => left * right,
      CalculatorOperation.divide => right == 0
          ? throw const CalculatorException('Cannot divide by zero')
          : left / right,
    };
  }
}

class CalculatorException implements Exception {
  const CalculatorException(this.message);

  final String message;

  @override
  String toString() => message;
}

String formatResult(double value) {
  if (value.isNaN || value.isInfinite) {
    return value.toString();
  }

  final rounded = value.roundToDouble();
  if ((value - rounded).abs() < 0.000000001) {
    return rounded.toInt().toString();
  }

  return value
      .toStringAsFixed(8)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
