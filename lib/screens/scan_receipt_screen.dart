import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({Key? key}) : super(key: key);

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  XFile? _captured;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterImmersive();
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitImmersive();
    _controller?.dispose();
    super.dispose();
  }

  /* ---------------- SYSTEM UI ---------------- */
  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed && _captured == null) {
      _initCamera();
    }
  }

  /* ---------------- CAMERA ---------------- */
  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw CameraException('none', 'No camera');
      _controller = CameraController(
        cams.first,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await _controller!.initialize();
    } catch (_) {
      // No camera (e.g. the simulator) or no permission: offer Photos instead.
      _controller = null;
    }
    if (mounted) setState(() => _initializing = false);
  }

  /// A receipt photo taken earlier, or a screenshot of an e-receipt.
  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92, // always hands back a JPEG
    );
    if (picked == null) return;
    _exitImmersive();
    setState(() => _captured = XFile(picked.path));
  }

  Future<void> _takePhoto() async {
    final tmp = await getTemporaryDirectory();
    final path = p.join(tmp.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");
    final shot = await _controller!.takePicture();
    await shot.saveTo(path);
    _exitImmersive(); // Show system UI in preview mode
    setState(() => _captured = XFile(path));
  }

  /* ---------------- SEND BUTTON ---------------- */
  Future<void> _send() async {
    if (_captured == null) return;
    // 1. Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Flexible(child: Text("Reading your receipt…")),
          ],
        ),
      ),
    );

    try {
      // 2. Upload JPEG to Cloud Storage  → triggers CF
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final fileName = "${DateTime.now().millisecondsSinceEpoch}.jpg";
      final ref = FirebaseStorage.instance.ref("receipts/$uid/$fileName");
      final file = File(_captured!.path);

      await ref.putFile(file, SettableMetadata(contentType: "image/jpeg"));

      // 3. Wait for the Cloud Function to write the parsed receipt
      final snap = await FirebaseFirestore.instance
          .collection("receipts")
          .where("storagePath", isEqualTo: ref.fullPath)
          .limit(1)
          .snapshots()
          .firstWhere((res) => res.docs.isNotEmpty)
          .timeout(const Duration(seconds: 180))
          .then((res) => res.docs.first);
      if (!mounted) return;
      Navigator.pop(context); // close dialog

      if (snap.data()['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't read that receipt. Try a flatter, "
              "well-lit photo with the whole receipt in frame."),
        ));
        return; // stay on the preview so they can retake it
      }
      Navigator.pop(context, snap.id); // return Firestore doc-ID
    } on TimeoutException {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Reading the receipt is taking too long. Try again in a minute."),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed: $e")),
      );
    }
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _captured == null ? _cameraView() : _previewView();
  }

  /* Full‑screen camera view */
  Widget _cameraView() => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null)
          CameraPreview(_controller!)
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.no_photography_outlined,
                    color: Colors.white70, size: 48),
                const SizedBox(height: 12),
                const Text('Camera unavailable',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from Photos'),
                  onPressed: _pickPhoto,
                ),
              ],
            ),
          ),

        /* ← BACK */
        Positioned(
          top: 8,
          left: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
              onPressed: () {
                _exitImmersive();
                Navigator.pop(context);
              },
            ),
          ),
        ),

        if (_controller != null) ...[
          /* Photos */
          Positioned(
            bottom: 32,
            left: 32,
            child: IconButton(
              icon: const Icon(Icons.photo_library_outlined,
                  color: Colors.white, size: 32),
              tooltip: 'Choose from Photos',
              onPressed: _pickPhoto,
            ),
          ),

          /* Shutter */
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: const Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 65,
                      height: 65,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  /* Polished preview UI */
  /* Polished preview UI with help button */
  Widget _previewView() => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        color: Colors.red,
        onPressed: () {
          setState(() {
            _captured = null;
            _enterImmersive();
          });
        },
      ),
      actions: [
        /* HELP */
        IconButton(
          icon: const Icon(Icons.help_outline),
          color: Colors.blue,
          tooltip: 'How to take a good photo',
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => const AlertDialog(
                title: Text('Photo quality tips'),
                content: Text(
                  'Make sure the receipt is well‑lit, flat, and fills most of the frame. '
                      'Blurred or dim shots may not be processed correctly.',
                ),
              ),
            );
          },
        ),

        /* SEND */
        IconButton(
          icon: const Icon(Icons.check),
          color: Colors.green,
          onPressed: _send,
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.file(
            File(_captured!.path),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    ),
  );
}
