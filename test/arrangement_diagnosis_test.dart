import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:yalla_play/features/game/data/arrangement.dart';
import 'package:yalla_play/features/game/data/chord_symbol.dart';
import 'package:yalla_play/features/game/data/note_judge.dart';
import 'package:yalla_play/features/game/data/song_chart.dart';
import 'package:yalla_play/features/game/data/synth.dart';

/// Diagnosis of the backing the game plays to a song: the key it guesses,
/// the chord it picks for each stretch and what is left of each chord once
/// the player's pitch is taken out for the microphone.
///
/// Prints its report, in German for the app's owner:
///
///     flutter test test/arrangement_diagnosis_test.dart
///     flutter test test/arrangement_diagnosis_test.dart --dart-define=SONG=<id>
void main() {
  const id = String.fromEnvironment('SONG', defaultValue: 'badak');
  final chart = SongChart.parse(
    File('assets/songs/$id.json').readAsStringSync(),
  );

  test('the key ranking lists all keys, best first', () {
    final ranking = Arrangement.keyRanking(_melody(chart));
    expect(ranking, hasLength(24));
    for (var i = 1; i < ranking.length; i++) {
      expect(ranking[i].score, lessThanOrEqualTo(ranking[i - 1].score));
    }
  });

  test('reports the backing of $id beat by beat', () {
    final report = arrangementReport(chart);
    // ignore: avoid_print
    print(report);
    expect(report, contains('Geschätzte Tonart'));
    expect(report, contains('Zusammenfassung'));
  });
}

const _names = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B', //
];

String _pcs(Iterable<int> pcs) =>
    pcs.isEmpty ? '–' : pcs.map((pc) => _names[pc]).join(' ');

String _keyName(int tonic, bool minor) =>
    '${_names[tonic]}-${minor ? 'Moll' : 'Dur'}';

bool _same(Set<int> a, Set<int> b) => a.containsAll(b) && b.containsAll(a);

/// Lead-in before the first note, in ticks, as the game screen has it.
double _lead(SongChart chart) => chart.ticksPerBeat * 1.5;

/// The melody as the game screen hands it to [Arrangement.of].
List<MelodyNote> _melody(SongChart chart) => [
  for (final n in chart.notes)
    (
      start: n.tick + _lead(chart),
      length: n.note.d.toDouble(),
      frequency: noteFrequency(n.note),
    ),
];

/// How long each pitch class sounds in the melody between [from] and [to].
Map<int, double> _sounding(List<MelodyNote> melody, double from, double to) {
  final weight = <int, double>{};
  for (final n in melody) {
    final overlap = math.min(to, n.start + n.length) - math.max(from, n.start);
    if (overlap > 0) {
      weight.update(
        pitchClass(n.frequency),
        (w) => w + overlap,
        ifAbsent: () => overlap,
      );
    }
  }
  return weight;
}

