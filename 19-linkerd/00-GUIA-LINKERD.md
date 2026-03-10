# Módulo 19: Service Mesh con Linkerd

## ¿Qué problema resuelve un Service Mesh?

```
SIN Service Mesh:                     CON Service Mesh (sidecar):

  Pod A ────────────────────► Pod B     Pod A                  Pod B
  (app)   HTTP plano           (app)    ┌──────────────┐       ┌──────────────┐
          sin cifrar                    │  app │ envoy  │──────▶│ envoy │ app  │
          sin métricas L7              └──────────────┘  mTLS └──────────────┘
          sin retries                   proxy Linkerd           proxy Linkerd
          sin timeouts
                                       ✔ mTLS automático (zero config)
                                       ✔ Métricas golden signals por ruta
                                       ✔ Retries y timeouts declarativos
                                       ✔ Traffic splitting (canary)
                                       ✔ Dashboard en tiempo real
```

## Arquitectura del módulo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CLUSTER K8S — MÓDULO 19                             │
│                                                                             │
│  Namespace: linkerd (control plane)                                         │
│  ┌───────────────────────────────────────────┐                             │
│  │  linkerd-proxy-injector  linkerd-identity  │  ← Gestión de mTLS         │
│  │  linkerd-destination     linkerd-sp-validator│ ← Routing y ServiceProfile│
│  └───────────────────────────────────────────┘                             │
│                                                                             │
│  Namespace: linkerd-viz (dashboard)                                         │
│  ┌───────────────────────────────────────────┐                             │
│  │  web (dashboard UI)   tap (live traffic)  │  ← NodePort 30099          │
│  │  prometheus           grafana             │  ← Métricas L7             │
│  └───────────────────────────────────────────┘                             │
│                                                                             │
│  Namespace: linkerd-demo (app demo — auto-inject habilitado)                │
│  ┌────────────────────────────────────────────────────────────┐            │
│  │  frontend ──────────► backend-svc                          │            │
│  │  (nginx)               │                                   │            │
│  │                        ├──► backend-v1-svc (90%)           │            │
│  │                        └──► backend-v2-svc (10% canary)    │            │
│  │                                                            │            │
│  │  Cada pod: [app container] + [linkerd-proxy sidecar]       │            │
│  └────────────────────────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Versiones

| Componente       | Versión         |
|------------------|-----------------|
| Linkerd CLI      | stable-2.14.10  |
| Linkerd Viz      | incluido en CLI |
| Kubernetes       | 1.28.x          |
| NodePort Viz     | 30099           |

---

## Paso 0 (Opcional): Agregar un Worker Node

> **¿Cuándo aplicar este paso?**
> Linkerd es muy ligero (~200MB RAM en control plane, ~25MB por sidecar).
> Con 2 workers de 4GB+ RAM el cluster existente es suficiente.
> Solo agrega un tercer nodo si los workers tienen menos de 2GB disponibles
> o si quieres practicar la incorporación de nodos al cluster.

### Verificar recursos actuales

```bash
# Desde el master
kubectl get nodes
kubectl top nodes    # requiere metrics-server instalado
free -h              # en cada worker via SSH
```

### Crear la VM (VMware/VirtualBox)

```
Nombre:   k8s-worker03
SO:       Rocky Linux 9.6 (minimal)
CPU:      2 vCPUs
RAM:      4 GB
Disco:    30 GB
Red:      192.168.109.203 (misma red que el resto del cluster)
```

### Configuración inicial de la VM (como root)

```bash
# 1. Hostname e /etc/hosts
hostnamectl set-hostname k8s-worker03

cat >> /etc/hosts << 'EOF'
192.168.109.200  k8s-master01
192.168.109.201  k8s-worker01
192.168.109.202  k8s-worker02
192.168.109.203  k8s-worker03
EOF

# 2. Deshabilitar swap (requisito de K8s)
swapoff -a
sed -i '/swap/d' /etc/fstab

# 3. Deshabilitar SELinux
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 4. Deshabilitar firewall (entorno de clase)
systemctl disable --now firewalld

# 5. Módulos del kernel
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# 6. Parámetros de red
cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
```

### Instalar containerd

```bash
# Repositorio Docker CE
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y containerd.io

# Configuración
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl enable --now containerd
```

### Instalar kubeadm, kubelet, kubectl

```bash
cat > /etc/yum.repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

dnf install -y kubelet-1.28.15 kubeadm-1.28.15 kubectl-1.28.15
systemctl enable kubelet
```

### Unirse al cluster (desde el master: generar token fresco)

