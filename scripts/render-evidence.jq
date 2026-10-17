# Tabla Markdown con la evidencia de Azure Activity Log
if length == 0 then
  "_No se encontraron operaciones de escritura en la ventana consultada._"
else
  "| Hora (UTC) | Actor | Quién | Operación | Recurso |",
  "|---|---|---|---|---|",
  (.[] | "| " + (.time | tostring | .[0:19]) + " | "
        + (if .actor == "humano" then "👤 humano" else "🤖 automatización" end) + " | "
        + (.caller // "?") + " | `" + (.operation // "?") + "` | " + (.resource // "?") + " |")
end
