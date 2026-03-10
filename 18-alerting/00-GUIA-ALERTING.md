# Módulo 18: Alerting Completo — AlertManager + Grafana + SLOs

## La observabilidad sin alertas es solo un dashboard bonito

```
ANTES (módulos 10, 16, 17):           DESPUÉS (este módulo):

  Algo falla a las 3am                  Algo falla a las 3am
        ↓                                     ↓
  Nadie lo sabe                        AlertManager detecta
        ↓                                     ↓
  Cliente reporta el lunes             Alerta disparada en <1 min
                                             ↓
                                       Webhook/Slack/Email recibe
                                             ↓
                                       On-call ingresa y ve:
                                        • Dashboard Grafana (link directo)
                                        • Log del error (Loki)
                                        • Traza del fallo (Tempo)
```

## Arquitectura completa del módulo

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PIPELINE DE ALERTAS                              │
│                                                                     │
│  DETECCIÓN          PROCESAMIENTO         NOTIFICACIÓN             │
│                                                                     │
│  Prometheus         AlertManager          Webhook Receiver          │
│  ┌──────────┐      ┌─────────────┐       ┌─────────────────┐      │
│  │ Evalúa   │─────▶│  Agrupa     │──────▶│ UI visual de    │      │
│  │ rules    │      │  Enruta     │       │ alertas en demo │      │
│  │ cada 15s │      │  Silencia   │       │ :30098          │      │
│  └──────────┘      │  Inhibe     │       └─────────────────┘      │
│                    └──────┬──────┘                                  │
│  Grafana Alerting         │             (producción real):          │
│  ┌──────────┐             │              Slack / PagerDuty /        │
│  │ Alertas  │─────────────┘              OpsGenie / Email           │
│  │ en Loki  │                                                       │
│  │ y Tempo  │                                                       │
│  └──────────┘                                                       │
│                                                                     │
│  SLOs (Service Level Objectives)                                    │
│  ┌────────────────────────────────────────────┐                    │
│  │ "Mi servicio debe estar disponible 99.5%"  │                    │
│  │ Error budget: 3.6h/mes                     │                    │
│  │ Alerta si el burn rate es demasiado alto   │                    │
│  └────────────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────┘
```

## Versiones
- **AlertManager**: v0.26.0
- **Namespace**: monitoring
- **NodePorts nuevos**: 30097 (AlertManager UI), 30098 (Webhook demo)

---

## Conceptos clave antes de instalar

### Estados de una alerta en Prometheus

```
INACTIVE → PENDING → FIRING
    │          │         │
No cumple   Cumple    Cumple por
 condición  condición  más de X tiempo
             pero no   (for: 5m)
             el tiempo  → AlertManager
             definido     la recibe
```

### AlertManager: routing tree

```yaml
route:                              # Ruta raíz (fallback)
  receiver: webhook-demo
  routes:
    - match: {severity: critical}   # Rama para críticos
      receiver: webhook-demo
      group_wait: 10s               # Esperar 10s antes de enviar
    - match: {severity: warning}    # Rama para warnings
      receiver: webhook-demo
      group_wait: 5m                # Esperar 5 min (menos urgente)
```

### SLO / SLI / Error Budget

```
SLI (Indicador): tasa de peticiones exitosas = 99.7%
SLO (Objetivo):  "debe ser ≥ 99.5% en 30 días"
Error Budget:    0.5% × 30 días × 24h × 60m = 216 minutos/mes

Si el burn rate es muy alto → estás quemando el error budget
→ alerta ANTES de romper el SLO
```

---

## Instalación paso a paso

### Paso 1: Webhook Receiver (primero, para ver las alertas)

```bash
kubectl apply -f 07-webhook-receiver.yaml

# Verificar
kubectl get pods -n monitoring -l app=webhook-receiver
kubectl get svc -n monitoring webhook-receiver-svc

# Acceder a la UI del webhook
# http://192.168.109.200:30098
# (Aún no hay alertas, pero ya está listo para recibirlas)
```

### Paso 2: AlertManager

```bash
kubectl apply -f 01-alertmanager-configmap.yaml
kubectl apply -f 02-alertmanager-deployment.yaml

kubectl rollout status deployment/alertmanager -n monitoring

# Acceder a la UI de AlertManager
# http://192.168.109.200:30097
# Ver: Status → Config para confirmar la configuración cargada
```

### Paso 3: Prometheus Rules (alerting rules)

```bash
kubectl apply -f 03-prometheus-rules-infra.yaml
kubectl apply -f 04-prometheus-rules-app.yaml
kubectl apply -f 05-prometheus-rules-slo.yaml
```

### Paso 4: Conectar Prometheus con AlertManager

```bash
kubectl apply -f 06-prometheus-config-patch.yaml

# Reiniciar Prometheus para que tome la nueva config
kubectl rollout restart deployment/prometheus -n monitoring
kubectl rollout status deployment/prometheus -n monitoring

