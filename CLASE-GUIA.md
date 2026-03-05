# Guía de Clase — Kubernetes Básico

**Cluster:** k8s-master01 (192.168.109.200) | worker01 (.201) | worker02 (.202)
**Directorio:** `/root/devops2026`
**Versión:** Kubernetes v1.28.15

---

## Antes de empezar

```bash
# Verificar que el cluster está OK
kubectl get nodes
kubectl get nodes -o wide

# Verificar que estamos en el namespace correcto
kubectl config get-contexts
kubectl config view --minify | grep namespace
```

**Resultado esperado:** 3 nodos en estado `Ready`.

---

## MÓDULO 1 — Pods

> **Concepto:** El Pod es la unidad mínima de despliegue en Kubernetes.
> No se despliegan contenedores directamente, sino Pods que los contienen.

### 1.1 Pod básico

```bash
cd /root/devops2026

# Crear el Pod
kubectl apply -f 01-pods/01-pod-basico.yaml

# Ver el Pod
kubectl get pods
kubectl get pods -o wide     # ver en qué nodo quedó

# Esperar a que esté Running
kubectl get pods -w          # Ctrl+C para salir del watch
```

**Señalar en pantalla:**
- La columna `STATUS` cambia: `Pending → ContainerCreating → Running`
- La columna `NODE` muestra en qué worker quedó el Pod
- Kubernetes decidió el nodo automáticamente (scheduling)

```bash
# Inspeccionar el Pod en detalle
kubectl describe pod nginx-basico

# Ver logs del contenedor
kubectl logs nginx-basico

# Entrar al contenedor
kubectl exec -it nginx-basico -- bash
  # Dentro del contenedor:
  curl localhost
  hostname
  exit

# Eliminar el Pod
kubectl delete pod nginx-basico
kubectl get pods              # desapareció y NO vuelve (es solo un Pod)
```

> **Punto clave:** Si un Pod muere y no hay nada que lo gestione, se pierde.
> Por eso usamos ReplicaSets y Deployments.

---

### 1.2 Labels y Annotations

```bash
kubectl apply -f 01-pods/02-pod-labels-annotations.yaml

# Ver los labels
kubectl get pods --show-labels

# Filtrar por label
kubectl get pods -l app=web
kubectl get pods -l env=desarrollo
kubectl get pods -l app=web,env=desarrollo   # AND lógico

# Agregar un label en caliente
kubectl label pod nginx-etiquetado version=v2
kubectl get pods --show-labels

# Ver las annotations
kubectl describe pod nginx-etiquetado | grep -A5 Annotations

kubectl delete pod nginx-etiquetado
```

> **Punto clave:** Los labels son el mecanismo de "descubrimiento" en Kubernetes.
> Services y ReplicaSets usan labels para saber qué Pods controlar.

---

### 1.3 Recursos (requests y limits)

```bash
kubectl apply -f 01-pods/03-pod-recursos.yaml

kubectl describe pod nginx-recursos | grep -A6 "Limits\|Requests"
```

**Explicar en pizarra:**
```
requests  →  "Necesito al menos esto"   →  el Scheduler lo usa para ELEGIR NODO
limits    →  "No puedo usar más que esto" →  si lo supera:
              CPU:    throttling (lentitud)
              Memory: OOMKilled (reinicio)
```

```bash
# Simular que no hay nodo con suficientes recursos
# (solo para explicar, no ejecutar en clase)
# Un Pod con requests muy altos quedaría en Pending:
# kubectl describe pod → Events → "Insufficient cpu"

kubectl delete pod nginx-recursos
```

---

### 1.4 Pod Multicontenedor (patrón Sidecar)

