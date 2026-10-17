# Convierte `terraform show -json tfplan` en un resumen SEGURO para publicar.
# El repo es público: nunca se exponen valores de atributos fuera de la lista blanca
# (por ejemplo, las shared keys del workspace viajan dentro del plan).
# "azure"     = valor real que hay hoy en Azure
# "terraform" = valor declarado en el código (lo que se aplicaría)

def safe_attrs: [
  "retention_in_days", "sku", "location", "name", "daily_quota_gb",
  "internet_ingestion_enabled", "internet_query_enabled",
  "local_authentication_enabled"
];

[ (.resource_changes // [])[]
  | select(.change.actions != ["no-op"] and .change.actions != ["read"])
  | . as $rc
  | ($rc.change.before // {}) as $b
  | ($rc.change.after // {}) as $a
  | (if ($rc.change.after_unknown | type) == "object" then $rc.change.after_unknown else {} end) as $u
  | {
      address: $rc.address,
      type: $rc.type,
      actions: $rc.change.actions,
      changes: [
        ((($b | keys) + ($a | keys)) | unique)[] as $k
        | select($u[$k] != true)
        | select($b[$k] != $a[$k])
        | if $k == "tags" then
            ($b.tags // {}) as $bt
            | ($a.tags // {}) as $at
            | ((($bt | keys) + ($at | keys)) | unique)[] as $t
            | select($bt[$t] != $at[$t])
            | {attribute: ("tags." + $t), azure: $bt[$t], terraform: $at[$t]}
          elif (safe_attrs | index($k)) != null then
            {attribute: $k, azure: $b[$k], terraform: $a[$k]}
          else
            {attribute: $k, azure: "(oculto)", terraform: "(oculto)"}
          end
      ]
    }
]
