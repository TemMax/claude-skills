#!/usr/bin/env bash
# Tier 1 — structure. Cheap, offline, and the only tier that must never fail:
# everything here breaks the plugin outright rather than degrading it.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh

section "Manifests parse"
for f in .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json; do
  check "valid JSON: $f" "python3 -c 'import json;json.load(open(\"$f\"))'"
done
for f in plugins/*/hooks/hooks.json; do
  [ -e "$f" ] || continue
  check "valid JSON: $f" "python3 -c 'import json;json.load(open(\"$f\"))'"
done

section "Skill frontmatter parses and is complete"
for f in plugins/*/skills/*/SKILL.md; do
  out="$(ruby -ryaml -e '
    s = File.read(ARGV[0])
    fm = s[/\A---\n(.*?)\n---\n/m, 1] or (puts "NO-FRONTMATTER"; exit)
    d = YAML.safe_load(fm)
    miss = %w[name description].reject { |k| d[k].to_s.strip != "" }
    miss << "metadata.version" unless d.dig("metadata", "version").to_s =~ /\A\d+\.\d+\.\d+\z/
    puts(miss.empty? ? "OK #{d["name"]} #{d.dig("metadata","version")}" : "MISSING #{miss.join(",")}")
  ' "$f" 2>/dev/null | grep -v '^Ignoring')"
  case "$out" in
    OK*) pass "frontmatter: $(basename "$(dirname "$f")") $(echo "$out" | cut -d' ' -f3)" ;;
    *)   fail "frontmatter: $f" "$out" ;;
  esac
done

section "Skill version matches its plugin version"
for p in plugins/*/; do
  pv="$(python3 -c "import json;print(json.load(open('$p.claude-plugin/plugin.json'))['version'])" 2>/dev/null)"
  for f in "$p"skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    sv="$(sed -n 's/^  version: \(.*\)/\1/p' "$f" | head -1)"
    expect "version agrees: $(basename "$p") $pv" "$pv" "$sv"
  done
done

section "Executables are executable"
for f in plugins/*/hooks/*; do
  case "$f" in *.json) continue;; esac
  [ -f "$f" ] || continue
  check "executable: $(basename "$f")" "[ -x '$f' ]"
  check "shell syntax: $(basename "$f")" "bash -n '$f'"
done

section "Repository-wide prohibitions"
# Bracketed on purpose: this file must not contain the names it forbids.
check "no third-party reference implementation is named" \
  "! grep -riq '[k]ent\|[r]espawn' --exclude-dir=.git --exclude-dir=tests ."
check "no absolute home path leaked into a shipped file" \
  "! grep -rq '/Users/[a-z]' plugins/"

summary
