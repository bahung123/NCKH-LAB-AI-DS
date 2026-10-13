#!/usr/bin/env bash
# build.sh — biên dịch báo cáo sáng kiến.
# Ưu tiên xelatex (TeX Live/Overleaf-local); nếu không có, dùng Tectonic.
set -euo pipefail
TECTONIC="${TECTONIC:-$(command -v tectonic || true)}"

if command -v xelatex >/dev/null 2>&1; then
  xelatex -interaction=nonstopmode main.tex
  bibtex main || true
  xelatex -interaction=nonstopmode main.tex
  xelatex -interaction=nonstopmode main.tex
elif [ -n "$TECTONIC" ] && [ -x "$TECTONIC" ]; then
  "$TECTONIC" -X compile main.tex
else
  echo "Cần cài TeX Live (xelatex) hoặc đặt biến TECTONIC trỏ tới tectonic." >&2
  exit 1
fi
echo "OK -> main.pdf"
