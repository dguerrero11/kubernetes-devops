# Guía de Clase — NetworkPolicies en Kubernetes

**Namespace demo:** `red-demo`
**Directorio:** `/root/devops2026/14-network-policies/`
**CNI requerido:** Calico (ya instalado como CNI del cluster)

---

## 🎓 Guión para el instructor

### El concepto en una frase
> *"Por defecto, en Kubernetes todos los pods pueden hablar con todos. NetworkPolicy es el firewall interno: nosotros decidimos quién puede hablar con quién."*

### La analogía de la oficina de planta abierta (5 min)
```
Kubernetes sin NetworkPolicy:
  Oficina sin paredes ni puertas:
  → Cualquier empleado puede acercarse a cualquier otro
  → El servidor de base de datos puede recibir conexiones de cualquier pod
  → Un pod comprometido puede atacar a todos los demás

Con NetworkPolicy (modelo de lista blanca):
  Puertas con tarjeta de acceso:
  → Solo el empleado de RRHH puede entrar a Nóminas
  → Solo el servidor de aplicación puede hablar con la base de datos
  → Un pod comprometido queda aislado — no puede llegar a otros servicios
```

### El modelo mental clave — lista blanca (10 min)
```
SIN NetworkPolicy:
  pod-A → pod-B  ✅ (permitido por defecto)
  pod-X → pod-B  ✅ (cualquiera puede)

CON default-deny-all + reglas específicas:
  pod-A → pod-B  ✅ (permitido explícitamente)
  pod-X → pod-B  ❌ (bloqueado — no está en la lista blanca)

REGLA DE ORO:
  1. Primero aplica default-deny-all (cierra TODO)
  2. Luego abre solo lo que necesitas (whitelist)
```

### Los 3 selectores clave (10 min)
```
¿A qué pods aplica esta política?
  podSelector: {}                     → a TODOS los pods del namespace
  podSelector: {matchLabels: {app: X}} → solo a pods con label app=X

¿Desde/hacia dónde se permite?
  podSelector    → pods del mismo namespace con esas labels
  namespaceSelector → pods de otros namespaces con esas labels
  ipBlock        → rango de IPs externas (no pods K8s)
```

### Errores más comunes (10 min — para adelantarse a dudas)
```
ERROR 1: Aplicar default-deny-all y olvidar el egress DNS
  Síntoma: curl servidor-svc → "Could not resolve host: servidor-svc"
  Causa: los pods no pueden contactar a CoreDNS (puerto 53)
  Fix: SIEMPRE aplicar 05-allow-egress-dns.yaml después de deny-all

ERROR 2: Confundir ingress/egress
  ingress = tráfico ENTRANTE al pod (quien puede llegar al pod)
  egress  = tráfico SALIENTE del pod (a dónde puede ir el pod)

ERROR 3: selector vacío vs sin selector
  podSelector: {}    → aplica a TODOS los pods (vacío = todos)
  (sin podSelector)  → no aplica a ningún pod (malo en reglas de allow)
```

### Secuencia de demo recomendada (20 min)
```
1. Mostrar comunicación libre (antes de policies)
2. Aplicar 02-default-deny-all.yaml → demostrar bloqueo
3. Mostrar el error DNS (could not resolve)
4. Aplicar 05-allow-egress-dns.yaml → DNS funciona, pero no el tráfico
5. Aplicar 03-allow-same-namespace.yaml → comunicación intra-namespace OK
6. Intentar acceso desde pod externo → sigue bloqueado ✅
7. Aplicar 04-allow-desde-monitoring.yaml → mostrar scraping específico
```

### Preguntas clave para la clase
- *¿Qué pasa si aplico una NetworkPolicy sin ingress ni egress?* → Bloquea todo ese tipo de tráfico (deny-all implícito para esa dirección)
- *¿Necesito el CNI para que funcionen?* → Sí, el CNI (Calico) es quien realmente aplica las reglas
- *¿NetworkPolicy es un firewall de host?* → No, opera a nivel de Pod/namespace — el nodo en sí no está afectado
- *¿Puedo tener múltiples políticas en el mismo namespace?* → Sí, se suman (son aditivas — si alguna permite el tráfico, pasa)
- *¿Afecta al tráfico del host al pod?* → Depende del CNI, generalmente no (loopback y localhost no se ven afectados)

---

## Arquitectura de la clase

```
  Namespace: red-demo                    Namespace: default
  ┌─────────────────────────────────┐    ┌──────────────────┐
  │  pod-servidor (nginx)           │    │  pod-externo     │
  │  pod-cliente (alpine+curl)      │    │  (alpine+curl)   │
  │                                 │    └──────────────────┘
  │  Service: servidor-svc          │
  └─────────────────────────────────┘

  Namespace: monitoring
  ┌──────────────────────────┐
  │  Prometheus (scraper)    │
  │  app.kubernetes.io/name: │
  │    prometheus            │
  └──────────────────────────┘

  NetworkPolicies aplicadas en red-demo:
  ┌─────────────────────────────────────────────────────┐
  │  02-default-deny-all    → bloquea TODO              │
  │  03-allow-same-ns       → permite intra-namespace   │
  │  04-allow-monitoring    → permite scraping externo  │
  │  05-allow-egress-dns    → permite resolución DNS    │
  └─────────────────────────────────────────────────────┘
```

