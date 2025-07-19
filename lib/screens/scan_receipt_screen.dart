import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
    final cams = await availableCameras();
    _controller = CameraController(
      cams.first,
      ResolutionPreset.max,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() => _initializing = false);
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
            Flexible(child: Text("Uploading…")),
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

      await ref.putFile(file);

      // 3. Poll Firestore until CF writes its doc
      final q = FirebaseFirestore.instance
          .collection("receipts")
          .where("storagePath", isEqualTo: ref.fullPath)
          .limit(1);

      DocumentSnapshot? snap;
      while (snap == null) {
        await Future.delayed(const Duration(seconds: 1));
        final res = await q.get();
        if (res.docs.isNotEmpty) snap = res.docs.first;
      }
      if (!mounted) return;
      Navigator.pop(context); // close dialog
      Navigator.pop(context, snap.id); // return Firestore doc-ID
    } catch (e) {
      if (mounted) Navigator.pop(context);
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
        if (_controller != null) CameraPreview(_controller!),
        Positioned(
          bottom: 40,
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
                    width: 60,
                    height: 60,
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
    ),
  );

  /* Polished preview UI */
  Widget _previewView() => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            _captured = null;
            _enterImmersive();
          });
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.check),
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
