# Guía de Clase — RBAC Avanzado en Kubernetes

**Namespace demo:** `devops-dev`
**Directorio:** `/root/devops2026/13-rbac-avanzado/`

---

## 🎓 Guión para el instructor

### El concepto en una frase
> *"RBAC es el sistema de tarjetas de acceso del cluster: cada persona y cada aplicación solo puede entrar a las habitaciones que necesita, nada más."*

### Analogía del edificio (5 min)
```
Edificio corporativo:
  Empleado A  → tarjeta de piso 3 (su área) + recepción (todos)
  Empleado B  → tarjeta de todos los pisos (admin)
  Cámara CCTV → llave de sala de servidores (aplicación con acceso específico)

Kubernetes:
  Usuario developer → Role en devops-dev + ClusterRole readonly
  Usuario admin     → ClusterRole cluster-admin (acceso total)
  Pod app-sa        → Role con acceso solo a sus ConfigMaps
```

### Los 4 componentes de RBAC (10 min)
```
¿Quién?      ¿Puede hacer qué?    ¿En qué recursos?   ¿Conectado por?
──────────   ─────────────────    ─────────────────    ──────────────
User          verbs:               resources:           RoleBinding
ServiceAccount  get, list,           pods               ClusterRoleBinding
Group           create,              deployments
                delete,              secrets
                update               nodes...

         Role (namespace)  ──────► RoleBinding (namespace)
         ClusterRole        ──────► ClusterRoleBinding (cluster)
                            ──────► RoleBinding (namespace) ← ClusterRole también puede usarse aquí
```

### Diferencia clave: Role vs ClusterRole
```
Role:        solo aplica DENTRO de un namespace específico
ClusterRole: aplica en TODOS los namespaces o a recursos del cluster (nodes, PV)

Un ClusterRole puede usarse en un RoleBinding → limita el alcance al namespace
Un Role NO puede usarse en un ClusterRoleBinding
```

### Demo usuario real — la más impactante (20 min)
```
Demostrar que Kubernetes NO tiene un sistema de usuarios propio.
Los usuarios son certificados X.509 firmados por la CA del cluster.
El CN= del certificado = nombre del usuario.
El O= del certificado = grupos del usuario.
```

### Preguntas clave para la clase
- *¿Dónde están los usuarios de K8s?* → No existen en la API — son certificados externos
- *¿Qué pasa si no asigno un SA a un Pod?* → Usa el SA `default` del namespace (sin permisos extra)
- *¿Por qué no dar siempre cluster-admin?* → Principio de mínimo privilegio — si un pod es comprometido, el atacante solo tiene los permisos del SA
- *¿Cuándo uso Role vs ClusterRole?* → Role para recursos de namespace, ClusterRole para nodes/PV o cuando quieres reusar la definición en varios namespaces

---

## PASO 0 — Verificar RBAC habilitado

```bash
# RBAC está habilitado por defecto en K8s 1.6+
kubectl api-versions | grep rbac
# Debe mostrar: rbac.authorization.k8s.io/v1

# Ver el ClusterRole que usa el admin actual
kubectl describe clusterrolebinding cluster-admin
```

---

## PASO 1 — Crear namespace y aplicar RBAC

```bash
cd /root/devops2026/13-rbac-avanzado

kubectl apply -f 01-namespace-dev.yaml
kubectl apply -f 02-role-developer.yaml
kubectl apply -f 03-clusterrole-readonly.yaml
kubectl apply -f 04-rolebinding-developer.yaml
kubectl apply -f 05-clusterrolebinding-readonly.yaml

# Verificar
kubectl get role,rolebinding -n devops-dev
kubectl get clusterrole cluster-reader
kubectl get clusterrolebinding developer-cluster-reader
```

---

## PASO 2 — Crear el usuario 'developer' con certificado X.509

> Ejecutar en **k8s-master01** (necesita acceso a la CA del cluster)

```bash
cd /tmp

# 1. Generar clave privada del usuario
openssl genrsa -out developer.key 2048

# 2. Generar CSR (Certificate Signing Request)
#    CN= nombre de usuario en Kubernetes
#    O=  grupo al que pertenece
openssl req -new \
  -key developer.key \
  -out developer.csr \
  -subj "/CN=developer/O=devops-team"

# 3. Firmar el certificado con la CA del cluster (válido 365 días)
openssl x509 -req \
  -in developer.csr \
  -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key \
  -CAcreateserial \
  -out developer.crt \
  -days 365

# Verificar el certificado generado
openssl x509 -in developer.crt -noout -text | grep -A2 "Subject:"
```

---

## PASO 3 — Crear el kubeconfig del usuario developer

```bash
# Obtener la IP del API server
API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "API Server: $API_SERVER"

# Crear credenciales en el kubeconfig del sistema
kubectl config set-credentials developer \
  --client-certificate=/tmp/developer.crt \
  --client-key=/tmp/developer.key

# Crear contexto para el usuario developer
kubectl config set-context developer-context \
  --cluster=kubernetes \
  --user=developer \
  --namespace=devops-dev

# Ver los contextos disponibles
kubectl config get-contexts
```

