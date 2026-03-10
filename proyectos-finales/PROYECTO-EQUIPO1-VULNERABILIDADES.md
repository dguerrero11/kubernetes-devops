# Proyecto Final — Equipo 1
# Análisis de Vulnerabilidades y Auditoría de Seguridad en Kubernetes

**Diplomado:** Seguridad en Infraestructura y Kubernetes
**Duración estimada:** 2 semanas
**Integrantes:** 3 personas
**Stack de observabilidad asignado:** PLG (Prometheus + Loki + Grafana)

---

## Objetivo general

Realizar una auditoría completa de seguridad sobre un cluster de Kubernetes,
identificar vulnerabilidades en configuración e imágenes, implementar detección
de amenazas en tiempo real y presentar un plan de remediación priorizado.

---

## Alcance del proyecto

### Módulo 1 — Auditoría de configuración del cluster (CIS Benchmark)

**Herramienta:** `kube-bench`

Instalar y ejecutar kube-bench como Job en Kubernetes:

```bash
# Ejecutar kube-bench como Job
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml

# Ver resultados
kubectl logs job/kube-bench
```

**Entregables del módulo:**
- Tabla de resultados: total de PASS / FAIL / WARN por categoría
  - 1. Master Node Security Configuration
  - 2. Etcd Node Configuration
  - 3. Control Plane Configuration
  - 4. Worker Node Security Configuration
  - 5. Kubernetes Policies
- Top 5 hallazgos críticos (FAIL) con descripción del riesgo
- Plan de remediación para cada hallazgo crítico

---

### Módulo 2 — Análisis de vulnerabilidades en imágenes

**Herramienta:** `Trivy`

```bash
# Instalar Trivy en el nodo master
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Escanear imágenes usadas en el cluster
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u > imagenes.txt

# Escanear cada imagen
trivy image nginx:1.25
trivy image --severity HIGH,CRITICAL nginx:1.25

# Escanear el filesystem del cluster
trivy k8s --report summary cluster
```

**Entregables del módulo:**
- Lista de imágenes escaneadas (todas las que corren en el cluster)
- Tabla de CVEs encontrados organizados por: CRÍTICO / ALTO / MEDIO / BAJO
- Mínimo 3 imágenes escaneadas con reporte completo
- Propuesta de imágenes alternativas más seguras para los hallazgos críticos

---

### Módulo 3 — Pentesting del cluster

**Herramienta:** `kube-hunter`

```bash
# Ejecutar kube-hunter desde dentro del cluster (simula pod comprometido)
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-hunter/main/job.yaml

# Ejecutar desde fuera del cluster (simula atacante externo)
pip3 install kube-hunter
kube-hunter --remote 192.168.109.200
```

**Entregables del módulo:**
- Reporte de vulnerabilidades encontradas desde **dentro** del cluster
- Reporte de vulnerabilidades encontradas desde **fuera** del cluster
- Clasificación por severidad: High / Medium / Low
- Análisis: ¿qué podría hacer un atacante con cada vulnerabilidad encontrada?

---

### Módulo 4 — Detección de amenazas en runtime

**Herramienta:** `Falco`

```bash
# Instalar Falco como DaemonSet
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falcosidekick.enabled=true \
  --set falcosidekick.webui.enabled=true
```

**Reglas a demostrar (al menos 3 de las siguientes):**
```
✅ Terminal shell en contenedor      → kubectl exec -it <pod> -- /bin/sh
✅ Lectura de archivo sensible       → kubectl exec <pod> -- cat /etc/shadow
✅ Escritura en directorio del sistema → kubectl exec <pod> -- touch /etc/malware
✅ Proceso inesperado en contenedor  → kubectl exec <pod> -- wget http://...
✅ Montaje de hostPath sospechoso    → pod con hostPath: /etc montado
```

**Entregables del módulo:**
- Falco corriendo como DaemonSet (captura screenshot de pods Running)
- Demo en vivo: ejecutar acción sospechosa → ver alerta en logs de Falco
- Al menos 3 reglas de Falco disparadas con evidencia (logs)
- Propuesta de 2 reglas personalizadas relevantes para el entorno

---

### Módulo 5 — Observabilidad: Stack PLG

**Tecnología asignada:** Prometheus + Loki + Grafana

#### 5a. Prometheus + Grafana (métricas de seguridad)

Extender el setup de clase 10 con dashboards de seguridad:

```bash
# Verificar que Prometheus y Grafana están corriendo
kubectl get pods -n monitoring

# Importar dashboard de seguridad en Grafana:
# - ID 15757: Kubernetes Security Dashboard
# - ID 13770: Kubernetes All-in-one Cluster Monitoring

# Configurar alertas en Alertmanager para:
# - Pod corriendo como root
# - Imagen con :latest tag
# - Recurso sin ResourceLimits definidos
```

#### 5b. Loki + Promtail (logging centralizado)

```bash
# Instalar Loki Stack
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set prometheus.enabled=false \
  --set loki.persistence.enabled=true \
  --set loki.persistence.storageClassName=nfs-manual \
  --set loki.persistence.size=5Gi

# Promtail recolecta logs de todos los pods automáticamente
# Configurar en Grafana: datasource Loki → http://loki:3100
```

**Entregables del módulo:**
- Dashboard Grafana con métricas de seguridad del cluster
- Alertmanager configurado con al menos 2 alertas de seguridad
- Loki + Promtail corriendo: logs de TODOS los pods visibles en Grafana
- Demo: buscar en Grafana/Loki los logs de los eventos de Falco
- Query de Loki útil: `{namespace="falco"} |= "Warning"` para ver alertas

---

## Entregables finales del Equipo 1

```
Documentación:
  □ Reporte ejecutivo de seguridad (PDF/MD, máx 10 páginas)
  □ Tabla consolidada de hallazgos con severidad y remediación
  □ Diagrama de arquitectura del stack de observabilidad

Técnico (en el cluster):
  □ kube-bench: Job ejecutado, resultados guardados
  □ Trivy: reportes de imágenes en archivo
  □ kube-hunter: reportes interno y externo
  □ Falco: DaemonSet corriendo con al menos 3 reglas disparadas
  □ Loki + Promtail: logs centralizados en Grafana
  □ Dashboard Grafana: métricas de seguridad visibles

Presentación (15 minutos):
  □ 5 min — Resumen de hallazgos más críticos
  □ 5 min — Demo en vivo (Falco detectando amenaza)
  □ 5 min — Dashboard Grafana/Loki en vivo
```

---

## Stack de observabilidad — Resumen técnico

```
                    GRAFANA (UI unificada)
                   /          |          \
                  /           |           \
           Prometheus       Loki        Alertmanager
               |              |              |
          Node Exporter    Promtail       Alertas por
          Falco Exporter   (todos los     email/slack
          kube-state-      pods del
          metrics          cluster)
```

| Componente | Namespace | Puerto |
|---|---|---|
| Prometheus | monitoring | 9090 (interno) |
| Grafana | monitoring | NodePort 30093 |
| Loki | monitoring | 3100 (interno) |
| Promtail | monitoring | DaemonSet |
| Falco | falco | DaemonSet |

---

## Recursos de apoyo

- kube-bench: https://github.com/aquasecurity/kube-bench
- Trivy: https://github.com/aquasecurity/trivy
- kube-hunter: https://github.com/aquasecurity/kube-hunter
- Falco: https://falco.org/docs/
- Loki: https://grafana.com/docs/loki/latest/
- CIS Kubernetes Benchmark: https://www.cisecurity.org/benchmark/kubernetes
