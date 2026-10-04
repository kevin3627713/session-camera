import 'package:flutter/cupertino.dart';

import 'calculator.dart';

void main() {
  runApp(const IpaCiCalculatorApp());
}

class IpaCiCalculatorApp extends StatelessWidget {
  const IpaCiCalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      debugShowCheckedModeBanner: false,
      home: CalculatorPage(),
    );
  }
}

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage> {
  final _leftController = TextEditingController(text: '12');
  final _rightController = TextEditingController(text: '3');
  final _engine = const CalculatorEngine();

  CalculatorOperation _operation = CalculatorOperation.add;
  String _result = '15';

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  void _calculate(CalculatorOperation operation) {
    final left = double.tryParse(_leftController.text.trim());
    final right = double.tryParse(_rightController.text.trim());

    setState(() {
      _operation = operation;

      if (left == null || right == null) {
        _result = 'Enter two valid numbers';
        return;
      }

      try {
        _result = formatResult(_engine.calculate(left, right, operation));
      } on CalculatorException catch (error) {
        _result = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('Calculator Demo'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                'Simple calculator for GitHub Actions IPA builds',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 28),
              _NumberField(
                label: 'First number',
                controller: _leftController,
                onSubmitted: (_) => _calculate(_operation),
              ),
              const SizedBox(height: 14),
              _NumberField(
                label: 'Second number',
                controller: _rightController,
                onSubmitted: (_) => _calculate(_operation),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: CalculatorOperation.values
                    .map(
                      (operation) => CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 12,
                        ),
                        onPressed: () => _calculate(operation),
                        child: Text(operation.symbol),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 28),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Text(
                        'Result of ${_operation.symbol}',
                        style: const TextStyle(
                          color: CupertinoColors.systemGrey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _result,
                        key: const ValueKey('calculator-result'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      placeholder: label,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Text('$label: '),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      onSubmitted: onSubmitted,
    );
  }
}