```bash
kubectl apply -f 01-pods/04-pod-multicontenedor.yaml

# Ver que hay 2/2 contenedores listos
kubectl get pods nginx-sidecar

# Logs de cada contenedor por separado
kubectl logs nginx-sidecar -c nginx
kubectl logs nginx-sidecar -c generador-html

# Probar que el sidecar está escribiendo y nginx lo sirve
kubectl port-forward pod/nginx-sidecar 8080:80 &
curl http://localhost:8080
# Esperar 5 segundos y volver a probar
sleep 5 && curl http://localhost:8080
# La fecha en el HTML cambia cada 5 segundos (el sidecar escribe, nginx sirve)
kill %1   # detener el port-forward

kubectl delete pod nginx-sidecar
```

> **Punto clave:** Los dos contenedores comparten el mismo volumen `emptyDir`.
> El sidecar escribe, nginx lee. Mismo Pod = misma IP, mismos volúmenes.

---

## MÓDULO 2 — Namespaces

> **Concepto:** Partición virtual del cluster. Permite separar recursos por entorno, equipo o proyecto.

```bash
# Ver los namespaces que ya existen
kubectl get namespaces

# Ver qué hay en kube-system (componentes internos)
kubectl get pods -n kube-system

# Crear nuestro namespace
kubectl apply -f 02-namespaces/01-namespace.yaml
kubectl get ns

# Desplegar un Pod en ese namespace
kubectl apply -f 02-namespaces/02-pod-en-namespace.yaml

# Sin -n no se ve
kubectl get pods

# Con -n sí se ve
kubectl get pods -n devops-demo

# Ver todo en un namespace
kubectl get all -n devops-demo

# Cambiar el namespace por defecto del contexto
kubectl config set-context --current --namespace=devops-demo
kubectl get pods    # ahora muestra devops-demo sin -n

# Volver al namespace default
kubectl config set-context --current --namespace=default

kubectl delete ns devops-demo
# Nota: esto borra TODO lo que hay dentro del namespace
```

> **Punto clave:** Los nombres de recursos son únicos DENTRO de un namespace.
> Puedes tener un pod "nginx" en `default` y otro "nginx" en `devops-demo`.

---

## MÓDULO 3 — ReplicaSets

> **Concepto:** Garantiza que siempre haya N réplicas de un Pod corriendo.
> Es el mecanismo de auto-healing de Kubernetes.

```bash
kubectl apply -f 03-replicasets/01-replicaset.yaml

kubectl get rs
kubectl get pods
kubectl get pods -l app=nginx-rs    # solo los pods del RS

# ----- DEMO AUTO-HEALING -----
# Abrir segunda terminal y poner en watch:
kubectl get pods -w

# En la primera terminal, eliminar un Pod:
kubectl delete pod <nombre-de-uno-de-los-pods>

# Observar en el watch: el Pod muere y al instante aparece uno nuevo
# El RS detectó que hay 2 en vez de 3 y creó uno nuevo automáticamente

# ----- DEMO ESCALAR -----
kubectl scale rs nginx-replicaset --replicas=5
kubectl get pods

kubectl scale rs nginx-replicaset --replicas=2
kubectl get pods

kubectl describe rs nginx-replicaset   # ver eventos del RS

kubectl delete -f 03-replicasets/01-replicaset.yaml
```

> **Punto clave:** En la práctica no se crea un ReplicaSet directamente.
> Se usa un **Deployment**, que internamente crea y gestiona el ReplicaSet.

---

## MÓDULO 4 — Deployments

> **Concepto:** El recurso más usado en Kubernetes. Gestiona ReplicaSets y
> habilita actualizaciones sin downtime y rollback automático.
>
> Jerarquía: `Deployment → ReplicaSet → Pods`

### 4.1 Deployment básico

```bash
kubectl apply -f 04-deployments/01-deployment-basico.yaml

# Ver todos los recursos creados
kubectl get all
kubectl get deploy,rs,pods

kubectl describe deployment nginx-deploy

# Escalar
kubectl scale deployment nginx-deploy --replicas=5
kubectl get pods -w

kubectl scale deployment nginx-deploy --replicas=3
```

---

### 4.2 Rolling Update y Rollback

