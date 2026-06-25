# Kimiflow Launcher Design

Date: 2026-06-25
Language: de
Status: draft for review

## Ziel

Kimiflow bekommt einen kontextbewussten Launcher fuer leere oder vage Invocations. Wenn ein User nur
`/kimiflow`, `$kimiflow` oder sinngemaess "mach mit Kimiflow" schreibt, soll Kimiflow nicht passiv auf einen
perfekten Prompt warten. Es soll den Projektzustand lesen, ein kompaktes interaktives Menue zeigen, offene
Arbeit sichtbar machen und den User in den passenden Kimiflow-Flow fuehren.

Der Launcher ist kein zweiter Workflow neben Kimiflow. Er ist der Eingang in dieselben bestehenden Modi:
Project Map, Findings, Resume, Feature, Fix, Improve, Docs und spaeter Spec.

## Warum

Der User ist oft nicht bereit, die richtigen Flags oder Arbeitsschnitte selbst zu formulieren. Gleichzeitig ist
blindes Resume gefaehrlich: Ein geparkter Plan kann stale sein, wenn sich betroffene Dateien seit der Planung
geaendert haben. Der Launcher soll beide Probleme loesen:

- weniger Prompt-Arbeit fuer den User;
- mehr Sicherheit vor stale Plans, stale Maps und vergessenem Findings-Backlog.

## Research Input

- Hermes Agent zeigt den Wert von TUI, Slash-Autocomplete, Resume und Memory, aber offene Issues zeigen auch
  die Risiken stale Memory/Skill-Writes und stale Resume-Kontext.
- Aider zeigt den Wert klarer Modi (`ask`, `code`, `architect`) und Repo-Maps. Die Architect/Editor-Trennung
  ist nuetzlich, braucht aber Trust-Boundaries zwischen Planung und Umsetzung.
- OpenCode trennt Plan/Build und read-only Explore/Scout Agents. Das bestaetigt: Erst Zustand/Plan lesen,
  dann bauen.
- Das Stale-Plan-Pattern ist real: Wenn Plan und Code auseinanderlaufen, muss der Agent stoppen, den Plan
  revalidieren oder aktualisieren und erst danach weiterarbeiten.

Quellen:

- https://github.com/nousresearch/hermes-agent
- https://hermes-agent.nousresearch.com/docs/guides/tips
- https://github.com/NousResearch/hermes-agent/issues/9055
- https://github.com/NousResearch/hermes-agent/issues/35344
- https://aider.chat/docs/usage/modes.html
- https://aider.chat/
- https://opencode.ai/docs/agents/
- https://medium.com/@arijitdutta23/the-stale-plan-problem-in-coding-agents-cde2c741f8ab

## Leitprinzipien

- Kontext zuerst, Menue danach.
- Vorhandene `.kimiflow/project/`-Analyse zuerst nutzen; neue Recherche nur fuer Luecken oder stale Bereiche.
- Interaktiv, aber tokenarm: Statuszeilen + nummerierte Optionen statt langer Beratung.
- Kein blindes Resume: geparkte Runs muessen gegen aktuelle Repo-Realitaet geprueft werden.
- Drilldown statt Informationsflut: Findings und Runs zuerst zaehlen, Details erst auf Wunsch.
- Verbesserung entgrillen: "verbessern" wird in klare Hebel uebersetzt.
- Launcher schreibt keinen Code. Er routet in einen normalen Kimiflow-Flow.
- Headless/vage ohne Antwort darf nie riskant auto-waehlen.

## Trigger

Der Launcher startet bei:

- leerer Invocation: `/kimiflow`, `$kimiflow`, `@kimiflow`;
- sehr vager Invocation: "mach mit Kimiflow", "lass Kimiflow drueberlaufen";
- explizitem Launcher-Flag: `--launcher` oder `--menu`.

Er startet nicht bei klaren Requests:

