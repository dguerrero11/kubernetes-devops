# Guía de Clase — Ejercicio Integral: Canary + Tekton CI + Argo CD GitOps

**Módulo:** 20 — Canary Deployment con CI/CD completo
**Namespace:** `canary-demo`
**Directorio:** `/root/devops2026/20-canary-cicd/`
**Tiempo estimado:** 90–120 minutos

---

## Herramientas que se integran en este módulo

| Herramienta | Rol | URL |
|---|---|---|
| **Tekton** | CI — valida y actualiza manifests en Git | http://192.168.109.200:30094 |
| **Argo CD** | CD — sincroniza Git → cluster (GitOps) | http://192.168.109.200:30095 |
| **Prometheus + Grafana** | Métricas — réplicas y tráfico por versión | http://192.168.109.200:30093 |
| **Loki** | Logs — filtrados por label de versión | Grafana → Explore |
| **Linkerd Viz** | Tráfico en tiempo real entre servicios | http://192.168.109.200:30091 |

---

## Arquitectura del ejercicio

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FLUJO CI/CD CANARY                                   │
│                                                                               │
│  1. Developer                                                                 │
│     └─▶ git commit "activar canary v2"                                       │
│          └─▶ git push ──────────────────────────▶ GitHub (repo)              │
│                                                        │                      │
│  2. Tekton Pipeline (CI)  ◀─────── trigger manual ────┘                      │
│     ├─▶ Task: git-clone   (clona el repo)                                    │
│     ├─▶ Task: validate    (verifica YAMLs)                                   │
│     └─▶ Task: update-canary (cambia réplicas 0→1, git push)                 │
│                                                        │                      │
│  3. Argo CD (CD/GitOps)  ◀─── detecta cambio en Git ──┘                     │
│     └─▶ kubectl apply manifests/04-canary-deployment.yaml                   │
│                                                                               │
│  4. Kubernetes cluster                                                        │
│     ├─▶ webapp-stable:  9 pods ──┐                                           │
│     └─▶ webapp-canary:  1 pod  ──┴──▶ Service webapp (NodePort 30099)       │
│                                            │                                  │
│                              ┌─────────────┴──────────────┐                 │
│                              │   90% → v1 (azul)           │                 │
│                              │   10% → v2 (verde) CANARY   │                 │
│                              └────────────────────────────┘                 │
│                                                                               │
│  5. Observabilidad                                                            │
│     ├─▶ Grafana: réplicas por versión + % de tráfico                        │
│     └─▶ Loki:   logs filtrados por pod stable vs canary                     │
│                                                                               │
│  6. Promoción gradual (comandos manuales o scripts)                          │
│     Fase 1: stable=9, canary=1  → 90/10                                     │
│     Fase 2: stable=5, canary=5  → 50/50                                     │
│     Fase 3: stable=0, canary=10 → 100% v2 (completado)                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Guión para el instructor

### Apertura: El problema real (10 min)

Plantear a la clase:
```
Escenario: Tu equipo desarrolló WebApp v2.0 con nuevas features.
La quieren desplegar a producción, pero:

  Opción A: Desplegar todo de golpe (big-bang deploy)
    → Si v2 tiene un bug, el 100% de los usuarios se ve afectado
    → Rollback tardío y costoso

  Opción B: Canary Deployment
    → Primero el 10% del tráfico va a v2
    → Si hay problemas, solo afecta al 10%
    → Rollback instantáneo: kubectl scale --replicas=0
    → Con métricas OK → promover gradualmente al 100%
```

**Pregunta a la clase:** ¿Qué necesitamos para que el equipo pueda hacer esto de forma segura y repetible?
→ Respuesta: Un pipeline automatizado (Tekton) + GitOps (Argo CD) + Observabilidad

### Diagrama en pizarra — El loop GitOps+CI/CD (5 min)

