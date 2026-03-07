# Guía de Clase — Argo CD GitOps en Kubernetes

**Versión:** Argo CD v2.9.3
**Namespace propio:** `argocd`
**UI Argo CD:** http://192.168.109.200:30095
**Directorio:** `/root/devops2026/12-argocd/`

---

## 🎓 Guión para el instructor

### El concepto en una frase
> *"Con GitOps, Git es la única fuente de verdad. Nadie hace `kubectl apply` manualmente — Argo CD sincroniza el cluster automáticamente desde el repo."*

### El problema que resuelve (10 min — abrir con esto)

Plantear el escenario a la clase:
```
Equipo de 5 personas, todos con acceso a kubectl en producción:

  Dev A → kubectl apply -f deployment-v1.yaml    (lunes)
  Dev B → kubectl apply -f deployment-v2.yaml    (martes)
  Dev A → kubectl edit deployment nginx-web       (miércoles — "fix rápido")
  Dev C → kubectl scale deployment nginx --replicas=0  (jueves — "prueba")

Pregunta: ¿qué hay REALMENTE en producción el viernes?
→ Nadie lo sabe con certeza. No hay auditoría. No hay rollback fácil.
```

**Con GitOps:**
```
REGLA: lo que está en Git = lo que está en el cluster. Siempre.

Dev A → modifica YAML → git commit → git push → PR → aprobación → merge
                                                              │
                                                         Argo CD
                                                              │
                                                         kubectl apply
                                                         (automático)
```

Beneficios clave:
- **Auditoría**: `git log` muestra quién cambió qué y cuándo
- **Rollback**: `git revert` → Argo CD revierte el cluster
- **Consistencia**: el cluster SIEMPRE refleja Git, sin desviaciones

### Los 3 conceptos centrales de Argo CD (10 min)

**1. Application** — "qué sincronizar y desde dónde"
```yaml
source:  github.com/repo  →  carpeta 05-services/
destination: cluster local  →  namespace default
```

**2. Sync Status** — "¿Git == Cluster?"
```
Synced    → ✅ Git == Cluster (todo OK)
OutOfSync → ⚠️  Git != Cluster (hay diferencias pendientes)
Unknown   → ❓  No se puede comparar (error de conexión al repo)
```

**3. Health Status** — "¿los recursos funcionan?"
```
Healthy     → ✅ Pods running, Services con endpoints
Progressing → 🔄 Deployment actualizándose
Degraded    → ❌ Pods en CrashLoop o error
```

### Demo WOW — GitOps en vivo (15 min)

**Parte 1: cambio normal via Git**
```bash
# 1. Ver estado actual
kubectl get deployment nginx-web -n default

# 2. Cambiar replicas en Git (en el master o localmente)
vi 05-services/03-deployment-y-service-completo.yaml
# replicas: 1  →  replicas: 5

git add . && git commit -m "escalar a 5 replicas" && git push

# 3. En otro terminal: monitorear
watch kubectl get pods -n default

# 4. En la UI: ver el commit aparece como HEAD → OutOfSync → Syncing → Synced
```

**Parte 2: selfHeal — el más impactante**

> *"Imaginemos que alguien entra al cluster directamente y hace un cambio sin pasar por Git. Argo CD lo detecta y lo revierte."*

```bash
# Alguien bypasea Git y modifica el cluster directamente
kubectl scale deployment nginx-web -n default --replicas=1

# Argo CD detecta el drift en segundos
watch kubectl get pods -n default
# → Los pods VUELVEN al número que dice Git automáticamente
```

**Mensaje de cierre:**
> *"En producción real, nadie tiene acceso directo a kubectl. Todo pasa por Git → PR → aprobación → merge → Argo CD. El cluster es de solo lectura para los humanos."*

### Preguntas clave para la clase
- *¿Qué pasa si borro un recurso del cluster manualmente?* → `prune: true` lo vuelve a crear desde Git
- *¿Cómo hago un rollback?* → `git revert` o `HISTORY AND ROLLBACK` en la UI
- *¿Cada cuánto sincroniza?* → Polling cada 3 min, o inmediato con webhook de GitHub
- *¿Puede manejar secrets?* → Sí, con Sealed Secrets o External Secrets Operator (clase avanzada)

### Comparativa final: Tekton vs Argo CD
```
┌─────────────┬──────────────────────┬─────────────────────────┐
│             │ Tekton               │ Argo CD                 │
├─────────────┼──────────────────────┼─────────────────────────┤
│ Rol         │ CI (build, test)     │ CD (deploy, sync)       │
│ Qué hace    │ Ejecuta pipelines    │ Sincroniza Git→Cluster  │
│ Cuándo corre│ Al hacer push/manual │ Continuamente (3 min)   │
│ Fuente      │ Código fuente        │ Manifests YAML en Git   │
│ UI          │ :30094               │ :30095                  │
└─────────────┴──────────────────────┴─────────────────────────┘

El combo CI/CD completo:
  Developer → git push → Tekton (CI: build+test) → imagen nueva
                                    │
                                    ▼
                              actualiza tag en YAML
                                    │
                                    ▼
                             Argo CD (CD: deploy) → Cluster
```

