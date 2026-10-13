import 'dart:math' as math;
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'wheel_feed.dart';

/// Home "live world map".
///
/// * Background: a static night-lights world map (assets/images/
///   world_map.jpg), cropped tight to the continents. The sea is painted in
///   the app's page colour (AppColors.background / hero, #02050C) in the
///   image itself, so land floats on the page — no frame, no runtime cost.
///   Shown full width, edge to edge.
/// * Overlay (one CustomPainter): small neon trucks in mixed colours drive
///   along arcs between cities — glowing trail behind, thin dashed road
///   ahead, moving » chevrons — hubs pulse with rings (big hubs orange),
///   a ring flashes when a truck arrives or a "new load" pings at a random
///   city, and ~300 city lights twinkle.
///
/// Performance: one Ticker drives a ValueNotifier the painter listens to
/// (no widget rebuilds per frame); trucks are plain objects reused from a
/// fixed pool; no blur filters (glow = a wider, faint stroke). It pauses
/// while the feed scrolls, when the map is scrolled out of view and when
/// the tab is hidden (TickerMode). If frames get slow it drops to ~30 fps,
/// fewer trucks and no dashes / chevrons.
class LiveMap extends StatefulWidget {
  /// Text of the blinking badge in the map's top-right corner.
  final String liveLabel;
  const LiveMap({super.key, this.liveLabel = 'CANLI'});

  @override
  State<LiveMap> createState() => _LiveMapState();
}

/// Size of assets/images/world_map.jpg: the world cropped tight to the
/// continents (no empty margins), so the map looks big on a phone.
const double _imgW = 1220, _imgH = 580;

/// Hub positions below are on the original 1400×700 map; the shipped image
/// is that map cropped at this offset.
const Offset _crop = Offset(80, 40);

/// Hubs (pixel position on the map image), every continent; the Caucasus /
/// Turkey / Central Asia region is denser — that is where the loads are.
const List<Offset> _hubs = [
  Offset(254, 224), // New York
  Offset(104, 256), // Los Angeles
  Offset(220, 214), // Chicago
  Offset(142, 309), // Mexico City
  Offset(206, 373), // Bogotá
  Offset(321, 490), // São Paulo
  Offset(282, 536), // Buenos Aires
  Offset(558, 174), // London
  Offset(599, 186), // Central Europe
  Offset(539, 223), // Madrid
  Offset(698, 153), // Moscow
  Offset(693, 231), // Istanbul
  Offset(718, 264), // Cairo
  Offset(558, 371), // Lagos
  Offset(773, 426), // Nairobi
  Offset(693, 528), // Johannesburg
  Offset(795, 228), // Baku
  Offset(832, 295), // Dubai
  Offset(820, 244), // Tehran
  Offset(947, 215), // Almaty
  Offset(936, 281), // Delhi
  Offset(924, 327), // Mumbai
  Offset(937, 151), // Novosibirsk
  Offset(1135, 223), // Beijing
  Offset(1159, 269), // Shanghai
  Offset(1225, 253), // Tokyo
  Offset(1133, 312), // Hong Kong
  Offset(1082, 412), // Singapore
  Offset(1103, 448), // Jakarta
  Offset(1247, 570), // Sydney
  Offset(1125, 557), // Perth
  Offset(778, 218), // Tbilisi
  Offset(782, 234), // Yerevan
  Offset(705, 238), // Ankara
  Offset(672, 168), // Kyiv
  Offset(628, 163), // Warsaw
  Offset(832, 212), // Aktau
  Offset(862, 242), // Ashgabat
  Offset(905, 222), // Tashkent
  Offset(938, 208), // Bishkek
];

/// Big hubs (orange): Central Europe, Moscow, Istanbul, Baku, Shanghai.
const Set<int> _bigHubs = {8, 10, 11, 16, 24};

