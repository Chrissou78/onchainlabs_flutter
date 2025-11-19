import 'package:flutter/material.dart';
import 'package:onchainlabs_flutter/onchainlabs_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = OnchainLabsApi();
  final manager = await PolygonWalletManager.create(api);

  runApp(OnchainlabsApp(manager: manager));
}

class OnchainlabsApp extends StatelessWidget {
  final PolygonWalletManager manager;

  const OnchainlabsApp({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onchainlabs Wallet Example',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: WalletScreen(manager: manager),
    );
  }
}

class WalletScreen extends StatefulWidget {
  final PolygonWalletManager manager;

  const WalletScreen({super.key, required this.manager});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  PolygonWallet? _wallet;
  bool _busy = false;
  String _status = '';
  String _backendAddress = '';
  String _randomMessage = '';

  final TextEditingController _mnemonicController = TextEditingController();

  // We use a direct API client here to show low-level getRandomMessage usage.
  final OnchainLabsApi _api = OnchainLabsApi();

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _mnemonicController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Onchainlabs Wallet Example'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),

            // Wallet actions
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final w =
                                  await widget.manager.createWallet();
                              setState(() {
                                _wallet = w;
                                _backendAddress = '';
                                _randomMessage = '';
                                _status =
                                    'createWallet: wallet created and registered';
                              });
                            }),
                    child: const Text('Create wallet'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                              final w =
                                  await widget.manager.initWallet();
                              setState(() {
                                _wallet = w;
                                _backendAddress = '';
                                _randomMessage = '';
                                _status =
                                    'initWallet: loaded stored wallet or created new';
                              });
                            }),
                    child: const Text('Init wallet'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await widget.manager.clearStoredMnemonic();
                        setState(() {
                          _wallet = null;
                          _backendAddress = '';
                          _randomMessage = '';
                          _status = 'Stored mnemonic cleared';
                        });
                      }),
              child: const Text('Clear stored wallet'),
            ),

            const SizedBox(height: 24),
            const Text(
              'Restore from mnemonic:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: _mnemonicController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter 12 or 24 word phrase',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final phrase =
                            _mnemonicController.text.trim();
                        if (phrase.isEmpty) {
                          setState(() {
                            _status =
                                'Restore: mnemonic field is empty';
                          });
                          return;
                        }

                        final w = await widget.manager
                            .restoreWallet(phrase);
                        setState(() {
                          _wallet = w;
                          _backendAddress = '';
                          _randomMessage = '';
                          _status =
                              'restoreWallet: wallet restored, registered, and stored';
                        });
                      }),
              child: const Text('Restore wallet'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Explicit random message test
            const Text(
              'Random message (API, low-level test):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy || wallet == null
                  ? null
                  : () => _run(() async {
                        // This hits the real endpoint:
                        // POST https://ga-api.onchainlabs.ch/random
                        final msg = await _api.getRandomMessage(
                          wallet.address,
                        );
                        setState(() {
                          _randomMessage = msg;
                          _status =
                              'getRandomMessage: challenge fetched from backend';
                        });
                      }),
              child: const Text('Get random message for current wallet'),
            ),
            const SizedBox(height: 8),
            if (_randomMessage.isNotEmpty) ...[
              const Text(
                'Current random message:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(
                _randomMessage,
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
            ],

            const Divider(),
            const SizedBox(height: 16),

            // Auth actions
            const Text(
              'Authentication (real API, high-level):',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy || wallet == null
                  ? null
                  : () => _run(() async {
                        // This does:
                        // 1) getRandomMessage(wallet.address)
                        // 2) sign with private key
                        // 3) registerWallet(message, signature)
                        final addr = await widget.manager
                            .authenticateWallet(wallet);
                        setState(() {
                          _backendAddress = addr;
                          _status =
                              'authenticateWallet: backend accepted wallet';
                        });
                      }),
              child: const Text('Auth current wallet'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        final addr = await widget.manager
                            .authenticateStoredWallet();
                        setState(() {
                          _backendAddress = addr;
                          _status =
                              'authenticateStoredWallet: backend accepted stored wallet';
                        });
                      }),
              child: const Text('Auth stored wallet'),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Wallet info
            if (wallet != null) ...[
              const Text(
                'Wallet address:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(wallet.address),
              const SizedBox(height: 8),

              const Text(
                'Private key (hex):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText('0x${wallet.privateKeyHex}'),
              const SizedBox(height: 8),

              const Text(
                'Mnemonic:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(wallet.mnemonic),
              const SizedBox(height: 16),
            ],

            if (_backendAddress.isNotEmpty) ...[
              const Text(
                'Backend address:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(_backendAddress),
              const SizedBox(height: 16),
            ],

            const Text(
              'Status:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(_status, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
