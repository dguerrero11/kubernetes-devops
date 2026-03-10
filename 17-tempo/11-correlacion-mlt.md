# Correlación Métricas + Logs + Trazas (MLT) en Grafana

Esta es la capacidad diferencial del stack Grafana frente a otras soluciones:
**navegar entre los tres pilares de observabilidad sin cambiar de herramienta.**

---

## El flujo de diagnóstico real

```
ALERTA: Latencia P99 > 2s en demo-frontend
              │
              ▼ (clic en el punto del gráfico de Prometheus)
              │
    MÉTRICAS (Prometheus)
    ┌─────────────────────────────────────────┐
    │ rate(http_requests_total{job="frontend"}│
    │ [5m])                                   │
    │                                         │
    │ ● Spike a las 15:34 ← anomalía         │
    └───────────────┬─────────────────────────┘
                    │ clic en "Logs" (data link)
                    ▼
    LOGS (Loki)
    ┌─────────────────────────────────────────┐
    │ {app="demo-frontend"} | json            │
    │                                         │
    │ 15:34:02 ERROR timeout calling backend  │
    │ 15:34:03 ERROR timeout calling backend  │
    │ 15:34:04 WARN  retry 1/3               │
    │                                         │
    │ traceId=abc123def456 ←── aparece aquí  │
    └───────────────┬─────────────────────────┘
                    │ clic en el traceId
                    ▼
    TRAZAS (Tempo)
    ┌─────────────────────────────────────────┐
    │ Trace: abc123def456                     │
    │                                         │
    │ ▼ demo-frontend (2.1s) ← raíz          │
    │   ├─ HTTP GET /api/users/42 (50ms)      │
    │   └─ HTTP GET /api/products (2.0s) ←!  │
    │         └─ db.query.products (1.95s)    │
    │               ⚠ slow_query=true         │
    └─────────────────────────────────────────┘
    DIAGNÓSTICO: slow query en base de datos
```

---

## Configuración de las correlaciones

### 1. Activar Exemplars en Prometheus

Los **exemplars** son puntos de datos en Prometheus que incluyen un Trace ID.
Permiten hacer clic en un punto del gráfico y saltar a la traza de Tempo.

```bash
# Editar el ConfigMap de Prometheus (módulo 10)
kubectl edit configmap prometheus-config -n monitoring
```

Agregar al scrape de la app:
```yaml
# En prometheus.yml, en el job de la app demo:
- job_name: 'demo-frontend'
  static_configs:
    - targets: ['demo-frontend-svc.monitoring.svc.cluster.local:8080']
  # Habilitar recepción de exemplars
  sample_limit: 10000
```

También habilitar en Prometheus la feature de exemplars:
```yaml
# En el Deployment de Prometheus, agregar el flag:
args:
  - --storage.tsdb.exemplars-all-tenants
  - --enable-feature=exemplar-storage
```

### 2. Activar correlación Prometheus → Tempo en Grafana

Editar el datasource de Prometheus en Grafana:
```yaml
# Ir a: Grafana → Configuration → Data Sources → Prometheus → Edit
# En la sección "Exemplars":
internal_link: true
datasource_uid: tempo
url_display_label: "Ver Traza"
```

### 3. Activar correlación Loki → Tempo

En el ConfigMap del datasource de Loki (`09-grafana-loki-datasource.yaml` del módulo 16):
```yaml
derivedFields:
  - datasourceUid: tempo
    matcherRegex: "traceId=(\\w+)"
    name: TraceID
    url: "$${__value.raw}"
    urlDisplayLabel: "Ver en Tempo"
```

Aplicar y reiniciar Grafana:
```bash
kubectl apply -f ../16-loki/09-grafana-loki-datasource.yaml
kubectl rollout restart deployment/grafana -n monitoring
```

---

## Dashboard: Observabilidad Completa (MLT)

Crear un dashboard en Grafana con 4 paneles integrados:

### Panel 1: Tasa de requests (Prometheus)
```promql
# Query
sum by (job) (rate(http_requests_total{namespace="monitoring"}[5m]))

# Tipo: Time series
# Activar: Exemplars → ON
```

