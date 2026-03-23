import 'dart:async';
import 'package:flutter/material.dart';
import 'game/empire_flight_game.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
    debugPrintStack(stackTrace: details.stack);
  };

  runZonedGuarded(() {
    runApp(const EmpireFlightApp());
  }, (error, stack) {
    debugPrint('ZONE ERROR: $error');
    debugPrintStack(stackTrace: stack);
  });
}

class EmpireFlightApp extends StatelessWidget {
  const EmpireFlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Empire Flight',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF05070D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7FDBFF),
          secondary: Color(0xFFFFC857),
        ),
      ),
      home: const GameBootScreen(),
    );
  }
}

/// HACKABLE NOTE:
/// This is a temporary launcher/debug screen.
/// If you can see this screen on GitHub Pages, Flutter + deployment are working,
/// and the crash is inside EmpireFlightGame.
class GameBootScreen extends StatefulWidget {
  const GameBootScreen({super.key});

  @override
  State<GameBootScreen> createState() => _GameBootScreenState();
}

class _GameBootScreenState extends State<GameBootScreen> {
  bool _launchGame = false;
  Object? _caughtError;
  StackTrace? _caughtStack;

  @override
  Widget build(BuildContext context) {
    if (_launchGame) {
      return _GameErrorBoundary(
        onError: (error, stack) {
          setState(() {
            _caughtError = error;
            _caughtStack = stack;
            _launchGame = false;
          });
        },
        child: const EmpireFlightGame(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF101826),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF182235),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x4488AAFF), width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 20,
                      color: Color(0x44000000),
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'EMPIRE FLIGHT',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Boot screen loaded successfully.\n'
                      'That means Flutter and GitHub Pages are working.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _caughtError = null;
                          _caughtStack = null;
                          _launchGame = true;
                        });
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Text('Launch Game'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'HACKABLE NOTE:\n'
                      'If tapping Launch Game goes black or returns an error,\n'
                      'the issue is inside empire_flight_game.dart or one of its imports.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white54,
                      ),
                    ),
                    if (_caughtError != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A1520),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x66FF6B6B)),
                        ),
                        child: SelectableText(
                          'CAUGHT ERROR:\n$_caughtError\n\nSTACK:\n${_caughtStack ?? 'No stack trace'}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// HACKABLE NOTE:
/// This catches synchronous widget build errors from the game screen.
/// It is useful for turning a black screen into something readable.
class _GameErrorBoundary extends StatefulWidget {
  final Widget child;
  final void Function(Object error, StackTrace stack) onError;

  const _GameErrorBoundary({
    required this.child,
    required this.onError,
  });

  @override
  State<_GameErrorBoundary> createState() => _GameErrorBoundaryState();
}

class _GameErrorBoundaryState extends State<_GameErrorBoundary> {
  Object? _error;
  StackTrace? _stack;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1C1111),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: SelectableText(
                'GAME BUILD ERROR:\n$_error\n\nSTACK:\n${_stack ?? 'No stack trace'}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    try {
      return widget.child;
    } catch (e, s) {
      _error = e;
      _stack = s;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onError(e, s);
      });

      return Scaffold(
        backgroundColor: const Color(0xFF1C1111),
        body: const Center(
          child: Text(
            'Game crashed during build.',
            style: TextStyle(fontSize: 20),
          ),
        ),
      );
    }
  }
}
