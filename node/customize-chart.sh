#!/bin/bash
set -euo pipefail
CHART_FILE="$1"
DELTA="$2"
CHART_NAME="$(basename "$CHART_FILE")"
CHART_NAME="${CHART_NAME%.*}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TAR_FILE="$WORK/chart.tar"
# every server applies its own copy to the same HelmChart: any byte difference makes servers
# overwrite each other and trigger a helm upgrade, so no timestamps in tar or gzip headers
TAR_OPTS="--owner=0 --group=0 --mode=gou-s+r --numeric-owner --no-acls --no-selinux --no-xattrs --mtime=@0"
FILE="$WORK/values.yaml"
echo "Customizing $CHART_FILE with $DELTA"
yq -r .spec.chartContent "$CHART_FILE" | base64 -d | gunzip - > "$TAR_FILE"
tar -xOf "$TAR_FILE" "$CHART_NAME/values.yaml" > "$FILE"
yq -i e '. *= load("'$DELTA'")' "$FILE"
tar --delete -b 8192 -f "$TAR_FILE" "$CHART_NAME/values.yaml"
tar --transform="s|.*|$CHART_NAME/values.yaml|" $TAR_OPTS -vrf "$TAR_FILE" "$FILE"
gzip -9 -n -c "$TAR_FILE" | base64 -w 0 > "$TAR_FILE.b64"
yq -i e '.spec.chartContent = load_str("'$TAR_FILE'.b64")' "$CHART_FILE"