/// The report: key, chords per stretch, and the chord heard on each beat.
String arrangementReport(SongChart chart) {
  final lead = _lead(chart);
  final beat = chart.ticksPerBeat.toDouble();
  final bar = beat * chart.beatsPerBar;
  final melody = _melody(chart);
  final end = melody.map((n) => n.start + n.length).reduce(math.max);
  final arrangement = Arrangement.of(
    melody,
    firstBeat: lead,
    end: end,
    beatTicks: beat,
    barTicks: bar,
    ticksPerSecond: chart.ticksPerSecond,
    chords: [
      for (final c in chart.chords)
        (start: c.tick + lead, length: c.length.toDouble(), chord: c.chord),
    ],
  );
  String where(double t) {
    final from = t - lead;
    return 'Takt ${(from / bar).floor() + 1}.${(from % bar / beat).floor() + 1}';
  }

  final out = StringBuffer()
    ..writeln('══ Begleitung: „${chart.title}“ (${chart.id}.json) ══')
    ..writeln(
      '${chart.bpm.round()} BPM, ${chart.beatsPerBar} Schläge pro Takt, '
      '${chart.notes.length} Noten',
    )
    ..writeln(
      chart.chords.isEmpty
          ? 'Akkorde: keine im Song – die App wählt selbst, '
                'einen pro halben Takt.'
          : 'Akkorde: ${chart.chords.length} aus dem Song.',
    )
    ..writeln();

  // The key.
  final ranking = Arrangement.keyRanking(melody);
  final key = ranking.first;
  out.writeln(
    'Geschätzte Tonart: ${_keyName(key.tonic, key.minor)} '
    '(Punkte ${key.score.toStringAsFixed(1)})',
  );
  for (final k in ranking.skip(1).take(3)) {
    final behind = (1 - k.score / key.score) * 100;
    out.writeln(
      '  dahinter: ${_keyName(k.tonic, k.minor)} '
      '${k.score.toStringAsFixed(1)} (${behind.toStringAsFixed(1)} % weniger)',
    );
  }
  final weight = _sounding(melody, double.negativeInfinity, double.infinity);
  final total = weight.values.fold(0.0, (a, b) => a + b);
  final scale = key.minor
      ? const [0, 2, 3, 5, 7, 8, 10]
      : const [0, 2, 4, 5, 7, 9, 11];
  final durations = [
    for (final pc in weight.keys.toList()..sort())
      '${_names[pc]} ${weight[pc]!.round()}',
  ];
  out.writeln('Melodietöne nach Dauer (Ticks): ${durations.join(', ')}');
  final outside = [
    for (final pc in weight.keys)
      if (!scale.contains((pc - key.tonic) % 12)) pc,
  ]..sort();
  final outsideShare =
      outside.fold(0.0, (a, pc) => a + weight[pc]!) / total * 100;
  out
    ..writeln(
      'Nicht in der geschätzten Tonart: ${_pcs(outside)} '
      '(${outsideShare.toStringAsFixed(0)} % der Notendauer)',
    )
    ..writeln();

  // The chords, stretch by stretch.
  out.writeln('Akkorde (Melodietöne darin; „reibt“ = Halbton neben Akkordton):');
  var changes = 0, rubbing = 0;
  ChordSymbol? previous;
  for (final span in arrangement.chords) {
    final tones = span.chord.tones;
    final heard = _sounding(melody, span.start, span.start + span.length);
    final rubs = [
      for (final pc in heard.keys)
        if (!tones.contains(pc) &&
            (tones.contains((pc + 1) % 12) || tones.contains((pc + 11) % 12)))
          pc,
    ]..sort();
    if (previous != null && previous != span.chord) changes++;
    if (rubs.isNotEmpty) rubbing++;
    previous = span.chord;
    out.writeln(
      '  ${where(span.start).padRight(10)} ${span.chord.name.padRight(5)} '
      'Melodie: ${_pcs(heard.keys.toList()..sort()).padRight(12)}'
      '${rubs.isEmpty ? '' : ' reibt: ${_pcs(rubs)}'}',
    );
  }
  out
    ..writeln(
      '  → $changes Wechsel bei ${arrangement.chords.length} Abschnitten, '
      '$rubbing Abschnitte mit reibenden Melodietönen',
    )
    ..writeln();

  // What sounds on each beat once the player's pitch is left out.
  final triads = [
    for (var root = 0; root < 12; root++)
      for (final minor in [false, true]) ChordSymbol.triad(root, minor: minor),
  ];
  final chordTones = <double, Set<int>>{}, bass = <double, int>{};
  for (final e in arrangement.events) {
    if (e.voice == Voice.chord) {
      (chordTones[e.tick] ??= <int>{}).add(pitchClass(e.frequency));
    } else if (e.voice == Voice.bass) {
      bass[e.tick] = pitchClass(e.frequency);
    }
  }
  out.writeln(
    'Pro Schlag (Akkord | klingt | weggelassen fürs Mikrofon | ergänzt | Bass):',
  );
  var beats = 0, missing = 0, rootless = 0, other = 0, silent = 0;
  for (var t = lead; t < end; t += beat) {
    final spans = arrangement.chords.where(
      (c) => c.start <= t + 1e-6 && t < c.start + c.length - 1e-6,
    );
    if (spans.isEmpty) continue;
    final chord = spans.last.chord;
    beats++;
    final sounded = chordTones[t] ?? <int>{};
    final dropped = chord.tones.difference(sounded).toList()..sort();
    final added = sounded.difference(chord.tones).toList()..sort();
    if (sounded.isEmpty) silent++;
    if (dropped.isNotEmpty) missing++;
    if (dropped.contains(chord.root)) rootless++;
    final likeOther = sounded.containsAll(chord.tones)
        ? null
        : triads
              .where(
                (c) =>
                    !_same(c.tones, chord.tones) &&
                    sounded.containsAll(c.tones),
              )
              .firstOrNull;
    if (likeOther != null) other++;
    out.writeln(
      '  ${where(t).padRight(10)} ${chord.name.padRight(5)} '
      '| ${_pcs(sounded.toList()..sort()).padRight(8)} '
      '| ${_pcs(dropped).padRight(5)} '
      '| ${_pcs(added).padRight(3)} '
      '| ${bass[t] == null ? '' : _names[bass[t]!]}'
      '${likeOther == null ? '' : '   → klingt wie ${likeOther.name}'}',
    );
  }

  String share(int n) => '$n von $beats (${(n / beats * 100).round()} %)';
  out
    ..writeln()
    ..writeln('Zusammenfassung')
    ..writeln(
      '  Tonart: ${_keyName(key.tonic, key.minor)}, '
      '${outsideShare.toStringAsFixed(0)} % der Melodie liegt außerhalb',
    )
    ..writeln('  Schläge mit weggelassenem Akkordton: ${share(missing)}')
    ..writeln('  … davon ohne Grundton: ${share(rootless)}')
    ..writeln('  Schläge, die wie ein anderer Akkord klingen: ${share(other)}')
    ..writeln('  Schläge ganz ohne Akkord: ${share(silent)}')
    ..writeln(
      '  Akkordwechsel: $changes, Abschnitte mit Reibung: '
      '$rubbing von ${arrangement.chords.length}',
    );
  return out.toString();
}
