#!/usr/bin/env bash
# Uso: collect-evidence.sh <resource_group> <workspace_name> <lookback_hours> <out.json>
# Busca QUIÉN cambió algo en el Resource Group. Primero en Log Analytics (KQL sobre AzureActivity);
# si la ingesta aún no llegó (puede tardar varios minutos), cae a la API del Activity Log.
# Imprime la fuente usada: log_analytics | activity_log_api | none
set -uo pipefail

RG="$1"; WS="$2"; HOURS="$3"; OUT="$4"
TMP="$(mktemp -d)"
echo '[]' > "$OUT"
SOURCE="none"

az config set extension.use_dynamic_install=yes_without_prompt >/dev/null 2>&1 || true

WS_ID="$(az monitor log-analytics workspace show -g "$RG" -n "$WS" --query customerId -o tsv 2>/dev/null || true)"

if [ -n "$WS_ID" ]; then
  KQL="AzureActivity
| where TimeGenerated > ago(${HOURS}h)
| where ResourceGroup =~ '${RG}'
| where ActivityStatusValue =~ 'Success'
| where OperationNameValue endswith '/WRITE' or OperationNameValue endswith '/DELETE'
| project TimeGenerated, Caller, OperationNameValue, ResourceId
| order by TimeGenerated desc
| take 10"
  if az monitor log-analytics query -w "$WS_ID" --analytics-query "$KQL" -o json > "$TMP/la.json" 2>"$TMP/la.err"; then
    jq '[.[] | {time: .TimeGenerated, caller: .Caller, operation: .OperationNameValue,
               resource: ((.ResourceId // "") | split("/") | last),
               actor: (if ((.Caller // "") | test("@")) then "humano" else "automatizacion" end)}]' \
      "$TMP/la.json" > "$OUT" 2>/dev/null || echo '[]' > "$OUT"
    [ "$(jq 'length' "$OUT")" -gt 0 ] && SOURCE="log_analytics"
  else
    echo "Aviso: consulta KQL falló: $(head -c 300 "$TMP/la.err")" >&2
  fi
fi

if [ "$(jq 'length' "$OUT")" -eq 0 ]; then
  if az monitor activity-log list -g "$RG" --offset "${HOURS}h" -o json > "$TMP/al.json" 2>/dev/null; then
    jq '[.[]
         | select((.status.value // "") == "Succeeded")
         | select((.operationName.value // "") | test("/(write|delete)$"; "i"))
         | {time: .eventTimestamp, caller: .caller, operation: .operationName.value,
            resource: ((.resourceId // "") | split("/") | last),
            actor: (if ((.caller // "") | test("@")) then "humano" else "automatizacion" end)}
        ] | .[:10]' "$TMP/al.json" > "$OUT" 2>/dev/null || echo '[]' > "$OUT"
    [ "$(jq 'length' "$OUT")" -gt 0 ] && SOURCE="activity_log_api"
  fi
fi

echo "$SOURCE"
