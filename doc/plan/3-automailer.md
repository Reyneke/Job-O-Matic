# Automailer

Zum Zwecke der Automatisierung sollte ein Automailer in die App integriert werden, um die fertigen Bewerbungen direkt an die entsprechenden Stellen zu versenden oder, sofern eine Eintragung in einem Bewerberportal erforderlich ist, diese ebenfalls automatisiert auszufüllen.

---

## 1. Automailer – E-Mail-Versand

### Mögliche Ansätze

| Ansatz | Vorteile | Nachteile |
|--------|----------|-----------|
| **SMTP (eigener Mailserver / Relay)** | Volle Kontrolle, keine Drittanbieter-Abhängigkeit | Erfordert eigenen SMTP-Server, Spam-Risiko bei falscher Konfiguration, Zustellbarkeit schwierig |
| **Brevo (ehem. Sendinblue)** | Speziell auf Transaktions-Mails ausgelegt, gute API (REST + SMTP), 300 E-Mails/Tag kostenlos | API-Key erforderlich, Datenschutz (DSGVO – Server in EU) |
| **SendGrid (Twilio)** | Hohe Zustellraten, gute Dokumentation, 100 E-Mails/Tag kostenlos | US-Server (DSGVO: SCCs erforderlich) |
| **Mailgun** | Entwicklerfreundlich, 5.000 E-Mails/Monat kostenlos | US-Server (DSGVO: SCCs erforderlich) |
| **Resend** | Modern, React-E-Mail-Templates, 100 E-Mails/Tag kostenlos | Relativ neu, noch wenig etabliert |
| **nodemailer (lokal)** + SMTP-Relay (z. B. Gmail, Outlook) | Einfach, keine zusätzliche API | Gmail: 500 E-Mails/Tag Limit, weniger professionell |

### Empfehlung

**Brevo** bietet das beste Verhältnis aus:
- Kostenloser Einstieg (300 E-Mails/Tag)
- DSGVO-konforme Serverstandorte (EU)
- REST-API + SMTP-Schnittstelle
- Guter Deutschland-Support

Alternativ: **nodemailer** mit eigenem SMTP für vollständige Unabhängigkeit.

### Architektur (Vorschlag mit Queue-Pattern)

```
┌──────────────────┐    speichert     ┌──────────────────┐
│   Job-O-Matic    │ ───────────────► │  Mail Queue      │
│   (Backend)      │                  │  (Datenbank)     │
│                  │                  │                  │
│ 1. Generiert     │                  │ Status: pending  │
│    PDF + Mail    │                  │ Retry-Count: 0   │
│ 2. Queue-Eintrag │                  │ Next-Try: now    │
│ 3. Status open   │                  └────────┬─────────┘
└──────────────────┘                           │
                                                │ Background Worker
                                                ▼
                                     ┌──────────────────┐
                                     │  Mail Dispatcher  │
                                     │                   │
                                     │ • Batch-Verarbeitung         │
                                     │ • Rate-Limiter (z. B. 10/min)│
                                     │ • Retry mit Backoff          │
                                     │ • Circuit Breaker            │
                                     └────────┬──────────────────┘
                                              │ REST/SMTP
                                              ▼
                                    ┌──────────────────┐
                                    │   Brevo API      │
                                    │   / SMTP         │
                                    └──────────────────┘
                                              │
                                              ▼
                                       Zustellung an
                                       HR-Abteilung
```

### Umsetzungsschritte

1. **Brevo-Account erstellen** und API-Key generieren
2. **Secrets-Manager einrichten** (z. B. Azure Key Vault, HashiCorp Vault oder Umgebungsvariablen mit verschlüsselter Konfiguration)
3. **E-Mail-Vorlagen** (mit Platzhaltern für Name, Firma, Position) definieren – Template-Engine wie `handlebars` oder `mustache` verwenden
4. **PDF-Anhänge** aus den bereits generierten Bewerbungsdokumenten anhängen
5. **Queue-System** implementieren:
   - Eintrag bei Generierung erstellen (Status: `pending`)
   - Worker liest in Batches aus (z. B. je 5 E-Mails)
   - Sendevorgang mit Rate-Limiter (z. B. 10 E-Mails pro Minute konfigurierbar)
   - Bei Erfolg: Status → `sent`
   - Bei Fehler: Retry mit exponentiellem Backoff (1min → 5min → 30min → 2h → max 3 Versuche) → dann `failed`
