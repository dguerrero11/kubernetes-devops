# Linkerd Cheatsheet — Referencia rápida

## Instalación y verificación

```bash
# Verificar CLI
linkerd version

# Pre-flight check (antes de instalar)
linkerd check --pre

# Instalar control plane
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Verificar control plane
linkerd check

# Instalar extensión Viz
linkerd viz install | kubectl apply -f -
linkerd viz check

# Desinstalar todo
linkerd viz uninstall | kubectl delete -f -
linkerd uninstall | kubectl delete -f -
```

---

## Inyección de sidecars

```bash
# Opción 1: Namespace completo (recomendado para la clase)
kubectl annotate namespace <ns> linkerd.io/inject=enabled

# Opción 2: En el YAML del namespace
metadata:
  annotations:
    linkerd.io/inject: enabled

# Opción 3: Inyección manual en un deployment existente
kubectl get deployment <name> -n <ns> -o yaml \
  | linkerd inject - \
  | kubectl apply -f -

# Inyectar todos los deployments de un namespace
kubectl get deployment -n <ns> -o yaml \
  | linkerd inject - \
  | kubectl apply -f -

# Verificar que el sidecar está inyectado
kubectl get pods -n <ns>
# Los pods con sidecar muestran 2/2 (app + proxy) en lugar de 1/1
```

---

## Métricas y observabilidad

```bash
# Golden signals de todos los deployments del namespace
linkerd viz stat deployment -n linkerd-demo

# Golden signals de services
linkerd viz stat service -n linkerd-demo

# Golden signals de pods
linkerd viz stat pod -n linkerd-demo

# Métricas agrupadas por ruta HTTP (requiere ServiceProfile)
linkerd viz routes deployment/<name> -n <ns>
linkerd viz routes service/<name> -n <ns>

# Edges: ver qué servicios se comunican y si usan mTLS
linkerd viz edges deployment -n linkerd-demo

# Top: tráfico en tiempo real (como top de Linux)
linkerd viz top deployment -n linkerd-demo
```

---

## TAP: Live Traffic Inspection

```bash
# Ver todo el tráfico de un deployment
linkerd viz tap deployment/frontend -n linkerd-demo

# Filtrar por destino
linkerd viz tap deployment/frontend -n linkerd-demo \
  --to service/backend-svc

# Filtrar por método HTTP
linkerd viz tap deployment/frontend -n linkerd-demo \
  --method GET

# Filtrar por ruta
linkerd viz tap deployment/frontend -n linkerd-demo \
  --path /api/data

# Ver solo respuestas con error
linkerd viz tap deployment/frontend -n linkerd-demo \
  | grep "status=5"
```

---

## mTLS

```bash
# Ver estado mTLS entre servicios
linkerd viz edges deployment -n linkerd-demo
# SECURED = √ significa mTLS activo

# Ver el certificado del proxy
kubectl exec -n linkerd-demo deployment/frontend -c linkerd-proxy \
  -- /usr/lib/linkerd/linkerd2-proxy \
     --tls-cert /var/run/linkerd/tls/tls.crt 2>/dev/null | openssl x509 -text

# Verificar que el tráfico está cifrado
linkerd viz stat deployment -n linkerd-demo
# La columna SECURED muestra el porcentaje de tráfico con mTLS
```

---

## ServiceProfile

```bash
# Listar ServiceProfiles
kubectl get serviceprofile -n linkerd-demo

# Ver detalles
kubectl describe serviceprofile <name> -n <ns>

# Ver métricas por ruta (requiere ServiceProfile aplicado)
linkerd viz routes svc/backend-svc -n linkerd-demo

# Estructura del nombre del ServiceProfile:
# <service-name>.<namespace>.svc.cluster.local
# Ejemplo: backend-svc.linkerd-demo.svc.cluster.local
```

---

## HTTPRoute (Traffic Splitting)

```bash
# Listar HTTPRoutes
kubectl get httproute -n linkerd-demo

# Aplicar split
kubectl apply -f 03-traffic-split.yaml

# Modificar weights en tiempo real
kubectl edit httproute backend-traffic-split -n linkerd-demo

# Eliminar split (vuelve a distribución normal de K8s)
kubectl delete httproute backend-traffic-split -n linkerd-demo
```

---

## Dashboard

```bash
# Abrir dashboard (port-forward automático)
linkerd viz dashboard &

# O via NodePort (después de aplicar 06-linkerd-viz-nodeport.yaml)
# http://192.168.109.200:30099

# Acceder directamente a Prometheus de Viz
kubectl port-forward -n linkerd-viz svc/prometheus 9090:9090
```

---

## Diagnóstico de problemas

```bash
# Ver logs del proxy de un pod específico
kubectl logs -n linkerd-demo <pod-name> -c linkerd-proxy

# Ver logs del control plane
kubectl logs -n linkerd -l component=destination
kubectl logs -n linkerd -l component=identity
kubectl logs -n linkerd -l component=proxy-injector

# Verificar que el proxy está recibiendo configuración
linkerd diagnostics proxy-metrics -n linkerd-demo <pod-name>

# Verificar conectividad de Linkerd
linkerd check

# Re-check después de cambios
linkerd viz check
```

---

## Generación de tráfico para demos

```bash
# Pod temporal para generar tráfico continuo
kubectl run -n linkerd-demo -it --rm traffic \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- sh -c 'while true; do
      curl -s http://frontend-svc:80/api/data
      sleep 0.5
    done'

# Contar respuestas de cada versión (en 100 requests)
kubectl run -n linkerd-demo -it --rm counter \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- sh -c 'for i in $(seq 1 100); do
      curl -s http://frontend-svc:80/ 2>/dev/null
    done | sort | uniq -c | sort -rn'
```

---

## Comparativa Linkerd vs Istio

| Feature              | Linkerd v2.14      | Istio v1.20         |
|----------------------|--------------------|---------------------|
| mTLS automático      | ✔ (zero-config)    | ✔ (requiere config) |
| Traffic splitting    | HTTPRoute          | VirtualService      |
| Retries/Timeouts     | ServiceProfile     | VirtualService      |
| Circuit Breaking     | No nativo          | DestinationRule     |
| RAM control plane    | ~200MB             | ~1.5GB+             |
| RAM por sidecar      | ~25MB              | ~100MB+             |
| Instalación          | ~5 min             | ~20 min             |
| Curva de aprendizaje | Baja               | Alta                |
| Protocolo proxy      | Rust (linkerd2-proxy) | C++ (envoy)      |

---

## NodePorts del cluster (módulos 1-19)

| Módulo | Servicio                | NodePort |
|--------|-------------------------|----------|
| 05     | nginx-nodeport          | 30080    |
| 05     | nginx-web-svc           | 30090    |
| 08     | nginx-storage-svc       | 30091    |
| 10     | Prometheus              | 30092    |
| 10     | Grafana                 | 30093    |
| 11     | Tekton Dashboard        | 30094    |
| 12     | Argo CD HTTP            | 30095    |
| 12     | Argo CD HTTPS           | 30096    |
| 18     | AlertManager            | 30097    |
| 18     | Webhook Receiver        | 30098    |
| 19     | Linkerd Viz Dashboard   | 30099    |
| 19     | Frontend Demo App       | 30100    |