---

## PASO 4 — Probar los permisos del usuario developer

```bash
# Cambiar al contexto del usuario developer
kubectl config use-context developer-context

# ✅ DEBE FUNCIONAR: listar pods en devops-dev (su namespace)
kubectl get pods -n devops-dev

# ✅ DEBE FUNCIONAR: ver nodos (ClusterRole readonly)
kubectl get nodes

# ✅ DEBE FUNCIONAR: ver pods en monitoring (solo lectura global)
kubectl get pods -n monitoring

# ❌ DEBE FALLAR: crear un deployment en monitoring (no tiene permisos)
kubectl create deployment test --image=nginx -n monitoring
# Error: deployments.apps is forbidden: User "developer" cannot create...

# ❌ DEBE FALLAR: ver secrets (no tiene permisos en ningún namespace)
kubectl get secrets -n devops-dev
# Error: secrets is forbidden

# Volver al contexto admin
kubectl config use-context kubernetes-admin@kubernetes
```

---

## PASO 5 — Verificar permisos con kubectl auth can-i

```bash
# Herramienta clave para auditar permisos

# ¿Qué puede hacer el usuario developer?
kubectl auth can-i get pods --as=developer -n devops-dev       # yes
kubectl auth can-i delete pods --as=developer -n devops-dev    # yes
kubectl auth can-i get secrets --as=developer -n devops-dev    # no
kubectl auth can-i get nodes --as=developer                    # yes
kubectl auth can-i create deployments --as=developer -n monitoring # no

# Listar TODO lo que puede hacer un usuario en un namespace
kubectl auth can-i --list --as=developer -n devops-dev
```

---

## PASO 6 — ServiceAccount para aplicaciones

```bash
cd /root/devops2026/13-rbac-avanzado

kubectl apply -f 06-serviceaccount-app.yaml
kubectl apply -f 07-pod-con-sa.yaml

# Esperar que el pod arranque
kubectl get pod app-pod -n devops-dev -w
```

### Demo: el pod usa su token para llamar a la API de K8s

```bash
# Entrar al pod
kubectl exec -it app-pod -n devops-dev -- sh

# Dentro del pod, el token está disponible automáticamente:
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)

# Llamar a la API de K8s usando el token del ServiceAccount
# ✅ DEBE FUNCIONAR: listar pods del namespace
curl -s --cacert $CACERT \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NAMESPACE/pods \
  | grep '"name"' | head -5

# ❌ DEBE FALLAR: listar pods de otro namespace
curl -s --cacert $CACERT \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/monitoring/pods \
  | grep '"message"'
# "pods is forbidden: User "system:serviceaccount:devops-dev:app-sa" cannot list..."

exit
```

---

## PASO 7 — Comandos de diagnóstico RBAC

```bash
# Ver todos los RoleBindings de un namespace
kubectl get rolebindings -n devops-dev -o wide

# Ver qué permisos tiene un ServiceAccount específico
kubectl auth can-i --list \
  --as=system:serviceaccount:devops-dev:app-sa \
  -n devops-dev

# Describir un Role para ver sus reglas
kubectl describe role developer-role -n devops-dev

# Ver todos los ClusterRoles del sistema (muchos son internos de K8s)
kubectl get clusterroles | grep -v "system:"

# Ver quién tiene acceso a los Secrets en un namespace
kubectl get rolebindings,clusterrolebindings -A \
  -o jsonpath='{range .items[?(@.roleRef.name=="cluster-admin")]}{.metadata.name}{"\n"}{end}'
```

---

## Resumen del modelo de permisos aplicado

```
Usuario: developer
─────────────────────────────────────────────────────────
Namespace devops-dev:
  Role developer-role → pods, deployments, services (CRUD)
  configmaps (solo lectura)

Cluster (todos los namespaces):
  ClusterRole cluster-reader → todos los recursos (solo lectura)

Resultado:
  - Puede VER todo el cluster
  - Puede GESTIONAR recursos solo en devops-dev
  - NO puede tocar secrets, nodes, ni recursos fuera de devops-dev

ServiceAccount: app-sa (en devops-dev)
─────────────────────────────────────────────────────────
  Role app-role → configmaps (lectura), pods (lectura)
  Resultado: la app solo lee su configuración, nada más
```

---

## Orden de despliegue (resumen)

```bash
cd /root/devops2026/13-rbac-avanzado

# 1. Infraestructura
kubectl apply -f 01-namespace-dev.yaml

# 2. Permisos usuario humano
kubectl apply -f 02-role-developer.yaml
kubectl apply -f 03-clusterrole-readonly.yaml
kubectl apply -f 04-rolebinding-developer.yaml
kubectl apply -f 05-clusterrolebinding-readonly.yaml

# 3. Crear certificado y contexto (comandos del PASO 2 y 3)

# 4. Permisos ServiceAccount (aplicación)
kubectl apply -f 06-serviceaccount-app.yaml
kubectl apply -f 07-pod-con-sa.yaml

# 5. Verificar con auth can-i
kubectl auth can-i --list --as=developer -n devops-dev
```
