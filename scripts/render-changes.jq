# Renderiza el resumen de cambios como Markdown legible (para el agente, el issue y el job summary).
def show:
  if . == null then "(no existe)"
  elif . == "(oculto)" then "(oculto)"
  elif type == "string" then "\"" + . + "\""
  else tojson end;

def verb:
  if . == ["update"] then "actualizar"
  elif . == ["create"] then "crear"
  elif . == ["delete"] then "ELIMINAR"
  elif (index("delete") != null) then "REEMPLAZAR"
  else join("+") end;

if length == 0 then
  "Sin diferencias: Azure coincide con lo declarado en Terraform."
else
  .[]
  | ("- **" + .address + "** → " + (.actions | verb)),
    (.changes[] | "  - `" + .attribute + "`: en Azure " + (.azure | show) + " · en Terraform " + (.terraform | show))
end