```bash
kubectl apply -f 04-deployments/02-deployment-rolling-update.yaml
kubectl get pods

# ----- DEMO ROLLING UPDATE -----
# Abrir segunda terminal con watch
kubectl get pods -w

# Actualizar la imagen (dispara el rolling update)
kubectl set image deployment/nginx-rolling nginx=nginx:1.26

# Observar: Kubernetes crea Pods nuevos de a 1 (maxSurge=1)
# y espera que estén Ready antes de eliminar los viejos (maxUnavailable=0)
# → CERO DOWNTIME durante la actualización

# Ver el estado del rollout
kubectl rollout status deployment/nginx-rolling

# Ver el historial
kubectl rollout history deployment/nginx-rolling

# Actualizar de nuevo con una "causa" registrada
kubectl set image deployment/nginx-rolling nginx=nginx:1.27
kubectl annotate deployment/nginx-rolling \
  kubernetes.io/change-cause="Actualización a nginx 1.27 por prueba de clase"

kubectl rollout history deployment/nginx-rolling

# ----- DEMO ROLLBACK -----
kubectl rollout undo deployment/nginx-rolling
kubectl rollout status deployment/nginx-rolling

# Volver a una revisión específica
kubectl rollout undo deployment/nginx-rolling --to-revision=1
kubectl rollout history deployment/nginx-rolling

kubectl delete -f 04-deployments/02-deployment-rolling-update.yaml
```

> **Punto clave:** `maxUnavailable=0` + `maxSurge=1` = zero downtime deployment.
> Siempre hay al menos N Pods disponibles durante la actualización.

---

### 4.3 Health Checks (Probes)

```bash
kubectl apply -f 04-deployments/03-deployment-probes.yaml
kubectl get pods

kubectl describe pod <nombre-pod> | grep -A15 "Liveness\|Readiness"

# ----- DEMO: simular fallo de liveness -----
kubectl exec -it <nombre-pod> -- nginx -s stop

# El proceso nginx muere → liveness falla → Kubernetes reinicia el contenedor
kubectl get pods -w   # ver RESTARTS incrementar

kubectl delete -f 04-deployments/03-deployment-probes.yaml
```

**Cuadro resumen Probes:**

| Probe | Si falla | Cuándo usar |
|---|---|---|
| `livenessProbe` | Reinicia el contenedor | Detectar deadlocks, procesos colgados |
| `readinessProbe` | Saca el Pod del Service | App en calentamiento, BD no disponible |
| `startupProbe` | Reinicia el contenedor | Apps lentas en arrancar |

---

## MÓDULO 5 — Services

> **Concepto:** Los Pods tienen IPs dinámicas (cambian al reiniciarse).
> Un Service da una IP y DNS estables para acceder a un grupo de Pods.

### 5.1 ClusterIP

```bash
kubectl apply -f 04-deployments/01-deployment-basico.yaml
kubectl apply -f 05-services/01-service-clusterip.yaml

kubectl get svc
kubectl describe svc nginx-clusterip
# Ver: Endpoints → IPs de los Pods seleccionados

# Probar desde dentro del cluster
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://nginx-clusterip

# El DNS de Kubernetes resuelve el nombre del Service:
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  curl http://nginx-clusterip.default.svc.cluster.local
```

> **Punto clave:** Solo accesible DENTRO del cluster. Para comunicación entre microservicios.

---

### 5.2 NodePort

```bash
kubectl apply -f 05-services/02-service-nodeport.yaml

kubectl get svc nginx-nodeport
# Ver: PORT(S) → 80:30080/TCP

# Probar desde FUERA del cluster (desde tu PC o el servidor):
curl http://192.168.109.200:30080
curl http://192.168.109.201:30080
curl http://192.168.109.202:30080
# Los tres responden igual (el tráfico llega a los mismos Pods)

kubectl delete -f 04-deployments/01-deployment-basico.yaml
kubectl delete -f 05-services/01-service-clusterip.yaml
kubectl delete -f 05-services/02-service-nodeport.yaml
```