```
Code change
    │
    ▼
Tekton Pipeline  ──▶  valida + actualiza manifest  ──▶  git push
                                                              │
                                                         GitHub repo
                                                              │
                                                         Argo CD detects
                                                              │
                                                         kubectl apply
                                                              │
                                                         Canary pod aparece
                                                              │
                                                     10% tráfico → v2
                                                              │
                                              Observar en Grafana/Loki/Linkerd
                                                              │
                                                    OK → Promover (50% → 100%)
                                                    ERROR → Rollback inmediato
```

---

## Pre-requisitos

```bash
# Verificar que los stacks previos están corriendo
kubectl get pods -n monitoring        # Prometheus, Grafana, Loki, Tempo
kubectl get pods -n argocd            # Argo CD
kubectl get pods -n tekton-pipelines  # Tekton
kubectl get pods -n linkerd           # Linkerd

# El repo debe ser PÚBLICO en GitHub
# Variables del instructor — ajustar según el entorno:
REPO_URL="https://github.com/dguerrero11/kubernetes-devops"
REPO_OWNER="dguerrero11"
REPO_NAME="kubernetes-devops"
```

---

## FASE 0 — Preparación inicial

### 0.1 — Crear el namespace e inyectar Linkerd

```bash
cd /root/devops2026/20-canary-cicd

kubectl apply -f manifests/01-namespace.yaml

# Verificar que Linkerd está inyectado
kubectl get namespace canary-demo --show-labels
```

### 0.2 — Crear el GitHub PAT Secret (para que Tekton pueda hacer git push)

El instructor debe crear un PAT en GitHub:
```
GitHub → Settings → Developer settings → Personal access tokens
→ Generate new token (classic)
→ Scope: repo (full control)
→ Copiar el token
```

```bash
# Editar el archivo con el token real antes de aplicar
# kubectl create secret generic github-token \
#   --from-literal=token=ghp_TU_TOKEN_AQUI \
#   -n tekton-pipelines

# O aplicar el template y editar luego:
kubectl apply -f tekton/01-github-secret.yaml
kubectl edit secret github-token -n tekton-pipelines
# Reemplazar el valor en base64: echo -n "ghp_TU_TOKEN" | base64
```

### 0.3 — Crear workspace y RBAC para Tekton

```bash
kubectl apply -f tekton/02-rbac.yaml
kubectl apply -f tekton/03-workspace-pvc.yaml

# Verificar
kubectl get pvc -n tekton-pipelines
kubectl get serviceaccount canary-pipeline-sa -n tekton-pipelines
```

---

## FASE 1 — Desplegar v1 Stable con Argo CD

### 1.1 — Aplicar la Application de Argo CD

```bash
kubectl apply -f argocd/01-app-canary.yaml

# Ver la app en Argo CD UI → http://192.168.109.200:30095
# La app "webapp-canary" debería aparecer como OutOfSync al principio
```

### 1.2 — Sincronizar manualmente (primera vez)

```bash
# Vía CLI
argocd app sync webapp-canary

# O en la UI: click en el botón "SYNC"
```

**¿Qué hace Argo CD aquí?**
Lee la carpeta `20-canary-cicd/manifests/` del repo GitHub y aplica todos los YAMLs en el namespace `canary-demo`.

### 1.3 — Verificar el estado inicial

```bash
kubectl get pods -n canary-demo
```

Salida esperada:
```
NAME                            READY   STATUS    RESTARTS   AGE
webapp-stable-xxxxx-1           2/2     Running   0          30s   ← 2/2 = sidecar Linkerd
webapp-stable-xxxxx-2           2/2     Running   0          30s
webapp-stable-xxxxx-3           2/2     Running   0          30s
...  (9 pods stable, 0 pods canary)
```

```bash
# Ver el split actual (debería ser 9 stable, 0 canary)
kubectl get deployments -n canary-demo
```

### 1.4 — Abrir la aplicación en el browser

```
http://192.168.109.200:30099
```

**Ver en clase:** Página azul → VERSION 1.0 — STABLE
Refrescar varias veces → siempre azul (no hay pods canary todavía)

---

## FASE 2 — Activar el Canary v2 con Tekton CI

### 2.1 — Registrar las Tasks y el Pipeline de Tekton

