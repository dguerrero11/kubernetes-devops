# Proyecto Final — Equipo 2
# Despliegue Seguro de Aplicación Multi-Capa en Kubernetes

**Diplomado:** Seguridad en Infraestructura y Kubernetes
**Duración estimada:** 2 semanas
**Integrantes:** 3 personas
**Stack de observabilidad asignado:** EFK (Elasticsearch + Fluentd + Kibana)

---

## Objetivo general

Desplegar una aplicación web multi-capa (WordPress + MySQL) aplicando todos
los controles de seguridad disponibles en Kubernetes (clases 00-08), demostrando
que cada capa del stack está protegida según las mejores prácticas, y habilitando
observabilidad completa con el stack EFK.

---

## Arquitectura objetivo

```
  Internet
     │
     ▼
  Ingress (HTTPS / TLS)
     │
     ▼
  Service ClusterIP
     │
     ▼
  WordPress Deployment ──────────────────────────────────────────┐
  (namespace: proyecto-web)                                      │
  - SecurityContext: runAsNonRoot, readOnlyFS                    │
  - Resources: requests + limits                                 │
  - ConfigMap: configuración WP                                  │
  - Secret: credenciales DB                                      │
     │                                                           │
     │ NetworkPolicy: solo WordPress→MySQL                       │
     ▼                                                           │
  MySQL Deployment                                               │
  (namespace: proyecto-web)                                      │
  - SecurityContext completo                                     │
  - Secret: root password + app password                        │
  - PVC → NFS Storage                                           │
     │                                                           │
     ▼                                                           ▼
  PersistentVolume (NFS)                                 EFK Stack (logging)
  192.168.109.210:/srv/nfs/k8s/proyecto-web              (namespace: logging)
```

---

## Alcance del proyecto

### Módulo 1 — Namespaces y control de recursos

```yaml
# Crear namespace dedicado
kubectl create namespace proyecto-web

# Aplicar ResourceQuota al namespace
apiVersion: v1
kind: ResourceQuota
metadata:
  name: proyecto-quota
  namespace: proyecto-web
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
    secrets: "10"
    persistentvolumeclaims: "5"

# Aplicar LimitRange (valores por defecto para todos los pods)
apiVersion: v1
kind: LimitRange
metadata:
  name: proyecto-limits
  namespace: proyecto-web
spec:
  limits:
    - type: Container
      default:
        cpu: "200m"
        memory: "256Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "1"
        memory: "1Gi"
```

**Entregables del módulo:**
- ResourceQuota y LimitRange aplicados y verificados
- `kubectl describe namespace proyecto-web` mostrando los límites
- `kubectl describe resourcequota -n proyecto-web` con usage vs limits

---

### Módulo 2 — Gestión segura de credenciales

**Requisito:** NINGUNA credencial en texto plano en los manifests YAML

```bash
# Crear Secrets para MySQL
kubectl create secret generic mysql-credentials \
  --from-literal=MYSQL_ROOT_PASSWORD=<root-pass> \
  --from-literal=MYSQL_DATABASE=wordpress \
  --from-literal=MYSQL_USER=wpuser \
  --from-literal=MYSQL_PASSWORD=<wp-pass> \
  --namespace proyecto-web

# Crear ConfigMap para WordPress
kubectl create configmap wordpress-config \
  --from-literal=WORDPRESS_DB_HOST=mysql-service \
  --from-literal=WORDPRESS_DB_NAME=wordpress \
  --namespace proyecto-web

# Verificar que el secret está codificado (no en texto)
kubectl get secret mysql-credentials -n proyecto-web -o yaml
# → data: MYSQL_ROOT_PASSWORD: <base64> (NO debe verse el valor real)
```

**Entregables del módulo:**
- Secrets creados y usados como variables de entorno (envFrom o env.valueFrom)
- Demostrar que borrando el pod, los datos persisten (MySQL en PVC)
- Demostrar que el Secret no está en texto plano en ningún YAML del repo

