# LogQL — Queries de Referencia

LogQL es el lenguaje de consulta de Loki. Similar a PromQL pero para logs.

## Anatomía de un query LogQL

```
{selector} | filter | parser | aggregation
    ▲            ▲        ▲          ▲
  Obligatorio  Opcional Opcional  Opcional
```

---

## 1. Log Stream Selectors (obligatorio)

Seleccionan qué streams de logs consultar usando labels:

```logql
# Por namespace
{namespace="monitoring"}

# Por nombre de pod (exacto)
{pod="loki-0"}

# Por nombre de pod (regex)
{pod=~"loki.*"}

# Por app
{app="demo-logger"}

# Por nodo
{node="k8s-worker01"}

# Combinar labels (AND implícito)
{namespace="monitoring", app="demo-logger"}

# Por job (sistema)
{job="systemd-journal"}

# Por unidad systemd
{unit="kubelet.service"}
```

---

## 2. Filtros de Línea

Aplicados después del selector, filtran las líneas de log:

```logql
# Contiene el texto (case-sensitive)
{namespace="monitoring"} |= "error"

# No contiene
{namespace="monitoring"} != "health"

# Regex: contiene error o warning
{namespace="monitoring"} |~ "error|warn|Error|Warning"

# Regex negativo: excluir líneas de debug
{namespace="monitoring"} !~ "DEBUG|debug"

# Encadenar filtros
{namespace="monitoring"} |= "ERROR" != "test" |~ "timeout|refused"
```

---

## 3. Parsers de Formato

Extraen campos del contenido del log para poder filtrar por ellos:

### JSON parser
```logql
# App demo-logger genera JSON: {"level":"ERROR","message":"..."}
{app="demo-logger"} | json

# Filtrar por campo extraído
{app="demo-logger"} | json | level="ERROR"

# Mostrar solo el campo message
{app="demo-logger"} | json | line_format "{{.level}}: {{.message}}"
```

### Logfmt parser
```logql
# Logs formato: key=value key2=value2
{namespace="monitoring"} | logfmt

# Filtrar por campo
{namespace="monitoring"} | logfmt | status="500"
```

### Regex parser
```logql
# Extraer campos con regex nombrados
{app="demo-logger"}
  | regexp `(?P<method>\w+) (?P<path>/\S*) HTTP/[\d.]+ (?P<status>\d+)`

# Filtrar por campo extraído
{app="demo-logger"}
  | regexp `(?P<method>\w+) (?P<path>/\S*) HTTP/[\d.]+ (?P<status>\d+)`
  | status="404"
```

---

## 4. Queries con Métricas (Metric Queries)

Convierten logs en métricas para graficar en Grafana:

```logql
# Tasa de logs por segundo en los últimos 5 minutos
rate({namespace="monitoring"}[5m])

# Tasa de errores por minuto
rate({namespace="monitoring"} |= "error" [1m])

# Contar líneas en una ventana de tiempo
count_over_time({app="demo-logger"}[5m])

# Suma por pod
sum by (pod) (
  count_over_time({namespace="monitoring"}[5m])
)

# Tasa de errores agrupados por app
sum by (app) (
  rate({namespace="monitoring"} | json | level="ERROR" [5m])
)

# Top 5 pods con más logs de error
topk(5,
  sum by (pod) (
    count_over_time({namespace="monitoring"} |= "error" [10m])
  )
)

# Porcentaje de errores vs total
(
  sum(rate({app="demo-logger"} | json | level="ERROR" [5m]))
  /
  sum(rate({app="demo-logger"}[5m]))
) * 100

# Bytes por segundo ingestados
bytes_rate({namespace="monitoring"}[5m])
```

---

## 5. Ejemplos Prácticos para la Demo

### Ver logs de la app demo en tiempo real
```logql
{app="demo-logger", container="log-generator"}
```

### Solo errores críticos
```logql
{app="demo-logger"} | json | level="ERROR"
```

### Logs de Kubernetes system
```logql
{namespace="kube-system"}
```

### Ver qué pasó en el cluster hace 1 hora
```logql
{namespace=~"monitoring|kube-system"} |= "error"
```

### Logs del kubelet (systemd)
```logql
{unit="kubelet.service"} |= "error"
```

### Dashboard de errores por app (para panel de Grafana)
```logql
sum by (app) (
  count_over_time(
    {namespace="monitoring"} | json | level="ERROR" [5m]
  )
)
```

### Alertar cuando hay más de 10 errores por minuto
```logql
sum(rate({namespace="monitoring"} | json | level="ERROR" [1m])) > 10
```

---

## 6. Comandos CLI útiles

```bash
# Consultar Loki desde dentro del cluster
kubectl run logcli --rm -it --image=grafana/logcli:2.9.6 --restart=Never -- \
  --addr=http://loki.monitoring.svc.cluster.local:3100 \
  query '{namespace="monitoring"}' --limit 10

# Ver labels disponibles
kubectl run logcli --rm -it --image=grafana/logcli:2.9.6 --restart=Never -- \
  --addr=http://loki.monitoring.svc.cluster.local:3100 \
  labels

# Ver valores de un label específico
kubectl run logcli --rm -it --image=grafana/logcli:2.9.6 --restart=Never -- \
  --addr=http://loki.monitoring.svc.cluster.local:3100 \
  labels namespace
```

---

## 7. Comparativa PromQL vs LogQL

| Concepto | PromQL (Prometheus) | LogQL (Loki) |
|----------|---------------------|--------------|
| Selector | `{job="app"}` | `{app="demo"}` |
| Filtro texto | No aplica | `\|= "error"` |
| Parser | No aplica | `\| json` |
| Rate | `rate(metric[5m])` | `rate({label}[5m])` |
| Sum by | `sum by (label)` | `sum by (label)` |
| Top K | `topk(5, ...)` | `topk(5, ...)` |
