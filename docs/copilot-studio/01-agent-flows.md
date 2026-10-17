# Agent flows de Modo Hawkeye (Copilot Studio)

Cuatro herramientas. Cada una responde al agente en **menos de 100 segundos** (límite de Copilot Studio).
Lo que tarda más (la aprobación humana) se ejecuta **después** de “Respond to the agent”.

| # | Tool | Qué hace | Tiempo típico |
|---|------|----------|---------------|
| 1 | `Hawkeye - Iniciar diagnóstico` | Dispara `hawkeye-diagnose.yml` y devuelve el ID | 2–5 s |
| 2 | `Hawkeye - Consultar diagnóstico` | Espera y lee el resultado publicado por GitHub Actions | 10–80 s |
| 3 | `Hawkeye - Solicitar corrección` | Dispara `hawkeye-remediate.yml` y pide aprobación en Teams | 3–5 s (+ aprobación en segundo plano) |
| 4 | `Hawkeye - Consultar corrección` | Lee el resultado de la corrección | 10–80 s |

> Crea los flows desde **Copilot Studio → tu agente → Tools → Add a tool → New tool → Agent flow**.
> Así vienen ya el trigger *When an agent calls the flow* y la acción *Respond to the agent*.
> En *Respond to the agent → Settings → Networking*, **Asynchronous response = Off**.

---

## 0. Valores comunes

### Token de GitHub
Para la demo, la vía más simple y comprobada: **classic PAT** con scope `repo`, expiración 7 días.
(Alternativa fine‑grained: repo `modo-hawkeye` con *Actions: RW*, *Contents: R*, *Deployments: RW*, *Environments: R*. Si la org exige aprobación de fine‑grained PATs, hazlo con tiempo.)

El dueño del token **debe ser reviewer** del environment `hawkeye-remediation` (el bootstrap te pone a ti).

En cada flow, primera acción:

**Initialize variable** → Name `GitHubPat` · Type `String` · Value: el token.
Luego, en *Settings* de cada acción HTTP que lo use: **Secure inputs = On** y **Secure outputs = On**.
(En producción: variable de entorno de tipo *Secret* respaldada por Azure Key Vault.)

### Headers de todas las llamadas HTTP

| Header | Valor |
|---|---|
| `Authorization` | `Bearer @{variables('GitHubPat')}` |
| `Accept` | `application/vnd.github+json` |
| `X-GitHub-Api-Version` | `2022-11-28` |
| `User-Agent` | `modo-hawkeye-agent` |

Base: `https://api.github.com/repos/CloudExpeditioners/modo-hawkeye`

> El conector **HTTP** es premium. Dentro de un agent flow de Copilot Studio corre sobre la capacidad/licencia de Copilot Studio; si lo armas como cloud flow normal de Power Automate necesitas licencia Premium.

---

## Tool 1 · Hawkeye - Iniciar diagnóstico

**Descripción de la tool (importante, el orquestador la lee):**
> Inicia un diagnóstico de drift de infraestructura en Azure ejecutando Terraform plan en GitHub Actions con una identidad de solo lectura. No modifica nada. Úsala cuando el usuario pida investigar cambios, desviaciones, drift o “quién tocó la infraestructura”. Devuelve un diagnosisId que se debe pasar a “Hawkeye - Consultar diagnóstico”.

**Trigger – inputs:**
| Nombre | Tipo | Descripción |
|---|---|---|
| `solicitante` | Text | Nombre de quien pide el diagnóstico |
| `motivo` | Text | Por qué se pide el diagnóstico, en una frase |

**Acciones:**

1. Initialize variable `GitHubPat` (ver arriba).
2. **Compose** → nombre `DiagnosisId`:
   ```
   concat('diag-', formatDateTime(utcNow(),'yyyyMMdd-HHmmss'), '-', substring(guid(), 0, 8))
   ```
