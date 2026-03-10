# Proyecto Final — Equipo 3
# Integración de Identidad: Keycloak + OIDC + Kubernetes RBAC

**Diplomado:** Seguridad en Infraestructura y Kubernetes
**Duración estimada:** 2 semanas
**Integrantes:** 3 personas
**Stack de observabilidad asignado:** Jaeger (tracing) + Fluent Bit + Loki

---

## Objetivo general

Desplegar Keycloak como proveedor de identidad OAuth2/OIDC dentro del cluster
de Kubernetes, integrarlo con el API Server de Kubernetes para autenticación
centralizada de usuarios, y mapear grupos de Keycloak a roles RBAC de Kubernetes,
demostrando un modelo de identidad empresarial moderno.

---

## Arquitectura objetivo

```
  Developer en su PC
       │
       │  1. Login via OIDC
       ▼
  Keycloak (en K8s)                    Kubernetes API Server
  NodePort 30097                              │
  Realm: kubernetes-demo                      │  4. Valida token JWT
  Client: kubernetes                          │     contra Keycloak
  Groups:                                     │
    k8s-ops         ──────────────────────────┤
    k8s-developers  ── 2. emite token JWT ──► │
    k8s-readonly                              │  5. RBAC según grupo
                                              │
  kubectl con kubelogin ──── 3. token ──────► │
                                              ▼
                                       Acceso permitido/denegado
                                       según ClusterRole/Role

  Namespace: keycloak    → Keycloak
  Namespace: logging     → Fluent Bit + Loki
  Namespace: tracing     → Jaeger
```

---

## Alcance del proyecto

### Módulo 1 — Desplegar Keycloak en Kubernetes

```bash
# Crear namespace
kubectl create namespace keycloak

# Secret con credenciales de admin
kubectl create secret generic keycloak-admin \
  --from-literal=KEYCLOAK_ADMIN=admin \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD=Admin1234! \
  -n keycloak
```

Deployment de Keycloak (modo desarrollo con H2 embebida):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: quay.io/keycloak/keycloak:23.0
          args: ["start-dev"]           # modo desarrollo (H2 embebida)
          env:
            - name: KEYCLOAK_ADMIN
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin
                  key: KEYCLOAK_ADMIN
            - name: KEYCLOAK_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-admin
                  key: KEYCLOAK_ADMIN_PASSWORD
            - name: KC_HTTP_PORT
              value: "8080"
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "1"
              memory: "1Gi"
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  selector:
    app: keycloak
  ports:
    - port: 8080
      targetPort: 8080
      nodePort: 30097
  type: NodePort
```

**Entregables del módulo:**
- Keycloak corriendo y accesible en http://192.168.109.200:30097
- Captura de pantalla de la consola de administración
- Descripción del pod: `kubectl describe pod -n keycloak -l app=keycloak`

---

### Módulo 2 — Configurar Keycloak (consola web)

Acceder a http://192.168.109.200:30097 → Admin Console

#### 2.1 Crear Realm

```
Admin Console → Create Realm
  Name: kubernetes-demo
  Enabled: ON
```

#### 2.2 Crear Client

```
Realm: kubernetes-demo → Clients → Create client
  Client ID: kubernetes
  Client Protocol: openid-connect
  Client Authentication: ON (confidential)
  Valid Redirect URIs: http://localhost:*
  Web Origins: *

→ Credentials tab → copiar Client Secret (lo necesitará para kubectl)
```

#### 2.3 Crear mapper de grupos en el token

```
Clients → kubernetes → Client Scopes → kubernetes-dedicated
  → Add mapper → By configuration → Group Membership
    Name: groups
    Token Claim Name: groups
    Full group path: OFF
    Add to ID token: ON
    Add to access token: ON
    Add to userinfo: ON
```

#### 2.4 Crear Grupos

```
Realm: kubernetes-demo → Groups → Create group
  k8s-ops
  k8s-developers
  k8s-readonly
```

#### 2.5 Crear Usuarios

```
Realm: kubernetes-demo → Users → Create user

Usuario 1: ops-user
  Email: ops@demo.local
  Groups: k8s-ops
  Credentials → Set password: Ops1234! (Temporary: OFF)

Usuario 2: dev-user
  Email: dev@demo.local
  Groups: k8s-developers
  Credentials → Set password: Dev1234! (Temporary: OFF)

Usuario 3: viewer
  Email: viewer@demo.local
  Groups: k8s-readonly
  Credentials → Set password: View1234! (Temporary: OFF)
```

**Entregables del módulo:**
- Capturas de pantalla: Realm, Client, 3 Grupos, 3 Usuarios configurados
- Verificar el token JWT: obtener un token y decodificarlo en jwt.io
  → El campo `groups` debe aparecer con el grupo del usuario

---

### Módulo 3 — Configurar kube-apiserver con OIDC

```bash
# En k8s-master01 — modificar el static pod del API server
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Agregar los siguientes flags en la sección `command`:

