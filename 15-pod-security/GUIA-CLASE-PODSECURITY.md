# Guía de Clase — Pod Security en Kubernetes

**Namespace demo:** `seguro-demo` (restricted) · `desarrollo-demo` (baseline)
**Directorio:** `/root/devops2026/15-pod-security/`

---

## 🎓 Guión para el instructor

### El concepto en una frase
> *"Principio de mínimo privilegio: el proceso solo puede hacer lo que necesita, nada más. Si un contenedor es comprometido, el atacante queda atrapado en una jaula muy pequeña."*

### La analogía del empleado contratista (5 min)
```
Empleado de limpieza en un banco:
  ❌ SIN SecurityContext:
     → tiene llave maestra de todas las salas (root)
     → puede abrir la caja fuerte (SYS_ADMIN capability)
     → puede llevarse documentos (escritura en cualquier lugar)
     → puede cambiar de rol durante el trabajo (escalada de privilegios)

  ✅ CON SecurityContext:
     → tiene llave solo de salas de limpieza (UID 1000, no-root)
     → no puede abrir cajas fuertes (capabilities: drop ALL)
     → solo puede escribir en el cubo de basura (readOnlyRootFilesystem)
     → no puede convertirse en gerente mientras trabaja (allowPrivilegeEscalation: false)

Si el empleado es un atacante, con SecurityContext solo compromete la sala de limpieza.
Sin SecurityContext, compromete todo el banco.
```

### Los 2 mecanismos de Pod Security (15 min)
```
MECANISMO 1: SecurityContext (nivel Pod/Contenedor)
─────────────────────────────────────────────────────
Tú como desarrollador defines en el YAML lo que el proceso puede y no puede hacer.
Se aplica directamente en la spec del Pod/Deployment.

MECANISMO 2: PodSecurityAdmission (PSA) (nivel Namespace)
─────────────────────────────────────────────────────
El cluster verifica que los pods cumplan con un nivel mínimo de seguridad.
Si no cumplen, el pod es RECHAZADO antes de crearse.
Es el "portero del namespace".

Relación entre ambos:
  Desarrollador escribe SecurityContext en el YAML (Mecanismo 1)
  PSA verifica que el SecurityContext sea suficientemente seguro (Mecanismo 2)
```

### Los 3 niveles PSA — en pizarra (10 min)
```
┌─────────────┬────────────────────────────────────────────────────────────┐
│ privileged  │ Sin restricciones. Para pods del sistema (calico, etc.)    │
│             │ NUNCA usar para aplicaciones de negocio                    │
├─────────────┼────────────────────────────────────────────────────────────┤
│ baseline    │ Bloquea lo más peligroso: hostPID, hostNetwork,            │
│             │ contenedores privilegiados, hostPath mounts                │
│             │ ✅ nginx:1.25 funciona aquí                                 │
├─────────────┼────────────────────────────────────────────────────────────┤
│ restricted  │ Máxima seguridad: runAsNonRoot, drop ALL caps,             │
│             │ allowPrivilegeEscalation: false, seccompProfile            │
│             │ ⚠️  nginx:1.25 NO funciona (corre como root)               │
│             │ ✅ nginxinc/nginx-unprivileged funciona                     │
└─────────────┴────────────────────────────────────────────────────────────┘
```

### Los 3 modos PSA — en pizarra (5 min)
```
enforce → BLOQUEA el pod si viola el nivel (Error + Forbidden)
warn    → Permite el pod pero muestra WARNING en kubectl
audit   → Permite el pod pero registra en el audit log del cluster

Uso típico en producción:
  enforce: restricted   ← rechaza lo inseguro
  warn: restricted      ← avisa a los devs mientras migran
  audit: restricted     ← traza histórico de violaciones
```

### Demo más impactante: rechazar un pod (10 min)
```bash
# 1. Mostrar que en namespace default TODO funciona (sin PSA)
kubectl apply -f 02-pod-inseguro.yaml  # va a namespace default → OK

# 2. Intentar en el namespace restricted
kubectl apply -f 02-pod-inseguro.yaml -n seguro-demo
# → Error from server (Forbidden): pods "pod-inseguro" is forbidden:
#    violates PodSecurity "restricted:latest":
#    allowPrivilegeEscalation != false (container "nginx" must set
#    securityContext.allowPrivilegeEscalation=false),
#    unrestricted capabilities (container "nginx" must set
#    securityContext.capabilities.drop=["ALL"]), ...

# 3. Mostrar que el pod seguro SÍ funciona
kubectl apply -f 03-deployment-seguro.yaml  # → creado OK
```

