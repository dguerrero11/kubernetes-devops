# Queries de referencia — Etapa 8 MONITOR

## ⚠️ IMPORTANTE: Datasource correcto

| Tipo de consulta | Datasource en Grafana | Lenguaje |
|------------------|----------------------|----------|
| Métricas (pods, CPU, etc.) | **Prometheus** | PromQL |
| Logs (texto de contenedores) | **Loki** | LogQL |

---

## Prometheus (datasource: Prometheus)

### Estado de pods en el namespace de la demo
```promql
kube_pod_status_phase{namespace="devsecops-demo"}
```

### CPU usada por contenedores de la demo
```promql
rate(container_cpu_usage_seconds_total{namespace="devsecops-demo"}[5m])
```

### Pods en estado Running
```promql
kube_pod_status_phase{namespace="devsecops-demo", phase="Running"}
```

---

## Loki (datasource: Loki) — LogQL

### ✅ Query combinada (ambos namespaces con regex)
```logql
{namespace=~"devsecops-demo|falco"} |~ "error|Warning"
```
> Usa `=~` para regex en el stream selector, y `|~` para filtro de contenido

### ✅ Solo alertas Warning de Falco
```logql
{namespace="falco"} |= "Warning"
```

### ✅ Solo logs de la app
```logql
{namespace="devsecops-demo"}
```

### ✅ Filtrar logs de shell spawned (Falco)
```logql
{namespace="falco"} |= "shell was spawned"
```

### ❌ ERROR COMÚN — NO funciona en Loki
```
# INCORRECTO: Esta es PromQL, no LogQL
kube_pod_status_phase{namespace="devsecops-demo"}

# INCORRECTO: `or` no es sintaxis válida en LogQL
{namespace="devsecops-demo"} |= "error" or {namespace="falco"} |= "Warning"
```

---

## Resumen de errores comunes y sus fixes

| Error | Causa | Fix |
|-------|-------|-----|
| `unexpected IDENTIFIER` en Loki | Pegaste una query PromQL en datasource Loki | Cambiar datasource a **Prometheus** |
| `unexpected type for left leg of binary operation (or)` | Usar `or` entre pipelines LogQL | Usar regex `=~` en namespace selector |
| Alertas Falco no aparecen | Watching pod incorrecto (nodo equivocado) | Ver fix Stage 7 abajo |
| `namespace conflict` al aplicar YAML | El YAML tenía `namespace: default` hardcoded | Quitar `namespace:` del metadata del YAML |

---

## Fix Stage 7 — Falco pod correcto

Falco es un DaemonSet: hay 1 pod por nodo. Las alertas aparecen
en el pod del MISMO nodo donde corre el pod monitoreado.

```bash
# 1. Ver en qué nodo corre el webapp
kubectl get pod -n devsecops-demo -o wide

# 2. Identificar el pod de Falco en ese nodo (ej: worker02)
kubectl get pod -n falco -o wide | grep worker02

# 3. Ver logs de ESE pod específico
NODO="k8s-worker02"   # <-- ajustar al nodo real
FALCO_POD=$(kubectl get pod -n falco -o wide | grep $NODO | awk '{print $1}')
kubectl logs -n falco $FALCO_POD -f | grep -E "Warning|Notice|Error"
```
