"""Motor do Meety: transcrição (mlx-whisper) e resumo (mlx-lm) na GPU do Mac.

Roda no Python embutido no app. Fala com o Swift por JSON Lines no stdout: uma linha por evento,
sempre com a chave "event". Tudo que não for JSON (avisos de bibliotecas) vai para o stderr.

Comandos:
  health
      {"event":"health","python":"3.12.x","mlx":"0.32.4","metal":true}
  transcribe --audio <pcm.f32> --model <pasta> [--language pt] [--word-timestamps]
      O áudio é PCM float32 little-endian, mono, 16 kHz, cru (sem cabeçalho), já decodificado
      pelo AVFoundation. Eventos: stage, progress (percent 0..100), result.
  summarize --model <pasta> --prompt-file <txt> [--max-tokens 1500] [--system-file <txt>]
      Eventos: stage, token (texto parcial), result (texto completo).
  serve [--idle 600]
      Processo que fica vivo para o ditado, com o Whisper já carregado entre um pedido e outro.
      Lê um pedido JSON por linha no stdin: {"id":"…","audio":"<pcm.f32>","model":"<pasta>","language":"pt"}
      (ou {"id":"…","model":"<pasta>","warm":true}, que só carrega o modelo)
      e responde {"event":"result","id":"…","text":"…"} ou {"event":"error","id":"…","message":"…"}.
      Sai sozinho depois de --idle segundos sem pedidos (o modelo deixa a memória) ou quando o stdin fecha.

Qualquer falha termina com {"event":"error","message":"..."} e código 1.
"""
import argparse
import json
import os
import sys
import time
import traceback

# Depois do download, o motor nunca fala com a internet: os modelos chegam por caminho local.
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

OUT = sys.stdout


def emit(event, **data):
    data["event"] = event
    OUT.write(json.dumps(data, ensure_ascii=False) + "\n")
    OUT.flush()


def fail(message, code=1):
    emit("error", message=str(message))
    sys.exit(code)


# ---------------------------------------------------------------- health

def cmd_health(_):
    import platform
    info = {"python": platform.python_version()}
    try:
        import mlx.core as mx
        info["mlx"] = mx.__version__
        info["metal"] = bool(mx.metal.is_available())
        if info["metal"]:
            d = mx.device_info()
            info["device"] = d.get("device_name")
            info["memory"] = int(d.get("memory_size", 0))
    except Exception as e:  # noqa: BLE001
        info["mlx"] = None
        info["metal"] = False
        info["mlx_error"] = str(e)
    emit("health", **info)


# ---------------------------------------------------------------- transcribe

def cmd_transcribe(a):
    import numpy as np

    emit("stage", stage="loading")
    import importlib
    import mlx_whisper
    import tqdm as _tqdm

    audio = np.fromfile(a.audio, dtype=np.float32)
    if audio.size == 0:
        fail("Áudio vazio.")
    duration = audio.size / 16000.0
    emit("info", duration=duration)

    # O mlx_whisper mostra progresso com tqdm (em frames de 16 kHz); trocamos a barra por eventos.
    _t = importlib.import_module("mlx_whisper.transcribe")
    last = {"p": -1, "t": 0.0}

    class _Progress(_tqdm.tqdm):
        def __init__(self, *args, **kw):
            kw["file"] = open(os.devnull, "w")
            kw["disable"] = False
            super().__init__(*args, **kw)

        def update(self, n=1):
            r = super().update(n)
            if self.total:
                p = min(100.0, 100.0 * self.n / self.total)
                now = time.time()
                if int(p) != last["p"] or now - last["t"] > 2:
                    last["p"] = int(p)
                    last["t"] = now
                    emit("progress", percent=round(p, 1), seconds=round(duration * p / 100, 1))
            return r

    _t.tqdm.tqdm = _Progress

    emit("stage", stage="transcribing")
    t0 = time.time()
    result = mlx_whisper.transcribe(
        audio,
        path_or_hf_repo=a.model,
        language=a.language or None,
        task="transcribe",
        word_timestamps=bool(a.word_timestamps),
        # Sem condicionar no texto anterior: evita os laços de repetição em reuniões longas.
        condition_on_previous_text=False,
        verbose=None,
    )
    segments = []
    for s in result.get("segments", []):
        text = (s.get("text") or "").strip()
        if not text:
            continue
        seg = {"start": round(float(s["start"]), 3), "end": round(float(s["end"]), 3), "text": text}
        if a.word_timestamps and s.get("words"):
            seg["words"] = [
                {"start": round(float(w["start"]), 3), "end": round(float(w["end"]), 3), "word": w["word"]}
                for w in s["words"]
            ]
        segments.append(seg)
    emit("result", language=result.get("language") or a.language, segments=segments,
         elapsed=round(time.time() - t0, 1), duration=round(duration, 1))


