#!/usr/bin/env python3
"""Local sequence-frame viewer. Python standard library only; no Maker dependency."""
import argparse
import hashlib
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit
from urllib.request import urlopen
import webbrowser

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
ASSETS = PROJECT / "assets"
IDENTITY = hashlib.sha256(str(PROJECT).encode()).hexdigest()[:16]
LABELS = {
    "worker": "红细胞", "neutrophil": "中性粒白细胞", "bone_marrow_nest": "骨髓造血巢", "oxygen_relay": "氧气中转站",
    "walk": "空载行走", "move": "移动", "oxygen": "携氧行走",
    "glucose": "携糖行走", "build": "建造 / 维修", "hit": "受击",
    "death": "死亡", "shoot": "瞄准射击", "projectileFlight": "颗粒弹飞行", "idle": "待机呼吸",
}


def catalog():
    """Use character manifests so superseded generated variants stay out of the list."""
    entries, seen = [], set()
    for manifest in sorted((ASSETS / "image").glob("*/animations.json")):
        try:
            data = json.loads(manifest.read_text())
            group = LABELS.get(data.get("character"), data.get("displayName") or manifest.parent.name)
            for key, reference in data.items():
                if not isinstance(reference, str) or not reference.endswith(".json"):
                    continue
                if key == "idle" and any(other != "idle" and value == reference for other, value in data.items()):
                    continue
                path = (manifest.parent / reference).resolve()
                if not path.is_relative_to(ASSETS.resolve()) or not path.is_file() or path in seen:
                    continue
                seen.add(path)
                entries.append({"group": group, "name": LABELS.get(key, key),
                                "url": "/assets/" + path.relative_to(ASSETS).as_posix()})
        except (OSError, ValueError, TypeError):
            continue
    return entries


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        self._serve()

    def do_HEAD(self):
        self._serve(head=True)

    def _serve(self, head=False):
        path = unquote(urlsplit(self.path).path)
        if path == "/api/catalog":
            payload = json.dumps({"application": "cell-war-sequence-preview", "project": IDENTITY,
                                  "entries": catalog()}, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            if not head:
                self.wfile.write(payload)
            return
        if path.startswith("/assets/"):
            target = (ASSETS / path[len("/assets/"):]).resolve()
            allowed = target.is_relative_to(ASSETS.resolve())
        else:
            target = (HERE / (path.lstrip("/") or "index.html")).resolve()
            allowed = target.parent == HERE and target.name in {"index.html", "preview.js", "preview.css"}
        if not allowed or not target.is_file():
            self.send_error(404)
            return
        self._target = target
        if head:
            super().do_HEAD()
        else:
            super().do_GET()

    def translate_path(self, path):
        return str(self._target)

    def end_headers(self):
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true", help="Open in your default browser")
    args = parser.parse_args()
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), partial(Handler, directory=str(HERE)))
    except OSError as error:
        if args.open:
            try:
                with urlopen(f"http://127.0.0.1:{args.port}/api/catalog", timeout=2) as response:
                    existing = json.load(response)
                if existing.get("application") == "cell-war-sequence-preview" and existing.get("project") == IDENTITY:
                    webbrowser.open(f"http://127.0.0.1:{args.port}/")
                    print("Opened the existing sequence preview.")
                    return
            except (OSError, ValueError):
                pass
        parser.exit(1, f"Cannot start local viewer: {error}. Try --port 8766.\n")
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"Sequence preview: {url}\nCtrl+C to stop. Files are read-only; imports stay in your browser.", flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
