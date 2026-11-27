// SPDX-License-Identifier: GPL-3.0-or-later
// Erinnerung an die eigenen Reservationen – ohne Push-Dienst (Entscheid
// Stefan 27.11.2026: kein ntfy). Die App fragt beim Oeffnen und danach jede
// Minute ihre eigenen Termine ab und zeigt oben einen Hinweis; kurz vor
// Beginn kommt zusaetzlich eine Meldung, solange die App offen ist.

import 'daten.dart';

/// Wie dringend.
enum ErinnerungsArt {
  /// Laeuft gerade.
  laeuft,

  /// Beginnt in hoechstens [Erinnerung.bald].
  bald,

  /// Heute oder morgen.
  demnaechst,
}

class Erinnerung {
  const Erinnerung(this.reservation, this.art, this.text);

  final Reservation reservation;
  final ErinnerungsArt art;
  final String text;

  /// Ab hier „gleich“: Meldung, auch wenn die App schon offen ist.
  static const bald = Duration(minutes: 15);

  /// Bis hier zeigt die App den naechsten Termin oben an.
  static const voraus = Duration(hours: 36);

  /// Naechster eigener Termin, der laeuft oder innerhalb von [voraus]
  /// beginnt; sonst null.
  static Erinnerung? fuer(List<Reservation> meine, DateTime jetzt) {
    final offen = [for (final r in meine) if (!r.vorbei(jetzt)) r]..sort((a, b) => a.von.compareTo(b.von));
    if (offen.isEmpty) return null;
    final r = offen.first;
    final raum = r.raumName ?? 'Waschküche';
    final zeit = '${_uhr(r.von)}–${_uhr(r.bis)}';
    if (r.laeuft(jetzt)) {
      return Erinnerung(r, ErinnerungsArt.laeuft, 'Deine Reservation läuft: $raum bis ${_uhr(r.bis)}.');
    }
    final bis = r.von.difference(jetzt);
    if (bis > voraus) return null;
    if (bis <= bald) {
      final min = (bis.inSeconds / 60).ceil();
      return Erinnerung(r, ErinnerungsArt.bald, 'In $min ${min == 1 ? 'Minute' : 'Minuten'}: $raum, $zeit.');
    }
    return Erinnerung(r, ErinnerungsArt.demnaechst, '${tagWort(r.von, jetzt)} $zeit: $raum.');
  }
}

String _uhr(DateTime z) => '${z.hour.toString().padLeft(2, '0')}:${z.minute.toString().padLeft(2, '0')}';

/// „Heute“, „Morgen“, „Übermorgen“ oder „Mo 30.11.“.
String tagWort(DateTime tag, DateTime jetzt) {
  final a = DateTime(jetzt.year, jetzt.month, jetzt.day);
  final b = DateTime(tag.year, tag.month, tag.day);
  final d = DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  return switch (d) {
    0 => 'Heute',
    1 => 'Morgen',
    2 => 'Übermorgen',
    _ => '${const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][tag.weekday - 1]} ${tag.day}.${tag.month}.',
  };
}
