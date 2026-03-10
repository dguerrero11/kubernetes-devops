# Módulo 17: Trazas Distribuidas con Tempo + OpenTelemetry

## Observabilidad Completa: el tercer pilar

```
┌─────────────────────────────────────────────────────────────────┐
│                  LOS 3 PILARES DE OBSERVABILIDAD                 │
├──────────────────┬────────────────────┬─────────────────────────┤
│    MÉTRICAS      │      LOGS          │       TRAZAS            │
│   (Módulo 10)    │   (Módulo 16)      │    (Este módulo)        │
│                  │                    │                         │
│ ¿Qué tan rápido? │ ¿Qué ocurrió       │ ¿Por qué tardó         │
│ ¿Cuántos errores?│  exactamente?      │  esta petición?        │
│ ¿Cuánta CPU?     │                    │                         │
│                  │                    │ Sigue UNA petición      │
│  Prometheus      │    Loki            │  a través de TODOS      │
│  Grafana         │    Promtail        │  los servicios          │
│                  │    Grafana         │                         │
│                  │                    │  Tempo + OTel + Grafana │
└──────────────────┴────────────────────┴─────────────────────────┘
```

---

## ¿Qué es una Traza Distribuida?

En una arquitectura de microservicios, una petición del usuario atraviesa múltiples servicios:

```
Usuario → Frontend → Auth Service → API Gateway → DB Service → Cache
                         ↓                ↓             ↓
                      JWT Check      Product DB    Redis Cache
```

**Sin trazas**: Cuando hay un error o lentitud, no sabes qué servicio fue el culpable.
**Con trazas**: Cada paso queda registrado con tiempos exactos → diagnóstico inmediato.

### Conceptos clave

```
TRAZA (Trace)
└── Es el viaje completo de UNA petición, de inicio a fin
    Tiene un Trace ID único (ej: abc123def456)

    SPAN
    └── Cada operación individual dentro de la traza
        Tiene: nombre, duración, estado (OK/Error), atributos
        Ejemplo: "db.query" tomó 45ms, "http.request" tomó 200ms

        SPAN PADRE / HIJO
        └── Los spans forman un árbol (llamadas anidadas)
            frontend (200ms)
              ├── auth-check (15ms)
              ├── api-call (150ms)
              │     ├── db-query (80ms)  ← el cuello de botella
              │     └── cache-read (5ms)
              └── render (30ms)
```

### Context Propagation

Para que los spans de distintos servicios se conecten en una traza, se pasan cabeceras HTTP:

```http
traceparent: 00-abc123def456-span789-01
             ^^  trace_id     span_id  flags
```

OpenTelemetry estandariza esto con el protocolo **W3C TraceContext**.

---

## Arquitectura del Stack

```
┌───────────────────────────────────────────────────────────────────┐
│                        CLUSTER KUBERNETES                          │
│                                                                   │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐  │
│  │  App Service │     │  App Service │     │  App Service     │  │
│  │  (OTel SDK)  │     │  (OTel SDK)  │     │  (OTel SDK)      │  │
│  └──────┬───────┘     └──────┬───────┘     └────────┬─────────┘  │
│         │                   │                       │             │
│         └──────────────────OTLP─────────────────────┘             │
│                              │                                    │
│                              ▼ :4317 (gRPC) / :4318 (HTTP)        │
│                    ┌─────────────────────┐                        │
│                    │   OTel Collector    │ ← Recibe, procesa      │
│                    │  (otelcol-contrib)  │   y enruta             │
│                    └──────────┬──────────┘                        │
│                               │ OTLP gRPC                         │
│                               ▼ :4317                             │
│                    ┌─────────────────────┐                        │
│                    │       TEMPO         │ ← Almacena trazas      │
│                    │   (single binary)   │   NFS: /srv/nfs/k8s/  │
│                    │                     │          /tempo        │
│                    └──────────┬──────────┘                        │
│                               │ HTTP :3200                        │
│                               ▼                                   │
│                    ┌─────────────────────┐                        │
│                    │       GRAFANA       │ ← Visualiza trazas     │
│                    │  (ya instalado)     │   + correlación con    │
│                    │  Puerto 30093       │   Loki y Prometheus    │
│                    └─────────────────────┘                        │
└───────────────────────────────────────────────────────────────────┘
```

## Versiones
- **Grafana Tempo**: v2.3.1
- **OpenTelemetry Collector Contrib**: v0.89.0
- **Namespace**: monitoring

---

## Preparación: NFS Server