6. **Tracking** – Versandstatus (`pending`, `sending`, `sent`, `failed`, `bounced`) in der Datenbank speichern
7. **Logging & Monitoring** – Jeden Versand mit Timestamp, Empfänger, Status und Fehlermeldung loggen
8. **Benachrichtigung** – Bei Fehlschlag: In-App-Benachrichtigung + optional E-Mail an Admin
9. **Fallback** – Bei finalem Fehlschlag: manuellen Versand per E-Mail-Client ermöglichen (Button "Als Entwurf exportieren")

### Deliverability-Grundlagen

- **DKIM** und **SPF**-Einträge für die Versand-Domain konfigurieren (notwendig für hohe Zustellrate)
- **Bounce-Handling** – Webhook von Brevo für Bounces und Spam-Reports einrichten
- **Absender-Name** personalisieren (z. B. "Max Mustermann via Job-O-Matic")

---

## 2. Automatisches Ausfüllen von Bewerberportalen

### Herausforderungen

- Keine einheitliche API / Schnittstelle
- Jedes Portal hat eigenes HTML-Formular (teilweise dynamisch via JavaScript)
- CAPTCHAs (reCAPTCHA, hCaptcha) verhindern Automatisierung
- Datenschutzrechtliche Bedenken (automatisierte Eingabe fremder Systeme)

### Mögliche Ansätze

| Ansatz | Beschreibung | Bewertung |
|--------|-------------|-----------|
| **REST-API (wenn vorhanden)** | Viele Portale (z. B. StepStone, LinkedIn) bieten Partner-APIs | Beste Lösung, aber meist kostenpflichtig und mit Zulassung |
| **Browser-Automation (Playwright)** | Headless-Browser steuert Formularausfüllung | Flexibel, aber anfällig für UI-Änderungen und CAPTCHAs |
| **Browser-Automation (Selenium)** | Ähnlich wie Playwright | Langsamer, weniger moderne API |
| **RPA-Tool (UiPath, Power Automate)** | Low-Code-Automation für Web-UI | Überdimensioniert für diesen Anwendungsfall |
| **Browser-Extension** | Halbautomatisch: Benutzer öffnet Portal, Extension füllt Felder vor | Weniger invasiv, einfacher zu warten |

### Empfehlung

**Hybrid-Ansatz (iterativ aufbauend):**

1. **Phase 1:** Direkte E-Mail-Zustellung über Brevo (für Stellen mit E-Mail-Kontakt)
2. **Phase 2:** Browser-Extension für häufig genutzte Portale (Benutzer öffnet Portal selbst)
3. **Phase 3:** Playwright-Skript für Massenbewerbungen auf unterstützten Portalen
4. **Fallback:** Manuelle Übergabe mit ausgefüllten Daten als JSON-Export zum Einfügen

### Architektur (Vorschlag für Playwright-Ansatz)

```
┌─────────────┐  JSON-Daten  ┌──────────────────┐
│ Job-O-Matic  │ ───────────► │  Playwright-Worker│
│ (Datenbank)  │             │  (isolierter      │
│              │             │   Container/Prozess)│
└─────────────┘             └────────┬───────────┘
    ▲                                │
    │ Status-Updates                 ▼
    │ (via Callback/DB)      Bewerberportal
    └──────────────────────── (StepStone, etc.)
```

### Umsetzungsschritte (REST)

1. Prüfen, ob das Zielportal eine öffentliche REST-API anbietet
2. Falls ja: API-Key beantragen, Endpunkte identifizieren
3. Bewerbungsdaten als JSON aufbereiten und per `POST` senden
4. Response (Bestätigung / Fehler) auswerten und speichern