```bash
# Aplicar en orden
kubectl apply -f tekton/04-task-clone.yaml
kubectl apply -f tekton/05-task-validate.yaml
kubectl apply -f tekton/06-task-update-canary.yaml
kubectl apply -f tekton/07-pipeline.yaml

# Verificar
kubectl get tasks -n tekton-pipelines
kubectl get pipeline -n tekton-pipelines
```

Salida esperada:
```
NAME                          AGE
canary-clone-task             10s
canary-validate-task          10s
canary-update-manifest-task   10s

NAME               AGE
canary-pipeline    10s
```

### 2.2 — Abrir el Tekton Dashboard

```
http://192.168.109.200:30094
```

Tener el dashboard abierto para que la clase vea el pipeline en tiempo real.

### 2.3 — Lanzar el PipelineRun (¡aquí empieza la acción!)

```bash
# Editar el PipelineRun si se necesita cambiar parámetros
cat tekton/08-pipelinerun.yaml

# Lanzar el pipeline
kubectl create -f tekton/08-pipelinerun.yaml

# Ver el estado en tiempo real
kubectl get pipelinerun -n tekton-pipelines -w
```

**En el Tekton Dashboard** — mostrar en pantalla:
1. PipelineRun aparece → `Running`
2. TaskRun `clone` → aparece el pod → Running → Succeeded
3. TaskRun `validate` → Running → Succeeded
4. TaskRun `update-canary` → Running → **Succeeded** (cambia réplicas + git push)

### 2.4 — Verificar que el manifest cambió en GitHub

Abrir el repo en GitHub y navegar a:
```
20-canary-cicd/manifests/04-canary-deployment.yaml
```

**Ver en clase:** El campo `replicas` pasó de `0` → `1`
El commit fue hecho por "Tekton Pipeline" con mensaje: `canary: activate v2 with 1 replica [ci]`

### 2.5 — Argo CD detecta el cambio automáticamente

```bash
# Argo CD pollean cada 3 minutos. Para demostrarlo más rápido:
argocd app sync webapp-canary

# O esperar 3 min y refrescar la UI de Argo CD
```

**En el Argo CD UI** — mostrar en pantalla:
- La app pasa de `Synced` → `OutOfSync` (detectó el cambio en git)
- Luego de `OutOfSync` → `Syncing` → `Synced`
- En la vista de árbol: aparece el pod `webapp-canary-xxxxx`

---

## FASE 3 — Observar el Canary (10% tráfico)

### 3.1 — Verificar pods: 9 stable + 1 canary

```bash
kubectl get pods -n canary-demo --show-labels
```

Salida esperada:
```
NAME                            READY   STATUS    LABELS
webapp-stable-xxxxx-0001        2/2     Running   app=webapp,version=stable
...                                               (9 pods)
webapp-canary-yyyyy-0001        2/2     Running   app=webapp,version=canary
```

```bash
# Ver el split de réplicas
kubectl get deployments -n canary-demo
```

```
NAME             READY   UP-TO-DATE   AVAILABLE
webapp-stable    9/9     9            9
webapp-canary    1/1     1            1
```

### 3.2 — Ejecutar el generador de carga

```bash
# El load-generator ya debería estar corriendo (lo desplegó Argo CD)
kubectl get pods -n canary-demo -l app=load-generator

# Si se quiere ver el tráfico en tiempo real desde el master:
watch -n 1 'kubectl logs -n canary-demo -l app=load-generator --tail=5'
```

### 3.3 — Ver el tráfico en tiempo real desde fuera

Desde la máquina local del estudiante (o desde el master):

```bash
# Script watch-traffic: pide la URL 20 veces y cuenta v1 vs v2
bash scripts/watch-traffic.sh
```

Salida esperada (aproximada con 10% canary):
```
Enviando 20 peticiones a http://192.168.109.200:30099 ...

v1 (azul)   : ████████████████████░░░░░░░░░░ 18/20  (90%)
v2 (verde)  : ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░  2/20  (10%)

Split actual: STABLE=9  CANARY=1
```

### 3.4 — Ver logs en Grafana/Loki

En Grafana → Explore → Loki:

```logql
# Logs del pod stable
{namespace="canary-demo"} |= "stable"

# Logs del pod canary
{namespace="canary-demo"} |= "canary"

# Comparar ambos en panels separados
{namespace="canary-demo", pod=~"webapp-stable.*"}
{namespace="canary-demo", pod=~"webapp-canary.*"}
```

### 3.5 — Ver métricas en Grafana/Prometheus

En Grafana → Explore → Prometheus:

```promql
# Réplicas deseadas por versión
kube_deployment_spec_replicas{namespace="canary-demo"}

# Pods listos por versión
kube_deployment_status_replicas_ready{namespace="canary-demo"}

# % de tráfico hacia canary (réplica-based)
kube_deployment_spec_replicas{namespace="canary-demo",deployment="webapp-canary"}
  /
(kube_deployment_spec_replicas{namespace="canary-demo",deployment="webapp-stable"}
  + kube_deployment_spec_replicas{namespace="canary-demo",deployment="webapp-canary"})
* 100
```

**Importar el dashboard de Grafana:**
```bash
# El JSON del dashboard está en monitoring/02-grafana-canary-dashboard.json
# En Grafana → Dashboards → Import → subir el archivo JSON
```

### 3.6 — Ver en Linkerd Viz

```
http://192.168.109.200:30091
```

Navegando a `Deployments → canary-demo`:
- `webapp-stable`: success rate, RPS, latency P99
- `webapp-canary`: success rate, RPS, latency P99

---

## FASE 4 — Promover al 50/50

### Método GitOps (recomendado en producción)

```bash
# Editar los manifests localmente
cd /root/devops2026

# Cambiar stable: 9 → 5 réplicas
yq e '.spec.replicas = 5' -i 20-canary-cicd/manifests/03-stable-deployment.yaml

# Cambiar canary: 1 → 5 réplicas
yq e '.spec.replicas = 5' -i 20-canary-cicd/manifests/04-canary-deployment.yaml

# Commit y push
git add 20-canary-cicd/manifests/
git commit -m "canary: promote to 50/50 split"
git push

# Sincronizar Argo CD (o esperar 3 min)
argocd app sync webapp-canary
```

### Método rápido para la demo (kubectl directo)

```bash
bash scripts/promote-10-to-50.sh
```

### Verificar el split 50/50

```bash
kubectl get deployments -n canary-demo
```

```
NAME             READY   UP-TO-DATE   AVAILABLE
webapp-stable    5/5     5            5
webapp-canary    5/5     5            5
```

```bash
# Verificar con watch-traffic
bash scripts/watch-traffic.sh
```

Salida esperada:
```
v1 (azul)   : ███████████████░░░░░░░░░░░░░░░ 10/20  (50%)
v2 (verde)  : ███████████████░░░░░░░░░░░░░░░ 10/20  (50%)
```

---

## FASE 5 — Promover al 100% v2 (Full Rollout)

```bash
# Método rápido
bash scripts/promote-50-to-100.sh

# O GitOps:
yq e '.spec.replicas = 0' -i 20-canary-cicd/manifests/03-stable-deployment.yaml
yq e '.spec.replicas = 10' -i 20-canary-cicd/manifests/04-canary-deployment.yaml
git add 20-canary-cicd/manifests/
git commit -m "canary: promote to 100% v2 — migration complete"
git push
argocd app sync webapp-canary
```

### Verificar el 100%

```bash
kubectl get deployments -n canary-demo
```

```
NAME             READY   UP-TO-DATE   AVAILABLE
webapp-stable    0/0     0            0      ← inactivo
webapp-canary    10/10   10           10     ← 100% tráfico
```

Abrir `http://192.168.109.200:30099` → siempre verde → Version 2.0
Refrescar muchas veces → siempre v2. ¡Migración completa!

---

## FASE 6 — Rollback de Emergencia

### Escenario: v2 tiene un bug crítico en producción

```bash
# Rollback INMEDIATO: restaurar v1 al 100%
bash scripts/rollback.sh
```