---

## Arquitectura de la clase

```
  GitHub Repo                     Cluster K8s
  (fuente de verdad)
                                  namespace: default
  kubernetes-devops/              ┌─────────────────────────┐
  └── 05-services/          ◄──── │  Argo CD Application    │
       ├── 01-service-clusterip   │  "demo-services"        │
       ├── 02-service-nodeport    │                         │
       └── 03-deployment-...      │  ✓ Synced               │
                                  │  ✓ Healthy              │
  git push → Argo CD              └─────────────────────────┘
             detecta el                       │
             cambio (3min)      namespace: argocd
             y sincroniza       ┌─────────────────────────┐
                                │  argocd-server          │
                                │  argocd-repo-server     │
                                │  application-controller │
                                │  redis                  │
                                └─────────────────────────┘
                                          │
                                     NodePort 30095
                                          │
                           http://192.168.109.200:30095
```

---

## PASO 0 — Introducción a GitOps

> **¿Qué es GitOps?**
> El repositorio Git es la **única fuente de verdad** del cluster.
> Cualquier cambio en el cluster **debe pasar primero por Git**.
> Argo CD observa el repo y garantiza que el cluster siempre refleje Git.

```
SIN GitOps (push manual):
  Developer → kubectl apply -f deployment.yaml → Cluster
  Problema: ¿qué hay realmente en el cluster? ¿quién cambió qué?

CON GitOps (Argo CD):
  Developer → git commit → git push → Argo CD → Cluster
  Ventaja: historial, auditoría, rollback con git revert
```

**El flujo GitOps:**
```
1. Developer hace cambios en los YAML del repo
2. git push a GitHub
3. Argo CD detecta el cambio (polling cada 3 min o webhook)
4. Argo CD compara Git vs Cluster → detecta "drift"
5. Argo CD aplica los cambios automáticamente
6. Cluster queda en sync con Git
```

---

## PASO 1 — Instalar Argo CD

> Ejecutar en **k8s-master01**

```bash
# Crear el namespace de Argo CD
kubectl create namespace argocd

# Instalar Argo CD v2.9.3
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml

# Esperar a que todos los pods estén Running (3-5 minutos)
kubectl get pods -n argocd -w
```

Pods que deben quedar Running:
```
NAME                                      READY   STATUS
argocd-application-controller-xxx         1/1     Running
argocd-dex-server-xxx                     1/1     Running
argocd-notifications-controller-xxx       1/1     Running
argocd-redis-xxx                          1/1     Running
argocd-repo-server-xxx                    1/1     Running
argocd-server-xxx                         1/1     Running
```

---

## PASO 2 — Exponer la UI con NodePort

```bash
cd /root/devops2026/12-argocd

# Deshabilitar TLS en argocd-server para acceso HTTP simple
kubectl patch deployment argocd-server -n argocd \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'

# Esperar a que el pod se reinicie
kubectl rollout status deployment/argocd-server -n argocd

# Crear el Service NodePort
kubectl apply -f 01-argocd-nodeport.yaml

# Verificar
kubectl get svc argocd-server-nodeport -n argocd
```

**Acceder a la UI:** http://192.168.109.200:30095

---

## PASO 3 — Obtener contraseña inicial y acceder

Argo CD genera una contraseña aleatoria en el primer arranque y la guarda en un Secret.

```bash
# Obtener la contraseña inicial del admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Guardar la contraseña para la clase
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
echo "Password: $ARGOCD_PASS"
```

**Acceso a la UI:**
```
URL:      http://192.168.109.200:30095
Usuario:  admin
Password: (el valor del comando anterior)
```

### Instalar CLI argocd (opcional)

```bash
curl -sSL -o /usr/local/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/download/v2.9.3/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Login desde CLI
argocd login 192.168.109.200:30095 \
  --username admin \
  --password $ARGOCD_PASS \
  --insecure
```

---

## PASO 4 — Explorar la UI antes de crear la Application

Mostrar a la clase:
1. **Applications** → vacío por ahora
2. **Settings → Repositories** → donde se conectan repos Git
3. **Settings → Clusters** → el cluster local ya está registrado como `in-cluster`

> **Dato importante:** El repo de GitHub (`dguerrero11/kubernetes-devops`) es público,
> por lo que Argo CD puede acceder sin credenciales.
> Si fuera privado, habría que registrar un token SSH/HTTPS aquí.

---

## PASO 5 — Crear la Application

```bash
cd /root/devops2026/12-argocd
kubectl apply -f 02-argocd-app-demo.yaml
```

