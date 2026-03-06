# Instalación de Kubernetes 1.28 en Rocky Linux 9.6

## Infraestructura del cluster

| Rol    | Hostname      | IP                  | OS              |
|--------|---------------|---------------------|-----------------|
| Master | k8s-master01  | 192.168.109.200     | Rocky Linux 9.6 |
| Worker | k8s-worker01  | 192.168.109.201     | Rocky Linux 9.6 |
| Worker | k8s-worker02  | 192.168.109.202     | Rocky Linux 9.6 |

- **Kubernetes**: v1.28
- **Runtime**: containerd
- **CNI**: Calico v3.26.1

---

## Paso 1: Configurar hostname y archivo /etc/hosts

Ejecutar en **cada nodo** el comando correspondiente:

```bash
# En k8s-master01
sudo hostnamectl set-hostname "k8s-master01" && exec bash

# En k8s-worker01
sudo hostnamectl set-hostname "k8s-worker01" && exec bash

# En k8s-worker02
sudo hostnamectl set-hostname "k8s-worker02" && exec bash
```

Agregar las siguientes entradas al archivo `/etc/hosts` en **todos los nodos**:

```bash
sudo tee -a /etc/hosts <<EOF
192.168.109.200   k8s-master01
192.168.109.201   k8s-worker01
192.168.109.202   k8s-worker02
EOF
```

Verificar:
```bash
cat /etc/hosts
ping -c 2 k8s-master01
```

---

## Paso 2: Deshabilitar Swap

Kubernetes requiere que el swap esté deshabilitado. Ejecutar en **todos los nodos**:

```bash
# Deshabilitar swap en caliente
sudo swapoff -a

# Deshabilitar swap permanentemente (comentar la línea en fstab)
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

Verificar que no hay swap activo:
```bash
free -h
# La línea Swap debe mostrar: 0B  0B  0B
```

---

## Paso 3: Configurar SELinux y Firewall

### SELinux — todos los nodos

Poner SELinux en modo permissive (deja que el sistema funcione pero registra violaciones):

```bash
sudo setenforce 0
sudo sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/sysconfig/selinux
```

Verificar:
```bash
getenforce
# Debe mostrar: Permissive
```

### Firewall — nodo Master (192.168.109.200)

```bash
sudo firewall-cmd --permanent --add-port={6443,2379,2380,10250,10251,10252,10257,10259,179}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload
```

Puertos del master:
- `6443` — API Server (punto de entrada de kubectl)
- `2379-2380` — etcd (base de datos del cluster)
- `10250` — kubelet API
- `10251,10252,10257,10259` — scheduler y controller-manager
- `179` — BGP (usado por Calico)
- `4789/udp` — VXLAN (red de pods)

### Firewall — nodos Worker (192.168.109.201 y 192.168.109.202)

```bash
sudo firewall-cmd --permanent --add-port={179,10250,30000-32767}/tcp
sudo firewall-cmd --permanent --add-port=4789/udp
sudo firewall-cmd --reload
```

Puertos del worker:
- `10250` — kubelet API
- `30000-32767` — NodePort Services (acceso externo a aplicaciones)
- `179` — BGP (Calico)
- `4789/udp` — VXLAN

---

## Paso 4: Agregar módulos del kernel y parámetros de red

Ejecutar en **todos los nodos**:

### Módulos del kernel

```bash
# Crear archivo de configuración de módulos
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

# Cargar los módulos inmediatamente
sudo modprobe overlay
sudo modprobe br_netfilter
```

- `overlay` — sistema de archivos por capas usado por los contenedores
- `br_netfilter` — permite que iptables vea el tráfico de puentes de red (necesario para Kubernetes)

### Parámetros del kernel

```bash
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Aplicar los parámetros sin reiniciar
sudo sysctl --system
```

---

## Paso 5: Instalar containerd

Containerd es el runtime de contenedores que usa Kubernetes. Ejecutar en **todos los nodos**:

```bash
# Agregar el repositorio de Docker (contiene containerd)
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Instalar containerd
sudo dnf install containerd.io -y
```

### Configurar containerd con SystemdCgroup

```bash
# Generar la configuración por defecto
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