### Umsetzungsschritte (Playwright)

1. Playwright als Abhängigkeit ins Projekt aufnehmen
2. Für jedes Portal ein eigenes "Formular-Mapping" (`portal-config.json`) definieren:
   ```json
   {
     "portal": "example",
     "url": "https://example.com/bewerben",
     "fields": {
       "vorname": "#vorname-input",
       "nachname": "#nachname-input",
       "email": "#email-input",
       "lebenslauf": "input[type='file']"
     },
     "actions": [
       { "type": "click", "selector": "#submit-btn" }
     ],
     "selectors": {
       "captcha": "iframe[src*='recaptcha'], div.g-recaptcha",
       "success": ".alert-success, .confirmation-message",
       "error": ".alert-error, .error-message"
     },
     "timeout": 30000,
     "retryOnError": true
   }
   ```
3. Skript führt Felder selektorgesteuert aus
4. CAPTCHA-Erkennung: Bei Auftreten Skript abbrechen → Status `captcha_blocked` → Benachrichtigung an Benutzer → manuelle Eingabe erforderlich
5. Screenshot bei Fehlschlag erstellen (für Debugging)

---

## 3. Entscheidungen & offene Fragen

### Bereits getroffene Entscheidungen

| Entscheidung | Beschluss | Begründung |
|-------------|-----------|------------|
| **E-Mail-Dienst** | Brevo | DSGVO-konform (EU-Server), 300 E-Mails/Tag kostenlos, REST + SMTP |
| **API-Key-Management** | Secrets-Manager | Sicherer als Umgebungsvariablen; bei kleinerem Setup reichen verschlüsselte Env-Vars |
| **CAPTCHA-Strategie** | Abbruch + Benachrichtigung + manuelles Eingreifen | Automatisierte CAPTCHA-Lösung ist rechtlich und technisch bedenklich |
| **Test-Phase** | Zuerst E-Mail-Versand, später Portal-Automation | Portal-Automation ist deutlich komplexer und rechtlich heikler |

### Offene Fragen & nächste Schritte

- [ ] **Portal-Unterstützung priorisieren:** Welche Portale außer Jobcenter sollen unterstützt werden?  
  *Votum:* 1. Jobcenter, dann nach Bedarf. Qualität der Portal-APIs muss vorab geprüft werden.

- [x] **Rate-Limiting – konkrete Werte festlegen:**  
  *Vorschlag:*  
  - E-Mail-Versand: max. 10 E-Mails pro Minute (einstellbar, z. B. über `config.yaml`) – das entspricht 600/h und bleibt weit unter Brevos Limit von 300/Tag im Free-Tier (also könnte der Wert niedriger sein, z. B. 5/min)  
  - Portal-Automation: max. 1 Bewerbung pro 5 Minuten (um Detektion zu vermeiden)  
  - Queue-Intervall: konfigurierbarer Cron-Job (z. B. alle 15 Minuten Batch verarbeiten)  
  *Entscheidung:* Benutzer kann Limits in den App-Optionen einstellen.

- [ ] **Rechtliche Prüfung:** Ist automatisierte Portal-Eingabe mit den AGB der Portale vereinbar?  
  *Nächster Schritt:* Vor Baubeginn der Portal-Automation eine rechtliche Einschätzung einholen (Anwalt für IT-Recht).

