#!/usr/bin/env bash
# build.sh — biên dịch báo cáo, tự cài đủ môi trường khi gặp máy mới.
#
# Trình tự:
#   1. Có xelatex (TeX Live)            -> dùng xelatex + bibtex như truyền thống.
#   2. Có tectonic (hoặc biến TECTONIC) -> dùng tectonic.
#   3. Không có gì                      -> tự tải Tectonic (nhị phân tĩnh, không cần sudo)
#                                          về ~/.local/bin, tự kiểm tra/cài font DejaVu
#                                          nếu máy thiếu, rồi build.
# Lưu ý: lần chạy đầu cần Internet — Tectonic tự tải các gói TeX cần dùng vào
#        ~/.cache/Tectonic; các lần build sau không cần mạng.
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
LOCAL_FONTS="$HOME/.local/share/fonts"
TECTONIC="${TECTONIC:-}"

download() { # download <url> <tệp-đích>
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    return 1
  fi
}

# Bảo đảm có công cụ tải (curl hoặc wget); Debian/Ubuntu: thử tự cài curl.
ensure_downloader() {
  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "Thiếu curl/wget — thử cài curl qua apt-get (cần quyền)..." >&2
    if sudo -n apt-get update -qq && sudo -n apt-get install -y -qq curl ca-certificates; then
      return 0
    fi
  fi
  echo "Không có công cụ tải xuống. Hãy cài curl (hoặc wget) rồi chạy lại ./build.sh" >&2
  exit 1
}

# Cài Tectonic (nhị phân tĩnh) vào ~/.local/bin — không cần sudo.
ensure_tectonic() {
  if [ -x "$LOCAL_BIN/tectonic" ]; then
    TECTONIC="$LOCAL_BIN/tectonic"
    return 0
  fi
  echo "Không tìm thấy xelatex/tectonic — tự tải Tectonic về $LOCAL_BIN ..." >&2
  ensure_downloader
  local tmp arch suffix url
  tmp="$(mktemp -d)"
  arch="$(uname -m)"
  case "$arch" in
    x86_64)  suffix="x86_64-unknown-linux-musl" ;;
    aarch64|arm64) suffix="aarch64-unknown-linux-gnu" ;;
    *) echo "Kiến trúc không hỗ trợ tự cài: $arch. Tải thủ công từ https://github.com/tectonic-typesetting/tectonic/releases" >&2; exit 1 ;;
  esac
  download "https://api.github.com/repos/tectonic-typesetting/tectonic/releases/latest" "$tmp/rel.json" \
    || { echo "Không truy vấn được bản phát hành Tectonic (kiểm tra mạng)." >&2; exit 1; }
  url="$(grep -o "\"browser_download_url\": *\"[^\"]*$suffix\.tar\.gz\"" "$tmp/rel.json" \
          | head -1 | grep -o 'https://[^"]*')" || true
  [ -n "$url" ] || { echo "Không tìm thấy gói Tectonic cho $arch. Tải thủ công: https://github.com/tectonic-typesetting/tectonic/releases" >&2; exit 1; }
  download "$url" "$tmp/t.tar.gz"
  tar -xzf "$tmp/t.tar.gz" -C "$tmp"
  mkdir -p "$LOCAL_BIN"
  install -m 0755 "$tmp/tectonic" "$LOCAL_BIN/tectonic"
  rm -rf "$tmp"
  TECTONIC="$LOCAL_BIN/tectonic"
  echo "Đã cài Tectonic vào $LOCAL_BIN." >&2
}

# Kiểm tra font DejaVu; thiếu thì tải về ~/.local/share/fonts (không cần sudo).
ensure_dejavu() {
  if command -v fc-list >/dev/null 2>&1 && fc-list 2>/dev/null | grep -qi "DejaVu Serif"; then
    return 0
  fi
  echo "Thiếu font DejaVu — tải về $LOCAL_FONTS ..." >&2
  ensure_downloader
  local tmp zip dir
  tmp="$(mktemp -d)"
  zip="$tmp/dejavu.zip"
  download "https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip" "$zip" \
    || { echo "Không tải được font DejaVu. Hãy cài: sudo apt install fonts-dejavu rồi chạy lại." >&2; exit 1; }
  dir="$tmp/e"
  mkdir -p "$LOCAL_FONTS/dejavu"
  if command -v unzip >/dev/null 2>&1; then
    unzip -oq "$zip" -d "$dir"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m zipfile -e "$zip" "$dir"
  else
    echo "Không có unzip/python3 để giải nén font. Hãy cài: sudo apt install fonts-dejavu" >&2
    exit 1
  fi
  cp "$dir"/dejavu-fonts-ttf-2.37/ttf/*.ttf "$LOCAL_FONTS/dejavu/" 2>/dev/null || true
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$LOCAL_FONTS" >/dev/null 2>&1 || true
  rm -rf "$tmp"
  echo "Đã cài font DejaVu." >&2
}

if command -v xelatex >/dev/null 2>&1; then
  xelatex -interaction=nonstopmode main.tex
  bibtex main || true
  xelatex -interaction=nonstopmode main.tex
  xelatex -interaction=nonstopmode main.tex
else
  if [ -z "$TECTONIC" ] || [ ! -x "$TECTONIC" ]; then
    if command -v tectonic >/dev/null 2>&1; then
      TECTONIC="$(command -v tectonic)"
    else
      ensure_tectonic
    fi
  fi
  case ":$PATH:" in
    *":$LOCAL_BIN:"*) ;;
    *) export PATH="$LOCAL_BIN:$PATH" ;;
  esac
  ensure_dejavu
  "$TECTONIC" -X compile main.tex
fi
echo "OK -> main.pdf"