```yaml
- --oidc-issuer-url=http://192.168.109.200:30097/realms/kubernetes-demo
- --oidc-client-id=kubernetes
- --oidc-username-claim=preferred_username
- --oidc-groups-claim=groups
- --oidc-groups-prefix=keycloak:
```

```bash
# El API server se reinicia automáticamente (static pod)
# Esperar ~60 segundos y verificar
kubectl get pods -n kube-system | grep apiserver

# Verificar que el API server arrancó correctamente
kubectl cluster-info
```

> ⚠️ **Nota importante:** En entornos de producción se usa HTTPS para Keycloak.
> Para esta demo usamos HTTP con el flag `--oidc-issuer-url` apuntando al NodePort.
> Si el API server rechaza HTTP, agregar también:
> `--oidc-ca-file` (con el CA cert) o configurar TLS en Keycloak.

**Entregables del módulo:**
- Captura del kube-apiserver.yaml con los flags OIDC
- `kubectl cluster-info` mostrando que el API server sigue funcionando
- Logs del API server sin errores OIDC:
  `kubectl logs -n kube-system kube-apiserver-k8s-master01 | grep oidc`

---

### Módulo 4 — RBAC mapeado a grupos de Keycloak

```yaml
# ─── ops-user: acceso total (cluster-admin) ──────────────────────
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloak-ops-admin
subjects:
  - kind: Group
    name: "keycloak:k8s-ops"        # prefijo keycloak: + nombre del grupo
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io

---
# ─── dev-user: acceso a namespace proyecto-dev ───────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: proyecto-dev
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: keycloak-dev-role
  namespace: proyecto-dev
subjects:
  - kind: Group
    name: "keycloak:k8s-developers"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: edit                         # ClusterRole built-in: crear/editar recursos
  apiGroup: rbac.authorization.k8s.io

---
# ─── viewer: solo lectura en todo el cluster ─────────────────────
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: keycloak-readonly
subjects:
  - kind: Group
    name: "keycloak:k8s-readonly"
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: view                         # ClusterRole built-in: solo lectura
  apiGroup: rbac.authorization.k8s.io
```

**Entregables del módulo:**
- 3 RoleBindings/ClusterRoleBindings creados y documentados
- Tabla de permisos:

| Usuario | Grupo Keycloak | Puede hacer |
|---|---|---|
| ops-user | k8s-ops | Todo (cluster-admin) |
| dev-user | k8s-developers | CRUD en namespace proyecto-dev |
| viewer | k8s-readonly | Solo `get/list/watch` en todo el cluster |

---

### Módulo 5 — Autenticación con kubectl via OIDC

```bash
# Instalar plugin kubelogin (en la máquina del alumno)
# Linux/Mac:
kubectl krew install oidc-login

# Windows:
# Descargar desde: https://github.com/int128/kubelogin/releases

# Obtener el Client Secret de Keycloak
# (Admin Console → Clients → kubernetes → Credentials → Secret)
CLIENT_SECRET="<copiar-de-keycloak>"

# Configurar credenciales OIDC para dev-user
kubectl config set-credentials dev-user \
  --exec-api-version=client.authentication.k8s.io/v1beta1 \
  --exec-command=kubectl \
  --exec-arg=oidc-login \
  --exec-arg=get-token \
  --exec-arg=--oidc-issuer-url=http://192.168.109.200:30097/realms/kubernetes-demo \
  --exec-arg=--oidc-client-id=kubernetes \
  --exec-arg=--oidc-client-secret=${CLIENT_SECRET} \
  --exec-arg=--oidc-extra-scope=groups

# Crear contexto para dev-user
kubectl config set-context dev-context \
  --cluster=kubernetes \
  --user=dev-user \
  --namespace=proyecto-dev
```

**Demo de autenticación:**

```bash
# Cambiar al contexto de dev-user
kubectl config use-context dev-context

# Primera vez: abre navegador para login en Keycloak
# Ingresar: dev-user / Dev1234!

# Verificar acceso (debe funcionar en proyecto-dev)
kubectl get pods -n proyecto-dev
# → No resources found (pero sin error de autorización) ✅

# Intentar acceder a kube-system (debe fallar)
kubectl get pods -n kube-system
# → Error from server (Forbidden) ✅

# Intentar borrar un nodo (debe fallar)
kubectl delete node k8s-worker01
# → Error from server (Forbidden) ✅

# Volver al contexto admin
kubectl config use-context kubernetes-admin@kubernetes
```

**Entregables del módulo:**
- `kubectl config get-contexts` mostrando el contexto OIDC
- Demo funcional: login con dev-user en Keycloak → token → kubectl
- Evidencia de los 3 usuarios con diferentes niveles de acceso

---

### Módulo 6 — Demo: cambio de grupo en Keycloak = cambio de permisos en K8s

