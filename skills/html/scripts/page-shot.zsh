#!/bin/zsh
# page-shot.zsh: screenshot a local HTML file at an EXACT viewport width with headless Chrome.
# usage: page-shot.zsh <abs-html> <abs-out.png> <width> <height> <auto|dark|attr-light|attr-dark> [anchor-id]
#   auto       = the system colour scheme
#   dark       = --force-dark-mode (prefers-color-scheme: dark)
#   attr-light / attr-dark = a copy of the page with <html data-theme="light|dark"> (the page must support it;
#                this is the only way to get LIGHT on a Mac that runs in dark mode)
# Why an iframe: a headless Chrome window is never narrower than 500px, so --window-size=390 does NOT give a
# phone layout. An iframe of the exact width does. The script also prints scrollWidth and clientWidth:
# scrollWidth > clientWidth = horizontal page scroll.
# Work files go to <out-dir>/.page-shot (nothing is deleted).
set -e
html=$1; out=$2; w=$3; h=$4; mode=$5; anchor=${6:-}
C="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="${out:h}/.page-shot"; mkdir -p "$work"
case $mode in
  attr-light|attr-dark)
    t=${mode#attr-}; copy="$work/page-$t.html"
    sed "s/<html\([^>]*\)>/<html\1 data-theme=\"$t\">/" "$html" > "$copy"; html=$copy ;;
esac
src="file://$html"; [[ -n "$anchor" ]] && src="$src#$anchor"
wrap="$work/wrap.html"
print -r -- "<!doctype html><meta charset=utf-8><style>:root{color-scheme:light dark}html,body{margin:0;background:#808080}iframe{border:0;display:block;width:${w}px;height:${h}px;margin:0 auto}</style><iframe id=f src=\"$src\"></iframe><pre id=o></pre><script>onload=function(){try{var d=document.getElementById('f').contentDocument.documentElement;document.getElementById('o').textContent='SCROLLW='+d.scrollWidth+' CLIENTW='+d.clientWidth+' DOCH='+d.scrollHeight}catch(e){document.getElementById('o').textContent='ERR '+e}}</script>" > "$wrap"
ww=$w; (( ww < 500 )) && ww=500
flags=(--headless=new --disable-gpu --hide-scrollbars --disable-web-security --allow-file-access-from-files --user-data-dir="$work/profile" --virtual-time-budget=4000 --window-size=${ww},${h})
[[ $mode == dark ]] && flags+=(--force-dark-mode)
"$C" $flags --screenshot="$out" "file://$wrap" >/dev/null 2>&1
"$C" $flags --dump-dom "file://$wrap" 2>/dev/null | grep -o 'SCROLLW=[^<]*\|ERR [^<]*' | head -1
(( w < ww )) && sips -c $h $w "$out" >/dev/null 2>&1   # centre crop = the iframe
print -r -- "saved $out"
