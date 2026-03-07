# Guía de Clase — Tekton CI en Kubernetes

**Versiones:** Tekton Pipelines v1.6.0 · Dashboard v0.63.1
**Namespace propio:** `tekton-pipelines`
**Dashboard:** http://192.168.109.200:30094
**Directorio:** `/root/devops2026/11-tekton/`

---

## Arquitectura de la clase

```
                    ┌─────────────────────────────────────────┐
                    │           Tekton Pipelines               │
                    │                                          │
                    │  PipelineRun                            │
                    │    │                                     │
                    │    ├─► paso-saludo (hello-task)         │
                    │    │       └─► Pod alpine               │
                    │    │                                     │
                    │    ├─► paso-clone (git-clone-task)      │
                    │    │       └─► Pod alpine/git           │
                    │    │              └─► workspace NFS      │
                    │    │                  192.168.109.210    │
                    │    │                                     │
                    │    └─► paso-resultado (hello-task)      │
                    │            └─► Pod alpine               │
                    └─────────────────────────────────────────┘
                                        │
                                   NodePort
                                    :30094
                                        │
                         http://192.168.109.200:30094
                              (Tekton Dashboard)
```

---

## PASO 0 — Preparar el servidor NFS

> Ejecutar en **nfs01** (`192.168.109.210`)

```bash
# Crear directorio para el workspace de Tekton
# Usamos 777 porque Tekton crea pods con distintos UIDs según la Task
mkdir -p /srv/nfs/k8s/tekton-workspace
chmod 777 /srv/nfs/k8s/tekton-workspace

# Verificar que está exportado (debe aparecer en la lista)
exportfs -v | grep tekton

# Si no aparece, agregar al /etc/exports y recargar:
echo "/srv/nfs/k8s/tekton-workspace 192.168.109.0/24(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
exportfs -ra
```

---

## PASO 1 — Instalar Tekton Pipelines y Dashboard

> Ejecutar en **k8s-master01**

```bash
# Instalar Tekton Pipelines v1.6.0 (usa ghcr.io — NO gcr.io que está deprecated)
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml

# Esperar a que los pods estén Running (puede tardar 2-3 minutos)
kubectl get pods -n tekton-pipelines -w

# Instalar Tekton Dashboard v0.63.1
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/latest/release-full.yaml

# Esperar al pod del dashboard
kubectl get pods -n tekton-pipelines -l app=tekton-dashboard -w
```

Salida esperada:
```
NAME                                          READY   STATUS    RESTARTS
tekton-dashboard-xxxxx                        1/1     Running   0
tekton-pipelines-controller-xxxxx            1/1     Running   0
tekton-pipelines-webhook-xxxxx               1/1     Running   0
```

### Exponer el Dashboard con NodePort

```bash
cd /root/devops2026/11-tekton
kubectl apply -f 07-tekton-dashboard-svc.yaml

# Verificar
kubectl get svc tekton-dashboard-nodeport -n tekton-pipelines
```

**Acceder al Dashboard:** http://192.168.109.200:30094

---

## PASO 2 — Instalar CLI tkn

La CLI `tkn` es la herramienta de línea de comandos de Tekton (como kubectl pero para Tekton).

```bash
# Instalar en el master
curl -LO https://github.com/tektoncd/cli/releases/download/v0.37.0/tkn_0.37.0_Linux_x86_64.tar.gz
tar xvzf tkn_0.37.0_Linux_x86_64.tar.gz -C /usr/local/bin tkn
chmod +x /usr/local/bin/tkn

# Verificar
tkn version
```

Comandos útiles de `tkn`:
```bash
tkn task list                          # listar Tasks
tkn pipeline list                      # listar Pipelines
tkn pipelinerun list                   # listar PipelineRuns
tkn pipelinerun logs <nombre> -f       # ver logs en tiempo real
tkn taskrun list                       # listar TaskRuns
```

---

## PASO 3 — RBAC para el pipeline

> **Concepto:** Tekton necesita permisos para crear Pods, leer Secrets y manejar PVCs.
> Sin RBAC, el PipelineRun fallaría al intentar crear los pods de cada Task.

```bash
cd /root/devops2026/11-tekton
kubectl apply -f 01-serviceaccount.yaml

# Verificar
kubectl get sa tekton-pipeline-sa
kubectl get clusterrole tekton-pipeline-role
kubectl get clusterrolebinding tekton-pipeline-rolebinding
```

---

## PASO 4 — Workspace: PV + PVC en NFS

> **Concepto:** Los Workspaces son volúmenes compartidos entre Tasks de un Pipeline.
> Sin workspace, cada Task correría en su propio Pod aislado y no podría leer
> los archivos que dejó la Task anterior.

```bash
kubectl apply -f 02-workspace-pvc.yaml

# Esperar a que el PVC quede en Bound
kubectl get pvc pvc-tekton-workspace -w
```

**Señalar en el manifest:**
- PVC en NFS → los archivos clonados persisten aunque el pod muera
- `ReadWriteOnce` → el pipeline corre en un solo nodo

---

## PASO 5 — Primera Task: Hello World

> **Concepto:** Una **Task** es la unidad básica de Tekton. Contiene Steps que
> corren secuencialmente dentro del mismo Pod.

```
Task
  └── Pod
        ├── Step 1 → Contenedor 1
        ├── Step 2 → Contenedor 2 (mismo Pod)
        └── Step 3 → Contenedor 3 (mismo Pod)
```

```bash
kubectl apply -f 03-task-hello.yaml

# Verificar que la Task fue creada
tkn task list
kubectl describe task hello-task
```

