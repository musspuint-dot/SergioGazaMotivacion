# 🔥 Sergio Gaza Motivación — App iOS (`.ipa`) con Notificaciones de Voz

Aplicación nativa para iOS en **SwiftUI** que reproduce las frases motivadoras de **`@mrsergiogaza` con su propio audio** cada vez que suena una notificación en tu iPhone (incluso con la pantalla bloqueada), además de incluir un **Soundboard**, programador por **intervalos y horarios fijos**, e **importador directo de Reels** desde el propio iPhone.

---

## ⚙️ Cómo funciona el sonido de las notificaciones en iOS

Apple permite que las notificaciones locales (`UNNotificationContent`) reproduzcan un archivo de voz real en lugar del sonido estándar de iOS cuando se cumplen estos requisitos (todos automatizados por este proyecto):
1. **Duración máxima**: Menos de **30 segundos** (el script recorta automáticamente cada frase a `≤ 28s`).
2. **Formato de audio**: `WAV` (Linear PCM 16-bit 44.1kHz mono) o `CAF`.
3. **Ubicación**: Empaquetado en el bundle de la app (`Resources/Sounds/`) o guardado dinámicamente desde el iPhone en `Library/Sounds/`.

---

## 🎙️ Paso 1: Extraer y escuchar todos los Reels de `@mrsergiogaza`

> **Nota técnica descubierta**: En `yt-dlp`, el extractor de perfiles enteros de Instagram (`instagram:user`) está roto actualmente, pero la descarga de Reels individuales (`/reel/XXXX/`) funciona perfectamente. Por eso [`scripts/extract_reels.py`](./scripts/extract_reels.py) incluye un recolector automático con **Playwright** + **Faster-Whisper** (IA de voz ya instalada en tu PC).

Tienes **3 formas** de cargar todos los Reels de `@mrsergiogaza`:

### Opción A — Recolector automático con navegador (Recomendado)
Haz doble clic en [`Sincronizar_Reels_SergioGaza.bat`](./Sincronizar_Reels_SergioGaza.bat) (o ejecuta):
```powershell
python scripts/extract_reels.py --collect-browser
```
1. Se abrirá una ventana de navegador en `https://www.instagram.com/mrsergiogaza/reels/`.
2. Si Instagram te pide iniciar sesión, inicia sesión una vez (la sesión queda guardada en `.playwright_ig_session`).
3. El script hará scroll automáticamente, capturará los enlaces `/reel/...`, descargará cada vídeo con `yt-dlp`, **escuchará cada reel con Faster-Whisper**, extraerá las frases en español, recortará el audio a `<28s` con `ffmpeg` y actualizará `ios/SergioGazaMotivacion/Resources/Sounds/` + `phrases.json`.

### Opción B — Pegar enlaces en `urls.txt` o vídeos en `raw_reels/`
- Pega enlaces de reels en [`urls.txt`](./urls.txt) (uno por línea), **o**
- Suelta vídeos `.mp4` descargados en la carpeta `raw_reels/`, y ejecuta:
```powershell
python scripts/extract_reels.py
```

### Opción C — Importar directamente desde tu iPhone (sin recompilar el `.ipa`)
Dentro de la propia app en tu iPhone, ve a la pestaña **"Importar Reel"**, elige cualquier vídeo `.mp4`/`.mov` o audio `.mp3`/`.wav` descargado en tu iPhone, escribe la frase y la app extraerá automáticamente los primeros 28 segundos en `Library/Sounds/` como tono de notificación.

---

## 📦 Paso 2: Generar el archivo `.ipa` gratis con GitHub Actions (desde Windows)

Al estar en Windows, el flujo incluido en [`.github/workflows/build-ipa.yml`](./.github/workflows/build-ipa.yml) utiliza un servidor `macos-14` gratuito de GitHub para compilar el proyecto SwiftUI y entregarte el archivo `SergioGazaMotivacion.ipa`:

1. Sube esta carpeta a un repositorio de GitHub (público o privado):
   ```powershell
   git init
   git add .
   git commit -m "Initial commit: App motivadora Sergio Gaza iOS"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/SergioGazaMotivacion.git
   git push -u origin main
   ```
2. En tu repositorio de GitHub, entra en la pestaña **Actions** → **Build iOS .ipa (Sergio Gaza Motivacion)**.
3. Al finalizar (tarda ~2 minutos), descarga el artefacto **`SergioGazaMotivacion-IPA`** (contiene `SergioGazaMotivacion.ipa`).

---

## 📲 Paso 3: Instalar el `.ipa` en tu iPhone desde Windows

1. Descarga e instala **[Sideloadly](https://sideloadly.io/)** o **[AltStore](https://altstore.io/)** en tu PC con Windows (con iTunes e iCloud versión web oficial de Apple instalados).
2. Conecta tu iPhone por cable USB, arrastra `SergioGazaMotivacion.ipa` a **Sideloadly**, introduce tu Apple ID y pulsa **Start**.
3. En tu iPhone, ve a **Ajustes → General → Gestión de dispositivos y VPN**, confía en tu certificado de desarrollador y abre **Sergio Gaza**.
4. Pulsa **"Probar Aviso (5s)"**, bloquea la pantalla de tu iPhone y escucharás la notificación con voz real.
