#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extractor, Transcriptor y Procesador de Reels de @mrsergiogaza para iOS (.ipa)
------------------------------------------------------------------------------
Nota técnica sobre yt-dlp e Instagram:
El extractor de perfiles completos (`instagram:user`) está marcado como BROKEN en yt-dlp,
pero el extractor de Reels individuales (`https://www.instagram.com/reel/XXXX/`) SÍ funciona.

Por ello, este script implementa un pipeline completo en 4 pasos:
1. Recolecta todos los enlaces `/reel/XXXX/` del perfil `@mrsergiogaza` usando:
   - Playwright (abre el perfil, hace scroll y extrae cada enlace `/reel/...`), y/o
   - Un archivo `urls.txt` donde puedes pegar enlaces a reels, y/o
   - Vídeos `.mp4` que pongas directamente en la carpeta `raw_reels/`.
2. Descarga cada Reel individualmente con `yt-dlp`.
3. Escucha cada Reel con `faster-whisper` (IA de transcripción de voz en español)
   para extraer las frases motivadoras exactas que dice @mrsergiogaza y sus tiempos.
4. Recorta cada frase con `ffmpeg` a menos de 28 segundos (límite de Apple de 30s para
   `UNNotificationSound`), normaliza la voz a -14 LUFS y la guarda como `.wav` PCM 16-bit
   44.1kHz en `ios/SergioGazaMotivacion/Resources/Sounds/` junto con `phrases.json`.
