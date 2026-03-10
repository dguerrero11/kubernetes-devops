# Alerting Cookbook — Referencia de Reglas Comunes

Colección de alertas listas para usar, organizadas por categoría.

---

## Formato de una regla de alerta

```yaml
- alert: NombreAlerta              # PascalCase, descriptivo
  expr: |                          # Expresión PromQL que evalúa la condición
    metrica > umbral
  for: 5m                          # Debe cumplirse DURANTE este tiempo antes de FIRING
  labels:
    severity: warning              # critical | warning | info | none
    namespace: "{{ $labels.namespace }}"
  annotations:
    summary: "Título corto (1 línea)"
    description: "Descripción detallada con contexto y acción sugerida."
```

---

## Por componente

### Kubernetes — Pods

```yaml
# Pod en OOMKilled (falta memoria)
- alert: PodOOMKilled
  expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
  for: 0m
  labels:
    severity: warning
  annotations:
    summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} terminado por OOM"
    description: "Aumentar los limits de memoria del pod {{ $labels.pod }}."

# Contenedor en Pending por más de 15 minutos (posible falta de recursos)
- alert: PodStuckPending
  expr: kube_pod_status_phase{phase="Pending"} == 1
  for: 15m
  labels:
    severity: warning
  annotations:
    summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} lleva 15 min en Pending"
    description: "Verificar: kubectl describe pod {{ $labels.pod }} -n {{ $labels.namespace }}"

# Container esperando por ImagePullBackOff
- alert: ImagePullBackOff
  expr: kube_pod_container_status_waiting_reason{reason="ImagePullBackOff"} == 1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Error descargando imagen en {{ $labels.pod }}"
    description: "Verificar que la imagen existe y el registry es accesible."

# Job fallido (batch job)
- alert: KubernetesJobFailed
  expr: kube_job_failed > 0
  for: 0m
  labels:
    severity: warning
  annotations:
    summary: "Job {{ $labels.namespace }}/{{ $labels.job_name }} falló"
    description: "Un Job de Kubernetes terminó con error."
```

### Kubernetes — Recursos del Cluster

```yaml
# Namespace con resource quota casi llena (>90%)
- alert: NamespaceResourceQuotaAlmostFull
  expr: |
    kube_resourcequota{type="used"} /
    kube_resourcequota{type="hard"} > 0.9
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Resource quota al {{ $value | humanizePercentage }} en {{ $labels.namespace }}"

# PVC sin espacio (<10% libre)
- alert: PersistentVolumeAlmostFull
  expr: |
    kubelet_volume_stats_available_bytes /
    kubelet_volume_stats_capacity_bytes < 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "PVC {{ $labels.persistentvolumeclaim }} casi lleno"
    description: "Solo queda {{ $value | humanizePercentage }} de espacio libre."

# PVC completamente lleno
- alert: PersistentVolumeFull
  expr: |
    kubelet_volume_stats_available_bytes /
    kubelet_volume_stats_capacity_bytes < 0.03
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "PVC {{ $labels.persistentvolumeclaim }} LLENO"
    description: "El volumen está lleno. Expandir PVC o limpiar datos urgentemente."
```

### Aplicaciones HTTP

```yaml
# Latencia P95 alta
- alert: HTTPLatencyHigh
  expr: |
    histogram_quantile(0.95,
      sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
    ) > 2
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "P95 latencia > 2s en {{ $labels.job }}"

# Aumento brusco de tráfico (spike)
- alert: TrafficSpike
  expr: |
    sum by (job) (rate(http_requests_total[2m]))
    /
    sum by (job) (rate(http_requests_total[30m]) > 0)
    > 3
  for: 5m
  labels:
    severity: info
  annotations:
    summary: "Spike de tráfico en {{ $labels.job }}: {{ $value | printf \"%.1f\" }}x"
    description: "El tráfico es {{ $value | printf \"%.1f\" }}x mayor que el promedio de la última media hora."

# Tasa de error 4xx alta (posible abuso o bug)
- alert: High4xxRate
  expr: |
    sum by (job) (rate(http_requests_total{status_code=~"4.."}[5m]))
    /
    sum by (job) (rate(http_requests_total[5m]))
    > 0.15
  for: 5m
  labels:
    severity: info
  annotations:
    summary: "Muchos errores 4xx en {{ $labels.job }}: {{ $value | humanizePercentage }}"
```

### Infraestructura NFS