/// City lights that twinkle (bright points of the cropped map image).
const List<Offset> _sparks = [
  Offset(1108, 221), Offset(451, 129), Offset(575, 148), Offset(482, 322), Offset(621, 490),
  Offset(522, 161), Offset(524, 131), Offset(628, 228), Offset(559, 135), Offset(867, 236),
  Offset(517, 101), Offset(132, 191), Offset(447, 335), Offset(517, 200), Offset(615, 496),
  Offset(182, 314), Offset(494, 160), Offset(1075, 239), Offset(152, 180), Offset(851, 277),
  Offset(1045, 203), Offset(621, 179), Offset(862, 257), Offset(609, 174), Offset(636, 206),
  Offset(571, 137), Offset(649, 220), Offset(535, 142), Offset(856, 237), Offset(254, 455),
  Offset(482, 339), Offset(1055, 212), Offset(630, 182), Offset(676, 270), Offset(1053, 205),
  Offset(1059, 226), Offset(448, 342), Offset(122, 217), Offset(844, 252), Offset(476, 318),
  Offset(610, 189), Offset(869, 249), Offset(502, 162), Offset(543, 133), Offset(517, 130),
  Offset(673, 164), Offset(465, 192), Offset(550, 112), Offset(1071, 192), Offset(1065, 217),
  Offset(604, 498), Offset(1044, 196), Offset(122, 181), Offset(1065, 194), Offset(874, 334),
  Offset(501, 153), Offset(543, 116), Offset(535, 172), Offset(1064, 233), Offset(522, 138),
  Offset(1024, 326), Offset(145, 197), Offset(1058, 201), Offset(502, 133), Offset(125, 233),
  Offset(1070, 228), Offset(851, 245), Offset(144, 182), Offset(163, 184), Offset(760, 258),
  Offset(561, 103), Offset(612, 491), Offset(260, 444), Offset(159, 190), Offset(652, 203),
  Offset(621, 466), Offset(545, 321), Offset(879, 325), Offset(480, 330), Offset(858, 247),
  Offset(475, 335), Offset(502, 146), Offset(479, 137), Offset(618, 383), Offset(200, 491),
  Offset(171, 307), Offset(998, 370), Offset(1040, 410), Offset(848, 267), Offset(509, 167),
  Offset(514, 159), Offset(509, 139), Offset(64, 272), Offset(140, 204), Offset(604, 163),
  Offset(509, 130), Offset(1003, 360), Offset(876, 251), Offset(1080, 249), Offset(620, 499),
  Offset(472, 146), Offset(132, 207), Offset(965, 274), Offset(871, 316), Offset(565, 145),
  Offset(561, 141), Offset(890, 299), Offset(501, 201), Offset(887, 259), Offset(1052, 268),
  Offset(535, 100), Offset(1050, 222), Offset(243, 454), Offset(868, 279), Offset(536, 149),
  Offset(848, 228), Offset(901, 273), Offset(586, 128), Offset(1008, 369), Offset(1009, 204),
  Offset(655, 198), Offset(605, 180), Offset(597, 96), Offset(454, 183), Offset(566, 100),
  Offset(245, 440), Offset(175, 312), Offset(1007, 298), Offset(644, 227), Offset(823, 254),
  Offset(490, 144), Offset(559, 125), Offset(612, 501), Offset(577, 132), Offset(855, 224),
  Offset(223, 461), Offset(553, 165), Offset(993, 303), Offset(710, 294), Offset(533, 313),
  Offset(624, 185), Offset(477, 325), Offset(153, 202), Offset(673, 386), Offset(880, 316),
  Offset(995, 312), Offset(468, 130), Offset(535, 157), Offset(861, 232), Offset(488, 200),
  Offset(493, 348), Offset(910, 278), Offset(159, 179), Offset(841, 271), Offset(496, 148),
  Offset(698, 217), Offset(553, 139), Offset(152, 192), Offset(247, 450), Offset(126, 331),
  Offset(583, 194), Offset(275, 408), Offset(863, 240), Offset(1026, 202), Offset(620, 479),
  Offset(252, 445), Offset(629, 458), Offset(450, 192), Offset(471, 136), Offset(832, 213),
  Offset(844, 223), Offset(876, 242), Offset(586, 494), Offset(126, 196), Offset(548, 176),
  Offset(520, 205), Offset(652, 211), Offset(1072, 266), Offset(707, 489), Offset(139, 193),
  Offset(486, 168), Offset(1040, 248), Offset(139, 185), Offset(582, 122), Offset(466, 335),
  Offset(481, 126), Offset(530, 124), Offset(507, 150), Offset(618, 226), Offset(610, 158),
  Offset(539, 138), Offset(293, 389), Offset(532, 135), Offset(624, 503), Offset(1140, 230),
  Offset(1101, 222), Offset(1013, 197), Offset(930, 265), Offset(528, 145), Offset(475, 174),
  Offset(572, 504), Offset(587, 94), Offset(264, 449), Offset(116, 215), Offset(472, 115),
  Offset(634, 188), Offset(865, 295), Offset(637, 228), Offset(464, 138), Offset(168, 178),
  Offset(1148, 221), Offset(693, 293), Offset(563, 171), Offset(130, 324), Offset(1057, 275),
  Offset(519, 146), Offset(1077, 260), Offset(819, 201), Offset(129, 237), Offset(1091, 213),
  Offset(1148, 230), Offset(990, 291), Offset(156, 270), Offset(226, 481), Offset(1107, 441),
  Offset(432, 187), Offset(622, 237), Offset(912, 259), Offset(258, 451), Offset(465, 171),
  Offset(658, 207), Offset(523, 150), Offset(124, 339), Offset(1042, 223), Offset(568, 516),
  Offset(1000, 307), Offset(1069, 271), Offset(540, 145), Offset(878, 294), Offset(757, 247),
  Offset(133, 330), Offset(638, 199), Offset(616, 487), Offset(967, 281), Offset(1048, 413),
  Offset(542, 126), Offset(894, 278), Offset(1072, 249), Offset(157, 196), Offset(467, 149),
  Offset(1042, 214), Offset(527, 117), Offset(515, 141), Offset(990, 309), Offset(545, 108),
  Offset(437, 177), Offset(913, 270), Offset(464, 319), Offset(236, 478), Offset(462, 340),
  Offset(881, 257), Offset(632, 249), Offset(1034, 408), Offset(473, 123), Offset(564, 128),
  Offset(664, 401), Offset(238, 464), Offset(528, 159), Offset(545, 160), Offset(611, 182),
  Offset(515, 184), Offset(131, 182), Offset(133, 200), Offset(1052, 278), Offset(269, 443),
  Offset(218, 478), Offset(469, 324), Offset(1007, 311), Offset(542, 174), Offset(250, 154),
  Offset(486, 150), Offset(540, 97), Offset(654, 385), Offset(887, 247), Offset(1098, 214),
  Offset(1035, 291), Offset(606, 169), Offset(1075, 186), Offset(172, 183), Offset(599, 173),
  Offset(476, 155), Offset(872, 309), Offset(887, 322), Offset(844, 276), Offset(180, 177),
  Offset(529, 169), Offset(483, 133), Offset(1150, 213), Offset(580, 490), Offset(480, 146),
];

