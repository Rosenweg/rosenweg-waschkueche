// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:rosenweg_basis/rosenweg_basis.dart';

import '../daten.dart';
import '../erinnerung.dart';
import '../stand.dart';
import 'haupt.dart';
import 'reservation_ansicht.dart';

/// Eigene kommende Reservationen, nach Tag gruppiert; antippen = Angaben,
/// Stornieren direkt in der Zeile (Serie: im Blatt).
class MeineSeite extends StatelessWidget {
  const MeineSeite({super.key, required this.stand});
  final WaschStand stand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: stand,
        builder: (context, _) {
          if (stand.raeume == null) {
            return stand.fehler != null ? FehlerAnzeige.aus(stand.fehler!, nochmals: stand.laden) : const LadeAnzeige();
          }
          final jetzt = stand.jetzt();
          final offen = [for (final r in stand.meine) if (!r.vorbei(jetzt)) r];
          final kinder = <Widget>[ErinnerungsLeiste(stand: stand)];
          if (offen.isEmpty) {
            kinder.add(const Padding(
              padding: EdgeInsets.all(16),
              child: Hinweis('Du hast keine kommenden Reservationen. Unter „Belegung“ eine freie Zeit antippen '
                  'oder „Reservieren“ wählen.'),
            ));
          } else {
            String? tag;
            for (final r in offen) {
              final t = tagWort(r.von, jetzt);
              final kopf = t.contains('.') ? tagLangText(r.von) : '$t, ${tagLangText(r.von).split(', ').last}';
              if (kopf != tag) {
                tag = kopf;
                kinder.add(Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(kopf, style: Theme.of(context).textTheme.titleSmall),
                ));
              }
              kinder.add(_Zeile(stand: stand, r: r, jetzt: jetzt));
            }
          }
          return RefreshIndicator(
            onRefresh: stand.meineLaden,
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: kinder),
          );
        },
      );
}

class _Zeile extends StatelessWidget {
  const _Zeile({required this.stand, required this.r, required this.jetzt});
  final WaschStand stand;
  final Reservation r;
  final DateTime jetzt;

  @override
  Widget build(BuildContext context) {
    final laeuft = r.laeuft(jetzt);
    return ListTile(
      leading: Icon(laeuft ? Icons.local_laundry_service : Icons.local_laundry_service_outlined,
          color: laeuft ? RosenwegFarben.gut : null),
      title: Text('${uhrText(r.von)}–${uhrText(r.bis)} · ${r.raumName ?? 'Waschküche'}'),
      subtitle: Text([
        dauerText(r.dauer),
        if (laeuft) 'läuft gerade',
        if (r.woechentlich) 'jede Woche',
      ].join(' · ')),
      onTap: () => zeigeReservation(context, stand: stand, reservation: r, eigene: true),
      trailing: IconButton(
        tooltip: 'Stornieren',
        icon: const Icon(Icons.event_busy_outlined),
        onPressed: () => stornieren(context, stand, r),
      ),
    );
  }
}
