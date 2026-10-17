#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Modo Hawkeye · Bootstrap de identidades y gobernanza
# Ejecutar en Azure Cloud Shell (bash) con:  az login  +  gh auth login
#
# Qué hace (idempotente, se puede re-ejecutar):
#  1. Crea la identidad de SOLO LECTURA  gha-modo-hawkeye-reader  (diagnóstico)
#  2. Crea el rol custom "Hawkeye Drift Reader" acotado al RG del laboratorio
#  3. Re-acota la identidad de ESCRITURA gha-modo-hawkeye: Contributor solo en el RG
#     y federación OIDC SOLO para el environment hawkeye-remediation
#  4. Crea el environment de GitHub con aprobación obligatoria (required reviewers)
#  5. Configura secrets y labels del repo
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GH_OWNER="${GH_OWNER:-CloudExpeditioners}"
GH_REPO="${GH_REPO:-modo-hawkeye}"
RG="${RG:-rg-modo-hawkeye-demo}"
STATE_RG="${STATE_RG:-rg-hawkeye-tfstate}"
STATE_SA="${STATE_SA:-sthawkeyetfstate2026}"
EXEC_APP_NAME="${EXEC_APP_NAME:-gha-modo-hawkeye}"
READER_APP_NAME="${READER_APP_NAME:-gha-modo-hawkeye-reader}"
ENV_NAME="hawkeye-remediation"
ROLE_NAME="Hawkeye Drift Reader"
# Pon SUBSCRIPTION_SCOPE_CLEANUP=true para quitar el Contributor a nivel suscripción del executor
SUBSCRIPTION_SCOPE_CLEANUP="${SUBSCRIPTION_SCOPE_CLEANUP:-true}"

REPO_FULL="$GH_OWNER/$GH_REPO"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

say() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
ok()  { printf '  \033[1;32m✔\033[0m %s\n' "$*"; }