3. **HTTP** → nombre `Disparar_diagnostico`
   - Method: `POST`
   - URI: `https://api.github.com/repos/CloudExpeditioners/modo-hawkeye/actions/workflows/hawkeye-diagnose.yml/dispatches`
   - Headers: los comunes
   - Body:
     ```json
     {
       "ref": "main",
       "inputs": {
         "correlation_id": "@{outputs('DiagnosisId')}",
         "requested_by": "@{triggerBody()?['text']}",
         "reason": "@{triggerBody()?['text_1']}",
         "lookback_hours": "6"
       }
     }
     ```
     > Si tus inputs tienen otros nombres internos, insértalos desde **contenido dinámico** (`solicitante`, `motivo`) en lugar de escribir `triggerBody()`.
   - Respuesta esperada: `204 No Content`.
4. **Respond to the agent** – outputs (Text):
   | Nombre | Valor |
   |---|---|
   | `diagnosisId` | `@{outputs('DiagnosisId')}` |
   | `estado` | `iniciado` |
   | `ejecuciones` | `https://github.com/CloudExpeditioners/modo-hawkeye/actions/workflows/hawkeye-diagnose.yml` |

---

## Tool 2 · Hawkeye - Consultar diagnóstico

**Descripción:**
> Obtiene el resultado de un diagnóstico iniciado con “Hawkeye - Iniciar diagnóstico”. Espera hasta ~75 segundos. Devuelve si hay drift, los cambios detectados (Azure vs Terraform), la evidencia de Azure Activity Log (quién hizo el cambio), el enlace a la ejecución en GitHub Actions, el incidente creado y la huella del plan. Si el estado es “en_progreso”, vuelve a llamarla con el mismo diagnosisId.

**Trigger – input:** `diagnosisId` (Text)

**Acciones:**

1. Initialize variable `GitHubPat`.
2. Initialize variable `Encontrado` · Boolean · `false`
3. Initialize variable `Intentos` · Integer · `0`
4. Initialize variable `Resultado` · String · vacío
5. **Do until** → condición (modo avanzado):
   ```
   @or(equals(variables('Encontrado'), true), greaterOrEquals(variables('Intentos'), 6))
   ```
   *Change limits*: Count `10`, Timeout `PT90S`.
   Dentro del loop:
   1. **HTTP** → nombre `Leer_resultado`
      - Method `GET`
      - URI: `https://api.github.com/repos/CloudExpeditioners/modo-hawkeye/contents/results/diagnosis/@{triggerBody()?['text']}.json?ref=hawkeye-results`
      - Headers comunes, pero **`Accept: application/vnd.github.raw+json`** (devuelve el JSON crudo)
   2. **Condition** → *Configure run after*: marcar **is successful** y **has failed**
      - Expresión: `@{outputs('Leer_resultado')?['statusCode']}` **is equal to** `200`
      - **True:**
        - Set variable `Resultado` = `@{string(body('Leer_resultado'))}`
        - Set variable `Encontrado` = `true`
      - **False:**
        - Delay `12` segundos
        - Increment variable `Intentos` en `1`
6. **Condition** `¿Encontrado?` → `variables('Encontrado')` is equal to `true`
   - **True:**
     - **Parse JSON** → Content: `@{json(variables('Resultado'))}` · Schema: pega el de `03-result-schemas.md` (diagnóstico)
     - **Respond to the agent** (outputs Text):
       | Nombre | Valor |
       |---|---|
       | `estado` | `status` |
       | `hayDrift` | `@{string(body('Parse_JSON')?['drift'])}` |
       | `resumen` | `summary` |
       | `cambios` | `changes_md` |
       | `evidencia` | `evidence_md` |
       | `fuenteEvidencia` | `evidence_source` |
       | `huella` | `@{substring(body('Parse_JSON')?['fingerprint'], 0, 16)}` |
       | `ejecucionUrl` | `run_url` |
       | `incidenteUrl` | `issue_url` |
       | `identidad` | `identity` |
   - **False:**
     - **Respond to the agent**: `estado` = `en_progreso`, `resumen` = `El diagnóstico sigue ejecutándose en GitHub Actions. Vuelve a consultar con el mismo diagnosisId.` (el resto vacío)