---

## PASO 0 — Verificar que Calico está funcionando

```bash
# Verificar que el CNI Calico está activo (requerido para NetworkPolicies)
kubectl get pods -n kube-system | grep calico

# Debe mostrar algo como:
# calico-kube-controllers-xxx   1/1   Running
# calico-node-xxx               1/1   Running (uno por nodo)

# Verificar que el API de NetworkPolicy está disponible
kubectl api-resources | grep networkpolicies
# Debe mostrar: networkpolicies   netpol   networking.k8s.io/v1
```

> **Nota:** Sin un CNI compatible (Calico, Cilium, Weave...), las NetworkPolicies
> se crean en la API pero NO se aplican. El cluster usará Calico (instalado como CNI).

---

## PASO 1 — Crear el namespace y los pods de demo

```bash
cd /root/devops2026/14-network-policies

kubectl apply -f 01-namespace-aislado.yaml

# Esperar a que todos los pods estén Running
kubectl get pods -n red-demo -w
```

Verificar los pods y el Service:
```bash
kubectl get pods -n red-demo -o wide
kubectl get service -n red-demo

# Probar conectividad ANTES de aplicar políticas (debe funcionar)
kubectl exec -it pod-cliente -n red-demo -- curl -s http://servidor-svc
# → Debe responder con HTML de nginx (tráfico libre antes de policies)

# También desde el pod externo (namespace default)
kubectl exec -it pod-externo -- curl -s --connect-timeout 3 http://servidor-svc.red-demo.svc.cluster.local
# → También funciona (sin políticas, todo está abierto)
```

---

## PASO 2 — Aplicar la política de deny-all

> **Concepto:** La primera política que siempre se aplica en producción.
> Bloquea TODO el tráfico entrante y saliente del namespace.
> A partir de aquí, solo lo que definamos explícitamente estará permitido.

```bash
kubectl apply -f 02-default-deny-all.yaml

# Verificar que se creó
kubectl get networkpolicies -n red-demo
```

### Demo: verificar el bloqueo

```bash
# Desde pod-cliente, intentar llegar al servidor (DEBE FALLAR)
kubectl exec -it pod-cliente -n red-demo -- curl -s --connect-timeout 3 http://servidor-svc
# → Timeout o "Connection refused" — la política está funcionando

# También intentar DNS (también bloqueado)
kubectl exec -it pod-cliente -n red-demo -- nslookup servidor-svc
# → "connection timed out; no servers could be reached"
# → Esto es porque el egress a CoreDNS (puerto 53) también está bloqueado
```

> 🎓 **Momento pedagógico:** Preguntar a la clase — *"¿Por qué no puedo ni resolver el DNS?"*
> Explicar que deny-all bloquea TODO el egress, incluido el UDP/53 a CoreDNS.

---

## PASO 3 — Permitir egress DNS (CRÍTICO)

> **Siempre hay que hacer esto después de un deny-all.**
> Sin DNS, los pods no pueden resolver nombres de Services.

```bash
kubectl apply -f 05-allow-egress-dns.yaml

# Verificar que DNS vuelve a funcionar
kubectl exec -it pod-cliente -n red-demo -- nslookup servidor-svc
# → Ahora resuelve la IP del Service ✅

# Pero el tráfico HTTP sigue bloqueado (DNS ≠ conectividad)
kubectl exec -it pod-cliente -n red-demo -- curl -s --connect-timeout 3 http://servidor-svc
# → Sigue fallando (el ingress al servidor no está permitido aún)
```

---

## PASO 4 — Permitir tráfico dentro del namespace

```bash
kubectl apply -f 03-allow-same-namespace.yaml

# Ahora pod-cliente SÍ puede llegar a pod-servidor (mismo namespace)
kubectl exec -it pod-cliente -n red-demo -- curl -s http://servidor-svc
# → Responde con HTML de nginx ✅

# Verificar las políticas activas
kubectl get networkpolicies -n red-demo
kubectl describe networkpolicy allow-same-namespace -n red-demo
```

### Demo: pod externo sigue bloqueado

```bash
# Desde el pod en namespace default (no está en red-demo)
kubectl exec -it pod-externo -- curl -s --connect-timeout 3 http://servidor-svc.red-demo.svc.cluster.local
# → Timeout — el tráfico inter-namespace sigue bloqueado ✅

# Esto demuestra el aislamiento entre namespaces
```

> 🎓 **Momento pedagógico:** *"Los pods del mismo namespace pueden hablar entre sí,
> pero los de otros namespaces no. Esto es micro-segmentación."*

---

## PASO 5 — Permitir scraping de Prometheus

