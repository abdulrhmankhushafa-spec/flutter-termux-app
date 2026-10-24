import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KineticMusicApp());
}

class KineticMusicApp extends StatelessWidget {
  const KineticMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kinetic Guitar & Drums',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D10),
      ),
      home: const KineticInstrumentScreen(),
    );
  }
}

/* =========================================================
 * 1. محرك توليد الصوت البرمجي (بدون ملفات خارجية)
 * ========================================================= */
class SynthAudioEngine {
  static const int sampleRate = 22050;
  final List<AudioPlayer> _pool = [];
  int _poolIndex = 0;

  final Map<String, Uint8List> _guitarCache = {};
  final Map<String, Uint8List> _drumCache = {};

  Future<void> init() async {
    // إنشاء مجموعة مشغلات صوتية لدعم تعدد النغمات في نفس اللحظة (Polyphony)
    for (int i = 0; i < 8; i++) {
      final player = AudioPlayer();
      await player.setPlayerMode(PlayerMode.lowLatency);
      _pool.add(player);
    }

    // توليد أصوات الطبول مسبقاً في الذاكرة
    _drumCache['kick'] = _generateDrumWav('kick');
    _drumCache['snare'] = _generateDrumWav('snare');
    _drumCache['hihat'] = _generateDrumWav('hihat');
    _drumCache['tom'] = _generateDrumWav('tom');
  }

  void playGuitar(double freq, {double velocity = 0.85}) {
    final key = freq.toStringAsFixed(1);
    final wav = _guitarCache.putIfAbsent(key, () => _generateGuitarWav(freq));
    _playBytes(wav, velocity.clamp(0.2, 1.0));
  }

  void playDrum(String type, {double velocity = 0.9}) {
    final wav = _drumCache[type];
    if (wav != null) {
      _playBytes(wav, velocity.clamp(0.25, 1.0));
    }
  }

  void _playBytes(Uint8List bytes, double volume) {
    if (_pool.isEmpty) return;
    final player = _pool[_poolIndex];
    _poolIndex = (_poolIndex + 1) % _pool.length;
    player.setVolume(volume);
    player.play(BytesSource(bytes));
  }

