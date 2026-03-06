# Guía de Clase 3 — Prometheus + Grafana en Kubernetes

**Stack:** Prometheus v2.48.1 · Node Exporter v1.7.0 · Grafana v10.2.3
**Storage:** NFS `192.168.109.210` · `/srv/nfs/k8s/prometheus` · `/srv/nfs/k8s/grafana`
**Directorio:** `/root/devops2026/10-monitoring/`

---

## Arquitectura de la clase

```
                    ┌─────────────────────────────────────────┐
                    │         namespace: monitoring            │
                    │                                          │
  nodo:9100  ──────►│  node-exporter   ──►                    │
  nodo:9100  ──────►│  (DaemonSet)        │                   │
  nodo:9100  ──────►│                     ▼                   │
                    │              prometheus ──► NFS          │
                    │              :9090    ◄── prometheus.yml │
                    │                │          (ConfigMap)    │
                    │                ▼                         │
                    │              grafana ───► NFS            │
                    │              :3000   ◄── datasource.yaml │
                    │                          (ConfigMap)     │
                    └─────────────────────────────────────────┘
                              │                │
                         NodePort          NodePort
                          :30092             :30093
                              │                │
                    http://192.168.109.200:30092  (Prometheus)
                    http://192.168.109.200:30093  (Grafana)
```

---

## PASO 0 — Preparar el servidor NFS

> Ejecutar en **nfs01** (`192.168.109.210`) antes de la clase

```bash
# Crear directorios de datos
mkdir -p /srv/nfs/k8s/prometheus
mkdir -p /srv/nfs/k8s/grafana

# Prometheus corre como UID 65534 (nobody)
chown 65534:65534 /srv/nfs/k8s/prometheus
chmod 755 /srv/nfs/k8s/prometheus

# Grafana corre como UID 472
chown 472:472 /srv/nfs/k8s/grafana
chmod 755 /srv/nfs/k8s/grafana

# Verificar
ls -la /srv/nfs/k8s/
```

---

## PASO 1 — Namespace

> **Concepto:** Todo el stack de monitoreo vive en su propio namespace.
> Aislamiento, permisos y limpieza sencilla.

```bash
cd /root/devops2026/10-monitoring

kubectl apply -f 01-namespace.yaml
kubectl get ns monitoring
```

---

## PASO 2 — RBAC para Prometheus

> **Concepto:** Prometheus necesita permisos para leer metadatos del cluster
> y hacer Service Discovery automático de Pods y nodos.

```bash
kubectl apply -f 02-prometheus-rbac.yaml

# Verificar los recursos creados
kubectl get serviceaccount prometheus -n monitoring
kubectl get clusterrole prometheus
kubectl get clusterrolebinding prometheus

# Ver qué permisos tiene el ClusterRole:
kubectl describe clusterrole prometheus
```

**Explicar en pizarra:**
```
Sin RBAC:  Prometheus → GET /api/v1/pods → 403 Forbidden
Con RBAC:  Prometheus → GET /api/v1/pods → 200 OK (lista de pods)
```

---

## PASO 3 — ConfigMap de Prometheus

> **Concepto:** La configuración de Prometheus (`prometheus.yml`) se monta
> desde un ConfigMap. Ventaja: cambiar la config sin reconstruir la imagen.

```bash
kubectl apply -f 03-prometheus-configmap.yaml

kubectl get cm prometheus-config -n monitoring
kubectl describe cm prometheus-config -n monitoring
```

**Señalar en el ConfigMap:**
- `scrape_interval: 15s` → cada 15s pide métricas a los targets
- `job_name: 'prometheus'` → se monitorea a sí mismo
- `job_name: 'node-exporter'` → descubre node-exporter via Kubernetes SD
- `job_name: 'kubernetes-pods'` → autodescubrimiento por annotations

**Mostrar el mecanismo de autodescubrimiento:**
```yaml
# Un Pod con estas annotations es descubierto automáticamente:
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
  prometheus.io/path: "/metrics"
```

---

## PASO 4 — Almacenamiento de Prometheus (PV + PVC)

> **Concepto:** Los datos TSDB de Prometheus deben persistir en NFS.
> Sin PVC perderíamos el historial de métricas al reiniciar el Pod.