> **Escenario real:** Prometheus está en el namespace `monitoring` y necesita
> hacer scraping HTTP (métricas) a los pods del namespace `red-demo`.
> Sin esta política, Prometheus no puede acceder — sus métricas estarían vacías.

```bash
kubectl apply -f 04-allow-desde-monitoring.yaml

# Ver la política
kubectl describe networkpolicy allow-desde-monitoring -n red-demo
```

Verificar con el pod-externo que solo monitoring puede acceder:
```bash
# El pod en namespace default AÚN no puede acceder (no es monitoring)
kubectl exec -it pod-externo -- curl -s --connect-timeout 3 http://servidor-svc.red-demo.svc.cluster.local
# → Sigue fallando ✅

# Solo Prometheus (namespace: monitoring, label: prometheus) podría
```

---

## PASO 6 — Diagrama final del estado de las políticas

```bash
# Ver todas las NetworkPolicies del namespace
kubectl get networkpolicies -n red-demo

# Describir cada una para entender las reglas
kubectl describe networkpolicy default-deny-all -n red-demo
kubectl describe networkpolicy allow-same-namespace -n red-demo
kubectl describe networkpolicy allow-desde-monitoring -n red-demo
kubectl describe networkpolicy allow-egress-dns -n red-demo
```

**Estado final del tráfico:**
```
pod-cliente → servidor-svc          ✅ (allow-same-namespace)
pod-externo → servidor-svc          ❌ (default-deny-all)
Prometheus  → pods red-demo :9090   ✅ (allow-desde-monitoring)
pod-cliente → CoreDNS :53           ✅ (allow-egress-dns)
pod-cliente → internet              ❌ (default-deny-all egress)
```

---

## PASO 7 — Comandos de diagnóstico

```bash
# Ver todas las NetworkPolicies en todos los namespaces
kubectl get networkpolicies -A

# Describir una política (ver reglas detalladas)
kubectl describe networkpolicy <nombre> -n red-demo

# Ver si un pod tiene políticas aplicadas sobre él
kubectl get netpol -n red-demo -o yaml | grep -A5 podSelector

# Verificar conectividad desde un pod (debugging)
kubectl exec -it pod-cliente -n red-demo -- sh
  > nslookup servidor-svc          # ¿funciona DNS?
  > curl -v --connect-timeout 3 http://servidor-svc  # ¿hay conectividad?
  > exit

# Ver los eventos del namespace (útil si algo falla)
kubectl get events -n red-demo --sort-by='.lastTimestamp'
```

---

## Resumen de políticas aplicadas

```
NetworkPolicy aplicadas en namespace red-demo:
─────────────────────────────────────────────────────────

1. default-deny-all
   → Bloquea TODO el ingress y egress
   → Aplica a todos los pods del namespace
   → Base obligatoria del modelo de seguridad

2. allow-egress-dns
   → Permite egress hacia CoreDNS (UDP/TCP :53)
   → Permite egress hacia API server (:443, :6443)
   → Sin esto: los pods no pueden resolver nombres de Services

3. allow-same-namespace
   → Permite ingress y egress entre pods del mismo namespace
   → Selector: podSelector: {} (todos los pods de red-demo)
   → Resultado: comunicación libre intra-namespace

4. allow-desde-monitoring
   → Permite ingress desde namespace 'monitoring' (Prometheus)
   → Solo a pods con label role: backend
   → Puertos: 9090 (Prometheus) y 8080 (HTTP app)

Flujo de tráfico resultante:
  red-demo ←→ red-demo    : ✅ libre
  monitoring → red-demo   : ✅ solo puertos de métricas
  default → red-demo      : ❌ bloqueado
  red-demo → internet     : ❌ bloqueado (solo DNS y API server)
```

---

## Orden de despliegue (resumen)

```bash
cd /root/devops2026/14-network-policies

# 1. Preparar el entorno
kubectl apply -f 01-namespace-aislado.yaml
kubectl get pods -n red-demo -w

# 2. Verificar conectividad inicial (debe funcionar)
kubectl exec -it pod-cliente -n red-demo -- curl -s http://servidor-svc

# 3. Aplicar deny-all (bloquear todo)
kubectl apply -f 02-default-deny-all.yaml

# 4. Verificar bloqueo
kubectl exec -it pod-cliente -n red-demo -- curl -s --connect-timeout 3 http://servidor-svc
# → DEBE fallar

# 5. Restaurar DNS (siempre necesario)
kubectl apply -f 05-allow-egress-dns.yaml

# 6. Permitir tráfico intra-namespace
kubectl apply -f 03-allow-same-namespace.yaml

# 7. Permitir scraping de Prometheus
kubectl apply -f 04-allow-desde-monitoring.yaml

# 8. Verificar estado final
kubectl get networkpolicies -n red-demo
kubectl exec -it pod-cliente -n red-demo -- curl -s http://servidor-svc
```

---

## Limpieza (al final de la clase)

```bash
# Eliminar el namespace y todos sus recursos (pods, services, policies)
kubectl delete namespace red-demo

# El pod-externo (en default) también puede borrarse
kubectl delete pod pod-externo
```