/// Mixed truck colours.
const List<Color> _truckColors = [
  Color(0xFFFF8A2A), // orange
  Color(0xFF3BA3FF), // blue
  Color(0xFF3DDC84), // green
  Color(0xFFFFD23F), // yellow
  Color(0xFFB07CFF), // violet
  Color(0xFFFF4D6D), // red
  Color(0xFF2FE0E0), // cyan
  Color(0xFFFF7AD9), // pink
];
const _orange = Color(0xFFFF8A2A);
const _blue = Color(0xFF3BA3FF);
const _green = Color(0xFF3DDC84);

class _Truck {
  Offset a = Offset.zero, b = Offset.zero, c = Offset.zero; // image px; c = arc control
  int to = 0;
  Color color = _orange;
  double t = 0; // 0..1 along the arc
  double speed = 0.2; // share of the arc per second

  Offset at(double t) {
    final u = 1 - t;
    return Offset(u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx, u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy);
  }

  Offset dir(double t) => Offset(
        2 * (1 - t) * (c.dx - a.dx) + 2 * t * (b.dx - c.dx),
        2 * (1 - t) * (c.dy - a.dy) + 2 * t * (b.dy - c.dy),
      );
}

class _Flash {
  int hub = 0;
  Color color = _orange;
  double born = -10;
}

