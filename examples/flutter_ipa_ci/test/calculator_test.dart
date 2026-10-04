import 'package:flutter_test/flutter_test.dart';
import 'package:ipa_ci_demo/calculator.dart';

void main() {
  const engine = CalculatorEngine();

  test('adds two numbers', () {
    expect(engine.calculate(8, 4, CalculatorOperation.add), 12);
  });

  test('subtracts two numbers', () {
    expect(engine.calculate(8, 4, CalculatorOperation.subtract), 4);
  });

  test('multiplies two numbers', () {
    expect(engine.calculate(8, 4, CalculatorOperation.multiply), 32);
  });

  test('divides two numbers', () {
    expect(engine.calculate(8, 4, CalculatorOperation.divide), 2);
  });

  test('rejects division by zero', () {
    expect(
      () => engine.calculate(8, 0, CalculatorOperation.divide),
      throwsA(isA<CalculatorException>()),
    );
  });

  test('formats whole and decimal results', () {
    expect(formatResult(3), '3');
    expect(formatResult(10 / 4), '2.5');
  });
}
