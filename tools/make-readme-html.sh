#!/bin/bash
# tools/make-readme-html.sh
#
# Turns README.md into macOS/Solid Copy Read Me.html: the Read Me that
# Help > Solid Copy Help opens (it's copied into the app, as everything
# in macOS/ is) and that release.sh puts beside the app in the download.
#
# Why HTML: in Safari, VoiceOver can move by heading (VO-Command-H) and
# by link, which a plain .md file doesn't give you.
#
# Why GitHub renders it (gh api markdown): it's the same renderer as the
# repo's own page, so the Read Me matches what people see there, and no
# Markdown tool needs installing. It needs gh signed in and the internet;
# README.md is public anyway. The result is committed, so building the
# app never needs either.
#
# Run it after changing README.md (release.sh runs it too):
#   bash tools/make-readme-html.sh [path to README.md]
# With no path it uses this folder's README.md. release.sh passes the
# public repo's, which has no personal details in it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="macOS/Solid Copy Read Me.html"
REPO="https://github.com/Scott-H5/solid-copy"
SOURCE="${1:-README.md}"
[ -f "$SOURCE" ] || { echo "No README at $SOURCE." >&2; exit 1; }

# "markdown" mode, not "gfm": gfm turns each line break into <br>, which
# breaks every paragraph into short lines.
BODY="$(gh api markdown -f mode=markdown -f text="$(cat "$SOURCE")")"
[ -n "$BODY" ] || { echo "GitHub didn't render $SOURCE. Is gh signed in (gh auth status)?" >&2; exit 1; }

# Tidy what GitHub sends, with perl (part of macOS):
#   - drop its custom table wrapper, which only GitHub's page understands
#   - make each heading plain, with the id GitHub's page gives it, so
#     links such as (#automatic-uploads) work here too. GitHub adds a
#     "Permalink" link after every heading, which VoiceOver would read
#     each time; it's dropped.
#   - point links to other repo files (docs/...) at GitHub, since only
#     the Read Me travels with the app
BODY="$(perl -0pe '
  s{</?markdown-accessiblity-table>}{}g;
  s{ dir="auto"}{}g;
  s{<div class="markdown-heading"><(h[1-6]) class="heading-element">(.*?)</\1><a id="user-content-([^"]*)".*?</a></div>}{<$1 id="$3">$2</$1>}g;
  s{href="(?!https?:|#|mailto:)([^"]+)"}{href="'"$REPO"'/blob/main/$1"}g;
' <<<"$BODY")"

cat > "$OUT" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Solid Copy Read Me</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 17px/1.5 -apple-system, system-ui, sans-serif; max-width: 46em; margin: 0 auto; padding: 1em 16px 4em; }
  code, pre { font-family: ui-monospace, Menlo, monospace; font-size: 0.9em; }
  pre { overflow-x: auto; padding: 0.75em; border: 1px solid #8884; border-radius: 6px; }
  table { border-collapse: collapse; }
  th, td { border: 1px solid #8886; padding: 0.3em 0.6em; text-align: left; vertical-align: top; }
</style>
</head>
<body>
<p>The latest version of this Read Me, and every download, are at
<a href="$REPO">$REPO</a>.</p>
$BODY
</body>
</html>
HTML
echo "Wrote $OUT"