---

### Módulo 3 — Storage persistente para MySQL

```yaml
# PV en NFS
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-mysql-proyecto
spec:
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-manual
  nfs:
    server: 192.168.109.210
    path: /srv/nfs/k8s/proyecto-web/mysql

# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-mysql
  namespace: proyecto-web
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: nfs-manual
  resources:
    requests:
      storage: 5Gi
```

**Entregables del módulo:**
- PV y PVC en estado Bound
- Datos de WordPress persistiendo al eliminar y recrear el pod de MySQL

---

### Módulo 4 — Security Context en todos los pods

Aplicar SecurityContext tanto al Deployment de WordPress como al de MySQL:

```yaml
# En cada Deployment:
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
```

> Nota: Para WordPress usar imagen `wordpress:6.4-apache` y ajustar según sea necesario.
> Para MySQL usar `mysql:8.0` — verificar que el SecurityContext no rompa el inicio.

**Entregables del módulo:**
- Ambos pods corriendo con SecurityContext aplicado
- `kubectl exec <pod> -- id` mostrando UID 1000 (no root)
- Si algún SecurityContext debe relajarse, documentar el motivo técnico

---

### Módulo 5 — NetworkPolicy: aislamiento entre capas

```yaml
# Política 1: deny-all en el namespace
# Política 2: WordPress puede salir hacia MySQL (egress)
# Política 3: MySQL solo acepta conexiones desde WordPress (ingress)
# Política 4: Ingress controller puede llegar a WordPress
# Política 5: allow-egress-dns (para resolución de nombres)
```

**Demostrar:**
```bash
# Desde un pod externo (namespace default) — NO puede llegar a MySQL
kubectl run test-ext --image=alpine --restart=Never -- sleep 60
kubectl exec test-ext -- nc -zv mysql-service.proyecto-web.svc.cluster.local 3306
# → Timeout / Connection refused ✅

# WordPress SÍ puede llegar a MySQL (misma NetworkPolicy)
kubectl exec <wordpress-pod> -n proyecto-web -- nc -zv mysql-service 3306
# → open ✅
```

**Entregables del módulo:**
- 5 NetworkPolicies aplicadas y documentadas
- Demo: acceso externo a MySQL bloqueado
- Demo: acceso WordPress → MySQL permitido
- Diagrama de NetworkPolicies (quién puede hablar con quién)

---

### Módulo 6 — Ingress con TLS

```bash
# Crear certificado auto-firmado para la demo
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=wordpress.192.168.109.200.nip.io/O=proyecto-web"

# Crear Secret TLS en K8s
kubectl create secret tls wordpress-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n proyecto-web

# Configurar Ingress con TLS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wordpress-ingress
  namespace: proyecto-web
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
    - hosts:
        - wordpress.192.168.109.200.nip.io
      secretName: wordpress-tls
  rules:
    - host: wordpress.192.168.109.200.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: wordpress-service
                port:
                  number: 80
```

**Entregables del módulo:**
- WordPress accesible en https://wordpress.192.168.109.200.nip.io
- Certificado TLS válido (aunque sea self-signed para la demo)
- HTTP redirige automáticamente a HTTPS

---

### Módulo 7 — RBAC para el namespace

```yaml
# ServiceAccount para WordPress
# Role: solo puede leer Secrets y ConfigMaps propios
# RoleBinding: SA del pod de WordPress → Role limitado
# Demo: el pod NO puede listar pods de otros namespaces
```

**Entregables del módulo:**
- ServiceAccount dedicado para WordPress con mínimos privilegios
- `kubectl auth can-i list pods -n kube-system --as system:serviceaccount:proyecto-web:wordpress-sa`
- → `no` (no tiene acceso fuera de su namespace)

---

### Módulo 8 — Observabilidad: Stack EFK

**Tecnología asignada:** Elasticsearch + Fluentd + Kibana