```bash
# En el MASTER — el token original expira en 24h, generar uno nuevo:
kubeadm token create --print-join-command
# Copia el comando completo que aparece

# En el NUEVO WORKER (k8s-worker03) — pega el comando del master:
kubeadm join 192.168.109.200:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

### Verificar desde el master

```bash
kubectl get nodes
# NAME            STATUS   ROLES           AGE   VERSION
# k8s-master01    Ready    control-plane   ...   v1.28.15
# k8s-worker01    Ready    <none>          ...   v1.28.15
# k8s-worker02    Ready    <none>          ...   v1.28.15
# k8s-worker03    Ready    <none>          ...   v1.28.15  ← nuevo
```

---

## Paso 1: Instalar Linkerd CLI (en el master)

```bash
# Descargar la CLI de Linkerd
export LINKERD_VERSION=stable-2.14.10
curl -sL "https://github.com/linkerd/linkerd2/releases/download/${LINKERD_VERSION}/linkerd2-cli-${LINKERD_VERSION}-linux-amd64" \
  -o /usr/local/bin/linkerd

chmod +x /usr/local/bin/linkerd

# Verificar
linkerd version --client
# Client version: stable-2.14.10
```

---

## Paso 2: Pre-flight check

```bash
# Verifica que el cluster cumple todos los requisitos de Linkerd
linkerd check --pre
```

Salida esperada (todo en ✔):
```
kubernetes-api
--------------
✔ can initialize the client
✔ can query the Kubernetes API

kubernetes-version
------------------
✔ is running the minimum Kubernetes API version

pre-kubernetes-setup
--------------------
✔ control plane namespace does not already exist
✔ can create Namespaces
...
Status check results are √
```

> Si algo falla, el mensaje indica exactamente qué corregir.

---

## Paso 3: Instalar el Control Plane de Linkerd

```bash
# Instalar CRDs de Linkerd
linkerd install --crds | kubectl apply -f -

# Instalar el control plane
linkerd install | kubectl apply -f -

# Esperar a que todo esté listo (~2 minutos)
linkerd check
```

```bash
# Ver los pods del control plane
kubectl get pods -n linkerd
# NAME                                     READY   STATUS    RESTARTS
# linkerd-destination-xxx                  4/4     Running   0
# linkerd-identity-xxx                     2/2     Running   0
# linkerd-proxy-injector-xxx               2/2     Running   0
```

### ¿Qué instaló Linkerd?

| Componente              | Función                                          |
|-------------------------|--------------------------------------------------|
| `linkerd-identity`      | Emite certificados mTLS a cada proxy             |
| `linkerd-destination`   | Resuelve endpoints y aplica políticas de routing |
| `linkerd-proxy-injector`| Inyecta el sidecar en pods automáticamente       |

---

## Paso 4: Instalar Linkerd Viz (Dashboard + Métricas)

```bash
# Instalar la extensión de visualización
linkerd viz install | kubectl apply -f -

# Verificar
linkerd viz check
```

```bash
kubectl get pods -n linkerd-viz
# NAME                            READY   STATUS    RESTARTS
# grafana-xxx                     1/1     Running   0
# metrics-api-xxx                 2/2     Running   0
# prometheus-xxx                  2/2     Running   0
# tap-xxx                         2/2     Running   0
# tap-injector-xxx                2/2     Running   0
# web-xxx                         2/2     Running   0
```

### Exponer el dashboard via NodePort

```bash
# Aplicar el NodePort del dashboard (archivo 06-linkerd-viz-nodeport.yaml)
kubectl apply -f 06-linkerd-viz-nodeport.yaml

# Acceder al dashboard
# http://192.168.109.200:30099
# http://192.168.109.201:30099
```

> El dashboard también puede abrirse directamente con: `linkerd viz dashboard &`
> (hace port-forward automático)

---

## Paso 5: Desplegar la App de Demo

```bash
# Crear el namespace con inyección automática habilitada
kubectl apply -f 01-demo-namespace.yaml

# Verificar el label de inyección
kubectl get namespace linkerd-demo --show-labels
# linkerd.io/inject=enabled ← Linkerd inyectará el sidecar en todos los pods

# Desplegar la app completa
kubectl apply -f 02-demo-app.yaml

# Verificar pods (cada pod tiene 2 contenedores: app + linkerd-proxy)
kubectl get pods -n linkerd-demo
# NAME                           READY   STATUS    RESTARTS
# frontend-xxx                   2/2     Running   0   ← 2/2 = app + proxy
# backend-v1-xxx                 2/2     Running   0
# backend-v2-xxx                 2/2     Running   0
```

### Verificar que el sidecar fue inyectado

```bash
kubectl describe pod -n linkerd-demo -l app=frontend | grep "linkerd-proxy"
# linkerd-proxy:
#   Image: cr.l5d.io/linkerd/proxy:stable-2.14.10
```

---

## Paso 6: Verificar mTLS Automático

> **Concepto clave**: Linkerd cifra automáticamente TODO el tráfico entre pods
> que tienen el sidecar inyectado. Sin configuración adicional.

```bash
# Ver el estado de mTLS entre servicios
linkerd viz edges deployment -n linkerd-demo