---

### 5.3 Deployment + Service (manifiesto combinado)

```bash
kubectl apply -f 05-services/03-deployment-y-service-completo.yaml

kubectl get all -l app=nginx-web

# Ver a qué Pods está apuntando el Service
kubectl get endpoints nginx-web-svc

# Escalar y ver que el Service detecta los nuevos Pods automáticamente
kubectl scale deployment nginx-web --replicas=5
kubectl get endpoints nginx-web-svc   # aparecen las 5 IPs

# Probar desde fuera:
curl http://192.168.109.200:30090

kubectl delete -f 05-services/03-deployment-y-service-completo.yaml
```

---

## MÓDULO 6 — ConfigMaps

> **Concepto:** Almacena configuración NO sensible separada del código.
> Cambiar config sin reconstruir la imagen del contenedor.

### 6.1 Crear y explorar un ConfigMap

```bash
kubectl apply -f 06-configmaps/01-configmap-literal.yaml

kubectl get cm
kubectl describe cm app-config
kubectl get cm app-config -o yaml

# Crear desde línea de comandos (demostración rápida)
kubectl create configmap demo-rapido \
  --from-literal=ENV=produccion \
  --from-literal=PORT=3000
kubectl get cm demo-rapido -o yaml
kubectl delete cm demo-rapido
```

---

### 6.2 ConfigMap como variables de entorno

```bash
kubectl apply -f 06-configmaps/02-configmap-como-envvar.yaml

# Ver las env vars dentro del contenedor
kubectl exec -it pod-con-envfrom -- env | sort
kubectl exec -it pod-con-envfrom -- printenv APP_ENV
kubectl exec -it pod-con-envfrom -- printenv MI_ENTORNO

# Modificar el ConfigMap y ver que el Pod NO se actualiza
kubectl patch cm app-config -p '{"data":{"APP_ENV":"staging"}}'
kubectl exec -it pod-con-envfrom -- printenv APP_ENV
# Sigue mostrando "desarrollo" → hay que reiniciar el Pod

kubectl delete pod pod-con-envfrom   # el Pod se recrea (si hay Deployment)
# Si es solo un Pod, recrearlo manualmente con apply

kubectl delete pod pod-con-envfrom
```

---

### 6.3 ConfigMap como volumen (actualización automática)

```bash
kubectl apply -f 06-configmaps/03-configmap-como-volumen.yaml

kubectl exec -it pod-con-volumen-cm -- ls /etc/config/
kubectl exec -it pod-con-volumen-cm -- cat /etc/config/APP_ENV

# Modificar el ConfigMap
kubectl patch cm app-config -p '{"data":{"APP_ENV":"produccion"}}'

# Esperar ~60 segundos y verificar
sleep 60
kubectl exec -it pod-con-volumen-cm -- cat /etc/config/APP_ENV
# Ahora muestra "produccion" sin haber reiniciado el Pod

kubectl delete pod pod-con-volumen-cm
kubectl delete cm app-config
```

> **Diferencia clave:**
> - Env vars → se leen al iniciar → cambio requiere reinicio
> - Volumen  → se actualizan en ~60s → sin reinicio

---

## MÓDULO 7 — Secrets

> **Concepto:** Como ConfigMap pero para datos sensibles.
> Los valores se almacenan en base64 (NO es cifrado, es codificación).

### 7.1 Crear y explorar Secrets

```bash
kubectl apply -f 07-secrets/01-secret-opaque.yaml

kubectl get secrets
kubectl describe secret db-credentials   # NO muestra los valores

# Para ver el valor (base64):
kubectl get secret db-credentials -o yaml

# Decodificar:
kubectl get secret db-credentials \
  -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode
echo ""

# Crear Secret rápido (base64 automático):
kubectl create secret generic mi-secret \
  --from-literal=password=supersecreta123
kubectl get secret mi-secret -o jsonpath='{.data.password}' | base64 --decode
echo ""
kubectl delete secret mi-secret
```

