import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
// ignore: avoid_web_libraries_in_flutter
import 'dart:web_audio' as web_audio;

import 'audio_capture_base.dart';

AudioCaptureBase createAudioCapture() => WebAudioCapture();

class WebAudioCapture extends AudioCaptureBase {
  web_audio.AudioContext? _context;
  web_audio.ScriptProcessorNode? _processor;
  web_audio.GainNode? _gain;
  html.MediaStream? _stream;
  StreamSubscription? _processSub;

  @override
  Future<bool> init() async => true;

  @override
  Future<void> start(
    AudioDataCallback onData,
    AudioErrorCallback onError, {
    int sampleRate = 44100,
    int bufferSize = 4096,
  }) async {
    try {
      // getUserMedia triggers the browser's own permission prompt
      _stream = await html.window.navigator.mediaDevices!
          .getUserMedia({'audio': true});

      _context = web_audio.AudioContext();

      // Resume context if browser autoplay policy suspended it
      if (_context!.state == 'suspended') {
        await _context!.resume();
      }

      final source = _context!.createMediaStreamSource(_stream!);
      _processor = _context!.createScriptProcessor(bufferSize, 1, 1);

      // Muted gain node so mic audio is processed but not played back
      _gain = _context!.createGain();
      _gain!.gain!.value = 0;

      _processSub = _processor!.onAudioProcess.listen((event) {
        final Float32List data = event.inputBuffer!.getChannelData(0);
        // Pass a copy so the buffer can be reused by the browser
        onData(Float32List.fromList(data));
      });

      source.connectNode(_processor!);
      _processor!.connectNode(_gain!);
      _gain!.connectNode(_context!.destination!);
    } catch (e) {
      onError(e);
    }
  }

  @override
  Future<void> stop() async {
    _processSub?.cancel();
    _processSub = null;
    _processor?.disconnect();
    _gain?.disconnect();
    _stream?.getTracks().forEach((track) => track.stop());
    if (_context != null && _context!.state != 'closed') {
      await _context!.close();
    }
    _context = null;
    _processor = null;
    _gain = null;
    _stream = null;
  }
}
