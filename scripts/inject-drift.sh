#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Modo Hawkeye · Simula el "cambio manual del viernes a las 6 pm"
# Ejecútalo en Cloud Shell CON TU USUARIO (no con la app), para que la evidencia
# en Activity Log muestre a un humano como Caller.
#
# ⏱️ Hazlo 15–20 minutos ANTES de la demo: la ingesta de Activity Log en
#    Log Analytics puede tardar. (Hawkeye cae a la API de Activity Log si aún no llegó.)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
RG="${RG:-rg-modo-hawkeye-demo}"
WS="${WS:-law-modo-hawkeye-demo}"
MODE="${1:-full}"   # full | tags | retention | extra

echo "👤 Ejecutando como: $(az account show --query user.name -o tsv)"

if [ "$MODE" = "full" ] || [ "$MODE" = "tags" ]; then
  az group update -n "$RG" --set tags.cambio_manual="hotfix-viernes-6pm" -o none
  echo "  ✔ Etiqueta no declarada agregada a $RG (cambio_manual=hotfix-viernes-6pm)"
fi

if [ "$MODE" = "full" ] || [ "$MODE" = "retention" ]; then
  az monitor log-analytics workspace update -g "$RG" -n "$WS" --retention-time 90 -o none
  echo "  ✔ Retención de $WS cambiada a 90 días (Terraform declara 30 → impacto FinOps)"
fi

if [ "$MODE" = "extra" ]; then
  # Para la demo de bloqueo: un SEGUNDO cambio mientras la corrección espera aprobación.
  az group update -n "$RG" --set tags.segundo_cambio="$(date -u +%H%M%S)" -o none
  echo "  ✔ Segundo cambio aplicado: la huella del plan ya no coincidirá con la aprobada"
fi

echo
echo "🎯 Drift inyectado a las $(date -u +%H:%M) UTC. Espera ~15 min antes de pedirle a Hawkeye que investigue."