O manualmente:
```bash
kubectl scale deployment webapp-canary -n canary-demo --replicas=0
kubectl scale deployment webapp-stable -n canary-demo --replicas=9
```

**Ver en clase:**
- Pods de canary desaparecen en segundos
- `http://192.168.109.200:30099` → vuelve a azul

**Tiempo de rollback: < 30 segundos** ← punto clave para la clase

---

## FASE 7 — Ver cambios en el historial (Argo CD)

En Argo CD UI:
1. Click en la app `webapp-canary`
2. Tab **History and Rollback** → ver todos los syncs
3. Click en cualquier sync → ver el diff exacto del manifest
4. Botón **Rollback** → Argo CD revierte a ese estado en Git

**Punto clave:** El historial completo de todos los despliegues está en:
1. `git log` en el repo GitHub
2. Argo CD History tab
3. Tekton Dashboard → PipelineRuns

---

## Visualización completa — Panel de Control

Abrir todos estos en tabs separados del browser durante la demo:

```
Tab 1: http://192.168.109.200:30095     → Argo CD (estado GitOps)
Tab 2: http://192.168.109.200:30094     → Tekton Dashboard (pipeline CI)
Tab 3: http://192.168.109.200:30093     → Grafana (métricas + logs)
Tab 4: http://192.168.109.200:30091     → Linkerd Viz (tráfico en malla)
Tab 5: http://192.168.109.200:30099     → WebApp (ver v1 azul / v2 verde)
```

En terminal, en split-screen:
```bash
# Terminal izq: watch pods
watch -n 2 'kubectl get deployments -n canary-demo'

# Terminal der: watch tráfico
bash scripts/watch-traffic.sh
```

---

## Resumen — Lo que integramos hoy

```
┌─────────────────┬─────────────────────────────────────────────────────┐
│ Módulo          │ Rol en este ejercicio                               │
├─────────────────┼─────────────────────────────────────────────────────┤
│ 11 — Tekton     │ CI: clone → validate → update manifest → git push   │
│ 12 — Argo CD    │ CD: detecta cambio en Git → aplica al cluster       │
│ 10 — Prometheus │ Métricas de réplicas y % de tráfico por versión     │
│ 16 — Loki       │ Logs filtrados por label version=stable/canary      │
│ 19 — Linkerd    │ Tráfico en tiempo real, success rate por versión    │
│ 14 — NetPolicy  │ (opcional) Aislar namespace canary-demo             │
│ 15 — Pod Sec    │ (opcional) PSA enforce baseline en canary-demo      │
└─────────────────┴─────────────────────────────────────────────────────┘
```

**El patrón GitOps completo:**
```
Developer → Git → Tekton CI → Git → Argo CD → Kubernetes
                                         ↑
                                    Observabilidad
                                 (Grafana + Loki + Linkerd)
```

---

## Troubleshooting

### Argo CD no sincroniza
```bash
# Forzar sync
argocd app sync webapp-canary --force

# Ver por qué no sincroniza
argocd app get webapp-canary
```

### Tekton PipelineRun falla en update-canary task
```bash
# Ver logs de la tarea
kubectl get pipelinerun -n tekton-pipelines
kubectl get taskrun -n tekton-pipelines
kubectl logs -n tekton-pipelines <taskrun-pod> -c step-git-push
```

### El PAT de GitHub no funciona
```bash
# Verificar el secret
kubectl get secret github-token -n tekton-pipelines -o jsonpath='{.data.token}' | base64 -d

# El token debe tener scope: repo (full control)
```

### Los pods canary no aparecen después de Argo CD sync
```bash
# Ver si el deployment canary tiene replicas=0 todavía en git
kubectl get deployment webapp-canary -n canary-demo -o yaml | grep replicas

# Ver los eventos
kubectl describe deployment webapp-canary -n canary-demo
```

### watch-traffic.sh siempre muestra 100% v1
```bash
# Verificar que el pod canary está running
kubectl get pods -n canary-demo -l version=canary

# Verificar que el service selecciona app=webapp (sin version filter)
kubectl get svc webapp -n canary-demo -o yaml | grep selector -A3
```
