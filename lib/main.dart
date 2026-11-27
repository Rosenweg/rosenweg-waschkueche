// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:rosenweg_basis/rosenweg_basis.dart';

import 'app.dart';
import 'attrappe.dart';
import 'erinnerung.dart';
import 'seiten/haupt.dart';
import 'wasch_api.dart';

/// Abfrage im Hintergrund (Android, iOS): eigene Reservationen holen und die
/// Erinnerungen 15 Minuten vor Beginn neu planen. Auf geteilten Telefonen und
/// ohne bestehende Anmeldung macht die Basis nichts.
@pragma('vm:entry-point')
void hintergrund() => HintergrundAbfrage.ausfuehren(appAngaben, erinnerungsAbfrage);

Future<void> erinnerungsAbfrage(HintergrundKontext k) async {
  final meine = await WaschApi(k.sitzung.api).meine();
  await erinnerungenAbgleichen(meine, k.speicher);
}

/// rosenwegStarten (rosenweg_basis): Logdatei, Fehlerfang, Anmeldung
/// (Anmeldeschirm mit Karte, QR, Konto; an Stationen still per Kerberos;
/// auf geteilten Telefonen ueber Rosenweg Geraet) und der Updater
/// (aus auf Rosenweg-Stationen, Android, iOS). Erst danach kommt [Haupt].
void main() {
  if (!attrappe) HintergrundAbfrage.anmelden(appAngaben, hintergrund);
  rosenwegStarten(
    appAngaben,
    (sitzung) => Haupt(sitzung: sitzung),
    sitzung: attrappe ? RosenwegSitzung(appAngaben, transport: Attrappe()) : null,
  );
}