```bash
kubectl apply -f 04-prometheus-storage.yaml

kubectl get pv pv-prometheus
kubectl get pvc pvc-prometheus -n monitoring

# Esperar a que el PVC quede en Bound
kubectl get pvc -n monitoring -w
```

**Señalar:**
- `accessModes: ReadWriteOnce` → Prometheus solo corre en 1 nodo
- `path: /srv/nfs/k8s/prometheus` → donde van los datos TSDB en el NFS
- `Retain` → al borrar el PVC, los datos NO se eliminan

---

## PASO 5 — Desplegar Prometheus

```bash
kubectl apply -f 05-prometheus-deployment.yaml

kubectl get pods -n monitoring -w    # esperar Running
kubectl get svc -n monitoring
```

**Verificar que levantó correctamente:**
```bash
kubectl logs -n monitoring deploy/prometheus | tail -20

# Acceder a la UI de Prometheus:
# http://192.168.109.200:30092

# O desde el servidor con port-forward:
kubectl port-forward -n monitoring svc/prometheus-svc 9090:9090 &
curl http://localhost:9090/-/healthy
kill %1
```

**Mostrar en la UI de Prometheus:**
1. `Status → Targets` → ver qué targets está scrapeando
2. Consulta: `up` → ver qué jobs están activos
3. Consulta: `prometheus_build_info` → info de la propia instancia

---

## PASO 6 — Node Exporter (DaemonSet)

> **Concepto:** DaemonSet garantiza que corra UN Pod en CADA nodo.
> Node Exporter expone métricas del SO: CPU, memoria, disco, red.

```bash
kubectl apply -f 06-node-exporter.yaml

# Ver el DaemonSet
kubectl get ds -n monitoring
kubectl get pods -n monitoring -o wide    # un Pod por nodo

# Ver métricas directamente en el nodo:
curl http://192.168.109.200:9100/metrics | grep node_cpu_seconds | head -5
curl http://192.168.109.201:9100/metrics | grep node_memory_MemAvailable | head -3
```

**Consultas en Prometheus UI (`http://192.168.109.200:30092`):**
```promql
# CPU usada por nodo (porcentaje)
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memoria disponible en bytes
node_memory_MemAvailable_bytes

# Memoria disponible en GB
node_memory_MemAvailable_bytes / 1024 / 1024 / 1024

# Espacio libre en disco
node_filesystem_avail_bytes{fstype!="tmpfs"}

# Tráfico de red recibido (bytes/s)
rate(node_network_receive_bytes_total[5m])
```

---

## PASO 7 — Almacenamiento de Grafana (PV + PVC)

```bash
kubectl apply -f 09-grafana-storage.yaml

kubectl get pv pv-grafana
kubectl get pvc pvc-grafana -n monitoring
```

**Señalar diferencia con Prometheus:**
- Prometheus: UID 65534 (nobody) → `chown 65534`
- Grafana: UID 472 (grafana) → `chown 472`
- Cada imagen tiene su propio usuario, hay que conocerlo para el NFS

---

## PASO 8 — Secret y ConfigMap de Grafana

> **Concepto:** Las credenciales van en un Secret. La configuración del
> datasource va en un ConfigMap. Separación de responsabilidades.

```bash
kubectl apply -f 07-grafana-secret.yaml
kubectl apply -f 08-grafana-datasource.yaml

# Ver el Secret (no muestra valores)
kubectl describe secret grafana-credentials -n monitoring

# Verificar que el datasource ConfigMap está bien
kubectl describe cm grafana-datasource -n monitoring
```

**Preguntar a la clase:**
> ¿Por qué las credenciales en un Secret y la URL de Prometheus en un ConfigMap?

Respuesta: la URL de Prometheus no es sensible (cualquiera puede verla).
La contraseña SÍ es sensible → Secret.

---

## PASO 9 — Desplegar Grafana

```bash
kubectl apply -f 10-grafana-deployment.yaml

kubectl get pods -n monitoring -w    # esperar Running (puede tardar ~30s)
kubectl get svc -n monitoring
```

**Verificar:**
```bash
kubectl logs -n monitoring deploy/grafana | tail -20
```

**Acceder a Grafana:**
```
URL:      http://192.168.109.200:30093
Usuario:  admin
Password: devops2026
```

