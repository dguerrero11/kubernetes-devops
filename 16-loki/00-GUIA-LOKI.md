# Módulo 16: Logs con Loki (PLG Stack)

## Los 3 Pilares de Observabilidad

```
┌─────────────────────────────────────────────────────┐
│              OBSERVABILIDAD COMPLETA                  │
├───────────────┬──────────────────┬───────────────────┤
│   MÉTRICAS    │      LOGS        │     TRAZAS        │
│  (Módulo 10)  │  (Este módulo)   │  (Módulo 17)      │
│               │                  │                   │
│  Prometheus   │      Loki        │  Tempo / Jaeger   │
│  Grafana      │   Promtail       │  OpenTelemetry    │
│  Node Exporter│   Grafana        │                   │
└───────────────┴──────────────────┴───────────────────┘
```

## ¿Qué es Loki?

Loki es un sistema de agregación de logs desarrollado por Grafana Labs. A diferencia de Elasticsearch (ELK stack), Loki **no indexa el contenido** de los logs, solo los metadatos (labels). Esto lo hace:
- **Mucho más económico** en almacenamiento y CPU
- **Perfectamente integrado** con Grafana (misma interfaz que métricas)
- **Compatible con la sintaxis de PromQL** → LogQL

## Arquitectura PLG Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    CLUSTER KUBERNETES                         │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │  Pod App │    │  Pod App │    │  Pod App │              │
│  │  /var/   │    │  /var/   │    │  /var/   │              │
│  │  log/    │    │  log/    │    │  log/    │              │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘              │
│       │               │               │                     │
│       └───────────────┼───────────────┘                     │
│                       ▼                                     │
│              ┌─────────────────┐                           │
│              │   PROMTAIL      │ ← DaemonSet (1 pod/nodo) │
│              │  (Recolector)   │   Lee /var/log/pods/      │
│              └────────┬────────┘   Lee /var/log/journal    │
│                       │                                     │
│                       ▼ HTTP (3100)                         │
│              ┌─────────────────┐                           │
│              │      LOKI       │ ← StatefulSet              │
│              │  (Almacenamiento│   NFS: /srv/nfs/k8s/loki  │
│              │   y consultas)  │                            │
│              └────────┬────────┘                           │
│                       │                                     │
│                       ▼ Datasource                          │
│              ┌─────────────────┐                           │
│              │    GRAFANA      │ ← Ya instalado (módulo 10)│
│              │  (Visualización)│   Puerto 30093             │
│              └─────────────────┘                           │
└─────────────────────────────────────────────────────────────┘
```

## Versiones utilizadas
- **Loki**: v2.9.6
- **Promtail**: v2.9.6
- **Namespace**: monitoring (el mismo del módulo 10)

---

## Preparación: NFS Server

Crear el directorio en el servidor NFS (192.168.109.210):

```bash
# En el servidor NFS
ssh root@192.168.109.210

mkdir -p /srv/nfs/k8s/loki
chown -R nobody:nobody /srv/nfs/k8s/loki
chmod 777 /srv/nfs/k8s/loki

# Verificar que está exportado (debe incluir /srv/nfs/k8s)
cat /etc/exports
exportfs -ra
showmount -e localhost
```

---

## Instalación paso a paso

### Paso 1: PersistentVolume y PVC para Loki

```bash
kubectl apply -f 01-loki-pv.yaml
kubectl apply -f 02-loki-pvc.yaml

# Verificar
kubectl get pv loki-pv
kubectl get pvc loki-pvc -n monitoring
```

### Paso 2: ConfigMap de configuración de Loki

```bash
kubectl apply -f 03-loki-configmap.yaml
```

### Paso 3: Desplegar Loki

```bash
kubectl apply -f 04-loki-statefulset.yaml
kubectl apply -f 05-loki-service.yaml

# Esperar a que arranque
kubectl rollout status statefulset/loki -n monitoring
kubectl get pods -n monitoring -l app=loki

# Ver logs de Loki
kubectl logs -n monitoring -l app=loki --tail=30
```

### Paso 4: Desplegar Promtail (recolector de logs)

```bash
kubectl apply -f 06-promtail-rbac.yaml
kubectl apply -f 07-promtail-configmap.yaml
kubectl apply -f 08-promtail-daemonset.yaml

# Verificar: debe haber 1 pod por nodo
kubectl get pods -n monitoring -l app=promtail -o wide
# Esperado: 3 pods (master + 2 workers)

# Ver que está enviando logs a Loki
kubectl logs -n monitoring -l app=promtail --tail=20
```

### Paso 5: Agregar Loki como datasource en Grafana

```bash
kubectl apply -f 09-grafana-loki-datasource.yaml

# Reiniciar Grafana para que tome el nuevo datasource
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout status deployment/grafana -n monitoring
```

### Paso 6: App de demostración

```bash
kubectl apply -f 10-demo-app-logs.yaml

