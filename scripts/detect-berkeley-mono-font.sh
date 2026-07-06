#!/usr/bin/env bash
set -euo pipefail

font_name_from_path() {
  local font_path="$1"
  local filename="${font_path##*/}"
  local name="${filename%.*}"
  local suffix
  local -a style_suffixes=(
    "-Bold-Oblique"
    "-Bold Oblique"
    "-BoldItalic"
    "-Bold Italic"
    "-SemiBold"
    "-Semibold"
    "-DemiBold"
    "-Medium"
    "-Regular"
    "-Roman"
    "-Book"
    "-Bold"
    "-Italic"
    "-Oblique"
    " Bold Oblique"
    " BoldItalic"
    " Bold Italic"
    " SemiBold"
    " Semibold"
    " DemiBold"
    " Medium"
    " Regular"
    " Roman"
    " Book"
    " Bold"
    " Italic"
    " Oblique"
    "_Bold_Oblique"
    "_BoldItalic"
    "_Bold_Italic"
    "_SemiBold"
    "_Semibold"
    "_DemiBold"
    "_Medium"
    "_Regular"
    "_Roman"
    "_Book"
    "_Bold"
    "_Italic"
    "_Oblique"
  )

  for suffix in "${style_suffixes[@]}"; do
    case "$name" in
      *"$suffix")
        name="${name%"$suffix"}"
        break
        ;;
    esac
  done

  case "$name" in
    "" | *\"* | *\\* | *$'\n'* | *$'\r'*)
      return 1
      ;;
  esac

  printf '%s\n' "$name"
}

detect_berkeley_mono_font() {
  local font_dir
  local font_path
  local -a font_dirs=("$@")
  local -a font_patterns=(
    "*Berkeley*Mono*Regular*.otf"
    "*Berkeley*Mono*Regular*.ttf"
    "*Berkeley*Mono*.otf"
    "*Berkeley*Mono*.ttf"
  )
  local pattern

  if [ "${#font_dirs[@]}" -eq 0 ]; then
    font_dirs=(
      "$HOME/Library/Fonts"
      "/Library/Fonts"
      "/System/Library/Fonts"
      "/System/Library/Fonts/Supplemental"
    )
  fi

  shopt -s nullglob nocaseglob

  for font_dir in "${font_dirs[@]}"; do
    [ -d "$font_dir" ] || continue

    for pattern in "${font_patterns[@]}"; do
      for font_path in "$font_dir"/$pattern; do
        [ -f "$font_path" ] || continue
        font_name_from_path "$font_path"
        return 0
      done
    done
  done

  return 1
}

detect_berkeley_mono_font "$@"