### Panel 2: Tasa de errores (Prometheus)
```promql
# Query
100 * sum by (job) (
  rate(http_requests_total{status=~"5..",namespace="monitoring"}[5m])
) / sum by (job) (
  rate(http_requests_total{namespace="monitoring"}[5m])
)

# Tipo: Time series
# Threshold: 5% → warning (amarillo), 10% → critical (rojo)
```

### Panel 3: Logs en tiempo real (Loki)
```logql
# Query
{namespace="monitoring", app=~"demo-frontend|demo-backend"} | json | level != "INFO"

# Tipo: Logs
# Mostrar labels: app, level, pod
```

### Panel 4: Service Map (Tempo)
```
# En Tempo datasource → Service Graph
# Muestra grafo de dependencias entre microservicios
# Con colores según tasa de error y latencia
```

---

## Escenarios de Demo para la clase

### Escenario 1: Encontrar una petición lenta
```bash
# Generar tráfico
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=trace-load-generator -o name 2>/dev/null | head -1 || \
  kubectl run tmp --rm -it --image=curlimages/curl --restart=Never -- sh) -- \
  sh -c 'for i in $(seq 1 30); do curl -s http://demo-frontend-svc.monitoring.svc.cluster.local:8080/ > /dev/null; echo "req $i"; sleep 1; done'

# En Grafana:
# 1. Explore → Tempo → Search → duration > 500ms
# 2. Clic en una traza lenta → ver el flame graph
# 3. Identificar el span más lento (db.query.products con slow_query=true)
```

### Escenario 2: Rastrear un error 404
```bash
# En Grafana:
# 1. Explore → Tempo → TraceQL:
#    { status = error && resource.service.name = "demo-backend" }
# 2. Abrir la traza → ver el span con error
# 3. Hacer clic en "Logs" → ver los logs de ese pod en ese momento
```

### Escenario 3: Comparar con y sin correlación
```
SIN correlación (mundo antiguo):
  - Ver alerta en PagerDuty → hora del incidente
  - Abrir Kibana/ELK → buscar logs en ese rango de tiempo
  - Copiar manualmente el traceId del log
  - Abrir Jaeger → pegar traceId
  - Tiempo: 10-15 minutos

CON correlación MLT en Grafana:
  - Ver alerta → clic en el gráfico de Prometheus
  - Ver logs automáticamente filtrados
  - Clic en el traceId → flame graph instantáneo
  - Tiempo: 30 segundos
```

---

## Mapa conceptual del stack completo

```
┌─────────────────────────────────────────────────────────────────────┐
│                    STACK DE OBSERVABILIDAD COMPLETO                  │
│                                                                     │
│  Apps (frontend + backend + database)                               │
│    │                                                                │
│    ├── OTel SDK ──────────────────────► OTel Collector              │
│    │   (traces + metrics + logs)              │                     │
│    │                                          ├──► Tempo (traces)   │
│    ├── Logs a stdout ──► Promtail ────────────├──► Loki (logs)      │
│    │                                          │                     │
│    └── /metrics ──────► Prometheus ───────────┘   (metrics)        │
│                              │                                      │
│                              └──────────────────────────────────────►
│                                                                     │
│                           GRAFANA                                   │
│                     (punto único de acceso)                         │
│               http://192.168.109.200:30093                          │
│                                                                     │
│  Explore → Metrics (PromQL)                                         │
│  Explore → Logs    (LogQL)                                          │
│  Explore → Traces  (TraceQL)                                        │
│  Dashboards → Todo junto con correlación automática                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Comparativa: stack auto-gestionado vs managed (EKS)

| Componente | Bare Metal (este módulo) | AWS EKS (módulo 18) |
|------------|--------------------------|---------------------|
| Métricas | Prometheus + NFS | Amazon Managed Prometheus (AMP) |
| Logs | Loki + NFS | Amazon CloudWatch Logs / Loki en S3 |
| Trazas | Tempo + NFS | Tempo en S3 / AWS X-Ray |
| Dashboards | Grafana auto-gestionado | Amazon Managed Grafana (AMG) |
| Gestión | Manual | AWS gestiona la infra |
| Coste | Solo recursos del cluster | + coste AWS managed services |
| Escalabilidad | Limitada por NFS | Ilimitada (S3) |