### Demo de comparativa: ver la diferencia real (10 min)
```bash
# Aplicar ambos pods de demo en namespace default
kubectl apply -f 04-securitycontext-demo.yaml

# Pod inseguro: corre como root con todas las capabilities
kubectl exec demo-inseguro -- id
# → uid=0(root) gid=0(root) groups=0(root)
kubectl exec demo-inseguro -- cat /proc/1/status | grep Cap
# → CapEff: 00000000a80425fb  (capabilities habilitadas)
kubectl exec demo-inseguro -- touch /etc/test-write
# → funciona (puede escribir en /etc)

# Pod seguro: corre como UID 1000, capabilities droped
kubectl exec demo-seguro -- id
# → uid=1000 gid=1000 groups=1000
kubectl exec demo-seguro -- cat /proc/1/status | grep Cap
# → CapEff: 0000000000000000  (ninguna capability)
kubectl exec demo-seguro -- touch /etc/test-write
# → Error: Read-only file system
```

### Preguntas clave para la clase
- *¿Por qué nginx:1.25 no funciona en restricted?* → Nginx lee puertos <1024 (requiere CAP_NET_BIND_SERVICE) y su proceso maestro inicia como root para hacer bind al puerto 80
- *¿readOnlyRootFilesystem rompe las apps?* → Solo si escriben en el filesystem. Solución: agregar emptyDir para /tmp, logs, etc.
- *¿Qué capabilities necesita mi app realmente?* → La mayoría de apps no necesitan ninguna — `drop: ALL` es seguro para APIs REST, microservicios, etc.
- *¿PSA reemplaza las NetworkPolicies?* → No — controlan cosas distintas: PSA = lo que el pod puede hacer en el nodo; NetworkPolicy = con quién puede comunicarse
- *¿Cómo migrar apps legacy a restricted?* → Empezar con `warn: restricted` → ver warnings → corregir → activar `enforce: restricted`

---

## Arquitectura de la clase

```
  namespace: default (sin PSA)         namespace: seguro-demo (restricted)
  ┌──────────────────────────────┐     ┌──────────────────────────────┐
  │  demo-inseguro (root, caps)  │     │  web-seguro (UID 1000)       │
  │  demo-seguro   (UID 1000)    │     │    - allowPrivEsc: false      │
  │                              │     │    - readOnlyFS: true         │
  │  → Para comparar lado a lado │     │    - caps drop ALL           │
  └──────────────────────────────┘     │    - seccompProfile: Default │
                                        └──────────────────────────────┘
  namespace: desarrollo-demo (baseline)
  ┌──────────────────────────────┐
  │  web-baseline (nginx:1.25)   │
  │    - funciona sin SecurityCtx│
  │    - Warning de restricted   │
  └──────────────────────────────┘

  Niveles PSA:
    seguro-demo    → enforce: restricted (rechaza inseguros)
    desarrollo-demo → enforce: baseline (solo bloquea lo peor)
    default        → sin PSA (acepta todo)
```

---

## PASO 0 — Verificar PSA disponible (K8s 1.23+)

```bash
# PSA está habilitado por defecto desde K8s 1.25 (GA)
# En K8s 1.28 ya no hay nada que habilitar

# Ver los labels PSA del namespace kube-system (ejemplo de sistema)
kubectl get namespace kube-system -o yaml | grep pod-security

# Ver todos los namespaces y sus labels PSA
kubectl get namespaces --show-labels | grep pod-security
```

---

## PASO 1 — Crear namespaces con diferentes niveles PSA

```bash
cd /root/devops2026/15-pod-security

# Namespace restricted (producción)
kubectl apply -f 01-namespace-restricted.yaml

# Namespace baseline (desarrollo)
kubectl apply -f 05-namespace-baseline.yaml

# Verificar los labels PSA aplicados
kubectl get namespace seguro-demo -o yaml | grep pod-security
kubectl get namespace desarrollo-demo -o yaml | grep pod-security
```

---

## PASO 2 — Demo: rechazar un pod inseguro

### La demo más impactante de la clase

```bash
# PRIMERO: demostrar que en namespace default funciona (sin PSA)
kubectl apply -f 02-pod-inseguro.yaml
kubectl get pod pod-inseguro
# → Running (namespace default acepta todo)

# LUEGO: intentar en el namespace restricted (DEBE SER RECHAZADO)
kubectl apply -f 02-pod-inseguro.yaml --namespace seguro-demo
```

Salida esperada (error de PSA):
```
Error from server (Forbidden): error when creating "02-pod-inseguro.yaml":
pods "pod-inseguro" is forbidden: violates PodSecurity "restricted:latest":
allowPrivilegeEscalation != false (container "nginx" must set
securityContext.allowPrivilegeEscalation=false),
unrestricted capabilities (container "nginx" must set
securityContext.capabilities.drop=["ALL"]),
runAsNonRoot != true (pod or container "nginx" must set
securityContext.runAsNonRoot=true),
seccompProfile (pod or containers "nginx" must set securityContext.seccompProfile.type
to "RuntimeDefault" or "Localhost")
```