> ⚠️ Para que el loop no marque el flow como fallido por el 404, la acción final (*Condition ¿Encontrado?*) debe tener *Configure run after* = **is successful** y **has failed** respecto del *Do until*.
> Si `huella` falla porque viene vacía (error en el plan), usa `@{if(empty(body('Parse_JSON')?['fingerprint']), '', substring(body('Parse_JSON')?['fingerprint'], 0, 16))}`.

---

## Tool 3 · Hawkeye - Solicitar corrección

**Descripción:**
> Solicita corregir el drift de un diagnóstico ya realizado. NO aplica nada directamente: inicia un workflow que queda bloqueado hasta que un humano aprueba en Microsoft Teams. Requiere el diagnosisId y una justificación. Úsala solo cuando el usuario pida explícitamente corregir/remediar. Devuelve un remediationId para “Hawkeye - Consultar corrección”.

**Trigger – inputs:** `diagnosisId` (Text), `justificacion` (Text), `solicitante` (Text)

**Acciones:**

1. Initialize variable `GitHubPat`.
2. **HTTP** `Leer_diagnostico` → GET `.../contents/results/diagnosis/@{diagnosisId}.json?ref=hawkeye-results` con `Accept: application/vnd.github.raw+json`
3. **Parse JSON** `Diag` → Content `@{json(string(body('Leer_diagnostico')))}` · schema de diagnóstico
4. **Condition** `¿Hay drift?` → `body('Diag')?['drift']` is equal to `true`
   - **False:** Respond to the agent → `estado` = `sin_cambios`, `mensaje` = `Ese diagnóstico no tiene drift; no hay nada que corregir.`, `remediationId` vacío. (Termina.)
   - **True:** continúa:
5. **Compose** `RemediationId`:
   ```
   concat('fix-', formatDateTime(utcNow(),'yyyyMMdd-HHmmss'), '-', substring(guid(), 0, 8))
   ```
6. **HTTP** `Disparar_correccion` → POST `.../actions/workflows/hawkeye-remediate.yml/dispatches`
   ```json
   {
     "ref": "main",
     "inputs": {
       "remediation_id": "@{outputs('RemediationId')}",
       "diagnosis_id": "@{body('Diag')?['id']}",
       "requested_by": "@{triggerBody()?['solicitante']}",
       "justification": "@{triggerBody()?['justificacion']}"
     }
   }
   ```
   (inserta los inputs desde contenido dinámico)
7. **Respond to the agent** (outputs Text):
   | Nombre | Valor |
   |---|---|
   | `remediationId` | `@{outputs('RemediationId')}` |
   | `estado` | `esperando_aprobacion` |
   | `mensaje` | `Corrección solicitada. El workflow está bloqueado en el environment hawkeye-remediation hasta que un aprobador responda en Microsoft Teams.` |

   ⬇️ **Todo lo siguiente corre DESPUÉS de responder al agente** (sin límite de 100 s).

8. Initialize variable `RunId` · String · vacío
9. **Do until** `@not(empty(variables('RunId')))` · Count `30` · Timeout `PT10M`
   1. Delay `10` segundos
   2. **HTTP** `Listar_runs` → GET `.../actions/workflows/hawkeye-remediate.yml/runs?event=workflow_dispatch&status=waiting&per_page=20`
   3. **Filter array** `Run_de_esta_correccion` → From `@body('Listar_runs')?['workflow_runs']` · condición (avanzado):
      ```
      @contains(item()?['display_title'], outputs('RemediationId'))
      ```
   4. **Condition** `@greater(length(body('Run_de_esta_correccion')), 0)` → True: Set variable `RunId` = `@{first(body('Run_de_esta_correccion'))?['id']}`