  // توليد موجة وتر الجيتار (رنين متناغم + نقرة الوتر)
  Uint8List _generateGuitarWav(double freq) {
    const double duration = 1.35;
    final int numSamples = (sampleRate * duration).toInt();
    final Float64List samples = Float64List(numSamples);
    final rng = math.Random(freq.toInt());

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      final double env = math.exp(-t * 3.4);
      final double harmEnv = math.exp(-t * 7.5);

      // النغمة الأساسية + التوافقيات
      double wave = math.sin(2 * math.pi * freq * t) * 0.65;
      wave += math.sin(2 * math.pi * (freq * 2.0) * t) * 0.25 * harmEnv;
      wave += math.sin(2 * math.pi * (freq * 3.0) * t) * 0.10 * harmEnv;

      // صوت نقرة الوتر في البداية (Pluck transient)
      if (t < 0.022) {
        final double pluckEnv = math.exp(-t * 140);
        wave += (rng.nextDouble() * 2 - 1) * 0.35 * pluckEnv;
      }

      samples[i] = (wave * env).clamp(-1.0, 1.0);
    }
    return _encodeWav(samples);
  }

  // توليد أصوات الطبول الأربعة
  Uint8List _generateDrumWav(String type) {
    final double duration = type == 'hihat' ? 0.14 : 0.36;
    final int numSamples = (sampleRate * duration).toInt();
    final Float64List samples = Float64List(numSamples);
    final rng = math.Random(type.hashCode);

    for (int i = 0; i < numSamples; i++) {
      final double t = i / sampleRate;
      double val = 0;

      if (type == 'kick') {
        final double freq = 36 + 115 * math.exp(-t * 28);
        final double env = math.exp(-t * 9.5);
        val = math.sin(2 * math.pi * freq * t) * env * 0.95;
      } else if (type == 'snare') {
        final double toneEnv = math.exp(-t * 22);
        final double noiseEnv = math.exp(-t * 14);
        final double tone = math.sin(2 * math.pi * 165 * t) * toneEnv * 0.45;
        final double noise = (rng.nextDouble() * 2 - 1) * noiseEnv * 0.65;
        val = tone + noise;
      } else if (type == 'hihat') {
        final double env = math.exp(-t * 32);
        final double metallic =
            (rng.nextDouble() * 2 - 1) * math.sin(i * 0.65);
        val = metallic * env * 0.65;
      } else if (type == 'tom') {
        final double freq = 92 + 130 * math.exp(-t * 16);
        final double env = math.exp(-t * 11);
        val = math.sin(2 * math.pi * freq * t) * env * 0.85;
      }

      samples[i] = val.clamp(-1.0, 1.0);
    }
    return _encodeWav(samples);
  }

  // تحويل الإشارة الرقمية إلى ملف WAV صالح للتشغيل في الذاكرة
  Uint8List _encodeWav(Float64List samples) {
    final int dataSize = samples.length * 2;
    final ByteData buffer = ByteData(44 + dataSize);

    void writeString(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeString(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // PCM chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little); // 16-bit
    writeString(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      final int pcm = (samples[i] * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}

/* =========================================================
 * 2. هياكل البيانات (الأوتار، الطبول، الكرات الحركية، النوتات)
 * ========================================================= */
class TuningNote {
  final String note;
  final double freq;
  final int step;
  final Color color;
  final bool sharp;

  const TuningNote({
    required this.note,
    required this.freq,
    required this.step,
    required this.color,
    this.sharp = false,
  });
}

const Map<String, List<TuningNote>> kTunings = {
  'pentatonic': [
    TuningNote(note: 'C4', freq: 261.63, step: -2, color: Color(0xFFF2A65A)),
    TuningNote(note: 'D4', freq: 293.66, step: -1, color: Color(0xFFF5B873)),
    TuningNote(note: 'E4', freq: 329.63, step: 0, color: Color(0xFFE8D086)),
    TuningNote(note: 'G4', freq: 392.00, step: 2, color: Color(0xFF8FD1B6)),
    TuningNote(note: 'A4', freq: 440.00, step: 3, color: Color(0xFF7AB8E6)),
    TuningNote(note: 'C5', freq: 523.25, step: 5, color: Color(0xFFB89CF6)),
  ],
  'standard': [
    TuningNote(note: 'E3', freq: 164.81, step: -2, color: Color(0xFFF2A65A)),
    TuningNote(note: 'A3', freq: 220.00, step: 0, color: Color(0xFFF5B873)),
    TuningNote(note: 'D4', freq: 293.66, step: 2, color: Color(0xFFE8D086)),
    TuningNote(note: 'G4', freq: 392.00, step: 4, color: Color(0xFF8FD1B6)),
    TuningNote(note: 'B4', freq: 493.88, step: 6, color: Color(0xFF7AB8E6)),
    TuningNote(note: 'E5', freq: 659.25, step: 8, color: Color(0xFFB89CF6)),
  ],
  'openD': [
    TuningNote(note: 'D3', freq: 146.83, step: -1, color: Color(0xFFF2A65A)),
    TuningNote(note: 'A3', freq: 220.00, step: 1, color: Color(0xFFF5B873)),
    TuningNote(note: 'D4', freq: 293.66, step: 3, color: Color(0xFFE8D086)),
    TuningNote(
      note: 'F#4',
      freq: 369.99,
      step: 5,
      color: Color(0xFF8FD1B6),
      sharp: true,
    ),
    TuningNote(note: 'A4', freq: 440.00, step: 6, color: Color(0xFF7AB8E6)),
    TuningNote(note: 'D5', freq: 587.33, step: 8, color: Color(0xFFB89CF6)),
  ],
  'maj9': [
    TuningNote(note: 'C3', freq: 130.81, step: -2, color: Color(0xFFF2A65A)),
    TuningNote(note: 'G3', freq: 196.00, step: 1, color: Color(0xFFF5B873)),
    TuningNote(note: 'D4', freq: 293.66, step: 3, color: Color(0xFFE8D086)),
    TuningNote(note: 'E4', freq: 329.63, step: 4, color: Color(0xFF8FD1B6)),
    TuningNote(note: 'B4', freq: 493.88, step: 7, color: Color(0xFF7AB8E6)),
    TuningNote(note: 'D5', freq: 587.33, step: 9, color: Color(0xFFB89CF6)),
  ],
};

class GuitarStringModel {
  final int index;
  final double yRatio;
  double pluckX = 0.5;
  double amp = 0;
  double phase = 0;
  String note;
  double freq;
  int step;
  bool sharp;
  Color color;
  int cooldown = 0;
  double nodeXRatio;
  double nodePulse = 0;

  GuitarStringModel({
    required this.index,
    required this.yRatio,
    required this.note,
    required this.freq,
    required this.step,
    required this.sharp,
    required this.color,
    required this.nodeXRatio,
  });
}

class DrumShapeModel {
  final String id;
  final String label;
  final String shape; // circle, triangle, diamond, hexagon
  double xRatio;
  double yRatio;
  final double radius;
  final Color color;
  final int step;
  double pulse = 0;
  double angle = 0;

  DrumShapeModel({
    required this.id,
    required this.label,
    required this.shape,
    required this.xRatio,
    required this.yRatio,
    required this.radius,
    required this.color,
    required this.step,
  });
}

class KineticOrb {
  double x;
  double y;
  double prevX;
  double prevY;
  double vx;
  double vy;
  final List<Offset> trail = [];
  final Map<String, int> shapeCooldowns = {};

  KineticOrb({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
  })  : prevX = x,
        prevY = y;
}

class SoundRipple {
  final double x;
  final double y;
  double r;
  final double maxR;
  final Color color;
  double alpha;

  SoundRipple({
    required this.x,
    required this.y,
    required this.r,
    required this.maxR,
    required this.color,
    this.alpha = 0.85,
  });
}

class SheetNoteModel {
  final String kind; // 'guitar' or 'drum'
  final String? drumType;
  final String note;
  final double freq;
  final int step;
  final bool sharp;
  final Color color;
  double alpha = 0.0;

  SheetNoteModel({
    required this.kind,
    this.drumType,
    required this.note,
    required this.freq,
    required this.step,
    required this.sharp,
    required this.color,
  });
}

/* =========================================================
 * 3. الشاشة الرئيسية وحلقة الفيزياء والتفاعل
 * ========================================================= */
class KineticInstrumentScreen extends StatefulWidget {
  const KineticInstrumentScreen({super.key});

  @override
  State<KineticInstrumentScreen> createState() =>
      _KineticInstrumentScreenState();
}

class _KineticInstrumentScreenState extends State<KineticInstrumentScreen>
    with SingleTickerProviderStateMixin {
  final SynthAudioEngine _audio = SynthAudioEngine();
  late final Ticker _ticker;

  String _currentTuning = 'pentatonic';
  bool _flowActive = true;
  Size _stageSize = Size.zero;

  final List<GuitarStringModel> _strings = [];
  final List<DrumShapeModel> _drums = [];
  final List<KineticOrb> _orbs = [];
  final List<SoundRipple> _ripples = [];
  final List<SheetNoteModel> _sheetNotes = [];
  final List<Offset> _pointerTrail = [];

  // حالة اللمس والسحب
  Offset? _lastPointer;
  DrumShapeModel? _draggingDrum;
  GuitarStringModel? _draggingNode;
  double _movedDistance = 0;
  final Map<String, int> _pointerCooldowns = {};
  final List<Timer> _replayTimers = [];

  @override
  void initState() {
    super.initState();
    _audio.init();
    _initInstrumentEntities();
    _ticker = createTicker(_onTick)..start();
  }

  void _initInstrumentEntities() {
    _strings.clear();
    final tuning = kTunings[_currentTuning]!;
    const count = 6;
    for (int i = 0; i < count; i++) {
      final t = tuning[count - 1 - i];
      _strings.add(
        GuitarStringModel(
          index: i,
          yRatio: 0.20 + (i / (count - 1)) * 0.60,
          note: t.note,
          freq: t.freq,
          step: t.step,
          sharp: t.sharp,
          color: t.color,
          nodeXRatio: 0.24 + ((i * 0.13) % 0.54),
        ),
      );
    }

    _drums.clear();
    _drums.addAll([
      DrumShapeModel(
        id: 'kick',
        label: 'KICK',
        shape: 'circle',
        xRatio: 0.22,
        yRatio: 0.30,
        radius: 28,
        color: const Color(0xFFF2785A),
        step: -5,
      ),
      DrumShapeModel(
        id: 'snare',
        label: 'SNARE',
        shape: 'triangle',
        xRatio: 0.78,
        yRatio: 0.34,
        radius: 28,
        color: const Color(0xFFF5C76B),
        step: 3,
      ),
      DrumShapeModel(
        id: 'hihat',
        label: 'HI-HAT',
        shape: 'diamond',
        xRatio: 0.50,
        yRatio: 0.13,
        radius: 25,
        color: const Color(0xFF7CE6D3),
        step: 9,
      ),
      DrumShapeModel(
        id: 'tom',
        label: 'TOM',
        shape: 'hexagon',
        xRatio: 0.52,
        yRatio: 0.87,
        radius: 27,
        color: const Color(0xFFA78BFA),
        step: 1,
      ),
    ]);
  }

  void _applyTuning(String key) {
    setState(() {
      _currentTuning = key;
      final tuning = kTunings[key]!;
      for (int i = 0; i < _strings.length; i++) {
        final t = tuning[_strings.length - 1 - i];
        _strings[i].note = t.note;
        _strings[i].freq = t.freq;
        _strings[i].step = t.step;
        _strings[i].sharp = t.sharp;
        _strings[i].color = t.color;
      }
    });
  }

  void _spawnOrb({double? x, double? y}) {
    if (_stageSize == Size.zero) return;
    final rng = math.Random();
    final angle = rng.nextDouble() * math.pi * 2;
    final speed = 2.4 + rng.nextDouble() * 1.3;
    _orbs.add(
      KineticOrb(
        x: x ?? _stageSize.width * (0.25 + rng.nextDouble() * 0.5),
        y: y ?? _stageSize.height * (0.25 + rng.nextDouble() * 0.5),
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
      ),
    );
  }

  void _onTick(Duration elapsed) {
    if (_stageSize == Size.zero) return;

    // 1. تحديث اهتزاز الأوتار
    for (final s in _strings) {
      if (s.cooldown > 0) s.cooldown--;
      if (s.nodePulse > 0) s.nodePulse *= 0.92;
      if (s.amp > 0.05) {
        s.phase += 0.42;
        s.amp *= 0.94;
      } else {
        s.amp = 0;
      }
    }

    // 2. تحديث دوران ونبض أشكال الطبول
    for (final d in _drums) {
      d.pulse *= 0.90;
      d.angle += 0.005 + d.pulse * 0.04;
    }

    // 3. تحديث الكرات الحركية وفحص تقاطعها مع الأوتار والأشكال
    final padX = _stageSize.width * 0.06;
    const padY = 22.0;

    for (final orb in _orbs) {
      if (_flowActive) {
        orb.prevX = orb.x;
        orb.prevY = orb.y;
        orb.x += orb.vx;
        orb.y += orb.vy;

        if (orb.x < padX || orb.x > _stageSize.width - padX) {
          orb.vx *= -1;
          orb.x = orb.x.clamp(padX, _stageSize.width - padX);
        }
        if (orb.y < padY || orb.y > _stageSize.height - padY) {
          orb.vy *= -1;
          orb.y = orb.y.clamp(padY, _stageSize.height - padY);
        }

        final speed = math.sqrt(orb.vx * orb.vx + orb.vy * orb.vy);
        _checkMotionInteractions(
          orb.prevX,
          orb.prevY,
          orb.x,
          orb.y,
          speed * 3.0,
          orb.shapeCooldowns,
        );
      }

      orb.trail.add(Offset(orb.x, orb.y));
      if (orb.trail.length > 20) orb.trail.removeAt(0);
    }

    // 4. تحديث الموجات البصرية
    for (int i = _ripples.length - 1; i >= 0; i--) {
      final rp = _ripples[i];
      rp.r += (rp.maxR - rp.r) * 0.14;
      rp.alpha *= 0.90;
      if (rp.alpha < 0.02) {
        _ripples.removeAt(i);
      }
    }

    // 5. تحديث ظهور النوتات الموسيقية
    for (final n in _sheetNotes) {
      if (n.alpha < 1.0) {
        n.alpha = (n.alpha + 0.12).clamp(0.0, 1.0);
      }
    }

    setState(() {});
  }

  void _pluckString(GuitarStringModel s, double xPos, double velocity) {
    if (s.cooldown > 0 || _stageSize == Size.zero) return;
    s.cooldown = 7;
    s.pluckX = (xPos / _stageSize.width).clamp(0.08, 0.92);
    s.amp = (12 + velocity * 16).clamp(8.0, 26.0);
    s.phase = 0;
    s.nodePulse = 1.0;

    final nodeX = s.nodeXRatio * _stageSize.width;
    final nearNode = (xPos - nodeX).abs() < 34;
    final freq = nearNode ? s.freq * 1.5 : s.freq;
    final step = nearNode ? s.step + 4 : s.step;
    final label = nearNode ? '${s.note}*' : s.note;

    _audio.playGuitar(freq, velocity: velocity);

    _ripples.add(
      SoundRipple(
        x: xPos,
        y: s.yRatio * _stageSize.height,
        r: 4,
        maxR: nearNode ? 58 : 40,
        color: s.color,
      ),
    );

    _recordSheetNote(
      SheetNoteModel(
        kind: 'guitar',
        note: label,
        freq: freq,
        step: step,
        sharp: s.sharp,
        color: s.color,
      ),
    );
  }

  void _triggerDrum(DrumShapeModel d, double velocity) {
    if (_stageSize == Size.zero) return;
    d.pulse = 1.0;
    _audio.playDrum(d.id, velocity: velocity);

    _ripples.add(
      SoundRipple(
        x: d.xRatio * _stageSize.width,
        y: d.yRatio * _stageSize.height,
        r: d.radius * 0.8,
        maxR: d.radius * 2.5,
        color: d.color,
      ),
    );

    _recordSheetNote(
      SheetNoteModel(
        kind: 'drum',
        drumType: d.id,
        note: d.label,
        freq: 0,
        step: d.step,
        sharp: false,
        color: d.color,
      ),
    );
  }

  void _recordSheetNote(SheetNoteModel note) {
    _sheetNotes.add(note);
    if (_sheetNotes.length > 50) {
      _sheetNotes.removeAt(0);
    }
  }

  void _checkMotionInteractions(
    double x1,
    double y1,
    double x2,
    double y2,
    double speed,
    Map<String, int> cooldownMap,
  ) {
    final w = _stageSize.width;
    final h = _stageSize.height;
    final leftPad = w * 0.06;
    final rightPad = w * 0.94;

    // عبور أوتار الجيتار أو العقد البلورية عليها
    for (final s in _strings) {
      final sy = s.yRatio * h;
      final crossed = (y1 <= sy && y2 >= sy) || (y1 >= sy && y2 <= sy);
      if (crossed && x2 >= leftPad && x2 <= rightPad) {
        final vel = (speed / 14).clamp(0.35, 1.0);
        _pluckString(s, x2, vel);
      } else {
        final nx = s.nodeXRatio * w;
        final dPrev = math.sqrt(math.pow(x1 - nx, 2) + math.pow(y1 - sy, 2));
        final dNow = math.sqrt(math.pow(x2 - nx, 2) + math.pow(y2 - sy, 2));
        if (dPrev > 20 && dNow <= 20) {
          _pluckString(s, nx, 0.95);
        }
      }
    }

    // المرور عبر الأشكال الهندسية للطبول
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final d in _drums) {
      final dx = d.xRatio * w;
      final dy = d.yRatio * h;
      final hitRadius = d.radius + 8;
      final dPrev = math.sqrt(math.pow(x1 - dx, 2) + math.pow(y1 - dy, 2));
      final dNow = math.sqrt(math.pow(x2 - dx, 2) + math.pow(y2 - dy, 2));

      final lastHit = cooldownMap[d.id] ?? 0;
      if (dPrev > hitRadius && dNow <= hitRadius && (nowMs - lastHit) > 130) {
        cooldownMap[d.id] = nowMs;
        final vel = (speed / 12).clamp(0.45, 1.0);
        _triggerDrum(d, vel);
      }
    }
  }

  /* =========================================================
   * 4. معالجة اللمس والسحب على شاشة الأندرويد
   * ========================================================= */
  void _onPointerDown(PointerDownEvent e) {
    final pt = e.localPosition;
    _lastPointer = pt;
    _movedDistance = 0;

    final w = _stageSize.width;
    final h = _stageSize.height;

    // فحص الضغط على أحد أشكال الطبول
    for (final d in _drums) {
      final dx = d.xRatio * w;
      final dy = d.yRatio * h;
      if ((pt - Offset(dx, dy)).distance <= d.radius + 8) {
        _draggingDrum = d;
        _triggerDrum(d, 0.92);
        return;
      }
    }

    // فحص الضغط على العقدة البلورية على الوتر
    for (final s in _strings) {
      final nx = s.nodeXRatio * w;
      final ny = s.yRatio * h;
      if ((pt - Offset(nx, ny)).distance <= 18) {
        _draggingNode = s;
        _pluckString(s, nx, 0.95);
        return;
      }
    }

    // فحص الضغط المباشر على وتر
    for (final s in _strings) {
      final sy = s.yRatio * h;
      if ((pt.dy - sy).abs() <= 12 && pt.dx >= w * 0.06 && pt.dx <= w * 0.94) {
        _pluckString(s, pt.dx, 0.85);
        return;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    final pt = e.localPosition;
    final prev = _lastPointer ?? pt;
    final speed = (pt - prev).distance;
    _movedDistance += speed;
    _lastPointer = pt;

    _pointerTrail.add(pt);
    if (_pointerTrail.length > 14) _pointerTrail.removeAt(0);

    final w = _stageSize.width;
    final h = _stageSize.height;

    if (_draggingDrum != null) {
      _draggingDrum!.xRatio = (pt.dx / w).clamp(0.08, 0.92);
      _draggingDrum!.yRatio = (pt.dy / h).clamp(0.08, 0.92);
      return;
    }

    if (_draggingNode != null) {
      _draggingNode!.nodeXRatio = (pt.dx / w).clamp(0.10, 0.90);
      return;
    }

    if (speed > 1.2) {
      _checkMotionInteractions(
        prev.dx,
        prev.dy,
        pt.dx,
        pt.dy,
        speed,
        _pointerCooldowns,
      );
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    final pt = e.localPosition;
    if (_draggingDrum == null && _draggingNode == null && _movedDistance < 10) {
      final onString = _strings.any(
        (s) => (pt.dy - s.yRatio * _stageSize.height).abs() <= 12,
      );
      if (!onString) {
        _spawnOrb(x: pt.dx, y: pt.dy);
      }
    }
    _draggingDrum = null;
    _draggingNode = null;
    _lastPointer = null;
    _pointerTrail.clear();
  }

  void _replayStaff() {
    for (final t in _replayTimers) {
      t.cancel();
    }
    _replayTimers.clear();

    final visible = _sheetNotes.length > 12
        ? _sheetNotes.sublist(_sheetNotes.length - 12)
        : List<SheetNoteModel>.from(_sheetNotes);

    for (int i = 0; i < visible.length; i++) {
      final n = visible[i];
      final timer = Timer(Duration(milliseconds: i * 190), () {
        n.alpha = 0.25;
        if (n.kind == 'guitar') {
          _audio.playGuitar(n.freq, velocity: 0.85);
        } else if (n.drumType != null) {
          _audio.playDrum(n.drumType!, velocity: 0.9);
        }
      });
      _replayTimers.add(timer);
    }
  }

  @override
  void dispose() {
    for (final t in _replayTimers) {
      t.cancel();
    }
    _ticker.dispose();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // المسرح التفاعلي للأوتار والطبول
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final newSize =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  if (_stageSize == Size.zero && newSize != Size.zero) {
                    _stageSize = newSize;
                    // إضافة كرتين حركيتين عند بدء التشغيل
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (_orbs.isEmpty) {
                        _spawnOrb(
                          x: _stageSize.width * 0.32,
                          y: _stageSize.height * 0.45,
                        );
                        _spawnOrb(
                          x: _stageSize.width * 0.68,
                          y: _stageSize.height * 0.58,
                        );
                      }
                    });
                  } else {
                    _stageSize = newSize;
                  }

                  return Stack(
                    children: [
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: StagePainter(
                            strings: _strings,
                            drums: _drums,
                            orbs: _orbs,
                            ripples: _ripples,
                            pointerTrail: _pointerTrail,
                          ),
                        ),
                      ),

                      // شريط التحكم العلوي المصغر
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildMinimalHud(),
                        ),
                      ),

                      // نص إرشادي خفيف أسفل المسرح
                      const Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: IgnorePointer(
                            child: Text(
                              'مرّر إصبعك عبر الأوتار والأشكال للعزف • انقر في الفراغ لإطلاق كرة حركية',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // شريط النوتة الموسيقية الحية في الأسفل
            Container(
              height: 175,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF13151B),
                border: Border(
                  top: BorderSide(color: Colors.white12, width: 1),
                ),
              ),
              child: Stack(
                children: [
                  CustomPaint(
                    size: const Size(double.infinity, 175),
                    painter: SheetMusicPainter(notes: _sheetNotes),
                  ),
                  Positioned(
                    top: 8,
                    right: 12,
                    child: Row(
                      children: [
                        _buildSmallButton('Replay Staff', _replayStaff),
                        const SizedBox(width: 6),
                        _buildSmallButton('Clear', () {
                          setState(() => _sheetNotes.clear());
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinimalHud() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF14161C).withOpacity(0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white12),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currentTuning,
              dropdownColor: const Color(0xFF181A20),
              style: const TextStyle(fontSize: 12, color: Color(0xFFE8E6DF)),
              isDense: true,
              items: const [
                DropdownMenuItem(
                    value: 'pentatonic', child: Text('Pentatonic')),
                DropdownMenuItem(value: 'standard', child: Text('Standard')),
                DropdownMenuItem(value: 'openD', child: Text('Open D')),
                DropdownMenuItem(value: 'maj9', child: Text('Dream Maj9')),
              ],
              onChanged: (val) {
                if (val != null) _applyTuning(val);
              },
            ),
          ),
          Container(width: 1, height: 14, color: Colors.white12),
          _buildHudChip('+ Orb', () => _spawnOrb(), false),
          _buildHudChip(
            _flowActive ? 'Flow: On' : 'Paused',
            () => setState(() => _flowActive = !_flowActive),
            _flowActive,
          ),
          _buildHudChip('Clear Orbs', () => _orbs.clear(), false),
        ],
      ),
    );
  }

  Widget _buildHudChip(String label, VoidCallback onTap, bool active) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFF2A65A).withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? const Color(0xFFF2A65A).withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? const Color(0xFFFFD19B) : const Color(0xFFE8E6DF),
          ),
        ),
      ),
    );
  }

  Widget _buildSmallButton(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ),
    );
  }
}