> 🎓 **Momento pedagógico:** Leer el error junto con la clase.
> Cada línea del error dice EXACTAMENTE qué falta.
> PSA es el "portero" que explica por qué no dejas entrar.

```bash
# Verificar que el pod NO fue creado
kubectl get pods -n seguro-demo
# → No resources found — el pod fue rechazado antes de existir
```

---

## PASO 3 — Comparativa SecurityContext

```bash
# Crear los dos pods de demo en namespace default
kubectl apply -f 04-securitycontext-demo.yaml

# Esperar que ambos estén Running
kubectl get pods -l demo=security-comparison -w
```

### Comparar el pod inseguro vs el seguro

```bash
# ──── POD INSEGURO ────────────────────────────────────────

# ¿Con qué usuario corre?
kubectl exec demo-inseguro -- id
# → uid=0(root) gid=0(root) groups=0(root)

# ¿Puede escribir en /etc?
kubectl exec demo-inseguro -- touch /etc/test-write && echo "ESCRITURA EXITOSA"
# → ESCRITURA EXITOSA (peligroso — puede modificar configs del sistema)

# ¿Qué capabilities tiene?
kubectl exec demo-inseguro -- cat /proc/1/status | grep CapEff
# → CapEff: 00000000a80425fb  (varias capabilities activas)


# ──── POD SEGURO ──────────────────────────────────────────

# ¿Con qué usuario corre?
kubectl exec demo-seguro -- id
# → uid=1000 gid=1000 groups=1000

# ¿Puede escribir en /etc?
kubectl exec demo-seguro -- touch /etc/test-write 2>&1
# → touch: /etc/test-write: Read-only file system

# ¿Puede escribir en /tmp (volumen emptyDir montado)?
kubectl exec demo-seguro -- touch /tmp/test-write && echo "Solo puedo escribir en /tmp"
# → Solo puedo escribir en /tmp

# ¿Qué capabilities tiene?
kubectl exec demo-seguro -- cat /proc/1/status | grep CapEff
# → CapEff: 0000000000000000  (ninguna capability — máximo aislamiento)
```

> 🎓 **Conclusión para la clase:**
> *"En el pod inseguro, un atacante que logre code execution tiene acceso root al
> contenedor con todas las capabilities. En el seguro, el atacante tiene UID 1000,
> filesystem de solo lectura y cero capabilities — prácticamente sin posibilidad
> de moverse lateralmente."*

---

## PASO 4 — Deployment seguro en namespace restricted

```bash
# Crear el deployment que cumple con restricted
kubectl apply -f 03-deployment-seguro.yaml

# Verificar que se creó correctamente
kubectl get deployment web-seguro -n seguro-demo
kubectl get pods -n seguro-demo

# Ver los detalles del SecurityContext
kubectl get pod -n seguro-demo -l app=web-seguro -o yaml | grep -A10 securityContext
```

Verificar que funciona correctamente:
```bash
# El pod debe estar Running — si falla, es por la imagen o configuración
kubectl get pods -n seguro-demo -w

# Ver los logs para confirmar que nginx arranca
kubectl logs -n seguro-demo -l app=web-seguro

# Verificar que corre como UID 1000 (no root)
POD=$(kubectl get pods -n seguro-demo -l app=web-seguro -o name | head -1)
kubectl exec -n seguro-demo $POD -- id
# → uid=1000 gid=1000 groups=1000
```

---

## PASO 5 — Namespace baseline para desarrollo

```bash
# Crear namespace baseline y el deployment de ejemplo
kubectl apply -f 05-namespace-baseline.yaml

# Verificar que el deployment de nginx:1.25 se acepta (cumple baseline)
kubectl get deployment web-baseline -n desarrollo-demo
kubectl get pods -n desarrollo-demo
```

### Ver el warning (warn: restricted activo)

```bash
# Al ver el deployment o crear recursos, kubectl muestra warnings
kubectl apply -f 05-namespace-baseline.yaml
# → Warning: would violate PodSecurity "restricted:latest":
#    allowPrivilegeEscalation != false (container "nginx"...
#    → El pod SE CREA pero avisa que no cumplría restricted

# Verificar que el pod SÍ corre (baseline lo acepta)
kubectl get pods -n desarrollo-demo
# → Running ✅ (baseline es más permisivo que restricted)
```