```bash
# En el servidor NFS (192.168.109.210)
ssh root@192.168.109.210

mkdir -p /srv/nfs/k8s/tempo
chown -R nobody:nobody /srv/nfs/k8s/tempo
chmod 777 /srv/nfs/k8s/tempo

exportfs -ra
```

---

## Instalación paso a paso

### Paso 1: Storage para Tempo

```bash
kubectl apply -f 01-tempo-pv.yaml
kubectl apply -f 02-tempo-pvc.yaml

kubectl get pv tempo-pv
kubectl get pvc tempo-pvc -n monitoring
```

### Paso 2: Desplegar Tempo

```bash
kubectl apply -f 03-tempo-configmap.yaml
kubectl apply -f 04-tempo-deployment.yaml
kubectl apply -f 05-tempo-service.yaml

kubectl rollout status deployment/tempo -n monitoring
kubectl get pods -n monitoring -l app=tempo

# Verificar que está listo
kubectl logs -n monitoring -l app=tempo --tail=20
# Buscar: "msg="starting component" component=ingester"
```

### Paso 3: Desplegar OpenTelemetry Collector

El OTel Collector es el gateway que recibe trazas de las apps y las envía a Tempo.

```bash
kubectl apply -f 06-otel-configmap.yaml
kubectl apply -f 07-otel-deployment.yaml
kubectl apply -f 08-otel-service.yaml

kubectl rollout status deployment/otel-collector -n monitoring
kubectl get pods -n monitoring -l app=otel-collector

# Ver que está listo
kubectl logs -n monitoring -l app=otel-collector --tail=20
# Buscar: "Everything is ready. Begin running and processing data."
```

### Paso 4: Agregar Tempo como datasource en Grafana

```bash
kubectl apply -f 09-grafana-tempo-datasource.yaml
kubectl rollout restart deployment/grafana -n monitoring
kubectl rollout status deployment/grafana -n monitoring
```

### Paso 5: App de demostración

```bash
kubectl apply -f 10-demo-traces.yaml

# Ver el generador de trazas corriendo
kubectl get pods -n monitoring -l app=trace-generator
kubectl logs -n monitoring -l app=trace-generator --tail=20

# Verificar que las trazas llegan al OTel Collector
kubectl logs -n monitoring -l app=otel-collector --tail=30 | grep -i "trace"
```

---

## Uso en Grafana

### Ver trazas en Explore

1. Ir a **http://192.168.109.200:30093**
2. Clic en **Explore** (ícono de brújula)
3. Seleccionar datasource **Tempo**
4. En **Query type** elegir **Search**
5. Filtrar por:
   - **Service name**: `demo-service`
   - **Span name**: `HTTP GET`
   - **Tags**: `http.status_code=200`
6. Clic en cualquier traza para ver el **flame graph** (árbol de spans)

### Buscar por Trace ID

Si conoces el Trace ID (p.ej. desde los logs de Loki):

```
Tempo → Explore → Query type: TraceQL → Buscar por Trace ID
```

### TraceQL — Lenguaje de consulta de Tempo

```traceql
# Todas las trazas del servicio demo-service
{ resource.service.name = "demo-service" }

# Trazas con errores
{ status = error }

# Trazas que duraron más de 500ms
{ duration > 500ms }

# Trazas del servicio con errores HTTP 5xx
{ resource.service.name = "frontend" && span.http.status_code >= 500 }

# Trazas que pasaron por el servicio de base de datos
{ resource.service.name = "db-service" && duration > 100ms }

# Combinar: trazas lentas CON errores
{ duration > 1s && status = error }

# Buscar por atributo personalizado
{ span.user.id = "usr_123" }
```

---

## Correlación: Métricas + Logs + Trazas en Grafana

Esta es la **característica más poderosa** del stack Grafana. Ver un problema desde los tres ángulos:

```
1. Prometheus te dice: "hubo spike de errores a las 15:34"
                              ↓
2. Loki te muestra: los logs de error de ese momento
                              ↓
3. Tempo te da: la traza exacta de una petición fallida
```

### Configurar el "data link" Prometheus → Tempo

En el datasource de Prometheus (ya configurado en módulo 10), activar **exemplars**:

```yaml
# En grafana-datasource.yaml del módulo 10, agregar:
exemplarTraceIdDestinations:
  - datasourceUid: tempo
    name: trace_id
```

Así, en los gráficos de Prometheus podrás hacer clic en un punto y saltar directamente a la traza de Tempo.

### Configurar "data link" Loki → Tempo

En el log-datasource de Loki, los logs que contengan un `traceId` permitirán saltar a Tempo:

```yaml
# En 09-grafana-loki-datasource.yaml del módulo 16:
derivedFields:
  - datasourceUid: tempo
    matcherRegex: "traceId=(\\w+)"
    name: TraceID
    url: "$${__value.raw}"
```