# Habilitar SystemdCgroup (requerido por Kubernetes)
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
```

> **¿Por qué SystemdCgroup = true?**
> Kubernetes gestiona los recursos de los contenedores (CPU/memoria) usando cgroups.
> Si containerd y kubelet no usan el mismo driver de cgroups, el cluster se vuelve inestable.
> Rocky Linux 9 usa systemd para gestionar cgroups, por eso se requiere `SystemdCgroup = true`.

```bash
# Iniciar y habilitar containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verificar estado
sudo systemctl status containerd
```

---

## Paso 6: Instalar herramientas de Kubernetes

Ejecutar en **todos los nodos**:

```bash
# Agregar el repositorio oficial de Kubernetes v1.28
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Instalar las tres herramientas
sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Habilitar kubelet al inicio del sistema
sudo systemctl enable --now kubelet
```

Herramientas instaladas:
- **kubeadm** — inicializa y gestiona el cluster
- **kubelet** — agente que corre en cada nodo y gestiona los pods
- **kubectl** — cliente de línea de comandos para interactuar con el cluster

---

## Paso 7: Inicializar el cluster (solo en el Master)

Ejecutar **únicamente en k8s-master01**:

```bash
sudo kubeadm init --control-plane-endpoint=k8s-master01
```

Al finalizar, el comando muestra un output similar a:
```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join k8s-master01:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

> **IMPORTANTE**: Copiar el comando `kubeadm join` que aparece al final. Se necesita en el Paso 8.

### Configurar kubectl en el Master

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Verificar que kubectl funciona:
```bash
kubectl get nodes
# Los nodos aparecerán en estado NotReady (normal, aún no hay CNI instalado)
```

---

## Paso 8: Unir los Worker Nodes al cluster

Ejecutar el comando `kubeadm join` obtenido en el paso anterior en **k8s-worker01 y k8s-worker02**.

El comando tiene la forma:
```bash
sudo kubeadm join k8s-master01:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>
```

> Si el token expiró (válido por 24h), generar uno nuevo desde el master:
> ```bash
> kubeadm token create --print-join-command
> ```

---

## Paso 9: Instalar el plugin de red Calico

Sin un CNI (Container Network Interface), los pods no pueden comunicarse entre sí y los nodos permanecen en estado `NotReady`.

Ejecutar **únicamente en k8s-master01**:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
```

Esperar a que los pods de Calico estén corriendo (1-2 minutos):
```bash
kubectl get pods -n kube-system -w
# Esperar hasta ver todos los pods de calico en estado Running
```

Verificar el estado de los nodos:
```bash
kubectl get nodes
```

Salida esperada:
```
NAME           STATUS   ROLES           AGE   VERSION
k8s-master01   Ready    control-plane   5m    v1.28.15
k8s-worker01   Ready    <none>          3m    v1.28.15
k8s-worker02   Ready    <none>          3m    v1.28.15
```

---

## Paso 10: Verificar la instalación

Desplegar una aplicación de prueba desde el master:

```bash
# Crear un deployment de nginx
kubectl create deployment web-test --image=nginx:1.25 --replicas=2

# Exponerlo con NodePort
kubectl expose deployment web-test --type=NodePort --port=80

# Ver el puerto asignado
kubectl get svc web-test
```

Probar el acceso (reemplazar NODEPORT con el puerto que aparece en el comando anterior):
```bash
curl http://192.168.109.201:<NODEPORT>
curl http://192.168.109.202:<NODEPORT>
```

Limpiar la prueba:
```bash
kubectl delete deployment web-test
kubectl delete svc web-test
```

---

## Resumen de comandos de verificación

```bash
# Estado de los nodos
kubectl get nodes -o wide

# Pods del sistema (deben estar todos Running)
kubectl get pods -n kube-system

# Información del cluster
kubectl cluster-info

# Versión instalada
kubectl version
```

---

## Arquitectura instalada

```
┌─────────────────────────────────────────────────┐
│           k8s-master01 (192.168.109.200)        │
│                                                  │
│  API Server ──── etcd                           │
│  Scheduler       Controller Manager             │
│  Calico (CNI)    CoreDNS                        │
└───────────────┬──────────────────────────────────┘
                │  kubeadm join
       ┌────────┴────────┐
       │                 │
┌──────▼──────┐   ┌──────▼──────┐
│ k8s-worker01│   │ k8s-worker02│
│ 109.201     │   │ 109.202     │
│             │   │             │
│ kubelet     │   │ kubelet     │
│ containerd  │   │ containerd  │
│ Calico      │   │ Calico      │
└─────────────┘   └─────────────┘
```