- `/kimiflow --fix <bug>`;
- `/kimiflow --project-map standard`;
- `/kimiflow --resume <slug>`;
- `/kimiflow Add dark mode toggle`.

Bei einem klaren Request laeuft Kimiflow wie bisher. Phase 0 darf trotzdem Map-Staleness pruefen.

## Launcher Status Snapshot

Vor dem Menue liest Kimiflow einen kompakten Status Snapshot:

```text
repo: present | missing
project_map: missing | quick | standard | deep
project_map_status: current | partially_stale | stale | unknown | missing
findings_open: <n>
improvements_open: <n>
parked_runs: <n>
active_runs: <n>
repo_docs: present | missing | unknown
working_tree: clean | dirty
last_commit: <sha|NOT VERIFIED>
```

V1 kann diesen Snapshot mit einem kleinen Helper `hooks/launcher-status.sh` erzeugen. Das Skript soll nur lesen
und stabile JSON/TSV-Ausgabe liefern. Es darf keine Dateien schreiben und keine LLM-Entscheidung ersetzen.

## Nutzung vorhandener Projektintelligenz

Der Launcher selbst und jeder daraus gestartete Build/Fix/Improve/Docs-Flow nutzt die bestehende Deep-Map als
erste Wissensquelle:

1. `hooks/launcher-status.sh` liest nur Status und Counts.
2. Bei konkreter Auswahl liest Kimiflow zuerst `.kimiflow/project/INDEX.json`.
3. Danach nur relevante `FACTS.jsonl`-Eintraege und passende Markdown-Artefakte.
4. Nur wenn die betroffene Section stale, unknown oder lueckenhaft ist, fragt Kimiflow nach Delta-Refresh oder
   gezielter Code-Erkundung.

Damit wird der Launcher nicht zu einem neuen Vollscan-Button. Er ist ein Router, der vorhandenes Projektwissen
sichtbar macht und nur dort nachlaedt, wo die Map nicht mehr vertraauenswuerdig ist.

## Startmenue

Beispiel bei vorhandener aktueller Map:

```text
Kimiflow Start

Projektkarte: standard · aktuell
Offene Findings: 4
Geparkte Runs: 2
Repo-Doku: vorhanden
Working Tree: geaendert

Was willst du tun?

1. Status ansehen
2. Projektkarte pruefen/aktualisieren
3. Offene Findings ansehen/abarbeiten
4. Geparkten Run fortsetzen
5. Bug fixen
6. Feature bauen
7. Verbesserungen priorisieren
8. Doku schreiben/aktualisieren
9. Idee/unklaren Auftrag ausarbeiten
```

Wenn keine Map existiert:

```text
Kimiflow hat ein Projekt gefunden, aber noch keine Projektkarte.

1. Projektkarte anlegen (standard, empfohlen)
2. Schnell analysieren
3. Tief analysieren
4. Ohne Projektkarte weiter
5. Erst Status/Dateien ansehen
```

## Drilldowns

### Findings

Wenn `findings_open > 0`, muss der User Details bekommen koennen:

```text
Offene Findings: 4

1. Kurz zusammenfassen
2. Kritischste zuerst fixen
3. Nach Bereich gruppieren
4. Alle Details anzeigen
5. Zurueck
```

Kimiflow liest dafuer `.kimiflow/project/FINDINGS.md` und zeigt maximal eine kompakte Liste. Fix-Auswahl routet
in einen normalen `--fix` oder Feature/Docs/Improve-Flow mit eigener State-Dir.

### Geparkte Runs

Geparkte Runs kommen aus `.kimiflow/*/STATE.md` mit `Status: backlog`. Das Menue zeigt Slug, Modus, Scope,
Plan-Basis und betroffene Pfade, soweit vorhanden.

```text
Geparkte Runs

1. add-codex-launcher · feature · plan approved · basis c2194da · risk: stale-check needed
2. update-release-docs · docs · plan approved · basis c2194da · risk: low
3. Zurueck
```

