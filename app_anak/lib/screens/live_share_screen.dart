import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api.dart';

/// Berbagi kamera + mikrofon ke orang tua (WebRTC, role offerer).
/// Layar ini TERLIHAT: anak tahu sedang berbagi (transparan).
class LiveShareScreen extends StatefulWidget {
  final String camera; // 'front' | 'back'
  const LiveShareScreen({super.key, this.camera = 'front'});
  @override
  State<LiveShareScreen> createState() => _LiveShareScreenState();
}

class _LiveShareScreenState extends State<LiveShareScreen> {
  final _local = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  WebSocketChannel? _ws;
  String _status = 'Menyiapkan kamera…';
  bool _sharing = false;

  static const _ice = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _local.initialize();
    try {
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': widget.camera == 'back' ? 'environment' : 'user',
        },
      });
      _local.srcObject = _stream;

      final pc = await createPeerConnection(_ice);
      for (final track in _stream!.getTracks()) {
        await pc.addTrack(track, _stream!);
      }
      pc.onIceCandidate = (RTCIceCandidate c) {
        _sendSignal({
          'type': 'ice',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };
      _pc = pc;

      _connectWs();

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      _sendSignal({'type': 'offer', 'sdp': offer.sdp});

      await Api.sendEvent('live_started');
      if (mounted) setState(() { _sharing = true; _status = 'Sedang berbagi'; });
    } catch (e) {
      if (mounted) setState(() => _status = 'Gagal buka kamera: $e');
    }
  }

  void _connectWs() {
    _ws = WebSocketChannel.connect(Api.wsUri());
    _ws!.stream.listen((raw) async {
      Map<String, dynamic> msg;
      try {
        msg = Map<String, dynamic>.from(jsonDecode(raw.toString()));
      } catch (_) {
        return;
      }
      if (msg['kind'] == 'signal') {
        await _onSignal(Map<String, dynamic>.from(msg['data']));
      } else if (msg['kind'] == 'command' && msg['type'] == 'live_stop') {
        if (mounted) Navigator.of(context).maybePop();
      }
    }, onError: (_) {}, onDone: () {});
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    switch (data['type']) {
      case 'answer':
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'answer'));
        break;
      case 'ice':
        await pc.addCandidate(RTCIceCandidate(
            data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        break;
      case 'bye':
        if (mounted) Navigator.of(context).maybePop();
        break;
    }
  }

  void _sendSignal(Map<String, dynamic> data) {
    _ws?.sink.add(jsonEncode({'kind': 'signal', 'data': data}));
  }

  Future<void> _switchCamera() async {
    final tracks = _stream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  @override
  void dispose() {
    _sendSignal({'type': 'bye'});
    Api.sendEvent('live_ended');
    _stream?.getTracks().forEach((t) => t.stop());
    _stream?.dispose();
    _pc?.close();
    _ws?.sink.close();
    _local.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: RTCVideoView(_local, mirror: widget.camera == 'front')),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.videocam, color: Colors.white),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sedang berbagi kamera & suara ke orang tua',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FloatingActionButton(
                      heroTag: 'switch',
                      onPressed: _sharing ? _switchCamera : null,
                      child: const Icon(Icons.cameraswitch),
                    ),
                    FloatingActionButton.extended(
                      heroTag: 'stop',
                      backgroundColor: Colors.red,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.stop),
                      label: const Text('Hentikan'),
                    ),
                  ],
                ),
              ),
              if (!_sharing)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 12),
                      Text(_status, style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