/* =========================================================
 * 5. رسام المسرح التفاعلي (الأوتار، الطبول، الكرات الحركية)
 * ========================================================= */
class StagePainter extends CustomPainter {
  final List<GuitarStringModel> strings;
  final List<DrumShapeModel> drums;
  final List<KineticOrb> orbs;
  final List<SoundRipple> ripples;
  final List<Offset> pointerTrail;

  StagePainter({
    required this.strings,
    required this.drums,
    required this.orbs,
    required this.ripples,
    required this.pointerTrail,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final leftX = w * 0.06;
    final rightX = w * 0.94;

    // 1. رسم الأوتار الستة مع الفيزياء الاهتزازية
    for (final s in strings) {
      final sy = s.yRatio * h;
      final displacement = math.sin(s.phase) * s.amp;
      final pluckPx = leftX + (rightX - leftX) * s.pluckX;

      final path = Path()..moveTo(leftX, sy);
      if (displacement.abs() > 0.2) {
        path.quadraticBezierTo(pluckPx, sy + displacement, rightX, sy);
      } else {
        path.lineTo(rightX, sy);
      }

      final activeGlow = (s.amp / 15.0).clamp(0.0, 1.0);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 + (strings.length - s.index) * 0.22 + activeGlow * 1.5
        ..color = activeGlow > 0.05
            ? s.color
            : const Color(0xFFE8E6DF).withOpacity(0.28);

      if (activeGlow > 0.05) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = paint.strokeWidth + 4
            ..color = s.color.withOpacity(0.3 * activeGlow)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
      canvas.drawPath(path, paint);

      // كتابة اسم النغمة على يسار الوتر
      final tp = TextPainter(
        text: TextSpan(
          text: s.note,
          style: TextStyle(
            color: activeGlow > 0.1 ? s.color : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftX - tp.width - 8, sy - tp.height / 2));

      // العقدة الهندسية على الوتر
      final nodeX = s.nodeXRatio * w;
      final nodeY = sy + displacement * 0.5;
      final nodePath = _createPolygonPath(
        nodeX,
        nodeY,
        6 + s.nodePulse * 5,
        4,
        math.pi / 4,
      );
      canvas.drawPath(nodePath, Paint()..color = const Color(0xFF14161C));
      canvas.drawPath(
        nodePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = s.color,
      );
    }

    // 2. رسم الأشكال الهندسية للطبول
    for (final d in drums) {
      final dx = d.xRatio * w;
      final dy = d.yRatio * h;
      final r = d.radius + d.pulse * 8;

      Path shapePath;
      if (d.shape == 'circle') {
        shapePath = Path()
          ..addOval(Rect.fromCircle(center: Offset(dx, dy), radius: r));
      } else if (d.shape == 'triangle') {
        shapePath = _createPolygonPath(dx, dy, r * 1.12, 3, d.angle - math.pi / 2);
      } else if (d.shape == 'diamond') {
        shapePath = _createPolygonPath(dx, dy, r * 1.08, 4, d.angle);
      } else {
        shapePath = _createPolygonPath(dx, dy, r, 6, d.angle);
      }

      canvas.drawPath(
        shapePath,
        Paint()..color = const Color(0xFF14161C).withOpacity(0.82),
      );

      if (d.pulse > 0.05) {
        canvas.drawPath(
          shapePath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = d.color.withOpacity(0.45 * d.pulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      canvas.drawPath(
        shapePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 + d.pulse * 2.0
          ..color = d.color,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: d.label,
          style: TextStyle(
            color: d.pulse > 0.15 ? Colors.white : Colors.white60,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    }

    // 3. رسم الكرات الحركية ومسارها المضيء
    for (final orb in orbs) {
      for (int i = 1; i < orb.trail.length; i++) {
        final ratio = i / orb.trail.length;
        canvas.drawLine(
          orb.trail[i - 1],
          orb.trail[i],
          Paint()
            ..color = const Color(0xFFF2A65A).withOpacity(ratio * 0.45)
            ..strokeWidth = ratio * 4
            ..strokeCap = StrokeCap.round,
        );
      }

      canvas.drawCircle(
        Offset(orb.x, orb.y),
        9,
        Paint()
          ..color = const Color(0xFFF2A65A).withOpacity(0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawCircle(
        Offset(orb.x, orb.y),
        5.5,
        Paint()..color = const Color(0xFFFFF5E6),
      );
    }

    // 4. رسم مسار اللمس
    for (int i = 1; i < pointerTrail.length; i++) {
      final ratio = i / pointerTrail.length;
      canvas.drawLine(
        pointerTrail[i - 1],
        pointerTrail[i],
        Paint()
          ..color = Colors.white.withOpacity(ratio * 0.25)
          ..strokeWidth = 2,
      );
    }

    // 5. رسم الموجات الصوتية المتسعة
    for (final rp in ripples) {
      canvas.drawCircle(
        Offset(rp.x, rp.y),
        rp.r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = rp.color.withOpacity(rp.alpha.clamp(0.0, 1.0)),
      );
    }
  }

  static Path _createPolygonPath(
      double x, double y, double radius, int sides, double rotation) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final a = rotation + (i * math.pi * 2) / sides;
      final px = x + math.cos(a) * radius;
      final py = y + math.sin(a) * radius;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant StagePainter oldDelegate) => true;
}

/* =========================================================
 * 6. رسام النوتة الموسيقية الحية في الأسفل
 * ========================================================= */
class SheetMusicPainter extends CustomPainter {
  final List<SheetNoteModel> notes;

  SheetMusicPainter({required this.notes});

  @override
  void paint(Canvas canvas, Size size) {
    final sw = size.width;
    final sh = size.height;

    const lineSpacing = 11.5;
    const stepSpacing = lineSpacing / 2;
    final bottomLineY = sh * 0.62;
    const staffLeft = 52.0;
    final staffRight = sw - 18.0;

    // 1. رسم خطوط المدرج الموسيقي الخمسة
    final linePaint = Paint()
      ..color = const Color(0xFFE8E6DF).withOpacity(0.18)
      ..strokeWidth = 1;

    for (int line = 0; line < 5; line++) {
      final y = bottomLineY - line * lineSpacing;
      canvas.drawLine(Offset(16, y), Offset(staffRight, y), linePaint);
    }

    // خط الإيقاع السفلي للطبول
    final bassLineY = bottomLineY + lineSpacing * 2.1;
    canvas.drawLine(
      Offset(16, bassLineY),
      Offset(staffRight, bassLineY),
      Paint()
        ..color = Colors.white.withOpacity(0.07)
        ..strokeWidth = 1,
    );

    // مفتاح صول الموسيقي (Treble Clef)
    final clefPainter = TextPainter(
      text: const TextSpan(
        text: '𝄞',
        style: TextStyle(fontSize: 34, color: Colors.white60),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    clefPainter.paint(
      canvas,
      Offset(22, bottomLineY - lineSpacing * 3.6),
    );

    // حساب عدد النوتات الظاهرة حسب عرض شاشة الهاتف
    const noteSpacing = 34.0;
    final maxVisible =
        math.max(6, ((staffRight - staffLeft - 20) / noteSpacing).floor());
    final visibleNotes = notes.length > maxVisible
        ? notes.sublist(notes.length - maxVisible)
        : notes;

    // 2. رسم كل نوتة موسيقية على المدرج
    for (int i = 0; i < visibleNotes.length; i++) {
      final n = visibleNotes[i];
      final x = staffLeft + 18 + i * noteSpacing;
      final y = bottomLineY - n.step * stepSpacing;
      final color = n.color.withOpacity(n.alpha.clamp(0.0, 1.0));

      // خطوط إضافية للنوتات المنخفضة (Ledger lines)
      if (n.kind == 'guitar' && n.step <= -2) {
        for (int st = -2; st >= n.step; st -= 2) {
          final ly = bottomLineY - st * stepSpacing;
          canvas.drawLine(
            Offset(x - 9, ly),
            Offset(x + 9, ly),
            Paint()
              ..color = Colors.white38.withOpacity(n.alpha)
              ..strokeWidth = 1.2,
          );
        }
      }

      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      if (n.kind == 'guitar') {
        // رأس النوتة البيضاوي المائل
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.3);
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 11.5, height: 8.2),
          fillPaint,
        );
        canvas.restore();

        // ساق النوتة (Stem)
        if (n.step < 4) {
          canvas.drawLine(Offset(x + 5, y), Offset(x + 5, y - 26), strokePaint);
        } else {
          canvas.drawLine(Offset(x - 5, y), Offset(x - 5, y + 26), strokePaint);
        }
      } else {
        // تدوين الطبول (X للهاي هات، معين للسنير والتوم، دائرة للكيك)
        if (n.drumType == 'hihat') {
          const sz = 4.5;
          canvas.drawLine(
              Offset(x - sz, y - sz), Offset(x + sz, y + sz), strokePaint);
          canvas.drawLine(
              Offset(x + sz, y - sz), Offset(x - sz, y + sz), strokePaint);
          canvas.drawLine(
              Offset(x + sz, y), Offset(x + sz, y - 22), strokePaint);
        } else if (n.drumType == 'snare' || n.drumType == 'tom') {
          final p = StagePainter._createPolygonPath(x, y, 5.5, 4, 0);
          canvas.drawPath(p, fillPaint);
          canvas.drawLine(Offset(x + 5, y), Offset(x + 5, y - 22), strokePaint);
        } else {
          final ky = bassLineY;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(x, ky), width: 11, height: 8),
            strokePaint,
          );
          canvas.drawLine(
              Offset(x - 5, ky), Offset(x - 5, ky + 16), strokePaint);
        }
      }

      // اسم النغمة أسفل المدرج
      final labelTp = TextPainter(
        text: TextSpan(
          text: n.note,
          style: TextStyle(
            fontSize: 9,
            color: Colors.white54.withOpacity(n.alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelTp.paint(canvas, Offset(x - labelTp.width / 2, sh - 18));
    }

    if (visibleNotes.isEmpty) {
      final emptyTp = TextPainter(
        text: const TextSpan(
          text: 'النوتة الموسيقية تُكتب هنا مباشرة عند العزف...',
          style: TextStyle(fontSize: 12, color: Colors.white24),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      emptyTp.paint(
        canvas,
        Offset((sw - emptyTp.width) / 2, bottomLineY - lineSpacing * 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant SheetMusicPainter oldDelegate) => true;
}

