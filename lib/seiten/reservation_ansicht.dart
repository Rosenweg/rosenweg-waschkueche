// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../erinnerung.dart';
import '../stand.dart';

/// Angaben zu einer Reservation (Blatt von unten). Eigene: „Stornieren“,
/// bei einer Serie auch „Ganze Serie stornieren“. true = etwas storniert.
Future<bool> zeigeReservation(BuildContext context, {required WaschStand stand, required Reservation reservation, required bool eigene}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _Blatt(stand: stand, r: reservation, eigene: eigene),
  );
  return r ?? false;
}

/// Einzelnen Termin stornieren (mit Rueckfrage). true = storniert.
Future<bool> stornieren(BuildContext context, WaschStand stand, Reservation r) async {
  final jetzt = stand.jetzt();
  if (!await frage(context, 'Reservation stornieren?', '${tagWort(r.von, jetzt)}, ${uhrText(r.von)}–${uhrText(r.bis)}, ${r.raumName ?? 'Waschküche'}.',
      ja: 'Stornieren', gefaehrlich: true)) {
    return false;
  }
  try {
    await stand.api.stornieren(r.id);
    await stand.meineLaden();
    if (context.mounted) zeigeMeldung(context, 'Reservation storniert.');
    return true;
  } catch (e) {
    if (context.mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    return false;
  }
}

/// Alle kuenftigen Termine der Serie stornieren (mit Rueckfrage).
Future<bool> serieStornieren(BuildContext context, WaschStand stand, Reservation r) async {
  if (!await frage(context, 'Ganze Serie stornieren?',
      'Alle kommenden Termine dieser wöchentlichen Reservation (${wochentageLang[r.von.weekday - 1]}s ${uhrText(r.von)}–${uhrText(r.bis)}) werden storniert.',
      ja: 'Serie stornieren', gefaehrlich: true)) {
    return false;
  }
  try {
    final n = await stand.api.serieStornieren(r.id);
    await stand.meineLaden();
    if (context.mounted) zeigeMeldung(context, n == 1 ? '1 Termin storniert.' : '$n Termine storniert.');
    return true;
  } catch (e) {
    if (context.mounted) zeigeMeldung(context, fehlerText(e), fehler: true);
    return false;
  }
}

class _Blatt extends StatelessWidget {
  const _Blatt({required this.stand, required this.r, required this.eigene});
  final WaschStand stand;
  final Reservation r;
  final bool eigene;

  @override
  Widget build(BuildContext context) {
    final jetzt = stand.jetzt();
    final t = Theme.of(context).textTheme;
    Widget zeile(IconData i, String text) => ListTile(dense: true, leading: Icon(i), title: Text(text));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(eigene ? 'Deine Reservation' : 'Reserviert', style: t.titleLarge),
          ),
          if (r.laeuft(jetzt))
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Hinweis('Läuft gerade.', art: HinweisArt.gut)),
          zeile(Icons.local_laundry_service_outlined, r.raumName ?? 'Waschküche'),
          zeile(Icons.event, tagLangText(r.von)),
          zeile(Icons.schedule, '${uhrText(r.von)}–${uhrText(r.bis)} (${dauerText(r.dauer)})'),
          if (!eigene) zeile(Icons.person_outline, r.personText),
          if (r.woechentlich) zeile(Icons.repeat, 'Jede Woche${r.serieBis == null ? '' : ' bis ${datumText(r.serieBis!)}'}'),
          if (eigene && !r.vorbei(jetzt)) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.end, children: [
                if (r.woechentlich)
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (await serieStornieren(context, stand, r) && context.mounted) Navigator.pop(context, true);
                    },
                    icon: const Icon(Icons.event_repeat),
                    label: const Text('Ganze Serie stornieren'),
                  ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () async {
                    if (await stornieren(context, stand, r) && context.mounted) Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.event_busy),
                  label: Text(r.woechentlich ? 'Diesen Termin stornieren' : 'Stornieren'),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
