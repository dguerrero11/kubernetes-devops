# Instalación de NGINX Ingress Controller (Bare Metal)

## ¿Qué es un Ingress Controller?

Un **Ingress** es una regla de enrutamiento HTTP/HTTPS.
Un **Ingress Controller** es el componente que lee esas reglas y las aplica (es el "router").

Sin Ingress Controller, los recursos Ingress no tienen efecto.

## Instalación en bare metal (NodePort)

```bash
# Instalar NGINX Ingress Controller oficial para bare metal
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.4/deploy/static/provider/baremetal/deploy.yaml

# Verificar que está corriendo (puede tardar 1-2 minutos)
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
```

La salida de `kubectl get svc -n ingress-nginx` mostrará algo como:
```
NAME                                 TYPE       CLUSTER-IP      PORT(S)
ingress-nginx-controller             NodePort   10.96.x.x       80:3xxxx/TCP,443:3xxxx/TCP
```

Anota los puertos NodePort asignados (ej: `30080` para HTTP, `30443` para HTTPS).

## Acceso a las aplicaciones con Ingress

Con bare metal y NodePort, la URL de acceso es:
```
http://<IP-cualquier-nodo>:<puerto-nodeport-http>
```

Para que el Ingress enrute por hostname, usar **nip.io** (DNS mágico):
```
http://mi-app.192.168.109.200.nip.io:<puerto-nodeport-http>
```
`nip.io` resuelve automáticamente `*.192.168.109.200.nip.io` → `192.168.109.200`

## Verificar puertos asignados

```bash
# Ver qué puerto NodePort asignó el Ingress Controller
kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'
```

## Diagrama de flujo

```
Usuario
  │
  ▼
http://app.192.168.109.200.nip.io:30080
  │
  ▼
NodePort (puerto 30080 en cualquier nodo)
  │
  ▼
NGINX Ingress Controller Pod
  │  Lee los recursos Ingress y enruta según host/path
  ▼
Service ClusterIP de la aplicación
  │
  ▼
Pods de la aplicación
```