command -v az >/dev/null || { echo "Falta Azure CLI"; exit 1; }
command -v gh >/dev/null || { echo "Falta GitHub CLI (gh). En Cloud Shell ya viene instalado."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Ejecuta primero: gh auth login"; exit 1; }

SUB_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
RG_ID="$(az group show -n "$RG" --query id -o tsv)"
SA_ID="$(az storage account show -g "$STATE_RG" -n "$STATE_SA" --query id -o tsv)"
ok "Suscripción: $SUB_ID"
ok "RG laboratorio: $RG_ID"

ensure_app() {
  local name="$1" app_id
  app_id="$(az ad app list --display-name "$name" --query "[0].appId" -o tsv)"
  if [ -z "$app_id" ]; then
    app_id="$(az ad app create --display-name "$name" --query appId -o tsv)"
  fi
  az ad sp show --id "$app_id" >/dev/null 2>&1 || az ad sp create --id "$app_id" >/dev/null
  echo "$app_id"
}

ensure_fic() {
  local app_id="$1" name="$2" subject="$3"
  if az ad app federated-credential list --id "$app_id" --query "[?subject=='$subject'] | length(@)" -o tsv | grep -q '^0$'; then
    az ad app federated-credential create --id "$app_id" --parameters "{
      \"name\": \"$name\", \"issuer\": \"$ISSUER\", \"subject\": \"$subject\",
      \"audiences\": [\"$AUDIENCE\"], \"description\": \"Modo Hawkeye\" }" >/dev/null
  fi
  ok "Federación: $subject"
}

ensure_role_assignment() {
  local assignee="$1" role="$2" scope="$3" i
  for i in 1 2 3 4 5 6; do
    if [ "$(az role assignment list --assignee "$assignee" --role "$role" --scope "$scope" --query 'length(@)' -o tsv 2>/dev/null)" != "0" ]; then
      ok "Rol '$role' ya asignado en $(basename "$scope")"; return 0
    fi
    if az role assignment create --assignee-object-id "$(az ad sp show --id "$assignee" --query id -o tsv)" \
         --assignee-principal-type ServicePrincipal --role "$role" --scope "$scope" >/dev/null 2>&1; then
      ok "Rol '$role' asignado en $(basename "$scope")"; return 0
    fi
    echo "  … esperando propagación (intento $i)"; sleep 15
  done
  echo "No se pudo asignar $role"; return 1
}

# ── 1. Identidad de solo lectura ────────────────────────────────────────────
say "1/5 Identidad de diagnóstico (solo lectura): $READER_APP_NAME"
READER_APP_ID="$(ensure_app "$READER_APP_NAME")"
ok "appId: $READER_APP_ID"
ensure_fic "$READER_APP_ID" "github-main" "repo:$REPO_FULL:ref:refs/heads/main"

# ── 2. Rol custom ───────────────────────────────────────────────────────────
say "2/5 Rol custom: $ROLE_NAME"
if [ -z "$(az role definition list --name "$ROLE_NAME" --custom-role-only true --query '[0].id' -o tsv)" ]; then
  cat > /tmp/hawkeye-role.json <<JSON
{
  "Name": "$ROLE_NAME",
  "IsCustom": true,
  "Description": "Modo Hawkeye: lectura de recursos y consultas de Log Analytics para detectar drift. Sin escritura.",
  "Actions": [
    "*/read",
    "Microsoft.OperationalInsights/workspaces/sharedKeys/action",
    "Microsoft.OperationalInsights/workspaces/search/action"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": ["$RG_ID"]
}
JSON
  az role definition create --role-definition @/tmp/hawkeye-role.json >/dev/null
  ok "Rol creado (puede tardar ~1 min en propagarse)"
else
  ok "Rol ya existe"
fi
ensure_role_assignment "$READER_APP_ID" "$ROLE_NAME" "$RG_ID"
ensure_role_assignment "$READER_APP_ID" "Storage Blob Data Reader" "$SA_ID"

# ── 3. Identidad de escritura ───────────────────────────────────────────────
say "3/5 Identidad de corrección (escritura): $EXEC_APP_NAME"
EXEC_APP_ID="$(az ad app list --display-name "$EXEC_APP_NAME" --query "[0].appId" -o tsv)"
[ -n "$EXEC_APP_ID" ] || { echo "No encontré la app $EXEC_APP_NAME"; exit 1; }
ok "appId: $EXEC_APP_ID"
ensure_fic "$EXEC_APP_ID" "github-env-remediation" "repo:$REPO_FULL:environment:$ENV_NAME"

# Quitar la federación por rama main: la escritura SOLO desde el environment aprobado
for fic in $(az ad app federated-credential list --id "$EXEC_APP_ID" \
               --query "[?subject=='repo:$REPO_FULL:ref:refs/heads/main'].id" -o tsv); do
  az ad app federated-credential delete --id "$EXEC_APP_ID" --federated-credential-id "$fic" >/dev/null
  ok "Eliminada federación por rama main del executor"
done

ensure_role_assignment "$EXEC_APP_ID" "Contributor" "$RG_ID"
ensure_role_assignment "$EXEC_APP_ID" "Storage Blob Data Contributor" "$SA_ID"

if [ "$SUBSCRIPTION_SCOPE_CLEANUP" = "true" ]; then
  EXEC_OID="$(az ad sp show --id "$EXEC_APP_ID" --query id -o tsv)"
  for ra in $(az role assignment list --assignee "$EXEC_OID" --scope "/subscriptions/$SUB_ID" \
                --query "[?roleDefinitionName=='Contributor' && scope=='/subscriptions/$SUB_ID'].id" -o tsv); do
    az role assignment delete --ids "$ra" >/dev/null
    ok "Quitado Contributor a nivel suscripción (mínimo privilegio)"
  done
fi

# ── 4. Environment de GitHub con aprobación ─────────────────────────────────
say "4/5 Environment GitHub: $ENV_NAME (aprobación obligatoria)"
GH_USER_ID="$(gh api user --jq .id)"
GH_USER_LOGIN="$(gh api user --jq .login)"
gh api -X PUT "repos/$REPO_FULL/environments/$ENV_NAME" --input - >/dev/null <<JSON
{
  "reviewers": [{ "type": "User", "id": $GH_USER_ID }],
  "prevent_self_review": false,
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
gh api -X POST "repos/$REPO_FULL/environments/$ENV_NAME/deployment-branch-policies" \
  -f name=main -f type=branch >/dev/null 2>&1 || true
ok "Reviewer: $GH_USER_LOGIN · solo rama main"
ENV_ID="$(gh api "repos/$REPO_FULL/environments/$ENV_NAME" --jq .id)"
ok "environment_id: $ENV_ID  (lo usarás en Power Automate)"

# ── 5. Secrets y labels ─────────────────────────────────────────────────────
say "5/5 Secrets y labels del repositorio"
gh secret set AZURE_READER_CLIENT_ID -R "$REPO_FULL" -b "$READER_APP_ID"
gh secret set AZURE_CLIENT_ID        -R "$REPO_FULL" -b "$EXEC_APP_ID"
gh secret set AZURE_TENANT_ID        -R "$REPO_FULL" -b "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID  -R "$REPO_FULL" -b "$SUB_ID"
gh label create hawkeye -R "$REPO_FULL" --color 7B2FF7 --description "Modo Hawkeye" --force >/dev/null
gh label create drift   -R "$REPO_FULL" --color D93F0B --description "Configuration drift" --force >/dev/null
ok "Secrets: AZURE_READER_CLIENT_ID, AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID"

cat <<SUMMARY

────────────────────────────────────────────────────────────
 ✅ Bootstrap completo

 Diagnóstico  → $READER_APP_NAME ($READER_APP_ID)
                Rol "$ROLE_NAME" en $RG · Blob Data Reader en estado
                OIDC: repo:$REPO_FULL:ref:refs/heads/main

 Corrección   → $EXEC_APP_NAME ($EXEC_APP_ID)
                Contributor SOLO en $RG
                OIDC: repo:$REPO_FULL:environment:$ENV_NAME (requiere aprobación)

 Para Power Automate anota:
   GitHub environment_id = $ENV_ID
   Reviewer               = $GH_USER_LOGIN
────────────────────────────────────────────────────────────
SUMMARY
