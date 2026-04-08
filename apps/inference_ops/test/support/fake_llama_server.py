import argparse
import json
import os
import signal
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


STATE_DIR = os.environ.get("LLAMA_CPP_SDK_FAKE_STATE_DIR")
MODE = os.environ.get("LLAMA_CPP_SDK_FAKE_MODE", "ready")


def state_path(name: str) -> str:
    return os.path.join(STATE_DIR, name)


def read_health() -> str:
    try:
        with open(state_path("health.txt"), "r", encoding="utf-8") as file:
            return file.read().strip() or "healthy"
    except FileNotFoundError:
        return "healthy"


class Handler(BaseHTTPRequestHandler):
    server_version = "FakeLlamaServer/1.0"

    def do_GET(self):
        health_path = "/health"
        prefixed_health_path = f"{self.server.api_prefix}/health" if self.server.api_prefix else "/health"
        models_path = f"{self.server.api_prefix}/v1/models"

        if self.path in {health_path, prefixed_health_path}:
            health = read_health()

            if health == "unavailable":
                self.send_response(503)
            else:
                self.send_response(200)

            self.send_header("content-type", "text/plain")
            self.end_headers()
            self.wfile.write(health.encode("utf-8"))
            return

        if self.path == models_path:
            payload = {
                "data": [
                    {
                        "id": self.server.model_alias,
                        "object": "model",
                    }
                ]
            }

            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(payload).encode("utf-8"))
            return

        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        completions_path = f"{self.server.api_prefix}/v1/chat/completions"

        if self.path != completions_path:
            self.send_response(404)
            self.end_headers()
            return

        if self.server.api_key:
            authorization = self.headers.get("authorization")

            if authorization != f"Bearer {self.server.api_key}":
                self.send_response(401)
                self.send_header("content-type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"error": {"message": "unauthorized"}}).encode("utf-8"))
                return

        content_length = int(self.headers.get("content-length", "0"))
        raw_body = self.rfile.read(content_length)
        payload = json.loads(raw_body or b"{}")
        response_text = build_completion_text(payload)
        model = payload.get("model") or self.server.model_alias
        prompt_tokens = max(1, len(response_text.split()))
        completion_tokens = max(1, len(response_text.split()))

        if payload.get("stream"):
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.send_header("cache-control", "no-cache")
            self.end_headers()

            for chunk in streaming_chunks(model, response_text):
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode("utf-8"))
                self.wfile.flush()
                time.sleep(0.01)

            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            return

        completion = {
            "id": "chatcmpl_fake_llama_123",
            "object": "chat.completion",
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "finish_reason": "stop",
                    "message": {
                        "role": "assistant",
                        "content": response_text,
                    },
                }
            ],
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": prompt_tokens + completion_tokens,
            },
        }

        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(completion).encode("utf-8"))

    def log_message(self, format, *args):
        return


def extract_text(value):
    if isinstance(value, str):
        return value

    if isinstance(value, list):
        parts = []

        for item in value:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text", ""))

        return "".join(parts)

    return ""


def build_completion_text(payload):
    messages = payload.get("messages") or []
    last_user_text = ""

    for message in reversed(messages):
        if isinstance(message, dict) and message.get("role") == "user":
            last_user_text = extract_text(message.get("content"))

            if last_user_text:
                break

    if not last_user_text:
        last_user_text = "ready"

    return f"Fake llama response: {last_user_text}"


def streaming_chunks(model, response_text):
    parts = split_text(response_text)

    for index, part in enumerate(parts):
        delta = {"content": part}

        if index == 0:
            delta["role"] = "assistant"

        yield {
            "id": "chatcmpl_fake_llama_stream_123",
            "object": "chat.completion.chunk",
            "model": model,
            "choices": [
                {
                    "index": 0,
                    "delta": delta,
                    "finish_reason": None,
                }
            ],
        }

    yield {
        "id": "chatcmpl_fake_llama_stream_123",
        "object": "chat.completion.chunk",
        "model": model,
        "choices": [
            {
                "index": 0,
                "delta": {},
                "finish_reason": "stop",
            }
        ],
        "usage": {
            "prompt_tokens": max(1, len(response_text.split())),
            "completion_tokens": max(1, len(response_text.split())),
            "total_tokens": max(2, len(response_text.split()) * 2),
        },
    }


def split_text(value):
    if not value:
        return [""]

    midpoint = max(1, len(value) // 2)
    return [value[:midpoint], value[midpoint:]]


def write_args(args, extras):
    payload = {
        "model": args.model,
        "alias": args.alias,
        "host": args.host,
        "port": args.port,
        "ctx_size": args.ctx_size,
        "gpu_layers": args.gpu_layers,
        "threads": args.threads,
        "threads_batch": args.threads_batch,
        "parallel": args.parallel,
        "flash_attn": args.flash_attn,
        "embedding": args.embedding,
        "api_key": args.api_key,
        "api_key_file": args.api_key_file,
        "api_prefix": args.api_prefix,
        "timeout": args.timeout,
        "threads_http": args.threads_http,
        "pooling": args.pooling,
        "extras": extras,
    }

    with open(state_path("args.json"), "w", encoding="utf-8") as file:
        json.dump(payload, file, indent=2, sort_keys=True)


def install_signal_handlers(server):
    def handle_signal(signum, _frame):
        with open(state_path("signal.txt"), "w", encoding="utf-8") as file:
            file.write(signal.Signals(signum).name + " interrupt_then_force_close")

        server.shutdown()
        raise SystemExit(0)

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)


def main():
    if not STATE_DIR:
        raise SystemExit("LLAMA_CPP_SDK_FAKE_STATE_DIR is required")

    os.makedirs(STATE_DIR, exist_ok=True)

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--model", required=True)
    parser.add_argument("--alias", required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--ctx-size", dest="ctx_size", type=int)
    parser.add_argument("--gpu-layers", dest="gpu_layers")
    parser.add_argument("--threads", type=int)
    parser.add_argument("--threads-batch", dest="threads_batch", type=int)
    parser.add_argument("--parallel", type=int)
    parser.add_argument("--flash-attn", dest="flash_attn")
    parser.add_argument("--embedding", action="store_true")
    parser.add_argument("--api-key", dest="api_key")
    parser.add_argument("--api-key-file", dest="api_key_file")
    parser.add_argument("--api-prefix", dest="api_prefix", default="")
    parser.add_argument("--timeout", type=int)
    parser.add_argument("--threads-http", dest="threads_http", type=int)
    parser.add_argument("--pooling")

    args, extras = parser.parse_known_args()
    write_args(args, extras)

    if MODE == "exit_before_ready":
        sys.stderr.write("fatal: fixture exiting before readiness\n")
        sys.stderr.flush()
        raise SystemExit(17)

    if MODE == "never_ready":
        while True:
            time.sleep(1)

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.api_prefix = args.api_prefix
    server.model_alias = args.alias
    server.api_key = args.api_key

    install_signal_handlers(server)

    print(f"listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