Auswahl eines Runs startet nie direkt Implementierung. Zuerst kommt der Resume Safety Check.

### Improve

"Verbessern" wird entgrillt:

```text
Welche Verbesserungsperspektive meinst du?

1. Die drei groessten Hebel finden
2. Architektur vereinfachen
3. Codequalitaet / Refactoring
4. Skalierbarkeit / Performance
5. Tests / Robustheit
6. Doku / Onboarding
7. Sicherheit / Privacy
```

Option 1 erzeugt erst eine priorisierte Improve-Analyse. Die anderen Optionen grenzen den Fokus ein und koennen
Project-Map-Deep-Analyse, `IMPROVEMENTS.md` oder einen normalen Kimiflow-Prepare-Lauf starten.

## Resume Safety Check

Vor jedem Fortsetzen eines geparkten Runs:

1. `STATE.md` lesen.
2. `PLAN.md`, `ACCEPTANCE.md`, `RESEARCH.md` oder `DIAGNOSIS.md` lesen, falls vorhanden.
3. Plan-Basis bestimmen: gespeicherter Commit oder `NOT VERIFIED`.
4. Betroffene Dateien bestimmen:
   - explizite `Affected files:` aus Artefakten;
   - Dateien aus Plan Tasks;
   - fallback: alle Dateien, die in Plan/Research/Diagnosis als `path:line` vorkommen.
5. `git diff --name-status <plan_commit> HEAD` + unstaged/staged Changes auswerten.
6. Betroffene Dateien und Project-Map-Sections gegen Aenderungen pruefen.
7. Resume-Menue zeigen.

Beispiel:

```text
Run: add-codex-launcher
Status: backlog
Plan-Basis: c2194da
Betroffene Dateien: SKILL.md, reference.md, hooks/project-map-status.sh

Seit der Planung geaendert:
- reference.md
- SKILL.md

Risiko: Plan moeglicherweise stale.

1. Plan revalidieren (empfohlen)
2. Plan anzeigen
3. Abbrechen
```

Nur wenn keine betroffenen Dateien geaendert wurden, darf "Fortsetzen" angeboten werden:

```text
1. Fortsetzen
2. Plan kurz anzeigen
3. Abbrechen
```

Wenn der Check `unknown` ist, gilt er als nicht sicher genug fuer blindes Resume. Empfohlen ist Revalidation.

## Plan Revalidation

Revalidation ist ein schlanker Kimiflow-Teilflow:

- aktuelle Map/Staleness lesen;
- betroffene Dateien gezielt neu pruefen;
- Planannahmen gegen Code vergleichen;
- `PLAN.md` und `ACCEPTANCE.md` aktualisieren, wenn Drift existiert;
- Entscheidung in `STATE.md` oder `REVIEW.md` protokollieren.

Wenn Drift gefunden wird, geht Kimiflow zurueck zu Phase 3/4. Wenn kein Drift gefunden wird, darf Phase 5
fortgesetzt werden.

## Spec-Phase Anschluss

Der Launcher bekommt Option 9: "Idee/unklaren Auftrag ausarbeiten". V1 routet das in einen vorhandenen
Explore/Prepare-Pfad und erzeugt ein klares Intent/Plan-Paket.

Der geplante Folge-Slice ist eine native Spec-Phase:

```text
/kimiflow --spec <idea>
/kimiflow --spec --resume <slug>
```

Diese Phase soll spaeter Brainstorming ersetzen koennen:

- Idee entgrillen;
- 2-3 Loesungswege mit Trade-offs;
- Design-Spec schreiben;
- Spec-Review-Gate;
- danach optional Plan/Prepare.

Nicht in Launcher V1: eine vollstaendige Spec-Engine. Der Launcher reserviert nur den Einstieg und die
Routenlogik.

## Datenmodell