10. **Start and wait for an approval** (conector *Approvals*, estándar)
    - Approval type: `Approve/Reject - First to respond`
    - Title: `🏹 Hawkeye: aprobar corrección de drift (@{outputs('RemediationId')})`
    - Assigned to: tu correo
    - Details (Markdown):
      ```
      **Solicitado por:** @{triggerBody()?['solicitante']}
      **Justificación:** @{triggerBody()?['justificacion']}
      **Diagnóstico:** @{body('Diag')?['id']}
      **Huella del plan:** @{substring(body('Diag')?['fingerprint'],0,16)}

      **Cambios que se aplicarán:**
      @{body('Diag')?['changes_md']}

      **Evidencia:**
      @{body('Diag')?['evidence_md']}
      ```
    - Item link: `https://github.com/CloudExpeditioners/modo-hawkeye/actions/runs/@{variables('RunId')}` · Item link description: `Ver ejecución en GitHub`
11. **Compose** `Decision`:
    ```
    if(equals(body('Start_and_wait_for_an_approval')?['outcome'], 'Approve'), 'approved', 'rejected')
    ```
12. **HTTP** `Resolver_environment` → POST `.../actions/runs/@{variables('RunId')}/pending_deployments`
    ```json
    {
      "environment_ids": [ ENV_ID_DEL_BOOTSTRAP ],
      "state": "@{outputs('Decision')}",
      "comment": "Decisión en Teams por @{first(body('Start_and_wait_for_an_approval')?['responses'])?['responder']?['displayName']}: @{first(body('Start_and_wait_for_an_approval')?['responses'])?['comments']}"
    }
    ```
    > `ENV_ID_DEL_BOOTSTRAP` es el número que imprime `scripts/bootstrap.sh` (sin comillas).
    > El aprobador real en GitHub es el dueño del token. La decisión humana se toma en Teams y **se ejecuta en la ruta de GitHub**: sin esa llamada, el job nunca obtiene el token OIDC de escritura.
13. (Opcional) **Post message in a chat or channel** (Teams) con el resultado de la decisión.

---

## Tool 4 · Hawkeye - Consultar corrección

**Descripción:**
> Obtiene el resultado de una corrección solicitada con “Hawkeye - Solicitar corrección”. Devuelve si fue aplicada y verificada, rechazada o bloqueada por control (huella distinta o política), quién aprobó y el enlace a la ejecución. Si el estado es “en_progreso”, la aprobación aún está pendiente o el workflow sigue corriendo.

**Trigger – input:** `remediationId` (Text)

Igual que la Tool 2, cambiando:
- URI: `.../contents/results/remediation/@{remediationId}.json?ref=hawkeye-results`
- Schema: el de corrección (`03-result-schemas.md`)
- Outputs del *Respond to the agent*:
  | Nombre | Valor |
  |---|---|
  | `estado` | `status` (remediated · blocked · rejected · nothing_to_do · failed) |
  | `resumen` | `summary` |
  | `cambios` | `changes_md` |
  | `verificado` | `@{string(body('Parse_JSON')?['verified'])}` |
  | `aprobadoPor` | `approved_by` |
  | `ejecucionUrl` | `run_url` |
  | `identidad` | `identity` |
- Mensaje si no se encontró: `La corrección está esperando aprobación en Teams o todavía se está ejecutando.`

---

## Checklist de prueba de cada tool (en el panel *Test* de Copilot Studio)

- [ ] Tool 1 devuelve `diagnosisId` y en GitHub aparece `Hawkeye diagnose · diag-…`
- [ ] Tool 2 devuelve `hayDrift = true` con cambios y evidencia
- [ ] En GitHub se abrió un issue `[Hawkeye] Drift detectado · diag-…`
- [ ] Tool 3 devuelve `remediationId` y en GitHub el run queda **Waiting** (environment)
- [ ] Llega la aprobación a Teams (app *Approvals*) y al aprobar el run continúa
- [ ] Tool 4 devuelve `remediated` y `verificado = true`; el issue se cierra solo