Verificar desde CLI:
```bash
# Ver el estado de la Application
kubectl get application demo-services -n argocd

# Descripción detallada
kubectl describe application demo-services -n argocd
```

O desde CLI argocd:
```bash
argocd app list
argocd app get demo-services
```

**Ver en la UI:**
- Ir a **Applications** → aparece `demo-services`
- Estado inicial: **Syncing** → luego **Synced + Healthy**
- Hacer clic en la Application → ver el grafo de recursos

---

## PASO 6 — Demo GitOps en vivo

> **Este es el momento WOW de la clase.** Vamos a modificar un YAML en GitHub
> y ver cómo Argo CD detecta el cambio y actualiza el cluster automáticamente.

### Escenario: cambiar las réplicas de un Deployment

1. **Ver el estado actual del cluster:**
```bash
kubectl get deployments -n default
kubectl get pods -n default
```

2. **Modificar el deployment en el repo local:**
```bash
# En el directorio local del repo (en tu máquina o en el master):
# Editar 05-services/03-deployment-y-service-completo.yaml
# Cambiar: replicas: 1  →  replicas: 3
```

3. **Hacer commit y push:**
```bash
git add 05-services/03-deployment-y-service-completo.yaml
git commit -m "demo: escalar a 3 replicas para la clase"
git push origin main
```

4. **Esperar a que Argo CD detecte el cambio (máx 3 minutos):**
```bash
# Monitorear en tiempo real
watch kubectl get pods -n default
```

> Argo CD hace polling al repo cada 3 minutos por defecto.
> Para forzar una sincronización inmediata desde la UI: botón **SYNC**

5. **Ver en la UI cómo Argo CD aplica el cambio:**
- La Application muestra estado **OutOfSync** cuando detecta el drift
- Luego pasa a **Syncing** y finalmente **Synced**

6. **Verificar el resultado:**
```bash
kubectl get pods -n default
# Deben aparecer 3 pods del deployment
```

### Escenario 2: rollback con git revert

```bash
# Revertir el cambio
git revert HEAD --no-edit
git push origin main

# Argo CD aplica el revert → vuelve a 1 réplica
watch kubectl get pods -n default
```

---

## PASO 7 — Conceptos clave a explicar en pizarra

### Sync Status
```
Synced     → Git == Cluster (todo OK)
OutOfSync  → Git != Cluster (hay diferencias)
Unknown    → Argo CD no puede determinar el estado
```

### Health Status
```
Healthy    → Los recursos están funcionando correctamente
Progressing→ Los recursos están actualizándose
Degraded   → Hay pods en error
Missing    → El recurso existe en Git pero no en el cluster
```

### selfHeal vs prune
```yaml
syncPolicy:
  automated:
    selfHeal: true  # alguien hizo kubectl edit → Argo CD lo revierte
    prune: true     # se borró un archivo de Git → Argo CD borra el recurso
```

**Demo de selfHeal:**
```bash
# Modificar manualmente el cluster (sin cambiar Git)
kubectl scale deployment nginx-web -n default --replicas=5

# Argo CD detecta el drift y revierte a lo que dice Git (1 replica)
watch kubectl get deployment nginx-web -n default
```

---

## Resumen de comandos

```bash
# Estado de todos los recursos de Argo CD
kubectl get all -n argocd

# Ver todas las Applications
kubectl get applications -n argocd

# Forzar sincronización manual
argocd app sync demo-services

# Ver historial de sincronizaciones
argocd app history demo-services

# Rollback a una versión anterior
argocd app rollback demo-services <ID>
```

---

## Orden de despliegue (resumen para clase)

```bash
cd /root/devops2026/12-argocd

# 1. Instalar Argo CD (solo la primera vez)
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.3/manifests/install.yaml
kubectl get pods -n argocd -w

# 2. Configurar acceso HTTP + NodePort
kubectl patch deployment argocd-server -n argocd \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--insecure"}]'
kubectl apply -f 01-argocd-nodeport.yaml

# 3. Obtener contraseña
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# 4. Crear Application
kubectl apply -f 02-argocd-app-demo.yaml

# 5. Verificar
kubectl get application demo-services -n argocd
```

---

## Comparativa: Tekton vs Argo CD

| Aspecto | Tekton | Argo CD |
|---------|--------|---------|
| Rol | CI (Integración Continua) | CD (Entrega Continua / GitOps) |
| Qué hace | Ejecuta pipelines (build, test) | Sincroniza Git → Cluster |
| Cuándo corre | Al hacer push / manualmente | Continuamente observando Git |
| Fuente de verdad | Código fuente | Manifests YAML en Git |
| Visualización | Tekton Dashboard (:30094) | Argo CD UI (:30095) |

**El combo completo CI/CD:**
```
Developer
    │
    ▼ git push
GitHub Repo
    │
    ├──► Tekton (CI): test → build → push imagen
    │
    └──► Argo CD (CD): detecta nuevo tag → actualiza Deployment → Cluster
```
