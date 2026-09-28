#!/usr/bin/env python3
"""Small OpenAI-compatible Whisper service for the ai-lab VM.

The service intentionally exposes only the transcription endpoint needed by
Noted.  It keeps one large-v3 model resident in memory and serializes requests
because the ai-lab VM is a small CPU-only machine.
"""

from __future__ import annotations

import hmac
import json
import os
import tempfile
import threading
import time
from email import policy
from email.parser import BytesParser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from faster_whisper import WhisperModel


HOST = os.getenv("TRANSCRIBER_HOST", "0.0.0.0")
PORT = int(os.getenv("TRANSCRIBER_PORT", "8787"))
MODEL_NAME = os.getenv("WHISPER_MODEL", "large-v3")
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "int8")
DEVICE = os.getenv("WHISPER_DEVICE", "cpu")
CPU_THREADS = int(os.getenv("WHISPER_CPU_THREADS", "4"))
BEAM_SIZE = int(os.getenv("WHISPER_BEAM_SIZE", "5"))
MAX_UPLOAD_BYTES = int(os.getenv("TRANSCRIBER_MAX_MB", "256")) * 1024 * 1024
SERVICE_KEY = os.getenv("TRANSCRIBER_API_KEY", "").strip()


class TranscriberState:
    def __init__(self) -> None:
        if MODEL_NAME != "large-v3":
            raise RuntimeError(f"Whisper model is locked to large-v3, not {MODEL_NAME!r}")
        self.started_at = time.time()
        self.model = WhisperModel(
            MODEL_NAME,
            device=DEVICE,
            compute_type=COMPUTE_TYPE,
            cpu_threads=CPU_THREADS,
        )
        self.lock = threading.Lock()


STATE = TranscriberState()


def json_bytes(payload: dict[str, Any]) -> bytes:
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def segment_json(index: int, segment: Any, include_words: bool) -> dict[str, Any]:
    words: list[dict[str, Any]] = []
    if include_words:
        for word in getattr(segment, "words", None) or []:
            words.append(
                {
                    "word": word.word,
                    "start": word.start,
                    "end": word.end,
                    "probability": getattr(word, "probability", None),
                }
            )
    return {
        "id": index,
        "seek": getattr(segment, "seek", 0),
        "start": segment.start,
        "end": segment.end,
        "text": segment.text,
        "tokens": list(getattr(segment, "tokens", []) or []),
        "temperature": getattr(segment, "temperature", 0.0),
        "avg_logprob": getattr(segment, "avg_logprob", None),
        "compression_ratio": getattr(segment, "compression_ratio", None),
        "no_speech_prob": getattr(segment, "no_speech_prob", None),
        "words": words,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "NotedAiLabTranscriber/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.address_string()} - {format % args}", flush=True)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self) -> bool:
        if not SERVICE_KEY:
            return True
        received = self.headers.get("Authorization", "")
        expected = f"Bearer {SERVICE_KEY}"
        return hmac.compare_digest(received, expected)

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if urlparse(self.path).path in {"/health", "/v1/health"}:
            self.send_json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "ready": True,
                    "model": MODEL_NAME,
                    "device": DEVICE,
                    "compute_type": COMPUTE_TYPE,
                    "uptime_seconds": round(time.time() - STATE.started_at, 1),
                },
            )
            return
        self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})

    def read_form(self) -> tuple[dict[str, str], str, bytes] | None:
        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("multipart/form-data"):
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "multipart/form-data is required"})
            return None
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            content_length = 0
        if content_length <= 0 or content_length > MAX_UPLOAD_BYTES:
            self.send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Audio upload is too large or empty"})
            return None
        raw = self.rfile.read(content_length)
        envelope = (
            f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode("utf-8")
            + raw
        )
        message = BytesParser(policy=policy.default).parsebytes(envelope)
        fields: dict[str, str] = {}
        filename = "audio.bin"
        audio = b""
        for part in message.iter_parts():
            name = part.get_param("name", header="content-disposition")
            payload = part.get_payload(decode=True) or b""
            if part.get_filename() is not None:
                filename = Path(part.get_filename() or filename).name
                audio = payload
            elif name:
                fields[name] = payload.decode("utf-8", errors="replace")
        if not audio:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "A file field is required"})
            return None
        return fields, filename, audio

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        if urlparse(self.path).path != "/v1/audio/transcriptions":
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "Not found"})
            return
        if not self.authorized():
            self.send_json(HTTPStatus.UNAUTHORIZED, {"error": "Authentication required"})
            return
        form = self.read_form()
        if form is None:
            return
        fields, filename, audio = form
        requested_model = fields.get("model", MODEL_NAME)
        if requested_model != MODEL_NAME:
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": f"This service is locked to {MODEL_NAME}"})
            return
        response_format = fields.get("response_format", "verbose_json")
        include_words = "word" in fields.get("timestamp_granularities[]", "") or "word" in fields.get("timestamp_granularities", "")
        language = fields.get("language") or None
        suffix = Path(filename).suffix or ".audio"
        started = time.perf_counter()
        with tempfile.NamedTemporaryFile(prefix="noted-", suffix=suffix, delete=True) as temporary:
            temporary.write(audio)
            temporary.flush()
            try:
                with STATE.lock:
                    segments_iterator, info = STATE.model.transcribe(
                        temporary.name,
                        language=language,
                        beam_size=BEAM_SIZE,
                        vad_filter=True,
                        word_timestamps=include_words,
                    )
                    segments = [segment_json(index, segment, include_words) for index, segment in enumerate(segments_iterator)]
            except Exception as error:  # provider boundary: turn model errors into API errors
                self.send_json(HTTPStatus.UNPROCESSABLE_ENTITY, {"error": f"Transcription failed: {error}"})
                return
        text = " ".join(segment["text"].strip() for segment in segments if segment["text"].strip()).strip()
        elapsed = time.perf_counter() - started
        result = {
            "task": "transcribe",
            "language": getattr(info, "language", language),
            "duration": getattr(info, "duration", None),
            "text": text,
            "segments": segments,
            "processing_seconds": round(elapsed, 3),
        }
        if response_format == "text":
            body = text.encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_json(HTTPStatus.OK, result)


def main() -> None:
    print(
        f"Starting Noted ai-lab transcriber: model={MODEL_NAME} device={DEVICE} compute={COMPUTE_TYPE} port={PORT}",
        flush=True,
    )
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
