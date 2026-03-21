# Instalación y configuración de Ansible en el master

## Prerrequisito: instalar Ansible en k8s-master01

```bash
# En k8s-master01 (192.168.109.200)
ssh root@192.168.109.200

# Instalar Ansible desde EPEL
dnf install -y epel-release
dnf install -y ansible

# Verificar versión
ansible --version

# Instalar colección community.general (para módulo timezone)
ansible-galaxy collection install community.general
```

---

## Copiar los playbooks al master

```bash
# Desde tu máquina local (ajustar ruta si es necesario)
scp -r /ruta/local/ansible-demo root@192.168.109.200:/root/devops2026/

# O via git (si ya hiciste commit)
ssh root@192.168.109.200 "cd /root/devops2026 && git pull"

# En el master
cd /root/devops2026/ansible-demo
```

---

## Verificar conectividad SSH entre nodos

```bash
# Desde el master, verificar que puede conectarse a los workers sin password
ssh-copy-id root@192.168.109.201
ssh-copy-id root@192.168.109.202

# Prueba manual
ssh root@192.168.109.201 hostname
ssh root@192.168.109.202 hostname
```

---

## Primer comando (verificar que todo funciona)

```bash
cd /root/devops2026/ansible-demo

# Ping a todos los nodos
ansible k8s -m ping

# Salida esperada:
# k8s-master01 | SUCCESS => {"changed": false, "ping": "pong"}
# k8s-worker01 | SUCCESS => {"changed": false, "ping": "pong"}
# k8s-worker02 | SUCCESS => {"changed": false, "ping": "pong"}
```

---

## Orden sugerido para la demo en clase

| # | Playbook / Comando | Tiempo | Qué muestra |
|---|-------------------|--------|-------------|
| 1 | `ansible k8s -m ping` | 30s | Conectividad sin agentes |
| 2 | `ansible k8s -m setup -a "filter=ansible_memory_mb"` | 30s | Facts automáticos |
| 3 | `ansible-playbook 01-ping-y-facts.yml` | 2 min | Info completa del cluster |
| 4 | `ansible-playbook 02-paquetes.yml` | 3 min | Instalación en 3 nodos a la vez |
| 5 | `ansible-playbook 02-paquetes.yml` (segunda vez) | 1 min | **Idempotencia** ← momento WOW |
| 6 | `ansible-playbook 03-usuarios.yml` | 2 min | Usuarios en toda la flota |
| 7 | `ansible-playbook 04-configuracion.yml --diff` | 2 min | Config declarativa + diff |
| 8 | `ansible-playbook 05-informe-cluster.yml` | 3 min | Informe automático |
| 9 | `ansible-playbook 06-k8s-health.yml` | 3 min | Health check del cluster |

**Total demo: ~17 minutos**