> 🎓 **Estrategia de migración:**
> ```
> 1. Hoy: enforce: privileged (sin restricciones)
> 2. Próxima semana: warn: restricted (ver qué violaría restricted)
> 3. Arreglar los pods que aparecen en los warnings
> 4. Cuando no haya más warnings: enforce: restricted
> ```

---

## PASO 6 — Comandos de diagnóstico

```bash
# Ver el nivel PSA de todos los namespaces
kubectl get ns -o custom-columns='NAME:.metadata.name,ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce'

# Describir por qué un pod violó PSA (buscar en eventos)
kubectl get events -n seguro-demo --field-selector reason=FailedCreate

# Ver el SecurityContext completo de un pod en producción
kubectl get pod <nombre> -n seguro-demo -o jsonpath='{.spec.securityContext}'
kubectl get pod <nombre> -n seguro-demo -o jsonpath='{.spec.containers[0].securityContext}'

# Verificar si un pod corre como root
kubectl exec <pod> -n seguro-demo -- id

# Simular PSA sin aplicar cambios (dry-run)
kubectl label namespace default \
  pod-security.kubernetes.io/enforce=restricted \
  --dry-run=server
# → Ver qué pods existentes violarían restricted
```

---

## Resumen: SecurityContext completo para producción

```yaml
# Plantilla SecurityContext para copiar en producción:

spec:
  # ─── A nivel POD ───────────────────────────────────────
  securityContext:
    runAsNonRoot: true              # proceso no puede ser root
    runAsUser: 1000                 # UID explícito
    runAsGroup: 1000                # GID del proceso
    fsGroup: 1000                   # GID para volúmenes
    seccompProfile:
      type: RuntimeDefault          # limita syscalls disponibles

  containers:
    - name: mi-app
      # ─── A nivel CONTENEDOR ────────────────────────────
      securityContext:
        allowPrivilegeEscalation: false   # no puede obtener más privilegios
        readOnlyRootFilesystem: true       # filesystem de solo lectura
        capabilities:
          drop:
            - ALL                         # eliminar TODAS las capabilities

      # Si tu app necesita escribir en disco:
      volumeMounts:
        - name: tmp-dir
          mountPath: /tmp

  volumes:
    - name: tmp-dir
      emptyDir: {}                  # volumen en memoria, permite escritura
```

---

## Orden de despliegue (resumen)

```bash
cd /root/devops2026/15-pod-security

# 1. Crear namespaces con PSA configurado
kubectl apply -f 01-namespace-restricted.yaml
kubectl apply -f 05-namespace-baseline.yaml

# 2. Demo de rechazo (el pod inseguro no entra en restricted)
kubectl apply -f 02-pod-inseguro.yaml          # → OK en default
kubectl apply -f 02-pod-inseguro.yaml -n seguro-demo  # → RECHAZADO ✅

# 3. Comparativa SecurityContext
kubectl apply -f 04-securitycontext-demo.yaml
kubectl exec demo-inseguro -- id               # → root
kubectl exec demo-seguro -- id                 # → uid=1000

# 4. Deployment seguro en namespace restricted
kubectl apply -f 03-deployment-seguro.yaml
kubectl get pods -n seguro-demo

# 5. Baseline con warning
kubectl apply -f 05-namespace-baseline.yaml    # → Warning pero acepta
```

---

## Comparativa de los 3 mecanismos de seguridad

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Seguridad en Kubernetes: 3 capas                     │
├─────────────────┬──────────────────────────────────────────────────────┤
│ RBAC            │ ¿Quién puede hacer qué con la API de K8s?            │
│ (Clase 13)      │ Controla: usuarios, ServiceAccounts, permisos        │
│                 │ No controla: lo que hace el proceso dentro del pod   │
├─────────────────┼──────────────────────────────────────────────────────┤
│ NetworkPolicy   │ ¿Con quién puede comunicarse el pod?                 │
│ (Clase 14)      │ Controla: tráfico TCP/UDP entre pods y namespaces    │
│                 │ No controla: lo que el proceso hace en el nodo       │
├─────────────────┼──────────────────────────────────────────────────────┤
│ Pod Security    │ ¿Qué puede hacer el proceso dentro del nodo?         │
│ (Esta clase)    │ Controla: UID, capabilities, filesystem, syscalls    │
│                 │ No controla: quién accede a la API o al red          │
└─────────────────┴──────────────────────────────────────────────────────┘

Las 3 capas son complementarias. En producción se usan las 3 juntas:
  RBAC + NetworkPolicy + Pod Security = defensa en profundidad
```

---

## Limpieza (al final de la clase)

```bash
# Eliminar namespaces y sus recursos
kubectl delete namespace seguro-demo
kubectl delete namespace desarrollo-demo

# Eliminar los pods de comparativa en default
kubectl delete pod demo-inseguro demo-seguro pod-inseguro
```
