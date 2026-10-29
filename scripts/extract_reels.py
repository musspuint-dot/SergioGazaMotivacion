#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extractor, Transcriptor y Procesador de Reels COMPLETOS para iOS (.ipa)
-----------------------------------------------------------------------
Genera para cada Reel descargado:
1. El AUDIO COMPLETO SIN CORTES (`<user>_reel_XXX_full.caf`) para que suene entero
   en modo alarma, en notificaciones con la app en segundo plano y en el Soundboard.
2. Las PARTES CONSECUTIVAS de 28s (`<user>_reel_XXX_p1.caf`, `p2.caf`, ...) para que,
   incluso si iOS reproduce la notificación mediante `UNNotificationSound` con la app
   cerrada, encadene automáticamente Parte 1 -> Parte 2 -> Parte 3 hasta sonar el
   Reel completo de principio a fin.
3. La transcripción completa por voz con Faster-Whisper en `phrases.json`.
"""

import argparse
import json
import math
import os
import re
import shutil
import subprocess
import sys
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

PART_DURATION_SECONDS = 28.0  # Límite por parte individual en UNNotificationSound (<30s)


def ensure_dirs():
    RAW_REELS_DIR.mkdir(parents=True, exist_ok=True)
    SOUNDS_DIR.mkdir(parents=True, exist_ok=True)


def check_command(cmd_name: str) -> bool:
    return shutil.which(cmd_name) is not None


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
    return 25.0


def convert_to_ios_caf(
    input_path: Path,
    output_caf: Path,
    start_sec: float = 0.0,
    duration_sec: float = None
) -> bool:
    """
    Convierte el audio a formato Apple Core Audio (.caf) con códec IMA4 (adpcm_ima_qt)
    a 22050 Hz mono y normalización de sonoridad (-14 LUFS).
    - Compatible al 100% tanto con `UNNotificationSound` como con `AVAudioPlayer`.
    - 8 veces más ligero que WAV sin comprimir, permitiendo empaquetar todos los Reels
      completos dentro del .ipa.
    """
    cmd = ["ffmpeg", "-y", "-ss", f"{start_sec:.2f}", "-i", str(input_path)]
    if duration_sec is not None:
        cmd += ["-t", f"{duration_sec:.2f}"]
    cmd += [
        "-vn",
        "-af", "loudnorm=I=-14:TP=-1.0:LRA=11",
        "-acodec", "adpcm_ima_qt",
        "-ar", "22050",
        "-ac", "1",
        str(output_caf)
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.returncode == 0 and output_caf.exists()


_WHISPER_MODEL = None


def transcribe_full_reel(media_path: Path) -> str:
    global _WHISPER_MODEL
    try:
        from faster_whisper import WhisperModel
        if _WHISPER_MODEL is None:
            print("    [🎙️ Cargando modelo Faster-Whisper (español)...]")
            _WHISPER_MODEL = WhisperModel("base", device="cpu", compute_type="int8")
        print(f"    [🎙️ Escuchando Reel completo] {media_path.name}...")
        segments, _ = _WHISPER_MODEL.transcribe(str(media_path), language="es", beam_size=5)
        texts = [seg.text.strip() for seg in segments if seg.text.strip()]
        if texts:
            return " ".join(texts)
    except Exception as e:
        print(f"    [!] Aviso en Faster-Whisper: {e}")

    info_json = media_path.with_suffix(".info.json")
    if info_json.exists():
        try:
            data = json.loads(info_json.read_text(encoding="utf-8"))
            desc = (data.get("description") or data.get("title") or "").strip()
            clean_desc = re.sub(r"(#\w+\s*)+$", "", desc).strip()
            if clean_desc:
                return clean_desc
        except Exception:
            pass
    return f"Audio motivador completo ({media_path.stem})"


def categorize_phrase(text: str) -> str:
    t = text.lower()
    if any(w in t for w in ["regla", "disciplina", "hábito", "levantarte", "alarma", "agua fría", "baño"]):
        return "Disciplina"
    if any(w in t for w in ["miedo", "duda", "overthinking", "fear", "paralítico", "salud", "quejar"]):
        return "Mentalidad"
    if any(w in t for w in ["ganar", "abundancia", "éxito", "billetes", "feria", "vip", "lograr"]):
        return "Éxito"
    if any(w in t for w in ["enfócate", "enfoque", "scrolleando", "distracciones", "tiempo", "familia"]):
        return "Enfoque"
    return "Disciplina"


# Transcripciones completas pulidas para los 13 Reels de @mrsergiogarza ya escuchados
CURATED_FULL_TRANSCRIPTIONS = {
    "De-nJyyMQSR": "¿Qué onda compadres? No desperdicien su salud. Si tienen sus manos y sus pies funcionando, pónganse a hacer algo bueno y dejen de andar de huevones. Tuve una plática de tres horas con un compadre que quedó paralítico hace dos años y me decía: 'Wey, cómo quisiera estar en tus zapatos y poder moverme'. De un segundo a otro te cambia la vida. Aprovechen que están sanos, pónganse bien pilas, trabajen duro, hagan ejercicio y no desperdicien ninguna energía. ¡Déjenlo todo en la cancha!",
    "De1nUi3RFi0": "Póngase verga mijo, pero tan verga que se arrepientan todos los que te faltaron al respeto cabrón. Constrúyete desde cero: ponte a leer, ponte a estudiar, ponte bien mamado, ya no tomes, ya no fumes, enfócate, disciplínate y cumple contigo mismo wey. ¡Vámonos cabrón!",
    "De4ydu7xgDs": "Llamada grupal 10 de la mañana con el grupo VIP, vámonos con todo perros. Esto es lo que tenemos que hacer a diario para lograr el plan: el plan es ejecución, comer bien, ejercitarte, alinearte todos los días y resolver cualquier problema con energía al máximo. ¡Aquí estamos presentes!",
    "De6AchzxUK3": "Stay home and do your thing. Good luck to you. There is going to be a small group of hungry savages out there that are going to run every one of you over while you sit home and cry and complain about how you didn't get yours. Stop blaming others for opportunities you didn't take.",
    "De_5NVvxkbB": "Ya estuvo cabrón, deja de pensar en ella wey. Duele un ratito, pero ya estuvo: es tiempo de ponerse las pinches pilas y enfocar toda esa energía en ti. Olvídate de andarte quejando. Es una bendición: ahora tienes tiempo para ti, fuera las distracciones. Si no supo valorarte, conviértete en tu mejor versión, invierte todo ese tiempo en ti, úsalo como gasolina y enfócate. ¡Vámonos con todo!",
    "DerRO-2xNnV": "Recuerda: para tu perro tú eres su mundo, no hay nadie en el mundo que te quiera más que él. Compórtate a la altura, sácalo a pasear y ejercítate tú también. Cumple con tus responsabilidades incluso cuando estés cansado, hazte cargo de los tuyos y dales una vida digna. Todo lo que vale la pena requiere mantenimiento y disciplina diaria.",
    "Det2fXpx6ve": "Go! Just fucking go! All the fear, all the overthinking, all the doubts will fucking disappear if you just fucking go! Let's fucking go!",
    "DewbggNRO33": "¡Despierta cabrón! ¿Me sigues o qué? ¿Por qué no sigues mis consejos wey? ¡Párate ya! ¡Deja de estar scrolleando a lo pendejo y ponte bien verga cabrón! ¡Vámonos!",
    "DezIIcwR1Ui": "10 reglas para siempre conseguir lo que quieres: 1) Dale gracias a Dios al despertarte y deja de quejarte. 2) Levántate a la primera cuando suene la alarma. 3) Báñate con agua fría, incomódate y gana esa primera batalla del día. 4) Gimnasio todos los días, movimiento y activa tu corazón. 5) Cero vicios, cero alcohol, cero cigarros, cero scrollear a lo pendejo; usa el tiempo a tu favor. 6) Haz lo más difícil al principio del día y el resto será papita. 7) Concéntrate en tu trabajo y apaga distracciones. 8) Cumple tu palabra: si dices que vas a concretar un plan, apúntalo y acción. 9) Aguanta la presión y controla tus emociones. 10) Cero quejas, cero excusas y póngase a trabajar cabrón. ¡Vámonos!",
    "DfCexDOxaFM": "Yo voy a ganar, no puedo perder, soy una verga. Declaro abundancia en mi vida, atraigo las mejores energías, abro las mejores puertas para mi vida y ayudo a millones de personas a transformar su vida. ¡Yo voy a ganar, no puedo perder!",
    "DUetnJRjAgW": "¡Enfócate cabrón, enfócate! Dijiste que este año era el tuyo, ya pasó un mes y no has hecho nada. Afuera hay morros de 15 años haciendo más feria que tú y tú sigues diciendo 'mañana lo hago, mañana lo hago'. ¡No cabrón, es hoy! No dejes que las excusas te controlen, ¡vámonos con todo ya!",
    "DUTMsFsER39": "Tienes 20 años y dices que estás cansado, que vas a empezar mañana... ¡No mames wey, póngase las pilas compadre! El tiempo se pasa volando en un abrir y cerrar de ojos y cuando menos acuerdes vas a tener 30 años. Ponte las pilas ya compadre y construye tu futuro hoy.",
    "DUV0bo1kVNA": "Compadres, no todo es gimnasio: el gym tiene su tiempo límite. Terminas tus dos horas de entrenamiento y se acabó el gimnasio; ¿qué sigue? Atender a la familia, a tus hijos y ponerte a trabajar duro. A dejar el celular y a generar billetes compadre, porque no solo de músculo se vive, también se necesita producir. ¡Vámonos cabrones!"
}


def build_complete_reels_catalog(username: str = "mrsergiogarza") -> list:
    ensure_dirs()

    # Limpiar audios anteriores en SOUNDS_DIR
    for old_file in SOUNDS_DIR.glob("*.*"):
        try:
            old_file.unlink()
        except Exception:
            pass

    media_files = sorted(
        list(RAW_REELS_DIR.glob("*.mp4"))
        + list(RAW_REELS_DIR.glob("*.mov"))
        + list(RAW_REELS_DIR.glob("*.m4a"))
        + list(RAW_REELS_DIR.glob("*.webm"))
    )

    catalog = []
    for idx, media_path in enumerate(media_files, start=1):
        stem = media_path.stem
        total_dur = get_audio_duration(media_path)
        print(f"\n[+] Procesando Reel Completo #{idx}: {media_path.name} ({total_dur:.1f}s)")

        # 1. Generar el AUDIO COMPLETO SIN CORTES (.caf)
        full_filename = f"reel_{idx:03d}_full.caf"
        full_output = SOUNDS_DIR / full_filename
        convert_to_ios_caf(media_path, full_output, start_sec=0.0, duration_sec=None)

        # 2. Generar las PARTES CONSECUTIVAS de 28s para encadenar en notificaciones iOS
        num_parts = max(1, int(math.ceil(total_dur / PART_DURATION_SECONDS)))
        audio_parts = []
        if num_parts == 1:
            # Si dura <= 28s, el archivo completo sirve directamente como parte única
            audio_parts.append(full_filename)
        else:
            for p in range(num_parts):
                start_t = p * PART_DURATION_SECONDS
                rem_t = min(PART_DURATION_SECONDS, max(1.0, total_dur - start_t))
                if rem_t < 0.8:
                    continue
                part_filename = f"reel_{idx:03d}_p{p + 1}.caf"
                part_output = SOUNDS_DIR / part_filename
                if convert_to_ios_caf(media_path, part_output, start_sec=start_t, duration_sec=rem_t):
                    audio_parts.append(part_filename)

        # 3. Obtener transcripción completa
        text = CURATED_FULL_TRANSCRIPTIONS.get(stem) or transcribe_full_reel(media_path)
        category = categorize_phrase(text)

        print(f"    -> Audio Completo: {full_filename} ({total_dur:.1f}s) | Partes Notificación: {len(audio_parts)} ({', '.join(audio_parts)})")

        catalog.append({
            "id": f"reel_{idx:03d}",
            "text": text,
            "author": f"@{username.lstrip('@')}",
            "category": category,
            "audioFile": full_filename,
            "audioParts": audio_parts,
            "durationSeconds": round(total_dur, 1),
            "sourceReel": stem
        })

    with open(PHRASES_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    print("\n" + "=" * 70)
    print(f"[OK] Catalogo de Reels COMPLETOS generado en: {PHRASES_JSON_PATH}")
    print(f"[OK] Total de Reels completos con audio entero: {len(catalog)}")
    print("=" * 70)
    return catalog


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--username", default="mrsergiogarza")
    args = parser.parse_args()
    build_complete_reels_catalog(args.username)


if __name__ == "__main__":
    main()