```yaml
# Servidor NFS no disponible (los pods con PV NFS fallarán)
- alert: NFSMountError
  expr: |
    node_filesystem_files{fstype="nfs4"} == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Montaje NFS no disponible en {{ $labels.instance }}"
    description: "Verificar el servidor NFS en 192.168.109.210."
```

---

## Mejores prácticas de alertas

### 1. La regla de oro: alerta sobre síntomas, no causas
```
❌ Malo:  alert cuando CPU > 80%    (causa técnica)
✅ Bueno: alert cuando latencia P99 > 1s  (síntoma que afecta usuarios)

La CPU alta es una CAUSA POSIBLE de latencia alta.
Pero hay muchas causas de latencia alta sin que la CPU sea alta.
Alertar sobre el síntoma garantiza que SIEMPRE captura el problema.
```

### 2. El `for:` evita falsos positivos
```yaml
# Spike de 30s → no alerta (estoy estresando el cluster intencionalmente)
for: 5m   # Solo alerta si dura 5 minutos seguidos

# Para alertas críticas, puede ser más corto:
for: 2m   # Urgente pero no dispara por spikes momentáneos

# Para Watchdog o ausencia de métrica:
for: 0m   # Sin espera → alerta inmediatamente
```

### 3. Severity levels (convención de la industria)
```
critical:  Requiere acción INMEDIATA. Despierta al on-call.
           Ejemplos: servicio caído, disco lleno, error budget en 2h
warning:   Requiere atención pronto. Crear ticket.
           Ejemplos: CPU alta, pod crasheando, latencia aumentando
info:      Informativo, no requiere acción urgente.
           Ejemplos: spike de tráfico, nuevo deploy detectado
none:      No notificar (Watchdog, etc.)
```

### 4. Annotations útiles
```yaml
annotations:
  summary: "Frase corta (aparece en subject del email/título Slack)"
  description: |
    Descripción detallada con:
    - Valor actual: {{ $value | printf "%.2f" }}
    - Acción sugerida: revisar logs con...
    - Dashboard: http://192.168.109.200:30093/d/xxx
    - Runbook: https://wiki.empresa.com/runbooks/xxx
  runbook_url: "https://wiki.empresa.com/runbooks/high-error-rate"
```

### 5. Inhibition para evitar alert storms
```yaml
# Regla: Si el nodo está down → inhibir alertas de sus pods
# Sin esto: 1 nodo down = 50 alertas (una por pod)
inhibit_rules:
  - source_matchers:
      - alertname = "KubernetesNodeNotReady"
    target_matchers:
      - alertname = "KubernetesPodNotRunning"
    equal: [node]
```

### 6. Silences para mantenimiento programado
```bash
# Silenciar todas las alertas del namespace monitoring durante 2 horas
# (mantenimiento del stack de observabilidad)
curl -X POST http://192.168.109.200:30097/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [{"name": "namespace", "value": "monitoring", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -d '+2 hours' +%Y-%m-%dT%H:%M:%SZ)'",
    "comment": "Mantenimiento del stack de observabilidad",
    "createdBy": "admin"
  }'
```

---

## Comandos de diagnóstico rápido

```bash
# ¿Qué alertas están FIRING ahora?
curl -s http://192.168.109.200:30097/api/v2/alerts?active=true | \
  python3 -c "import sys,json; [print(a['labels']['alertname'], a['status']['state']) for a in json.load(sys.stdin)]"

# ¿Por qué no llegan alertas? (ver logs de AlertManager)
kubectl logs -n monitoring -l app=alertmanager --tail=50 | grep -i "notify\|error\|webhook"

# Probar que el webhook funciona manualmente
curl -X POST http://192.168.109.200:30098/alerts \
  -H "Content-Type: application/json" \
  -d '{"status":"firing","alerts":[{"labels":{"alertname":"TestAlert","severity":"warning"},"annotations":{"summary":"Prueba manual del webhook"}}]}'

# Ver reglas que están evaluándose en Prometheus
curl -s http://192.168.109.200:30092/api/v1/rules | \
  python3 -c "import sys,json; d=json.load(sys.stdin); [print(r['name'],r['state']) for g in d['data']['groups'] for r in g['rules'] if r.get('type')=='alerting']"

# Hacer reload de AlertManager sin reiniciar
curl -X POST http://192.168.109.200:30097/-/reload

# Hacer reload de Prometheus rules sin reiniciar
curl -X POST http://192.168.109.200:30092/-/reload
```