### Correr la Task manualmente con un TaskRun

```bash
# Crear un TaskRun desde la CLI
tkn task start hello-task \
  --param mensaje="Hola clase DevOps 2026!" \
  --showlog

# O crear un TaskRun con YAML:
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: TaskRun
metadata:
  name: hello-taskrun-manual
  namespace: default
spec:
  taskRef:
    name: hello-task
  params:
    - name: mensaje
      value: "Primera Task corriendo en Kubernetes!"
EOF

# Ver los logs
tkn taskrun logs hello-taskrun-manual -f
```

**Ver en el Dashboard:** http://192.168.109.200:30094 → TaskRuns

---

## PASO 6 — Task con Workspace: Git Clone

> **Concepto:** Los **Workspaces** permiten que datos persistan entre Steps
> y se compartan entre Tasks del mismo Pipeline.

```bash
kubectl apply -f 04-task-git-clone.yaml

# Probar la Task de forma independiente
tkn task start git-clone-task \
  --param repo-url=https://github.com/dguerrero11/kubernetes-devops \
  --param revision=main \
  --workspace name=source,claimName=pvc-tekton-workspace \
  --serviceaccount tekton-pipeline-sa \
  --showlog
```

**Qué muestra:**
1. El git clone del repo
2. El contenido del repo (ls -la)
3. El conteo de archivos YAML

---

## PASO 7 — Pipeline: orquestando Tasks

> **Concepto:** Un **Pipeline** define el orden y las dependencias entre Tasks.
> El campo `runAfter` crea la dependencia explícita entre pasos.

```
Pipeline: demo-pipeline
  │
  ├─► paso-saludo (hello-task)     ← corre primero
  │
  ├─► paso-clone (git-clone-task)  ← corre DESPUÉS de paso-saludo
  │       runAfter: [paso-saludo]
  │
  └─► paso-resultado (hello-task)  ← corre DESPUÉS de paso-clone
          runAfter: [paso-clone]
```

```bash
kubectl apply -f 05-pipeline.yaml

# Verificar
tkn pipeline list
kubectl describe pipeline demo-pipeline
```

---

## PASO 8 — PipelineRun: ejecutar el Pipeline

```bash
cd /root/devops2026/11-tekton

# Ejecutar el pipeline (usa kubectl create, NO apply — cada run es único)
kubectl create -f 06-pipelinerun.yaml

# Seguir los logs en tiempo real
tkn pipelinerun logs demo-pipeline-run-01 -f

# Ver el estado
tkn pipelinerun describe demo-pipeline-run-01
```

Salida esperada:
```
Name:              demo-pipeline-run-01
Namespace:         default
Pipeline Ref:      demo-pipeline
Service Account:   tekton-pipeline-sa
Status:            Succeeded

TASKRUNS
NAME                                    TASK NAME      STARTED     DURATION   STATUS
demo-pipeline-run-01-paso-saludo-xxxx   paso-saludo    2m ago      5s         Succeeded
demo-pipeline-run-01-paso-clone-xxxx    paso-clone     1m ago      20s        Succeeded
demo-pipeline-run-01-paso-resultado-xx  paso-resultado 30s ago     5s         Succeeded
```

Para volver a ejecutar el pipeline, cambiar el nombre del PipelineRun:
```bash
# Opción 1: editar el nombre en el YAML y hacer kubectl create
sed 's/run-01/run-02/' 06-pipelinerun.yaml | kubectl create -f -

# Opción 2: desde la CLI
tkn pipeline start demo-pipeline \
  --param repo-url=https://github.com/dguerrero11/kubernetes-devops \
  --workspace name=shared-workspace,claimName=pvc-tekton-workspace \
  --serviceaccount tekton-pipeline-sa \
  --showlog
```

---

## PASO 9 — Explorar el Tekton Dashboard

**URL:** http://192.168.109.200:30094

Secciones a mostrar:
1. **PipelineRuns** → ver el estado de cada ejecución (verde = Succeeded)
2. **TaskRuns** → ver cada Task individual con sus logs
3. **Tasks** → ver las Tasks definidas
4. **Pipelines** → ver los Pipelines y su estructura
5. **Hacer clic en un PipelineRun** → ver el grafo de ejecución con los tiempos

---

## Resumen de comandos

```bash
# Ver todos los recursos Tekton
kubectl get tasks,pipelines,pipelineruns,taskruns -n default

# Ver pods creados por Tekton (uno por Step)
kubectl get pods --sort-by=.metadata.creationTimestamp | tail -20

# Limpiar PipelineRuns anteriores
tkn pipelinerun delete --all --keep 2

# Ver el workspace en el NFS (en nfs01)
ls -la /srv/nfs/k8s/tekton-workspace/
```

---

## Orden de despliegue (resumen para clase)

```bash
cd /root/devops2026/11-tekton

# 1. Instalar Tekton (solo la primera vez)
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.59.0/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/dashboard/previous/v0.43.0/release-full.yaml
kubectl get pods -n tekton-pipelines -w

# 2. Exponer Dashboard
kubectl apply -f 07-tekton-dashboard-svc.yaml

# 3. RBAC + Storage
kubectl apply -f 01-serviceaccount.yaml
kubectl apply -f 02-workspace-pvc.yaml

# 4. Tasks y Pipeline
kubectl apply -f 03-task-hello.yaml
kubectl apply -f 04-task-git-clone.yaml
kubectl apply -f 05-pipeline.yaml

# 5. Ejecutar
kubectl create -f 06-pipelinerun.yaml
tkn pipelinerun logs demo-pipeline-run-01 -f
```