```bash
# Escenario:
# 1. dev-user está en k8s-developers (solo puede acceder a proyecto-dev)
# 2. En Keycloak: mover dev-user a k8s-ops
# 3. Obtener nuevo token
# 4. Ahora dev-user tiene permisos de cluster-admin

# Paso 1: verificar acceso limitado de dev-user
kubectl get nodes --as dev-user
# → Forbidden (k8s-developers no tiene acceso a nodes)

# Paso 2: en Keycloak, mover dev-user de k8s-developers a k8s-ops
# (Admin Console → Users → dev-user → Groups → Join Group → k8s-ops)

# Paso 3: forzar nuevo token (logout + login en kubelogin)
kubectl oidc-login get-token ... --force-refresh

# Paso 4: verificar nuevos permisos
kubectl get nodes --as dev-user
# → Los nodos aparecen (ahora tiene cluster-admin via k8s-ops) ✅
```

---

### Módulo 7 — Observabilidad: Jaeger + Fluent Bit + Loki

**Tecnología asignada:** Jaeger (distributed tracing) + Fluent Bit → Loki

#### 7a. Desplegar Jaeger (tracing de flujos de autenticación)

```bash
# Instalar Jaeger Operator
kubectl create namespace tracing
kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.52.0/jaeger-operator.yaml -n tracing

# Crear instancia de Jaeger (all-in-one para demo)
kubectl apply -f - -n tracing <<EOF
apiVersion: jaegertracing.io/v1
kind: Jaeger
metadata:
  name: jaeger-demo
spec:
  strategy: allInOne
  allInOne:
    image: jaegertracing/all-in-one:1.52
  ingress:
    enabled: false
---
apiVersion: v1
kind: Service
metadata:
  name: jaeger-ui
  namespace: tracing
spec:
  selector:
    app: jaeger-demo
  ports:
    - port: 16686
      targetPort: 16686
      nodePort: 30100
  type: NodePort
EOF
```

Jaeger UI accesible en: http://192.168.109.200:30100

#### 7b. Desplegar Fluent Bit → Loki (logging ligero)

```bash
# Loki
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install loki grafana/loki-stack \
  --namespace logging \
  --create-namespace \
  --set grafana.enabled=true \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30101 \
  --set fluent-bit.enabled=true \
  --set prometheus.enabled=false
```

**Entregables del módulo:**
- Jaeger UI corriendo en NodePort 30100
  → Captura de trazas del proceso de autenticación OIDC
- Fluent Bit + Loki corriendo en namespace `logging`
- Grafana (NodePort 30101) con logs de Keycloak visibles
- Query útil en Loki:
  `{namespace="keycloak"} |= "login"` → ver todos los intentos de login
- `{namespace="keycloak"} |= "error"` → ver errores de autenticación

---

## Entregables finales del Equipo 3

```
Documentación:
  □ Diagrama de flujo completo: usuario → Keycloak → JWT → K8s RBAC
  □ Tabla de usuarios, grupos, roles y permisos
  □ Documento comparativo: OIDC/Keycloak vs certificados X.509 manuales
    (ventajas, desventajas, casos de uso de cada uno)

Técnico (en el cluster):
  □ Keycloak corriendo con Realm + Client + 3 Grupos + 3 Usuarios
  □ kube-apiserver configurado con flags OIDC
  □ 3 RoleBindings/ClusterRoleBindings mapeados a grupos Keycloak
  □ kubectl funcional con autenticación OIDC (kubelogin)
  □ Demo: cambio de grupo en Keycloak → permisos cambian en K8s
  □ Jaeger corriendo con trazas de autenticación
  □ Fluent Bit + Loki: logs de Keycloak visibles en Grafana

Presentación (15 minutos):
  □ 5 min — Demo: login OIDC en Keycloak → kubectl funciona
  □ 5 min — Demo: 3 usuarios con diferentes permisos
  □ 5 min — Jaeger y Loki mostrando flujos de autenticación
```

---

## Stack de observabilidad — Resumen técnico

```
  TRACING (Jaeger)                    LOGGING (Fluent Bit → Loki)
  ─────────────────                   ───────────────────────────
  Keycloak envía trazas               Fluent Bit (DaemonSet)
  OIDC → Jaeger Collector               │ recolecta logs de todos los pods
       │                                ▼
       ▼                             Loki (almacenamiento)
  Jaeger Storage (memoria)              │
       │                                ▼
       ▼                          Grafana (NodePort 30101)
  Jaeger UI (NodePort 30100)         - Logs de Keycloak
  - Trazas de auth flows             - Logs de K8s API server
  - Latencia de tokens               - Búsqueda: intentos de login
  - Errores de OIDC
```

| Componente | Namespace | Puerto |
|---|---|---|
| Keycloak | keycloak | NodePort 30097 |
| Jaeger UI | tracing | NodePort 30100 |
| Grafana+Loki | logging | NodePort 30101 |
| Fluent Bit | logging | DaemonSet |

---

## Recursos de apoyo

- Keycloak: https://www.keycloak.org/getting-started/getting-started-kube
- K8s OIDC Auth: https://kubernetes.io/docs/reference/access-authn-authz/authentication/#openid-connect-tokens
- kubelogin: https://github.com/int128/kubelogin
- Jaeger: https://www.jaegertracing.io/docs/1.52/operator/
- Fluent Bit + Loki: https://grafana.com/docs/loki/latest/send-data/fluentbit/
- JWT decoder (para verificar tokens): https://jwt.io