- [x] **Template-Engine für E-Mails:** Handlebars – damit lassen sich bedingte Blöcke und Schleifen in Vorlagen abbilden (z. B. "Sehr geehrte Frau X" vs "Sehr geehrter Herr X").

  **Wie funktioniert Handlebars?**
  
  Handlebars ist eine Logic-Less Template-Engine – das bedeutet, die Vorlage enthält Platzhalter in doppelten geschweiften Klammern (`{{variable}}`), und die Logik (Bedingungen, Schleifen) wird über Helfer-Blöcke gesteuert:
  
  **Template (z. B. `email-template.hbs`):**
  ```hbs
  Betreff: Bewerbung als {{position}} bei {{company}}
  
  {{#if gender}}
    {{#ifEquals gender "female"}}
      Sehr geehrte Frau {{lastName}},
    {{else}}
      Sehr geehrter Herr {{lastName}},
    {{/ifEquals}}
  {{else}}
    Hallo {{firstName}} {{lastName}},
  {{/if}}
  
  anbei erhalten Sie meine vollständigen Bewerbungsunterlagen für die Stelle
  als **{{position}}**.
  
  Mit freundlichen Grüßen
  {{firstName}} {{lastName}}
  ```
  
  **Integration in den Code (JavaScript/Node.js-Beispiel):**
  ```javascript
  import Handlebars from 'handlebars';
  import fs from 'fs';
  
  // 1. Template laden
  const templateSource = fs.readFileSync('templates/email-template.hbs', 'utf8');
  const template = Handlebars.compile(templateSource);
  
  // 2. Daten vorbereiten
  const data = {
    position: 'Softwareentwickler',
    company: 'Tech GmbH',
    firstName: 'Max',
    lastName: 'Mustermann',
    gender: 'male'
  };
  
  // 3. Custom-Helper für Gleichheitsprüfung registrieren
  Handlebars.registerHelper('ifEquals', function(arg1, arg2, options) {
    return (arg1 === arg2) ? options.fn(this) : options.inverse(this);
  });
  
  // 4. Template rendern → fertiger E-Mail-Text
  const emailBody = template(data);
  ```
  
  **In Dart/Flutter** könnte man stattdessen ein einfaches Template-System bauen oder ein Paket wie `mustache_template` nutzen:
  ```dart
  import 'package:mustache_template/mustache_template.dart';
  
  final template = Template('Sehr geehrte/r {{anrede}},');
  final output = template.renderString({'anrede': 'Frau Müller'});
  ```
  
  **Vorteile von Handlebars/Mustache:**
  - Trennung von Logik und Präsentation
  - Wiederverwendbare Vorlagen (eine Vorlage + Daten = viele verschiedene E-Mails)
  - Bedingungen und Schleifen ohne Programmcode in der Vorlage
  - Sicherer als `eval` oder String-Interpolation mit Benutzereingaben
  - Einfach zu testen (Template + Testdaten → erwarteten Output prüfen)
  
  *Entscheidung:* Handlebars verwenden. Im Dart-Umgebung kommt `mustache_template` zum Einsatz (nahezu identische Syntax).

- [ ] **Mehrere E-Mail-Profile** (z. B. private Bewerbung vs. über Agentur)  
  *Entscheidung:* Auf spätere Erweiterung verschoben – nicht in der ersten Iteration.

---

## 4. Ergänzende Architektur-Entwürfe

### Queue-basierte Verarbeitung (empfohlen)

```
Status-Modell für jede Bewerbung:
┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
│ pending  │──►│ queued   │──►│ sending  │──►│ sent     │
└──────────┘   └──────────┘   └──────────┘   └──────────┘
                                                │
                                          ┌─────┴─────┐
                                          │           │
                                          ▼           ▼
                                      ┌────────┐  ┌────────┐
                                      │ failed │  │bounced │
                                      └────────┘  └────────┘
                                          │
                                          ▼
                                    Benachrichtigung
                                    an Benutzer
```

### Retry-Logik (Exponential Backoff)

```
Versuch 1: sofort          → Fehler? → warte 1 Minute
Versuch 2: nach 1 Minute   → Fehler? → warte 5 Minuten
Versuch 3: nach 5 Minuten  → Fehler? → warte 30 Minuten
Versuch 4: nach 30 Minuten → Fehler? → Status → `failed`, Benachrichtigung
```

### Circuit Breaker (für API-Ausfälle)

```
                     ┌──────────┐
        ┌──────────► │  CLOSED  │ ◄──────────┐
        │            │ (normal) │            │
        │            └─────┬────┘            │
        │            Fehler┐                 │ Erfolg
        │            > 5   │                 │ (reset)
        │                  ▼                 │
        │            ┌──────────┐            │
        │            │   OPEN   │────────────┘
        │            │ (blocked)│  Timeout 30s
        │            └──────────┘
        │                  │
        │            ┌─────┴─────┐
        │            │  HALF-OPEN│
        │            │ (Test)    │
        └────────────┴───────────┘
```

