#!/usr/bin/env python3
"""把 web/ 打包成单文件 HTML：双击即玩（单机），零依赖、零服务器。"""
import base64
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEB = ROOT
OUT = ROOT.parent / "监利红中-网页版.html"

TILE_NAMES = (
    [f"Man{i}" for i in range(1, 10)]
    + [f"Pin{i}" for i in range(1, 10)]
    + [f"Sou{i}" for i in range(1, 10)]
    + ["Chun"]
)

def main():
    # 牌面已内联在 js/tileArt.js，无需替换占位
    patched_tiles = None

    # 用临时目录做一份带内联图表的 src，再交给 esbuild
    tmp = Path(tempfile.mkdtemp(prefix="jianli-build-"))
    shutil.copytree(WEB / "js", tmp / "js")

    out_js = tmp / "app.js"
    cmd = [
        "npx", "--yes", "esbuild",
        str(tmp / "js" / "game.js"),
        "--bundle", "--format=iife", "--minify",
        f"--outfile={out_js}",
    ]
    res = subprocess.run(cmd, cwd=WEB, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout, res.stderr)
        raise SystemExit("esbuild 打包失败")
    bundle = out_js.read_text(encoding="utf-8")

    css = (WEB / "css" / "table.css").read_text(encoding="utf-8")
    html = (WEB / "index.html").read_text(encoding="utf-8")
    html = html.replace('<link rel="stylesheet" href="css/table.css">', f"<style>\n{css}\n</style>")
    vendor = (WEB / "js" / "vendor" / "peerjs.min.js").read_text(encoding="utf-8")
    html = html.replace('<script src="js/vendor/peerjs.min.js"></script>', f"<script>\n{vendor}\n</script>")
    html = html.replace('<script type="module" src="js/game.js"></script>', f"<script>\n{bundle}\n</script>")
    html = re.sub(r'\s*<link rel="icon" href="data:,">', "", html)

    OUT.write_text(html, encoding="utf-8")
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"OK -> {OUT} ({OUT.stat().st_size/1024/1024:.2f} MB)")

if __name__ == "__main__":
    main()