# Generar tráfico de prueba
kubectl port-forward svc/demo-logger-svc -n monitoring 8080:80 &
for i in {1..20}; do curl -s http://localhost:8080/ > /dev/null; done

# Ver los logs generados
kubectl logs -n monitoring -l app=demo-logger --tail=20
```

---

## Uso en Grafana

### Acceder a Grafana
```
http://192.168.109.200:30093
Usuario: admin
Password: (el configurado en módulo 10)
```

### Explorar logs con LogQL

1. Ir a **Explore** (icono brújula izquierda)
2. Seleccionar datasource **Loki**
3. Usar el **Label browser** o escribir queries LogQL directamente

### LogQL — Queries básicas

```logql
# Ver todos los logs del namespace monitoring
{namespace="monitoring"}

# Logs de un pod específico
{pod=~"loki.*"}

# Logs de nivel ERROR en cualquier pod
{namespace="monitoring"} |= "error"

# Filtrar por regex (errores o warnings)
{namespace="monitoring"} |~ "error|warn|Error|Warning"

# Logs del sistema (journal)
{job="systemd-journal"}

# Logs de la app demo
{app="demo-logger"}

# Mostrar solo líneas que contienen "GET"
{app="demo-logger"} |= "GET"

# Excluir líneas de health check
{app="demo-logger"} != "health"
```

### LogQL — Queries avanzadas (métricas sobre logs)

```logql
# Tasa de logs de error por minuto
rate({namespace="monitoring"} |= "error" [1m])

# Contar líneas de log por pod en los últimos 5 min
sum by (pod) (count_over_time({namespace="monitoring"}[5m]))

# Top pods por volumen de logs
topk(5, sum by (pod) (rate({namespace="kube-system"}[5m])))

# Buscar logs de un rango de tiempo específico
{namespace="monitoring"} |= "error" | json | line_format "{{.level}}: {{.message}}"
```

### Panel en Dashboard de Grafana

Para crear un panel de logs en un dashboard existente:
1. Abrir el dashboard → **Add panel**
2. Cambiar datasource a **Loki**
3. Elegir visualización **Logs**
4. Query: `{namespace="monitoring"}`

---

## Verificación completa

```bash
# 1. Verificar que Loki está recibiendo streams
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
  wget -qO- http://localhost:3100/loki/api/v1/labels

# 2. Ver métricas de Loki
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=loki -o name | head -1) -- \
  wget -qO- http://localhost:3100/metrics | grep loki_ingester_streams_created_total

# 3. Consultar logs via API (desde el cluster)
kubectl run test-loki --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/query?query=%7Bnamespace%3D%22monitoring%22%7D&limit=5"
```

---

## Comparativa: Loki vs ELK Stack

| Característica | Loki | ELK Stack |
|----------------|------|-----------|
| Indexación | Solo labels | Contenido completo |
| Recursos | Bajo (CPU/RAM) | Alto |
| Almacenamiento | Comprimido | Sin comprimir por defecto |
| Integración | Grafana nativo | Kibana |
| Curva aprendizaje | Baja (LogQL ≈ PromQL) | Alta |
| Coste en cloud | Muy bajo | Alto |
| Búsqueda full-text | Limitada (grep) | Excelente |
| **Ideal para** | Kubernetes + Grafana | Búsquedas complejas |

---

## Notas para EKS (AWS)

Cuando se usa **AWS EKS**, las alternativas a Promtail son:

```
EKS Observabilidad de Logs:
  Opción 1: Promtail + Loki (esta misma guía, funciona igual en EKS)
  Opción 2: Fluent Bit → CloudWatch Logs (AWS nativo, DaemonSet)
  Opción 3: Fluent Bit → Kinesis → OpenSearch (más complejo)
  Opción 4: AWS Container Insights (métricas + logs integrado)
```

En EKS con Loki, la diferencia es el storage backend:
- **Bare metal/local**: filesystem (NFS)
- **EKS**: S3 como backend de Loki (mucho más escalable y económico)

```yaml
# Loki en EKS usa S3 como storage:
storage_config:
  aws:
    s3: s3://tu-bucket-region/loki/
    region: us-east-1
```

El módulo de EKS cubrirá esto en profundidad.

---

## Troubleshooting

```bash
# Promtail no envía logs → ver su configuración
kubectl describe configmap promtail-config -n monitoring

# Loki no guarda datos → verificar PVC
kubectl get pvc loki-pvc -n monitoring
kubectl describe pvc loki-pvc -n monitoring

# Errores de permisos NFS
kubectl logs -n monitoring -l app=loki | grep "permission denied"
# Solución: chmod 777 /srv/nfs/k8s/loki en el NFS server

# Grafana no muestra Loki como datasource
kubectl get configmap grafana-loki-datasource -n monitoring
kubectl rollout restart deployment/grafana -n monitoring

# Ver todos los logs de todos los pods del módulo
kubectl logs -n monitoring -l app=promtail --prefix=true --tail=10
kubectl logs -n monitoring -l app=loki --prefix=true --tail=10
```