---

### 7.2 Secret como env var y volumen

```bash
kubectl apply -f 07-secrets/02-secret-como-envvar-y-volumen.yaml

# Ver env vars (solo en clase/demo, nunca en producción)
kubectl exec -it pod-con-secret -- printenv DATABASE_USER
kubectl exec -it pod-con-secret -- printenv DATABASE_PASSWORD

# Ver archivos montados desde el Secret
kubectl exec -it pod-con-secret -- ls -la /etc/secretos/
kubectl exec -it pod-con-secret -- cat /etc/secretos/DB_PASSWORD

kubectl delete pod pod-con-secret
kubectl delete secret db-credentials api-credentials
```

> **Advertencia para producción:**
> - base64 NO es seguro por sí solo
> - En producción usar: Sealed Secrets, HashiCorp Vault, External Secrets Operator

---

## MÓDULO 8 — Almacenamiento Persistente

> **Concepto:** Los datos en un Pod se pierden cuando el Pod muere.
> PersistentVolumes permiten almacenamiento que sobrevive a los Pods.

**Flujo:** `Admin crea PV → Developer crea PVC → Pod monta el PVC`

```
nfs01 (192.168.109.210)
/srv/nfs/k8s              ← PV 1 (10Gi)
/srv/nfs/k8s-storage      ← PV 2 (20Gi)
```

### Prerequisito: cliente NFS en los nodos

```bash
# Verificar que nfs-utils está instalado en todos los nodos
# (ejecutar en master, worker01 y worker02)
rpm -q nfs-utils

# Si no está instalado:
# dnf install -y nfs-utils

# Verificar que el NFS es accesible desde el cluster
showmount -e 192.168.109.210
```

---

### 8.1 Crear PersistentVolumes

```bash
kubectl apply -f 08-storage/01-persistentvolume-nfs.yaml

kubectl get pv
# Ver STATUS: Available (sin PVC todavía)
kubectl describe pv pv-nfs-k8s
```

---

### 8.2 Crear PersistentVolumeClaims

```bash
kubectl apply -f 08-storage/02-persistentvolumeclaim.yaml

# Ver el binding PVC → PV
kubectl get pvc
kubectl get pv
# PVC: STATUS = Bound
# PV:  STATUS = Bound, CLAIM = default/pvc-app-datos

kubectl describe pvc pvc-app-datos
```

---

### 8.3 Demo de Persistencia

```bash
kubectl apply -f 08-storage/03-deployment-con-pvc.yaml

kubectl get pods -l app=nginx-storage

# PASO 1: escribir datos en el volumen persistente
POD=$(kubectl get pods -l app=nginx-storage -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -- bash -c \
  'echo "Datos que sobreviven al Pod - $(date)" > /datos/test.txt'
kubectl exec -it $POD -- cat /datos/test.txt

# PASO 2: eliminar el Pod
kubectl delete pod $POD
kubectl get pods -w   # Deployment crea uno nuevo automáticamente

# PASO 3: leer datos en el nuevo Pod
POD_NUEVO=$(kubectl get pods -l app=nginx-storage -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD_NUEVO -- cat /datos/test.txt
# ¡El archivo sigue ahí!

# PASO 4: verificar en el servidor NFS
# (en nfs01)
# ls /srv/nfs/k8s/
# cat /srv/nfs/k8s/test.txt

kubectl delete -f 08-storage/03-deployment-con-pvc.yaml
kubectl delete -f 08-storage/02-persistentvolumeclaim.yaml
kubectl delete -f 08-storage/01-persistentvolume-nfs.yaml
```

---

## MÓDULO 9 — Ingress

> **Concepto:** Un solo punto de entrada HTTP/HTTPS que enruta a múltiples Services
> según el hostname o el path de la URL.
>
> Sin Ingress → 1 NodePort por aplicación
> Con Ingress → 1 solo punto de entrada para todas las apps

