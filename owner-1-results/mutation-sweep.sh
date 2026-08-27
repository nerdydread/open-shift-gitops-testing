#!/bin/zsh
# TC-09 Step 3 (extended) — mutation sweep of the TT-17018 `enabled` escape hatch.
# For each render site that strips the synthetic `enabled` flag, re-introduce the
# original field leak (toYaml (omit $x "enabled") -> toYaml $x) one site at a time
# and record whether ANY unit test notices.
set -u
cd ~/playground/tt17018-owner1/tyk-charts-mutation || exit 1
OUT=~/playground/tt17018-owner1/evidence/tc09-mutation-sweep.txt
: > $OUT
SITES=$(grep -rn 'toYaml (omit \$[a-zA-Z]* "enabled")' components/*/templates/*.y*ml | cut -d: -f1,2)
CHARTS=(./components/tyk-bootstrap ./components/tyk-dashboard ./components/tyk-dev-portal ./components/tyk-pump ./tyk-control-plane ./tyk-stack)
for site in ${(f)SITES}; do
  file=${site%%:*}; line=${site##*:}
  var=$(sed -n "${line}p" $file | sed -E 's/.*omit (\$[a-zA-Z]+) "enabled".*/\1/')
  sed -i '' "${line}s/toYaml (omit ${var} \"enabled\")/toYaml ${var}/" $file
  helm dependency build ./tyk-stack >/dev/null 2>&1
  helm dependency build ./tyk-control-plane >/dev/null 2>&1
  res=$(helm unittest $CHARTS 2>&1)
  failed=$(echo "$res" | grep -E "^Tests:" | head -1)
  fails=$(echo "$res" | grep -E "^ FAIL" | sed 's/\t/ | /' | tr '\n' ';')
  if echo "$res" | grep -q "0 failed" || ! echo "$res" | grep -q "failed"; then
    verdict="NOT CAUGHT"
  else
    verdict="caught"
  fi
  printf '%-70s %-10s %s\n' "$file:$line ($var)" "$verdict" "$failed" >> $OUT
  [ -n "$fails" ] && echo "        $fails" >> $OUT
  git checkout -- $file
done
helm dependency build ./tyk-stack >/dev/null 2>&1
helm dependency build ./tyk-control-plane >/dev/null 2>&1
echo DONE >> $OUT