---

## 5. Test-Strategie

### E-Mail-Versand

| Test | Beschreibung |
|------|-------------|
| **Unit-Tests** | Template-Rendering, PDF-Anhang-Erstellung, Validierung der E-Mail-Struktur |
| **Integrationstests** | Queue-Eintrag → Worker → API-Call (mit Brevo-Sandbox oder Mock-Server) |
| **Deliverability-Tests** | Manuelle Tests an verschiedene Provider (Gmail, Outlook, GMX, Web.de) |
| **Bounce-Tests** | Testen mit ungültigen E-Mail-Adressen → korrekte Status-Erfassung |
| **Rate-Limit-Tests** | Batch-Sendungen nahe am Limit → korrektes Drosselverhalten |

### Portal-Automation

| Test | Beschreibung |
|------|-------------|
| **Selector-Tests** | Prüfen, ob die CSS-Selektoren in `portal-config.json` noch aktuell sind (regelmäßiger CI-Job) |
| **CAPTCHA-Erkennung** | Test mit echten CAPTCHA-Seiten → korrekte Blockierung |
| **Fehler-Screenshots** | Bei Fehlschlag muss ein Screenshot gespeichert werden, der das Problem zeigt |
| **Dummy-Bewerbungen** | Test auf Portalen mit Übungs-/Sandbox-Modus (falls vorhanden) |

---

## 6. Beschlossene Entscheidungen & nächste Schritte

### Beschlossene Entscheidungen

| # | Entscheidung | Status | Detail |
|---|-------------|--------|--------|
| 1 | **E-Mail-Dienst** | ✅ Brevo | DSGVO-konform, 300 E-Mails/Tag kostenlos |
| 2 | **Rate-Limiting** | ✅ Benutzerkonfigurierbar | In App-Optionen einstellbar (Vorschlag: 5 E-Mails/min, 1 Portal/5 min) |
| 3 | **Template-Engine** | ✅ Handlebars / Mustache | Dart: `mustache_template`-Paket, JS: `handlebars` |
| 4 | **Mehrere E-Mail-Profile** | ⏳ Verschoben | In späterer Iteration |

### Nächste Schritte (To-Do)

- [ ] **Portal-Unterstützung priorisieren** – Welche Portale außer Jobcenter? Qualität der Portal-APIs prüfen.
- [ ] **Rechtliche Prüfung der Portal-Automation** – Vor Baubeginn Phase 2/3 (Anwalt für IT-Recht)
- [ ] **Brevo-Account erstellen** und API-Key generieren
- [ ] **Secrets-Manager einrichten** (z. B. Azure Key Vault, HashiCorp Vault, oder verschlüsselte Env-Vars)
- [ ] **E-Mail-Vorlagen definieren** mit Handlebars/Mustache (Platzhalter für Name, Firma, Position, Anrede)
- [ ] **Queue-System implementieren** (Status-Modell: pending → queued → sending → sent/failed/bounced, Retry mit Backoff, Rate-Limiter)
- [ ] **Rate-Limiter in App-Optionen integrieren** (Sliders/Input-Felder für E-Mails/min und Portal-Intervalle)
- [ ] **Tests schreiben** (Unit: Template-Rendering + Integration: Queue → API + Deliverability: manuelle Tests)
- [ ] **Logging & Monitoring** aufsetzen (Timestamp, Empfänger, Status, Fehlermeldung pro Versand)
- [ ] **Fallback-Mechanismus** bauen ("Als Entwurf exportieren"-Button bei Fehlschlag)
- [ ] **Deliverability einrichten** (DKIM/SPF konfigurieren, Bounce-Webhook von Brevo)
- [ ] **Portal-Automation (Phase 2/3)** – erst nach erfolgreichem E-Mail-Versand und rechtlicher Prüfung