class _LiveMapState extends State<LiveMap> with TickerProviderStateMixin {
  static const int _maxTrucks = 15;
  static const int _liteTrucks = 8;

  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);
  final _rng = math.Random();
  late final List<_Truck> _trucks = List.generate(_maxTrucks, (i) => _place(_Truck(), i, _rng.nextDouble() * 0.9));
  final List<_Flash> _flashes = List.generate(16, (_) => _Flash());
  late final List<double> _sparkPhase = List.generate(_sparks.length, (_) => _rng.nextDouble() * 6.28);
  late final List<double> _sparkSpeed = List.generate(_sparks.length, (_) => 0.6 + _rng.nextDouble() * 1.2);
  late final AnimationController _badge =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  int _colorTurn = 0;
  int _flashTurn = 0;
  double _nextPing = 0.5;
  Duration _last = Duration.zero;

  // adaptive quality
  bool _lite = false;
  final List<double> _frameMs = [];
  bool _skipOdd = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    WheelSignals.scrolling.addListener(_onScrolling);
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    WheelSignals.scrolling.removeListener(_onScrolling);
    _ticker.dispose();
    _badge.dispose();
    _time.dispose();
    super.dispose();
  }

  /// Pause while the feed scrolls; resume only if the map is in view.
  void _onScrolling() {
    if (!mounted) return;
    if (WheelSignals.scrolling.value) {
      if (_ticker.isActive) _ticker.stop();
    } else if (WheelSignals.offset < 420 && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frameMs.add((t.buildDuration + t.rasterDuration).inMicroseconds / 1000.0);
    }
    if (_frameMs.length < 30) return;
    final avg = _frameMs.reduce((a, b) => a + b) / _frameMs.length;
    _frameMs.clear();
    if (avg > 20) {
      _lite = true;
    } else if (avg < 9) {
      _lite = false;
    }
  }

  /// New route for [tr]: two hubs not too close and not across half the globe.
  _Truck _place(_Truck tr, int turn, double startT) {
    final i = _rng.nextInt(_hubs.length);
    var j = _rng.nextInt(_hubs.length);
    var guard = 0;
    while (guard++ < 40) {
      final d = (_hubs[i] - _hubs[j]).distance;
      if (j != i && d > 60 && d < 620) break;
      j = _rng.nextInt(_hubs.length);
    }
    final a = _hubs[i], b = _hubs[j];
    final d = math.max(1.0, (b - a).distance);
    final n = Offset(-(b.dy - a.dy) / d, (b.dx - a.dx) / d);
    final lift = math.min(0.32 * d, 120.0) * (n.dy > 0 ? -1 : 1); // arc bends upwards
    tr
      ..a = a
      ..b = b
      ..to = j
      ..c = Offset((a.dx + b.dx) / 2 + n.dx * lift, (a.dy + b.dy) / 2 + n.dy * lift)
      ..color = _truckColors[turn % _truckColors.length]
      ..t = startT
      ..speed = 1 / (2.0 + d / 160);
    return tr;
  }

  void _onTick(Duration elapsed) {
    // Ticker restarts from zero after a pause: keep our own clock.
    final dt = _last == Duration.zero ? 0.016 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (_lite) {
      _skipOdd = !_skipOdd;
      if (_skipOdd) return; // ~30 fps on slow devices
    }
    final step = dt.clamp(0.0, 0.1).toDouble();
    final now = _time.value + step;
    final active = _lite ? _liteTrucks : _maxTrucks;
    for (var k = 0; k < active; k++) {
      final tr = _trucks[k];
      tr.t += tr.speed * step * (_lite ? 2 : 1); // lite skips every other frame
      if (tr.t >= 1) {
        final f = _flashes[_flashTurn++ % _flashes.length];
        f
          ..hub = tr.to
          ..color = tr.color
          ..born = now;
        _place(tr, _colorTurn++, 0);
      }
    }
    // "New load" pings: a coloured burst at a random city every 0.25–0.7 s.
    if (now >= _nextPing) {
      _nextPing = now + 0.25 + _rng.nextDouble() * 0.45;
      final f = _flashes[_flashTurn++ % _flashes.length];
      f
        ..hub = _rng.nextInt(_hubs.length)
        ..color = _truckColors[_rng.nextInt(_truckColors.length)]
        ..born = now;
    }
    _time.value = now;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _imgW / _imgH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Static background (sea already in the panel colour in the image).
          RepaintBoundary(
            child: Image.asset(
              'assets/images/world_map.jpg',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          // Animated transparent layer.
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _MapPainter(_time, _trucks, _flashes, _sparkPhase, _sparkSpeed, () => _lite),
              ),
            ),
          ),
          // "CANLI" badge with a breathing green light, top-right.
          Positioned(
            top: 6,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _green.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: CurvedAnimation(parent: _badge, curve: Curves.easeInOut).drive(Tween(begin: 0.25, end: 1.0)),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: _green.withValues(alpha: 0.7), blurRadius: 6)],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(widget.liveLabel,
                      style: const TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final ValueNotifier<double> time;
  final List<_Truck> trucks;
  final List<_Flash> flashes;
  final List<double> sparkPhase;
  final List<double> sparkSpeed;
  final bool Function() lite;
  _MapPainter(this.time, this.trucks, this.flashes, this.sparkPhase, this.sparkSpeed, this.lite) : super(repaint: time);

  static const int _trail = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final now = time.value;
    final isLite = lite();
    final sx = size.width / _imgW, sy = size.height / _imgH;
    // One size unit: the preview canvas (1040 px wide, factor 1.4) scaled
    // to this widget, so sizes look the same as in the approved preview.
    final s = size.width / 1040 * 1.4;
    Offset px(Offset p) => Offset((p.dx - _crop.dx) * sx, (p.dy - _crop.dy) * sy);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..style = PaintingStyle.fill;

    // 1) Twinkling city lights.
    final sparkUnit = size.width / 1040;
    for (var i = 0; i < _sparks.length; i++) {
      final v = math.sin(now * sparkSpeed[i] * math.pi + sparkPhase[i]);
      if (v < 0.55) continue;
      final a = (v - 0.55) / 0.45;
      final p = Offset(_sparks[i].dx * sx, _sparks[i].dy * sy);
      fill.color = const Color(0xFFFF9A3C).withValues(alpha: 0.28 * a);
      canvas.drawCircle(p, (4 + a * 3) * sparkUnit, fill);
      fill.color = const Color(0xFFFFD9A0).withValues(alpha: a);
      canvas.drawCircle(p, (1.6 + a * 1.8) * sparkUnit, fill);
    }

    // 2) Hubs: two pulsing rings + a glowing core.
    for (var i = 0; i < _hubs.length; i++) {
      final p = px(_hubs[i]);
      final big = _bigHubs.contains(i);
      final col = big ? _orange : _blue;
      final r0 = (big ? 4.2 : 3.0) * s;
      final ph = (now / 1.3 + i * 0.137) % 1.0;
      for (final off in const [0.0, 0.5]) {
        final q = (ph + off) % 1.0;
        stroke
          ..strokeWidth = 1.4 * s
          ..color = col.withValues(alpha: (1 - q) * 0.55);
        canvas.drawCircle(p, r0 + q * (big ? 18 : 12) * s, stroke);
      }
      fill.color = col.withValues(alpha: 0.3);
      canvas.drawCircle(p, r0 * 1.8, fill);
      fill.color = col;
      canvas.drawCircle(p, r0, fill);
      fill.color = const Color(0xFFFFF6EA);
      canvas.drawCircle(p, r0 * 0.45, fill);
    }

    // 3) Trucks: dashed road ahead, glowing trail behind, chevrons, icon.
    final active = isLite ? _LiveMapState._liteTrucks : _LiveMapState._maxTrucks;
    final dashShift = (now * 25) % 10; // marching dashes
    for (var k = 0; k < active && k < trucks.length; k++) {
      final tr = trucks[k];
      Offset at(double t) => px(tr.at(t));

      if (!isLite) {
        // dashed road ahead (dash length grows with the remaining path)
        stroke
          ..strokeWidth = 0.6 * s
          ..color = tr.color.withValues(alpha: 0.4);
        const dashes = 14;
        final rest = 1 - tr.t;
        for (var d = 0; d < dashes; d++) {
          final t0 = tr.t + rest * (d + dashShift / 10) / dashes;
          final t1 = t0 + rest * 0.5 / dashes;
          if (t1 > 1) continue;
          canvas.drawLine(at(t0), at(t1), stroke);
        }
      }

      // glowing trail
      final tail = math.max(0.0, tr.t - 0.4);
      for (var i = 0; i < _trail; i++) {
        final t0 = tail + (tr.t - tail) * i / _trail;
        final t1 = tail + (tr.t - tail) * (i + 1) / _trail;
        final kk = (i + 1) / _trail;
        final p0 = at(t0), p1 = at(t1);
        stroke
          ..strokeWidth = (0.5 + 1.4 * kk) * s * 2.6
          ..color = tr.color.withValues(alpha: 0.12 * kk);
        canvas.drawLine(p0, p1, stroke);
        stroke
          ..strokeWidth = (0.5 + 1.4 * kk) * s
          ..color = tr.color.withValues(alpha: kk);
        canvas.drawLine(p0, p1, stroke);
      }

      final dir = tr.dir(tr.t);
      final ang = math.atan2(dir.dy * sy, dir.dx * sx);

      if (!isLite) {
        // » chevrons just ahead, drifting forward
        final g = (now / 0.9) % 1.0;
        stroke
          ..strokeWidth = 1.8 * s * 0.6
          ..color = tr.color.withValues(alpha: 0.9 - g * 0.4);
        for (var c = 0; c < 2; c++) {
          final t = tr.t + 0.07 + c * 0.035 + g * 0.03;
          if (t >= 0.97) continue;
          final p = at(t);
          final dd = tr.dir(t);
          _chevron(canvas, p, math.atan2(dd.dy * sy, dd.dx * sx), s * 0.6, stroke);
        }
      }

      _truck(canvas, at(tr.t), ang, tr.color, s * 0.5);
    }

    // 4) Arrival flashes.
    for (final f in flashes) {
      final age = now - f.born;
      if (age < 0 || age > 0.9) continue;
      final q = age / 0.9;
      stroke
        ..strokeWidth = 2.2 * s
        ..color = f.color.withValues(alpha: (1 - q) * 0.9);
      canvas.drawCircle(px(_hubs[f.hub]), (6 + q * 26) * s, stroke);
    }
  }

  static void _chevron(Canvas canvas, Offset p, double ang, double s, Paint stroke) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(ang);
    final path = Path()
      ..moveTo(-3 * s, -3.5 * s)
      ..lineTo(1.5 * s, 0)
      ..lineTo(-3 * s, 3.5 * s);
    canvas.drawPath(path, stroke);
    canvas.restore();
  }

  /// Small neon truck, nose pointing along the road; never upside down.
  static void _truck(Canvas canvas, Offset p, double ang, Color col, double s) {
    var a = ang;
    var flip = 1.0;
    if (math.cos(ang) < 0) {
      a = ang + math.pi;
      flip = -1;
    }
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(a);
    canvas.scale(flip * s, s);
    final trailer = RRect.fromRectAndRadius(const Rect.fromLTWH(-13, -5.5, 17, 10), const Radius.circular(1.5));
    final cab = Path()
      ..moveTo(5, -3.5)
      ..lineTo(10, -3.5)
      ..lineTo(13, 0)
      ..lineTo(13, 4.5)
      ..lineTo(5, 4.5)
      ..close();
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..color = col.withValues(alpha: 0.28);
    canvas.drawRRect(trailer, glow);
    canvas.drawPath(cab, glow);
    final body = Paint()..color = const Color(0xD9080E1A);
    canvas.drawRRect(trailer, body);
    canvas.drawPath(cab, body);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..color = col;
    canvas.drawRRect(trailer, line);
    canvas.drawPath(cab, line);
    final wheel = Paint()..color = col;
    for (final wx in const [-9.0, -1.0, 10.0]) {
      canvas.drawCircle(Offset(wx, 5.5), 1.6, wheel);
    }
    canvas.drawRect(const Rect.fromLTWH(12, 1, 1.4, 1.6), Paint()..color = const Color(0xE6FFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => false;
}