# ---------------------------------------------------------------- summarize

def cmd_summarize(a):
    emit("stage", stage="loading")
    from mlx_lm import load, stream_generate

    model, tokenizer = load(a.model)
    with open(a.prompt_file, encoding="utf-8") as f:
        user = f.read()
    messages = []
    if a.system_file:
        with open(a.system_file, encoding="utf-8") as f:
            messages.append({"role": "system", "content": f.read()})
    messages.append({"role": "user", "content": user})
    kw = {}
    # Modelos com "modo pensar" (Qwen3 e afins): resposta direta, sem o raciocínio.
    try:
        prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True, enable_thinking=False)
    except TypeError:
        prompt = tokenizer.apply_chat_template(messages, add_generation_prompt=True)

    emit("stage", stage="generating")
    t0 = time.time()
    pieces = []
    for r in stream_generate(model, tokenizer, prompt, max_tokens=a.max_tokens, **kw):
        pieces.append(r.text)
        emit("token", text=r.text)
    text = "".join(pieces).strip()
    emit("result", text=text, elapsed=round(time.time() - t0, 1))


# ---------------------------------------------------------------- serve

def cmd_serve(a):
    import select
    import numpy as np
    import mlx_whisper  # o mlx_whisper guarda o último modelo carregado (ModelHolder)

    emit("ready")
    while True:
        ready, _, _ = select.select([sys.stdin], [], [], a.idle)
        if not ready:
            return  # ocioso: sai e devolve a memória
        line = sys.stdin.readline()
        if not line:
            return  # o app fechou o stdin
        try:
            req = json.loads(line)
        except ValueError:
            continue
        rid = req.get("id")
        try:
            if req.get("warm"):  # carrega o modelo enquanto a pessoa ainda fala
                import mlx.core as mx
                from mlx_whisper.transcribe import ModelHolder
                ModelHolder.get_model(req["model"], mx.float16)
                emit("result", id=rid, text="")
                continue
            audio = np.fromfile(req["audio"], dtype=np.float32)
            if audio.size == 0:
                raise ValueError("Áudio vazio.")
            t0 = time.time()
            result = mlx_whisper.transcribe(
                audio,
                path_or_hf_repo=req["model"],
                language=req.get("language") or None,
                task="transcribe",
                condition_on_previous_text=False,
                verbose=None,
            )
            text = " ".join((s.get("text") or "").strip() for s in result.get("segments", [])).strip()
            emit("result", id=rid, text=text, language=result.get("language"), elapsed=round(time.time() - t0, 2))
        except Exception as e:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            emit("error", id=rid, message=f"{type(e).__name__}: {e}")


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(prog="meety_engine")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("health")
    t = sub.add_parser("transcribe")
    t.add_argument("--audio", required=True)
    t.add_argument("--model", required=True)
    t.add_argument("--language", default=None)
    t.add_argument("--word-timestamps", action="store_true")
    s = sub.add_parser("summarize")
    s.add_argument("--model", required=True)
    s.add_argument("--prompt-file", required=True)
    s.add_argument("--system-file", default=None)
    s.add_argument("--max-tokens", type=int, default=1500)
    v = sub.add_parser("serve")
    v.add_argument("--idle", type=float, default=600)
    a = ap.parse_args()
    try:
        {"health": cmd_health, "transcribe": cmd_transcribe, "summarize": cmd_summarize, "serve": cmd_serve}[a.cmd](a)
    except SystemExit:
        raise
    except KeyboardInterrupt:
        fail("Cancelado.", 130)
    except Exception as e:  # noqa: BLE001
        traceback.print_exc(file=sys.stderr)
        fail(f"{type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