### 9.1 Instalar NGINX Ingress Controller

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

# Esperar a que esté listo (~1-2 minutos)
kubectl get pods -n ingress-nginx -w

# Ver el NodePort asignado
kubectl get svc -n ingress-nginx
```

**Anotar los puertos NodePort:**
```bash
HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
echo "Puerto HTTP del Ingress: $HTTP_PORT"
```

---

### 9.2 Ingress básico (un host → un Service)

```bash
# Preparar el backend
kubectl create deployment app-nginx --image=nginx:1.25 --replicas=2
kubectl expose deployment app-nginx --port=80 --name=nginx-clusterip

# Crear el Ingress
kubectl apply -f 09-ingress/01-ingress-basico.yaml

kubectl get ingress
kubectl describe ingress nginx-ingress-basico

# Probar (reemplazar $HTTP_PORT con el puerto real)
curl http://nginx.192.168.109.200.nip.io:$HTTP_PORT

# nip.io resuelve automáticamente nginx.192.168.109.200.nip.io → 192.168.109.200
# El Ingress Controller lee la cabecera Host y enruta al Service correcto
```

---

### 9.3 Ingress con múltiples aplicaciones

```bash
# Crear segundo backend con Apache (diferente al nginx)
kubectl create deployment app-apache --image=httpd:2.4 --replicas=2
kubectl expose deployment app-apache --port=80 --name=app1-svc

# Reexponer el nginx con el nombre que espera el manifiesto
kubectl expose deployment app-nginx --port=80 --name=app2-svc

kubectl apply -f 09-ingress/02-ingress-multiples-apps.yaml

kubectl get ingress

# Probar enrutamiento por HOSTNAME:
curl http://app1.192.168.109.200.nip.io:$HTTP_PORT   # → Apache
curl http://app2.192.168.109.200.nip.io:$HTTP_PORT   # → Nginx

# Probar enrutamiento por PATH:
curl http://demo.192.168.109.200.nip.io:$HTTP_PORT/api/   # → app1-svc (Apache)
curl http://demo.192.168.109.200.nip.io:$HTTP_PORT/web/   # → app2-svc (Nginx)
```

**Mostrar en diagrama:**
```
                         ┌─────────────────────────────┐
                         │   NGINX Ingress Controller   │
                         └──────────┬──────────────────┘
                                    │ lee los recursos Ingress
              ┌─────────────────────┼──────────────────────┐
              ▼                     ▼                        ▼
  app1.*.nip.io          app2.*.nip.io            demo.*.nip.io/api
       │                      │                        │
       ▼                      ▼                        ▼
  app1-svc (Apache)    app2-svc (Nginx)          app1-svc (Apache)
```

```bash
# Limpieza final
kubectl delete ingress --all
kubectl delete deployment app-nginx app-apache
kubectl delete svc app1-svc app2-svc nginx-clusterip
```

---

## Resumen de comandos más usados en clase

```bash
# Pods
kubectl get pods -o wide
kubectl describe pod <nombre>
kubectl logs <nombre> [-c <contenedor>]
kubectl exec -it <nombre> -- bash
kubectl delete pod <nombre>

# Deployments
kubectl apply -f archivo.yaml
kubectl scale deployment <nombre> --replicas=N
kubectl set image deployment/<nombre> <contenedor>=<imagen>:<tag>
kubectl rollout status deployment/<nombre>
kubectl rollout history deployment/<nombre>
kubectl rollout undo deployment/<nombre>

# Services e Ingress
kubectl get svc
kubectl get endpoints <svc>
kubectl get ingress

# Almacenamiento
kubectl get pv,pvc
kubectl describe pvc <nombre>

# Namespace
kubectl get all -n <namespace>
kubectl config set-context --current --namespace=<namespace>

# Debugging
kubectl get events --sort-by='.lastTimestamp'
kubectl top pods
kubectl top nodes
```

---

*Repositorio: https://github.com/dguerrero11/kubernetes-devops*
