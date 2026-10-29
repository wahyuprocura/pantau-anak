import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../api.dart';

/// Menonton kamera & suara HP anak secara live (WebRTC, role answerer).
class LiveViewScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  const LiveViewScreen({super.key, required this.deviceId, required this.deviceName});
  @override
  State<LiveViewScreen> createState() => _LiveViewScreenState();
}

class _LiveViewScreenState extends State<LiveViewScreen> {
  final _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  WebSocketChannel? _ws;
  String _status = 'Menghubungi HP anak…';
  bool _connected = false;
  String _camera = 'front';

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
    await _renderer.initialize();
    _connectWs();
    await _createPc();
    // Minta HP anak mulai berbagi live.
    try {
      await Api.command(widget.deviceId, 'live', params: {'camera': _camera});
      setState(() => _status = 'Menunggu HP anak memulai kamera…');
    } catch (e) {
      setState(() => _status = 'Gagal minta live: $e');
    }
  }

  Future<void> _createPc() async {
    final pc = await createPeerConnection(_ice);
    pc.onTrack = (RTCTrackEvent e) {
      if (e.streams.isNotEmpty) {
        _renderer.srcObject = e.streams[0];
        if (mounted) setState(() { _connected = true; _status = 'Terhubung'; });
      }
    };
    pc.onIceCandidate = (RTCIceCandidate c) {
      _sendSignal({
        'type': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (mounted) setState(() { _connected = false; _status = 'Koneksi terputus'; });
      }
    };
    _pc = pc;
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
      if (msg['kind'] != 'signal' || msg['deviceId'] != widget.deviceId) return;
      final data = Map<String, dynamic>.from(msg['data']);
      await _onSignal(data);
    }, onError: (_) {}, onDone: () {});
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    switch (data['type']) {
      case 'offer':
        await pc.setRemoteDescription(RTCSessionDescription(data['sdp'], 'offer'));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        _sendSignal({'type': 'answer', 'sdp': answer.sdp});
        break;
      case 'ice':
        await pc.addCandidate(RTCIceCandidate(
            data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        break;
      case 'bye':
        if (mounted) setState(() { _connected = false; _status = 'HP anak mengakhiri live'; });
        break;
    }
  }

  void _sendSignal(Map<String, dynamic> data) {
    _ws?.sink.add(jsonEncode({
      'kind': 'signal',
      'deviceId': widget.deviceId,
      'data': data,
    }));
  }

  @override
  void dispose() {
    try { Api.command(widget.deviceId, 'live_stop'); } catch (_) {}
    _sendSignal({'type': 'bye'});
    _pc?.close();
    _ws?.sink.close();
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Live • ${widget.deviceName}'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _connected
                ? RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(_status, style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, color: Colors.white, size: 10),
                    const SizedBox(width: 8),
                    Text(_connected ? 'LIVE' : _status,
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