# Verificar en Prometheus UI: Status → Runtime & Build Information
# Status → Alerts (verás las reglas cargadas)
# http://192.168.109.200:30092/alerts
```

### Paso 5: Configurar Grafana Unified Alerting

```bash
kubectl apply -f 08-grafana-alerting-config.yaml
kubectl rollout restart deployment/grafana -n monitoring

# Grafana Alerting está en: Alerting (icono campana en menú izquierdo)
# → Alert rules: ver reglas activas
# → Contact points: ver el webhook configurado
# → Notification policies: ver el routing
```

### Paso 6: Demo de chaos (disparar alertas)

```bash
kubectl apply -f 09-demo-chaos-app.yaml

# Verificar que la app funciona normalmente
kubectl get pods -n monitoring -l app=demo-chaos
SVC_IP=$(kubectl get svc demo-chaos-svc -n monitoring -o jsonpath='{.spec.clusterIP}')
kubectl run test --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s http://demo-chaos-svc.monitoring.svc.cluster.local/health

# Ver estado actual (todos OK)
# http://192.168.109.200:30092/alerts  → INACTIVE
```

---

## Demo estrella: disparar y resolver una alerta

### 1. Inyectar fallos (activar modo caos)

```bash
# Cambiar el ConfigMap para activar el modo caos
kubectl patch configmap chaos-config -n monitoring \
  --type merge \
  -p '{"data":{"CHAOS_MODE":"true","ERROR_RATE":"0.8"}}'

# Los pods detectan el cambio automáticamente (montado como volumen)
# La app empieza a devolver 80% de errores HTTP 500
```

### 2. Observar el pipeline de alertas

```bash
# Terminal 1: ver métricas en tiempo real
watch -n 5 'kubectl exec -n monitoring -it \
  $(kubectl get pod -n monitoring -l app=demo-chaos -o name | head -1) -- \
  wget -qO- http://localhost:8080/metrics | grep http_requests_total'

# Terminal 2: ver logs de AlertManager
kubectl logs -n monitoring -l app=alertmanager -f --tail=20
```

Tiempos esperados:
- **T+0s**: Prometheus evalúa la regla → estado `PENDING`
- **T+5m**: Alerta pasa a `FIRING` (después del `for: 5m`)
- **T+5m+30s**: AlertManager agrupa y envía al webhook
- **T+5m+30s**: Ver la alerta en http://192.168.109.200:30098

> 💡 **Para la clase**: reducir `for: 1m` en las reglas para ver el efecto más rápido

### 3. Silenciar la alerta (mantenimiento programado)

```bash
# En AlertManager UI (http://192.168.109.200:30097):
# → Silences → New Silence
# Matchers: alertname="HighErrorRate", namespace="monitoring"
# Duration: 30 minutos
# Comment: "Demo maintenance window"
```

### 4. Resolver el problema

```bash
# Desactivar el modo caos
kubectl patch configmap chaos-config -n monitoring \
  --type merge \
  -p '{"data":{"CHAOS_MODE":"false","ERROR_RATE":"0"}}'

# En ~5 min: la alerta pasa de FIRING → RESOLVED
# AlertManager envía notificación "RESOLVED" al webhook
# Ver el cambio en http://192.168.109.200:30098
```

---

## SLO Dashboard

```bash
kubectl apply -f 10-slo-dashboard.yaml
kubectl rollout restart deployment/grafana -n monitoring

# En Grafana: Dashboards → "SLO - Error Budget"
# Verás:
# - Disponibilidad actual (%) en los últimos 30 días
# - Error budget restante (minutos)
# - Burn rate actual (¿cuánto más rápido que lo normal consumes el budget?)
# - Tiempo estimado hasta romper el SLO
```

---

## Verificación del stack completo

```bash
# 1. AlertManager está conectado a Prometheus
curl -s http://192.168.109.200:30092/api/v1/alertmanagers | python3 -m json.tool

# 2. Ver reglas cargadas en Prometheus
curl -s http://192.168.109.200:30092/api/v1/rules | python3 -m json.tool 2>/dev/null | grep '"name"'

# 3. Ver alertas activas
curl -s http://192.168.109.200:30097/api/v2/alerts | python3 -m json.tool 2>/dev/null

# 4. Ver status de AlertManager
curl -s http://192.168.109.200:30097/api/v2/status | python3 -m json.tool 2>/dev/null
```

---

## Troubleshooting

```bash
# AlertManager no recibe alertas de Prometheus
# → Verificar que la URL en prometheus.yml sea correcta
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=prometheus -o name | head -1) -- \
  wget -qO- http://alertmanager.monitoring.svc.cluster.local:9093/-/ready

# Reglas no se cargan
kubectl logs -n monitoring -l app=prometheus | grep -i "rule\|error"

# Webhook no recibe alertas
kubectl logs -n monitoring -l app=alertmanager | grep -i "webhook\|error\|notify"

# Ver configuración activa de AlertManager
curl -s http://192.168.109.200:30097/api/v2/status

# Reload AlertManager sin reiniciar
curl -X POST http://192.168.109.200:30097/-/reload

# Reload Prometheus rules sin reiniciar
curl -X POST http://192.168.109.200:30092/-/reload
```