# Salida:
# SRC          DST            SRC_NS        DST_NS        SECURED
# frontend     backend-v1     linkerd-demo  linkerd-demo  √ (mTLS)
# frontend     backend-v2     linkerd-demo  linkerd-demo  √ (mTLS)
# prometheus   frontend       linkerd-viz   linkerd-demo  √ (mTLS)
```

```bash
# Ver las rutas de tráfico en tiempo real (Golden Signals)
linkerd viz stat deployment -n linkerd-demo

# NAME         MESHED   SUCCESS      RPS   LATENCY_P50   LATENCY_P99
# frontend       1/1   100.00%   1.2rps           1ms         10ms
# backend-v1     1/1   100.00%   0.9rps           1ms          5ms
# backend-v2     1/1   100.00%   0.3rps           1ms          5ms
```

### Generar tráfico para ver métricas

```bash
# Generar tráfico desde dentro del cluster
kubectl run -n linkerd-demo -it --rm curl-test \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- sh -c 'while true; do curl -s http://frontend-svc:80/; sleep 0.5; done'
```

En otra terminal, observar las métricas en tiempo real:
```bash
watch -n 1 linkerd viz stat deployment -n linkerd-demo
```

---

## Paso 7: Traffic Splitting — Canary Deployment

> **Objetivo**: Enviar el 90% del tráfico a backend-v1 (estable)
> y el 10% a backend-v2 (nueva versión en prueba)

```
frontend-svc ──► backend-svc (HTTPRoute)
                      │
                      ├──► backend-v1-svc  (weight: 90)  → "Backend V1 - Estable"
                      └──► backend-v2-svc  (weight: 10)  → "Backend V2 - Canary"
```

```bash
# Aplicar el HTTPRoute de traffic splitting
kubectl apply -f 03-traffic-split.yaml

# Verificar el HTTPRoute
kubectl get httproute -n linkerd-demo
kubectl describe httproute backend-traffic-split -n linkerd-demo
```

### Verificar la distribución de tráfico

```bash
# Generar tráfico y contar respuestas de cada versión
kubectl run -n linkerd-demo -it --rm traffic-gen \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- sh -c 'for i in $(seq 1 100); do curl -s http://frontend-svc:80/; done | sort | uniq -c'

# Resultado esperado (aproximado):
#   90 Backend V1 - Estable
#   10 Backend V2 - Canary
```

```bash
# Ver distribución en tiempo real con Linkerd viz
linkerd viz stat deployment -n linkerd-demo
# backend-v1   1/1   99.00%   0.9rps   1ms   5ms
# backend-v2   1/1  100.00%   0.1rps   1ms   5ms
```

### Ajustar el split en tiempo real

```bash
# Subir al 50% la nueva versión (editar el weight en 03-traffic-split.yaml)
# weight: 50 en ambos backendRefs
kubectl apply -f 03-traffic-split.yaml

# Verificar de nuevo
linkerd viz stat deployment -n linkerd-demo
```

---

## Paso 8: Retries y Timeouts con ServiceProfile

> **ServiceProfile** es el CRD de Linkerd para definir el comportamiento
> por ruta HTTP: timeouts, retries, y clasificación de errores.

```bash
# Aplicar el ServiceProfile
kubectl apply -f 04-service-profile.yaml

# Verificar
kubectl get serviceprofile -n linkerd-demo
kubectl describe serviceprofile backend-svc.linkerd-demo.svc.cluster.local -n linkerd-demo
```

### ¿Qué define el ServiceProfile?

```
Ruta: GET /api/data
  ├── Timeout: 500ms      → si backend tarda más, el proxy cancela y retorna error
  ├── Retry budget: 20%   → puede reintentar hasta 20% de las solicitudes fallidas
  └── isFailure: 5xx      → Linkerd clasifica 5xx como errores para métricas
```

```bash
# Ver rutas y métricas por ruta (requiere ServiceProfile)
linkerd viz routes deployment/backend-v1 -n linkerd-demo
# ROUTE            SERVICE        SUCCESS      RPS   LATENCY_P50   LATENCY_P99
# GET /api/data    backend-svc   100.00%   0.9rps           1ms         10ms
# [DEFAULT]        backend-svc    99.00%   0.1rps           1ms          5ms
```

---

## Paso 9: Fault Injection — Demo de Resiliencia

> Desplegamos un backend que falla el 100% de las veces.
> Luego habilitamos retries para ver cómo Linkerd los absorbe.

```bash
# Desplegar el servicio que falla
kubectl apply -f 05-fault-injection.yaml

