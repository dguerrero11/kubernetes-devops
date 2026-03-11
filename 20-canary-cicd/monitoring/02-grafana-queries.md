# Queries para Grafana — Canary Deployment Dashboard

## Cómo importar el dashboard en Grafana
```
Grafana → http://192.168.109.200:30093
→ Dashboards → New → New Dashboard
→ Add visualization (para cada panel)
```

---

## Panel 1: % de tráfico por versión (Gauge / Pie chart)

**Datasource:** Prometheus

```promql
# % de tráfico hacia Canary
(
  kube_deployment_spec_replicas{namespace="canary-demo", deployment="webapp-canary"}
  /
  (
    kube_deployment_spec_replicas{namespace="canary-demo", deployment="webapp-stable"}
    + kube_deployment_spec_replicas{namespace="canary-demo", deployment="webapp-canary"}
  )
) * 100
```

**Configuración del panel:**
- Tipo: Gauge
- Título: `% Tráfico → Canary v2`
- Unidad: Percent (0-100)
- Thresholds: 0=verde, 50=amarillo, 90=naranja

---

## Panel 2: Réplicas por versión (Time series / Bar gauge)

```promql
# Réplicas del Stable
kube_deployment_spec_replicas{namespace="canary-demo", deployment="webapp-stable"}

# Réplicas del Canary
kube_deployment_spec_replicas{namespace="canary-demo", deployment="webapp-canary"}
```

**Configuración del panel:**
- Tipo: Time series o Bar gauge
- Título: `Réplicas por Versión`
- Legend: `{{deployment}}`
- Colores: stable=azul (#2563eb), canary=verde (#16a34a)

---

## Panel 3: Pods listos vs deseados

```promql
# Pods listos (ready)
kube_deployment_status_replicas_ready{namespace="canary-demo"}

# Pods deseados
kube_deployment_spec_replicas{namespace="canary-demo"}
```

**Configuración:**
- Tipo: Stat
- Título: `Pods Ready / Total por versión`

---

## Panel 4: Logs de tráfico en Loki

**Datasource:** Loki

```logql
# Ver hits al stable (v1)
{namespace="canary-demo", pod=~"webapp-stable.*"} |= "GET"

# Ver hits al canary (v2)
{namespace="canary-demo", pod=~"webapp-canary.*"} |= "GET"

# Load generator — ver qué versión responde
{namespace="canary-demo", pod=~"load-generator.*"} |= "HIT"
```

**Configuración:**
- Tipo: Logs panel
- Título: `Accesos por versión (Loki)`

---

## Panel 5: Conteo de requests por versión (desde Load Generator logs)

```logql
# Requests al stable por minuto
sum by (pod) (
  count_over_time(
    {namespace="canary-demo", pod=~"load-generator.*"}
    |= "HIT stable v1"
    [1m]
  )
)

# Requests al canary por minuto
sum by (pod) (
  count_over_time(
    {namespace="canary-demo", pod=~"load-generator.*"}
    |= "HIT canary v2"
    [1m]
  )
)
```

**Configuración:**
- Tipo: Time series
- Título: `Requests/min por versión (Load Generator)`

---

## Panel 6: Estado del pipeline Tekton (InfoText)

Panel de texto estático con instrucciones:
```
Tekton Dashboard: http://192.168.109.200:30094
Argo CD UI:       http://192.168.109.200:30095
WebApp URL:       http://192.168.109.200:30099

Comandos útiles:
  kubectl get deployments -n canary-demo
  kubectl get pods -n canary-demo -w
  kubectl get pipelinerun -n tekton-pipelines
```

---

## Dashboard completo — JSON mínimo para importar

Para crear un dashboard básico en Grafana con los paneles de réplicas:

```
Grafana → Dashboards → New → Import → Pegar JSON
```

Usar este JSON (dashboard mínimo con réplicas + % canary):

```json
{
  "title": "Canary Deployment — Módulo 20",
  "uid": "canary-demo-m20",
  "tags": ["canary", "cicd", "devops2026"],
  "timezone": "browser",
  "refresh": "10s",
  "panels": [
    {
      "id": 1,
      "title": "% Tráfico Canary v2",
      "type": "gauge",
      "gridPos": { "h": 8, "w": 6, "x": 0, "y": 0 },
      "targets": [{
        "expr": "(kube_deployment_spec_replicas{namespace=\"canary-demo\",deployment=\"webapp-canary\"} / (kube_deployment_spec_replicas{namespace=\"canary-demo\",deployment=\"webapp-stable\"} + kube_deployment_spec_replicas{namespace=\"canary-demo\",deployment=\"webapp-canary\"})) * 100",
        "legendFormat": "Canary %"
      }],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "min": 0, "max": 100,
          "thresholds": {
            "steps": [
              {"color": "green", "value": 0},
              {"color": "yellow", "value": 50},
              {"color": "orange", "value": 90}
            ]
          }
        }
      }
    },
    {
      "id": 2,
      "title": "Réplicas por Versión",
      "type": "timeseries",
      "gridPos": { "h": 8, "w": 18, "x": 6, "y": 0 },
      "targets": [
        {
          "expr": "kube_deployment_spec_replicas{namespace=\"canary-demo\",deployment=\"webapp-stable\"}",
          "legendFormat": "v1 Stable"
        },
        {
          "expr": "kube_deployment_spec_replicas{namespace=\"canary-demo\",deployment=\"webapp-canary\"}",
          "legendFormat": "v2 Canary"
        }
      ]
    }
  ],
  "schemaVersion": 36
}
```