### Launcher Snapshot

V1-Ausgabe von `hooks/launcher-status.sh`:

```json
{
  "schema_version": 1,
  "repo": {"present": true, "root": "...", "head": "c2194da", "dirty": true},
  "project_map": {"present": true, "depth": "standard", "status": "current"},
  "findings": {"open": 4, "path": ".kimiflow/project/FINDINGS.md"},
  "improvements": {"open": 3, "path": ".kimiflow/project/IMPROVEMENTS.md"},
  "runs": {"active": 0, "backlog": 2},
  "repo_docs": {"present": true}
}
```

### Run Metadata

Bestehende `STATE.md` bleibt Quelle. Fuer bessere Revalidation sollte Phase 3/4 kuenftig optional diese Felder
in `STATE.md` schreiben:

```text
Plan commit: <sha|NOT VERIFIED>
Affected files:
- path/to/file
Plan status: approved|needs-revalidation|stale|current
```

V1 muss alte Runs ohne diese Felder tolerieren und per Artifact-Grep fallbacken.

## Fehlerverhalten

- Kein Git-Repo: Launcher kann Status zeigen, aber Resume-Staleness ist `NOT VERIFIED`; keine blinde
  Implementierung aus geparktem Plan.
- Keine `.kimiflow/project/`: Map-Bootstrap anbieten.
- Ungueltiges `INDEX.json`: als `unknown` behandeln, Refresh anbieten.
- Findings-Datei fehlt trotz Count-Wunsch: Count `unknown`, Details nicht behaupten.
- Run hat keine `STATE.md`: nicht als resumable anzeigen; optional als orphaned artifact melden.
- Plan-Basis-Commit existiert nicht mehr: Revalidation erforderlich.
- Working Tree dirty und betroffene Dateien geaendert: Revalidation erforderlich.

## Tests und Validation

Automatisiert:

- `hooks/launcher-status.sh` Unit-Test fuer:
  - keine Map;
  - aktuelle Map;
  - stale Map;
  - Findings vorhanden;
  - backlog Runs vorhanden;
  - dirty Working Tree;
  - missing/invalid JSON.
- Smoke-Test fuer Skill/README:
  - leerer Kimiflow-Aufruf ist als Launcher dokumentiert;
  - Launcher bleibt opt-in;
  - Resume Safety Check ist dokumentiert;
  - geparkte Runs duerfen nicht blind implementiert werden.
- Existing Smokes bleiben gruen:
  - `bash hooks/smoke-install.sh`
  - `bash hooks/smoke-install-codex.sh`
  - `bash hooks/test-project-map-status.sh`

Manuell:

- `/kimiflow` in Claude Code zeigt Launcher-Menue.
- `$kimiflow` in Codex zeigt Launcher-Menue.
- Projekt ohne Map bietet Bootstrap an.
- Projekt mit Map zeigt Tiefe und Status.
- Geparkter Run mit geaenderten betroffenen Dateien bietet Revalidation statt blindem Fortsetzen.
- Findings-Drilldown zeigt kompakte Details und routet in einen normalen Fix/Improve-Flow.

## Nicht-Ziele fuer V1

- Keine vollstaendige TUI.
- Keine persistenten Menue-Sessions ausserhalb der normalen Kimiflow-Artefakte.
- Keine bezahlten Provider, Embeddings oder Datenbank als Voraussetzung.
- Keine automatische Umsetzung aus einem geparkten Plan ohne Resume Safety Check.
- Keine native Spec-Engine in diesem Slice; nur Anschluss vorbereiten.

## Offene Folge-Slices

1. Native Spec-Phase.
2. Besser strukturierte Run-Metadaten fuer alle neuen Kimiflow-Laeufe.
3. Optionaler Vault-Index fuer Findings und Improvements.
4. Spaetere TUI/Plugin-UI, falls Claude/Codex dafuer stabile Flaechen anbieten.