---

## PASO 10 — Configurar Grafana (demo en UI)

### 10.1 Verificar el datasource automático

```
Home → Connections → Data Sources → Prometheus
```
→ Debe aparecer ya configurado (gracias al ConfigMap de provisioning).
→ Hacer clic en **"Test"** → verde = conectado con Prometheus.

### 10.2 Importar dashboard de Node Exporter

Grafana tiene miles de dashboards en https://grafana.com/grafana/dashboards/

```
Home → Dashboards → Import
→ ID: 1860   (Node Exporter Full - el más popular)
→ Load → seleccionar datasource: Prometheus → Import
```

**Mostrar en el dashboard:**
- CPU usage por nodo
- Memoria disponible
- Disco disponible
- Tráfico de red

### 10.3 Importar dashboard de Kubernetes

```
Home → Dashboards → Import
→ ID: 315    (Kubernetes cluster monitoring)
→ Load → seleccionar datasource: Prometheus → Import
```

### 10.4 Crear un panel personalizado (demo rápida)

```
Home → Dashboards → New → New Dashboard → Add visualization
→ Datasource: Prometheus
→ Metric: node_memory_MemAvailable_bytes
→ Legend: {{instance}}
→ Panel title: "Memoria disponible por nodo"
→ Apply → Save
```

---

## PASO 11 — Demostrar la Persistencia

> **El punto central de la clase:** los datos sobreviven al Pod.

```bash
# 1. Crear un panel o importar un dashboard en Grafana (UI)

# 2. Eliminar el Pod de Grafana
kubectl delete pod -n monitoring -l app=grafana
kubectl get pods -n monitoring -w   # el Deployment crea uno nuevo

# 3. Acceder a Grafana de nuevo
# http://192.168.109.200:30093
# → El dashboard que creamos sigue ahí (estaba en el NFS)

# Verificar en el NFS:
# En nfs01:
ls -la /srv/nfs/k8s/grafana/
ls -la /srv/nfs/k8s/prometheus/
```

---

## Resumen del estado del cluster al final

```bash
# Ver todo lo creado en el namespace monitoring
kubectl get all -n monitoring

# Ver el almacenamiento
kubectl get pv,pvc -n monitoring

# Ver el RBAC
kubectl get serviceaccount,clusterrole,clusterrolebinding -l app=prometheus
```

---

## Comandos de limpieza

```bash
# Borrar todo el stack de monitoreo
kubectl delete ns monitoring

# Esto elimina: Pods, Deployments, Services, ConfigMaps, Secrets, PVCs
# Los PVs quedan (política Retain) y los datos en NFS también

# Si quieres borrar también los PVs:
kubectl delete pv pv-prometheus pv-grafana

# Y los datos en NFS (en nfs01):
# rm -rf /srv/nfs/k8s/prometheus /srv/nfs/k8s/grafana
```

---

## Orden de despliegue (resumen para clase)

```bash
cd /root/devops2026/10-monitoring

# 1. Infraestructura base
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-prometheus-rbac.yaml

# 2. Configuración (ConfigMaps y Secrets)
kubectl apply -f 03-prometheus-configmap.yaml
kubectl apply -f 07-grafana-secret.yaml
kubectl apply -f 08-grafana-datasource.yaml

# 3. Almacenamiento (PV + PVC)
kubectl apply -f 04-prometheus-storage.yaml
kubectl apply -f 09-grafana-storage.yaml

# 4. Aplicaciones
kubectl apply -f 05-prometheus-deployment.yaml
kubectl apply -f 06-node-exporter.yaml
kubectl apply -f 10-grafana-deployment.yaml

# 5. Verificar todo
kubectl get all -n monitoring
kubectl get pv,pvc
```

---

## Dashboards recomendados para importar

| ID    | Nombre | Descripción |
|-------|--------|-------------|
| 1860  | Node Exporter Full | CPU, memoria, disco, red por nodo |
| 315   | Kubernetes cluster monitoring | Overview del cluster |
| 12740 | Kubernetes Monitoring | Pods, Deployments, Namespaces |
| 6417  | Kubernetes Pods | Métricas detalladas por Pod |

---

*Repositorio: https://github.com/dguerrero11/kubernetes-devops*