# Verificar que falla
kubectl run -n linkerd-demo -it --rm test-fail \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- curl -sv http://backend-failing-svc:8080/

# Debe retornar HTTP 500
```

### Redirigir tráfico al backend con fallos

```bash
# Editar 03-traffic-split.yaml temporalmente para enviar 30% al backend-failing
# backendRefs:
#   - name: backend-v1-svc     weight: 70
#   - name: backend-failing-svc weight: 30
kubectl apply -f 03-traffic-split.yaml
```

### Observar los errores en el dashboard

```bash
# Ver success rate caer en tiempo real
watch -n 1 "linkerd viz stat deployment -n linkerd-demo"

# En el dashboard web también se ve el success rate bajar
# http://192.168.109.200:30099
```

### Habilitar retries para absorber los fallos

```bash
# El ServiceProfile ya tiene retry budget configurado.
# Verificar en las métricas que el success rate mejora:
linkerd viz routes deployment/frontend -n linkerd-demo --to service/backend-svc

# Con retries habilitados, Linkerd reintenta las solicitudes fallidas
# El success rate efectivo sube aunque el backend falle.
```

### Restaurar el tráfico normal

```bash
# Volver al 03-traffic-split.yaml original (90/10 entre v1 y v2)
kubectl apply -f 03-traffic-split.yaml
kubectl delete -f 05-fault-injection.yaml
```

---

## Paso 10: Dashboard y Golden Metrics

### Linkerd Viz Dashboard

Abrir en el navegador: **http://192.168.109.200:30099**

```
Namespace: linkerd-demo
  │
  ├── Deployments
  │     frontend    ✔ meshed  100% success  1.2 RPS  p99=10ms
  │     backend-v1  ✔ meshed  100% success  0.9 RPS  p99=5ms
  │     backend-v2  ✔ meshed  100% success  0.1 RPS  p99=5ms
  │
  ├── Services
  │     frontend-svc
  │     backend-svc  → [HTTPRoute: 90% v1, 10% v2]
  │
  └── Live Traffic (TAP)
        Ver solicitudes individuales en tiempo real
        con src, dst, método HTTP, path, status, latencia
```

### Golden Signals disponibles por servicio

| Metric     | Comando                                     |
|------------|---------------------------------------------|
| Success rate | `linkerd viz stat deployment -n linkerd-demo` |
| RPS        | incluido en el anterior                     |
| Latencia P50/P99 | incluido en el anterior              |
| Por ruta   | `linkerd viz routes svc/backend-svc -n linkerd-demo` |
| Edges mTLS | `linkerd viz edges deployment -n linkerd-demo` |

### Live traffic inspection (TAP)

```bash
# Ver solicitudes HTTP en tiempo real entre frontend y backend
linkerd viz tap deployment/frontend -n linkerd-demo \
  --to service/backend-svc \
  --method GET

# Salida en tiempo real:
# req id=0:0 proxy=out src=10.244.1.5:54321 dst=backend-v1-svc:8080 ...
#   :method=GET :authority=backend-svc:8080 :path=/api/data
# rsp id=0:0 proxy=out src=10.244.1.5:54321 dst=backend-v1-svc:8080 ...
#   :status=200 latency=1234µs
```

---

## Resumen de conceptos cubiertos

| Concepto             | Mecanismo Linkerd          | Demo                          |
|----------------------|----------------------------|-------------------------------|
| mTLS automático      | linkerd-identity + proxy   | `linkerd viz edges`           |
| Traffic splitting    | HTTPRoute (policy API)     | 90% v1 / 10% v2              |
| Retries              | ServiceProfile retryBudget | Absorber fallos del backend   |
| Timeouts             | ServiceProfile timeout     | 500ms por ruta                |
| Golden signals L7    | linkerd-proxy métricas     | Dashboard + `viz stat`        |
| Live traffic (TAP)   | linkerd-tap                | `linkerd viz tap`             |

---

## Limpieza (opcional al final de la clase)

```bash
# Eliminar la app demo
kubectl delete -f 05-fault-injection.yaml --ignore-not-found
kubectl delete -f 04-service-profile.yaml
kubectl delete -f 03-traffic-split.yaml
kubectl delete -f 02-demo-app.yaml
kubectl delete -f 01-demo-namespace.yaml

# Eliminar Linkerd Viz
linkerd viz uninstall | kubectl delete -f -

# Eliminar Linkerd control plane
linkerd uninstall | kubectl delete -f -
```

---

## Referencia de puertos

| Servicio              | NodePort | URL                            |
|-----------------------|----------|--------------------------------|
| Linkerd Viz Dashboard | 30099    | http://192.168.109.200:30099   |
| Frontend Demo App     | 30100    | http://192.168.109.200:30100   |