#### 8a. Desplegar Elasticsearch

```bash
# Namespace dedicado para logging
kubectl create namespace logging

# Elasticsearch (versión 8.x, single node para demo)
# IMPORTANTE: xpack.security.enabled=false para simplificar demo
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: elasticsearch
  namespace: logging
spec:
  replicas: 1
  selector:
    matchLabels:
      app: elasticsearch
  template:
    metadata:
      labels:
        app: elasticsearch
    spec:
      containers:
        - name: elasticsearch
          image: elasticsearch:8.11.0
          env:
            - name: discovery.type
              value: single-node
            - name: xpack.security.enabled
              value: "false"
            - name: ES_JAVA_OPTS
              value: "-Xms512m -Xmx512m"
          resources:
            requests:
              memory: "1Gi"
            limits:
              memory: "2Gi"
          ports:
            - containerPort: 9200
EOF
```

#### 8b. Desplegar Fluentd como DaemonSet

```bash
# Fluentd recolecta logs de todos los pods del cluster
# Configurar output hacia Elasticsearch
# Usar ConfigMap para la configuración de Fluentd
```

#### 8c. Desplegar Kibana

```bash
# NodePort para acceso externo
# Conectar a Elasticsearch
# Crear Index Pattern: fluentd-*
```

**Entregables del módulo:**
- EFK Stack corriendo en namespace `logging`
- Kibana accesible en NodePort 30099
- Index pattern configurado: logs de todos los pods visibles en Kibana
- Dashboard Kibana con:
  - Logs de WordPress filtrados por namespace
  - Logs de MySQL filtrados
  - Conteo de errores HTTP 5xx de WordPress
- Demo: generar un error en WordPress → verlo en Kibana en tiempo real

---

## Entregables finales del Equipo 2

```
Documentación:
  □ Diagrama de arquitectura completo (con todos los controles de seguridad)
  □ Documento: "controles de seguridad aplicados y justificación"
  □ Inventario de Secrets: qué contiene cada uno (sin revelar valores)

Técnico (en el cluster):
  □ WordPress + MySQL corriendo y accesibles via HTTPS
  □ 5 NetworkPolicies aplicadas y verificadas
  □ ResourceQuota y LimitRange en el namespace
  □ SecurityContext en todos los pods
  □ PVC con datos persistentes (demo: borrar pod → datos persisten)
  □ EFK Stack corriendo con logs centralizados en Kibana

Presentación (15 minutos):
  □ 5 min — Demo: WordPress funcionando en HTTPS
  □ 5 min — Demo: acceso externo a MySQL bloqueado + logs en Kibana
  □ 5 min — Revisión de controles de seguridad aplicados
```

---

## Stack de observabilidad — Resumen técnico

```
  Todos los pods del cluster
         │
         │ logs (stdout/stderr)
         ▼
      Fluentd (DaemonSet)
         │
         │ envía logs parseados
         ▼
   Elasticsearch (Deployment)
         │
         │ almacena y indexa
         ▼
      Kibana (UI)
      NodePort 30099
         │
         ▼
   Dashboards + Alertas
   - Logs de WordPress
   - Logs de MySQL
   - Errores de aplicación
   - Eventos de seguridad K8s
```

| Componente | Namespace | Puerto |
|---|---|---|
| Elasticsearch | logging | 9200 (interno) |
| Fluentd | logging | DaemonSet |
| Kibana | logging | NodePort 30099 |
| WordPress | proyecto-web | via Ingress HTTPS |
| MySQL | proyecto-web | 3306 (interno) |

---

## Recursos de apoyo

- EFK Stack K8s: https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes
- WordPress en K8s: https://kubernetes.io/docs/tutorials/stateful-application/mysql-wordpress-persistent-volume/
- NetworkPolicies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Ingress TLS: https://kubernetes.io/docs/concepts/services-networking/ingress/#tls