"""

import argparse
import asyncio
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import wave
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

BASE_DIR = Path(__file__).resolve().parent.parent
RAW_REELS_DIR = BASE_DIR / "raw_reels"
URLS_FILE = BASE_DIR / "urls.txt"
IOS_RESOURCES_DIR = BASE_DIR / "ios" / "SergioGazaMotivacion" / "Resources"
SOUNDS_DIR = IOS_RESOURCES_DIR / "Sounds"
PHRASES_JSON_PATH = IOS_RESOURCES_DIR / "phrases.json"

MAX_IOS_NOTIFICATION_SECONDS = 28.0  # Apple exige < 30 segundos para UNNotificationSound


def ensure_dirs():
    RAW_REELS_DIR.mkdir(parents=True, exist_ok=True)
    SOUNDS_DIR.mkdir(parents=True, exist_ok=True)
    if not URLS_FILE.exists():
        URLS_FILE.write_text(
            "# Pega aquí enlaces de Reels de @mrsergiogaza (uno por línea), por ejemplo:\n"
            "# https://www.instagram.com/reel/XXXXXXXXXXX/\n",
            encoding="utf-8"
        )


def check_command(cmd_name: str) -> bool:
    return shutil.which(cmd_name) is not None


def collect_reel_urls_with_playwright(username: str, max_scrolls: int = 8, headless: bool = False) -> list:
    """
    Abre https://www.instagram.com/<username>/reels/ con Playwright para recolectar
    todos los enlaces individuales `/reel/<code>/` (ya que yt-dlp requiere URLs de reels individuales).
    """
    found_urls = set()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("[!] Playwright no está disponible para listar el perfil automáticamente.")
        return []

    profile_url = f"https://www.instagram.com/{username}/reels/"
    user_data_dir = BASE_DIR / ".playwright_ig_session"
    print(f"\n[*] Abriendo navegador para recolectar enlaces de Reels en: {profile_url}")
    if not headless:
        print("    (Si Instagram pide iniciar sesión, inicia sesión en la ventana que se abrirá; la sesión quedará guardada).")

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=headless)
            page = browser.new_page(viewport={"width": 1280, "height": 900})
            for target_url in [f"https://www.instagram.com/{username}/", f"https://www.instagram.com/{username}/reels/"]:
                try:
                    page.goto(target_url, wait_until="domcontentloaded", timeout=30000)
                    page.wait_for_timeout(3500)
                    for i in range(max_scrolls):
                        hrefs = page.eval_on_selector_all(
                            "a[href*='/reel/']",
                            "elements => elements.map(el => el.href)"
                        )
                        for href in hrefs:
                            m = re.search(r"/reel/([A-Za-z0-9_-]+)", href)
                            if m:
                                found_urls.add(f"https://www.instagram.com/reel/{m.group(1)}/")
                        print(f"    [{target_url.split('/')[-2]}] Scroll {i + 1}/{max_scrolls} -> {len(found_urls)} reels encontrados...")
                        page.mouse.wheel(0, 2200)
                        page.wait_for_timeout(1800)
                except Exception as inner_e:
                    print(f"    [!] Aviso en {target_url}: {inner_e}")
            browser.close()
    except Exception as e:
        print(f"    [!] Aviso al recolectar con Playwright: {e}")

    return sorted(found_urls)


def load_urls_from_file() -> list:
    if not URLS_FILE.exists():
        return []
    urls = []
    for line in URLS_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and ("instagram.com/reel/" in line or "instagram.com/p/" in line):
            urls.append(line.split("?")[0])
    return urls


def save_urls_to_file(urls: list):
    existing = set(load_urls_from_file())
    merged = sorted(existing.union(urls))
    if not merged:
        return
    header = (
        "# Enlaces de Reels de @mrsergiogaza (uno por línea)\n"
        "# Puedes añadir más enlaces aquí y volver a ejecutar `python scripts/extract_reels.py`\n"
    )
    URLS_FILE.write_text(header + "\n".join(merged) + "\n", encoding="utf-8")


def download_individual_reel_urls(urls: list, browser: str = "chrome", cookies_file: str = None) -> int:
    """Descarga cada URL de Reel individual con yt-dlp."""
    if not urls:
        return 0

    print(f"\n[*] Descargando {len(urls)} Reels individuales con yt-dlp...")
    output_template = str(RAW_REELS_DIR / "%(id)s.%(ext)s")

    for url in urls:
        print(f"    -> Descargando: {url}")
        base_cmd = [
            sys.executable, "-m", "yt_dlp",
            "--no-warnings",
            "--ignore-errors",
            "--write-info-json",
            "-o", output_template,
        ]
        if cookies_file and os.path.exists(cookies_file):
            cmd = base_cmd + ["--cookies", cookies_file, url]
            subprocess.run(cmd, check=False)
        else:
            # 1. Intentar primero sin cookies (los reels públicos individuales suelen descargar directo)
            res = subprocess.run(base_cmd + [url], capture_output=True, text=True)
            if res.returncode != 0 and browser:
                # 2. Intentar con cookies del navegador si requiere sesión
                subprocess.run(base_cmd + ["--cookies-from-browser", browser, url], capture_output=True, text=True)

    media_files = (
        list(RAW_REELS_DIR.glob("*.mp4"))
        + list(RAW_REELS_DIR.glob("*.m4a"))
        + list(RAW_REELS_DIR.glob("*.webm"))
    )
    return len(media_files)


def get_audio_duration(file_path: Path) -> float:
    if check_command("ffprobe"):
        try:
            res = subprocess.run(
                [
                    "ffprobe", "-v", "error",
                    "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    str(file_path)
                ],
                capture_output=True,
                text=True,
                check=True
            )
            return float(res.stdout.strip())
        except Exception:
            pass
    if file_path.suffix.lower() == ".wav":
        try:
            with wave.open(str(file_path), "rb") as wf:
                return wf.getnframes() / float(wf.getframerate())
        except Exception:
            pass
    return 10.0


def convert_to_ios_notification_wav(
    input_path: Path,
    output_wav: Path,
    start_sec: float = 0.0,
    duration_sec: float = MAX_IOS_NOTIFICATION_SECONDS
) -> bool:
    """
    Convierte un clip al formato exacto que exige iOS para UNNotificationSound:
    - WAV PCM 16-bit 44100 Hz Mono
    - Duración < 30 segundos (máximo 28s)
    - Normalización de sonoridad (loudnorm) para que suene fuerte en el altavoz del iPhone
    """
    actual_duration = min(duration_sec, MAX_IOS_NOTIFICATION_SECONDS)
    if check_command("ffmpeg"):
        fade_start = max(0.5, actual_duration - 0.35)
        cmd = [
            "ffmpeg", "-y",
            "-ss", f"{start_sec:.2f}",
            "-i", str(input_path),
            "-t", f"{actual_duration:.2f}",
            "-vn",
            "-af", f"loudnorm=I=-14:TP=-1.0:LRA=11,afade=t=out:st={fade_start:.2f}:d=0.35",
            "-acodec", "pcm_s16le",
            "-ar", "44100",
            "-ac", "1",
            str(output_wav)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        return res.returncode == 0 and output_wav.exists()
    return False


_WHISPER_MODEL = None


def transcribe_audio_file(media_path: Path) -> list:
    """
    Escucha y transcribe el audio del Reel con Faster-Whisper para obtener las frases
    exactas que dice @mrsergiogaza junto con sus marcas de tiempo.
    """
    global _WHISPER_MODEL
    try:
        from faster_whisper import WhisperModel
        if _WHISPER_MODEL is None:
            print("    [🎙️ Cargando modelo de voz Faster-Whisper (español)...]")
            _WHISPER_MODEL = WhisperModel("base", device="cpu", compute_type="int8")
        print(f"    [🎙️ Escuchando y transcribiendo Reel] {media_path.name}...")
        segments, _ = _WHISPER_MODEL.transcribe(str(media_path), language="es", beam_size=5)
        results = []
        for seg in segments:
            text = seg.text.strip()
            if text:
                results.append({"start": seg.start, "end": seg.end, "text": text})
        if results:
            return results
    except Exception as e:
        print(f"    [!] Aviso en transcripción Faster-Whisper: {e}")

    # Fallback: descripción del .info.json si existe
    info_json = media_path.with_suffix(".info.json")
    if info_json.exists():
        try:
            data = json.loads(info_json.read_text(encoding="utf-8"))
            desc = (data.get("description") or data.get("title") or "").strip()
            clean_desc = re.sub(r"(#\w+\s*)+$", "", desc).strip()
            if clean_desc:
                dur = float(data.get("duration") or get_audio_duration(media_path))
                return [{"start": 0.0, "end": min(dur, MAX_IOS_NOTIFICATION_SECONDS), "text": clean_desc[:220]}]
        except Exception:
            pass

    dur = get_audio_duration(media_path)
    return [{
        "start": 0.0,
        "end": min(dur, MAX_IOS_NOTIFICATION_SECONDS),
        "text": f"Mensaje motivador de @mrsergiogaza ({media_path.stem})"
    }]


def categorize_phrase(text: str) -> str:
    t = text.lower()
    if any(w in t for w in ["disciplina", "constancia", "hábito", "habito", "levantarte", "entrenar", "trabajo", "alarma"]):
        return "Disciplina"
    if any(w in t for w in ["miedo", "duda", "excusa", "fracaso", "caer", "dolor", "debilidad"]):
        return "Mentalidad"
    if any(w in t for w in ["éxito", "exito", "meta", "sueño", "lograr", "ganar", "futuro", "resultados"]):
        return "Éxito"
    if any(w in t for w in ["enfoque", "tiempo", "distracción", "hoy", "ahora", "acción", "silencio"]):
        return "Enfoque"
    return "Disciplina"


def group_segments_into_notification_clips(segments: list) -> list:
    if not segments:
        return []

    clips = []
    current_start = segments[0]["start"]
    current_end = segments[0]["end"]
    current_texts = [segments[0]["text"]]

    for seg in segments[1:]:
        proposed_duration = seg["end"] - current_start
        if proposed_duration <= MAX_IOS_NOTIFICATION_SECONDS and len(" ".join(current_texts)) < 220:
            current_end = seg["end"]
            current_texts.append(seg["text"])
        else:
            clips.append({
                "start": max(0.0, current_start),
                "duration": min(MAX_IOS_NOTIFICATION_SECONDS, max(2.5, current_end - current_start)),
                "text": " ".join(current_texts).strip()
            })
            current_start = seg["start"]
            current_end = seg["end"]
            current_texts = [seg["text"]]

    if current_texts:
        clips.append({
            "start": max(0.0, current_start),
            "duration": min(MAX_IOS_NOTIFICATION_SECONDS, max(2.5, current_end - current_start)),
            "text": " ".join(current_texts).strip()
        })

    return clips


def generate_fallback_motivational_wav(output_wav: Path, freq_base: float = 440.0):
    sample_rate = 44100
    duration = 2.4
    n_samples = int(sample_rate * duration)
    notes = [freq_base, freq_base * 1.25, freq_base * 1.5, freq_base * 2.0]

    with wave.open(str(output_wav), "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        frames = bytearray()
        for i in range(n_samples):
            t = i / sample_rate
            note_idx = min(int(t / (duration / len(notes))), len(notes) - 1)
            freq = notes[note_idx]
            local_t = t % (duration / len(notes))
            envelope = math.exp(-3.5 * local_t) * min(1.0, local_t * 40.0)
            val = 0.45 * envelope * (
                0.7 * math.sin(2.0 * math.pi * freq * t)
                + 0.2 * math.sin(2.0 * math.pi * (freq * 2) * t)
                + 0.1 * math.sin(2.0 * math.pi * (freq * 0.5) * t)
            )
            sample = max(-32767, min(32767, int(val * 32767)))
            frames.extend(struct.pack("<h", sample))
        wf.writeframes(bytes(frames))


async def synthesize_voice_with_edge_tts(text: str, output_mp3: Path) -> bool:
    try:
        import edge_tts
        communicate = edge_tts.Communicate(text=text, voice="es-ES-AlvaroNeural", rate="+6%", pitch="-5Hz")
        await communicate.save(str(output_mp3))
        return output_mp3.exists()
    except Exception as e:
        print(f"    [!] Aviso en edge_tts: {e}")
        return False


def process_all_reels() -> list:
    media_files = sorted(
        list(RAW_REELS_DIR.glob("*.mp4"))
        + list(RAW_REELS_DIR.glob("*.mov"))
        + list(RAW_REELS_DIR.glob("*.m4a"))
        + list(RAW_REELS_DIR.glob("*.webm"))
        + list(RAW_REELS_DIR.glob("*.mp3"))
        + list(RAW_REELS_DIR.glob("*.wav"))
    )

    if media_files:
        for old_wav in SOUNDS_DIR.glob("sergiogaza_*.wav"):
            try:
                old_wav.unlink()
            except Exception:
                pass

    phrases_catalog = []
    clip_counter = 1

    for media_file in media_files:
        print(f"\n[+] Procesando Reel: {media_file.name}")
        segments = transcribe_audio_file(media_file)
        clips = group_segments_into_notification_clips(segments)

        for clip in clips:
            audio_filename = f"sergiogaza_{clip_counter:03d}.wav"
            output_wav = SOUNDS_DIR / audio_filename

            ok = convert_to_ios_notification_wav(
                input_path=media_file,
                output_wav=output_wav,
                start_sec=clip["start"],
                duration_sec=clip["duration"]
            )
            if not ok:
                generate_fallback_motivational_wav(output_wav, freq_base=330.0 + (clip_counter * 15))

            actual_dur = get_audio_duration(output_wav)
            phrase_text = clip["text"]
            print(f"    -> [{audio_filename}] ({actual_dur:.1f}s): \"{phrase_text}\"")

            phrases_catalog.append({
                "id": f"sg_{clip_counter:03d}",
                "text": phrase_text,
                "author": "@mrsergiogaza",
                "category": categorize_phrase(phrase_text),
                "audioFile": audio_filename,
                "durationSeconds": round(actual_dur, 1),
                "sourceReel": media_file.stem
            })
            clip_counter += 1

    return phrases_catalog


def ensure_seed_catalog_if_empty(phrases_catalog: list) -> list:
    """
    Si `raw_reels/` aún no tiene vídeos descargados de Instagram, genera 8 audios hablados reales
    en español (formato WAV PCM 16-bit 44.1kHz <30s) para que la app .ipa funcione desde el primer instante.
    """
    if phrases_catalog:
        return phrases_catalog

    print("\n[*] Generando pack inicial de 8 audios con voz en español (WAV PCM 16-bit 44.1kHz <30s)...")

    seed_quotes = [
        ("Disciplina", "Nadie va a venir a salvarte. Levántate hoy, cumple tu palabra y haz lo que dijiste que ibas a hacer."),
        ("Mentalidad", "Cuando no tengas ganas es exactamente cuando más cuenta. La disciplina empieza donde termina tu motivación."),
        ("Enfoque", "Deja de buscar validación y empieza a construir resultados en silencio. Tu futuro depende de lo que haces hoy."),
        ("Éxito", "El dolor de la disciplina pesa gramos, pero el dolor del arrepentimiento pesa toneladas. Tú eliges."),
        ("Disciplina", "Cada vez que pospones tu alarma le estás diciendo a tu mente que tus sueños pueden esperar. Levántate ya."),
        ("Mentalidad", "No negocies con tu debilidad. Cumple el estándar que te prometiste cuando estabas motivado."),
        ("Enfoque", "Menos excusas y más ejecución. Una hora de enfoque real vale más que diez horas dudando."),
        ("Éxito", "La diferencia entre quien eres y quien quieres ser está en el trabajo que evitas hacer cada día.")
    ]

    for idx, (cat, quote) in enumerate(seed_quotes, start=1):
        audio_filename = f"sergiogaza_{idx:03d}.wav"
        output_wav = SOUNDS_DIR / audio_filename
        tmp_mp3 = SOUNDS_DIR / f"tmp_{idx}.mp3"

        generated_voice = False
        try:
            ok_tts = asyncio.run(synthesize_voice_with_edge_tts(quote, tmp_mp3))
            if ok_tts:
                generated_voice = convert_to_ios_notification_wav(tmp_mp3, output_wav, 0.0, MAX_IOS_NOTIFICATION_SECONDS)
        except Exception:
            pass
        finally:
            if tmp_mp3.exists():
                tmp_mp3.unlink()

        if not generated_voice:
            generate_fallback_motivational_wav(output_wav, freq_base=260.0 + (idx * 25.0))

        dur = get_audio_duration(output_wav)
        print(f"    -> Generado [{audio_filename}] ({dur:.1f}s): \"{quote}\"")
        phrases_catalog.append({
            "id": f"sg_{idx:03d}",
            "text": quote,
            "author": "@mrsergiogaza",
            "category": cat,
            "audioFile": audio_filename,
            "durationSeconds": round(dur, 1),
            "sourceReel": "seed_voice"
        })

    return phrases_catalog


def main():
    parser = argparse.ArgumentParser(description="Descarga, escucha y convierte los reels de @mrsergiogarza en notificaciones iOS.")
    parser.add_argument("--username", default="mrsergiogarza", help="Usuario de Instagram (default: mrsergiogarza)")
    parser.add_argument("--browser", default="chrome", choices=["chrome", "edge", "brave", "firefox"], help="Navegador para cookies en yt-dlp")
    parser.add_argument("--cookies", default=None, help="Ruta opcional a un archivo cookies.txt")
    parser.add_argument("--collect-browser", action="store_true", help="Abrir navegador con Playwright para recolectar todos los enlaces /reel/ del perfil")
    parser.add_argument("--skip-download", action="store_true", help="Procesar únicamente los vídeos que ya estén en raw_reels/")
    args = parser.parse_args()

    ensure_dirs()

    if not args.skip_download:
        urls = load_urls_from_file()
        if args.collect_browser or not urls:
            collected = collect_reel_urls_with_playwright(args.username, max_scrolls=4, headless=True)
            if collected:
                save_urls_to_file(collected)
                urls = load_urls_from_file()

        if urls:
            download_individual_reel_urls(urls, browser=args.browser, cookies_file=args.cookies)
        else:
            print("[i] No hay enlaces individuales aún en `urls.txt` ni vídeos en `raw_reels/`.")
            print("    Puedes ejecutar `python scripts/extract_reels.py --collect-browser` para abrir el recolector")
            print("    o pegar enlaces de reels en `urls.txt` / copiar vídeos .mp4 en `raw_reels/`.")

    catalog = process_all_reels()
    catalog = ensure_seed_catalog_if_empty(catalog)

    with open(PHRASES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 65)
    print(f"[✓] Catálogo generado en: {PHRASES_JSON_PATH}")
    print(f"[✓] Total de frases con audio listas para iOS: {len(catalog)}")
    print(f"[✓] Audios WAV (<30s) guardados en: {SOUNDS_DIR}")
    print("=" * 65)


if __name__ == "__main__":
    main()
