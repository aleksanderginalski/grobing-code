# grobing-code

Kod aplikacji **Grobing** (Flutter, Android, local-first). Projekt powstał świeżym `flutter create`
na przypiętej wersji SDK (ISSUE-002), **nie** jako kopia innego projektu.

- Agenci i reguły: `../grobing-agents/` (tam otwierasz sesje, `/pm`).
- Dokumentacja i decyzje: `../grobing-vault/`.
- ⚠️ **Żadnych danych rodziny w tym repo** — ani bazy, ani kopii, ani eksportów, ani zdjęć prawdziwych
  osób. Dane żyją w aplikacji na telefonie. `.gitignore` obok to pierwsza linia obrony, nie jedyna.

## Wersja Fluttera — przypięta

Flutter na tej maszynie jest **współdzielony z inną, wydaną aplikacją autora**, więc globalnego SDK
się nie aktualizuje bez decyzji (ADR-002).

- **Jeden sposób:** `pubspec.yaml` → `environment.flutter: 3.41.1`. Każde `flutter pub get`
  (a więc `run`, `test`, `build`) na innej wersji **odmawia** z komunikatem
  *„Because grobing requires Flutter SDK version 3.41.1, version solving failed."*
- Zadeklarowana wartość żyje w `../grobing-agents/.claude/rules/project-config.example.md`
  (`flutter_version_pinned`). **Zmiana wersji = obie linie w jednej paczce** + datowana linia w ADR-002.
- Czego to nie daje: dwóch wersji obok siebie. Gdy druga aplikacja będzie potrzebowała nowszego
  Fluttera, ten projekt przestanie się budować — wtedy decyzja: podbić wersję albo dołożyć menedżer
  wersji (FVM).

## Uruchomienie

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # debug — emulator albo telefon testowy
```

## Podpis wydania

Aktualizacja wchodzi na telefon tylko wtedy, gdy jest podpisana **tym samym kluczem** co zainstalowana
wersja ([Sign your app](https://developer.android.com/studio/publish/app-signing)). Inny klucz = trzeba
odinstalować aplikację, a **odinstalowanie kasuje bazę**.

> ⚠️ **Na telefonie z prawdziwymi danymi instaluj wyłącznie build release** (`flutter run --release`
> albo `flutter build apk --release`). Przejście z buildu debug na release też wymaga odinstalowania.

1. **Klucz tworzy autor sam** — `keytool` pyta o hasła, więc nie przechodzą przez żadną sesję ani
   historię. Katalog: `release_keystore_dir` z `../grobing-agents/.claude/rules/project-config.md`
   (lokalny, poza każdym drzewem projektu):

   ```powershell
   keytool -genkey -v -keystore <release_keystore_dir>\grobing-release.jks -storetype JKS `
     -keyalg RSA -keysize 2048 -validity 10000 -alias grobing
   ```

2. **`android/key.properties`** (gitignorowany — nigdy do repo). W `storeFile` ukośniki `/`, bo `\` jest
   w tym formacie znakiem ucieczki:

   ```properties
   storePassword=<hasło magazynu>
   keyPassword=<hasło klucza>
   keyAlias=grobing
   storeFile=<release_keystore_dir z ukośnikami />/grobing-release.jks
   ```

3. **Kopia klucza** (`.jks` + hasła) w zaszyfrowanym miejscu autora, tym samym co kopia notatek
   (NT-001) — nie na tym samym dysku.

Bez `android/key.properties` build release **kończy się błędem** — nigdy nie podpisuje się po cichu
kluczem debug (`android/app/build.gradle.kts`).

## Tożsamość aplikacji

Nazwa pakietu i root widget są zapisane w
`../grobing-agents/.claude/rules/project-config.example.md` (*Product invariants*) — agenci ich nie
wymyślają. **Nazwy pakietu nie zmienia się nigdy**: inna nazwa to dla Androida inna aplikacja, która nie
widzi bazy poprzedniej.