---

## Verificación completa del pipeline

```bash
# 1. ¿Tempo recibe trazas?
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=tempo -o name | head -1) -- \
  wget -qO- "http://localhost:3200/api/search?limit=5" | python3 -m json.tool 2>/dev/null || \
  wget -qO- "http://localhost:3200/api/search?limit=5"

# 2. ¿Cuántas trazas tiene Tempo?
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=tempo -o name | head -1) -- \
  wget -qO- http://localhost:3200/metrics | grep tempo_ingester_traces_created_total

# 3. ¿OTel Collector procesa trazas?
kubectl logs -n monitoring -l app=otel-collector | grep -E "SpansReceived|SpansSent|error"

# 4. Ver trace IDs disponibles
kubectl run tempo-query --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s "http://tempo.monitoring.svc.cluster.local:3200/api/search?limit=10"
```

---

## Instrumentar tu propia app con OpenTelemetry

### Python (Flask/FastAPI)
```bash
pip install opentelemetry-sdk opentelemetry-exporter-otlp
```

```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

# Configurar
provider = TracerProvider()
exporter = OTLPSpanExporter(
    endpoint="http://otel-collector.monitoring.svc.cluster.local:4317",
    insecure=True
)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Usar
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("mi-operacion") as span:
    span.set_attribute("user.id", "123")
    # tu código aquí
```

### Node.js
```bash
npm install @opentelemetry/sdk-node @opentelemetry/exporter-trace-otlp-grpc
```

```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-collector.monitoring.svc.cluster.local:4317',
  }),
});
sdk.start();
```

### Auto-instrumentación sin cambiar código (Java)
```yaml
# En el Deployment, agregar init container que inyecta el agente:
initContainers:
  - name: otel-agent
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.0
    command: ["cp", "/javaagent.jar", "/otel-auto-instrumentation/javaagent.jar"]
    volumeMounts:
      - name: otel-auto-instrumentation
        mountPath: /otel-auto-instrumentation
```

---

## Comparativa: Tempo vs Jaeger vs Zipkin

| Característica | **Tempo** | Jaeger | Zipkin |
|----------------|-----------|--------|--------|
| Backend storage | S3/NFS/GCS | Elasticsearch/Cassandra | Elasticsearch/MySQL |
| UI | Via Grafana | Jaeger UI nativo | Zipkin UI nativo |
| Integración Grafana | ✅ Nativa | ⚠️ Plugin | ⚠️ Plugin |
| Escalabilidad | Alta (S3) | Media | Media |
| Recursos | Bajos | Medios | Bajos |
| Correlación MLT | ✅ Exemplars | ❌ Limitada | ❌ Limitada |
| **Ideal para** | Stack Grafana | Multi-lenguaje legacy | Apps Java/Spring |

---

## Troubleshooting

```bash
# Tempo no inicia → permisos NFS
kubectl logs -n monitoring -l app=tempo | grep -i "error\|permission"
# Solución: chmod 777 /srv/nfs/k8s/tempo en el NFS server

# OTel Collector no reenvía a Tempo → ver conectividad
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=otel-collector -o name | head -1) -- \
  wget -qO- http://tempo.monitoring.svc.cluster.local:3200/ready

# Tempo dice "ready" pero Grafana no encuentra trazas → datasource URL
# Verificar que la URL en el datasource es: http://tempo.monitoring.svc.cluster.local:3200

# Ver métricas internas de Tempo
kubectl exec -n monitoring -it $(kubectl get pod -n monitoring -l app=tempo -o name | head -1) -- \
  wget -qO- http://localhost:3200/metrics | grep -E "tempo_request|tempo_ingester"

# Reiniciar todo el stack de observabilidad
kubectl rollout restart deployment/tempo deployment/otel-collector deployment/grafana -n monitoring
```

---

## Notas para EKS (AWS)

En **AWS EKS**, el stack de trazas puede usar:

```
Opción 1: Tempo en EKS + S3 como backend (más económico y escalable)
  storage:
    trace:
      backend: s3
      s3:
        bucket: mi-bucket-tempo
        region: us-east-1

Opción 2: AWS X-Ray (nativo de AWS)
  - Integra con IAM, CloudWatch
  - OTel Collector puede exportar a X-Ray también
  - Integración con Grafana vía datasource X-Ray

Opción 3: Managed Grafana + AMG (Amazon Managed Grafana)
  - Tempo, Prometheus, Loki en AWS managed
  - Sin gestión de infraestructura
```

El módulo de EKS cubrirá estas opciones en profundidad.
