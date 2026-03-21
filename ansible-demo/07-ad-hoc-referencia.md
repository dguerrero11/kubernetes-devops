# Comandos Ad-hoc de Ansible — Referencia rápida para clase

Los comandos ad-hoc son la forma más rápida de demostrar el poder de Ansible
**sin playbooks**. Perfectos para impresionar en una demo de 5 minutos.

---

## Sintaxis general
```bash
ansible <patrón> -m <módulo> -a "<argumentos>"
```

---

## 🔌 Conectividad

```bash
# Ping a todos los nodos
ansible k8s -m ping

# Ping solo a los workers
ansible workers -m ping

# Ping a un nodo específico
ansible k8s-master01 -m ping
```

---

## 📋 Información del sistema (facts)

```bash
# Ver TODOS los facts de un nodo (enorme salida)
ansible k8s-master01 -m setup

# Filtrar solo memoria
ansible k8s -m setup -a "filter=ansible_memory_mb"

# Filtrar solo interfaces de red
ansible k8s -m setup -a "filter=ansible_interfaces"

# Filtrar CPU
ansible k8s -m setup -a "filter=ansible_processor*"

# IP de todos los nodos
ansible k8s -m setup -a "filter=ansible_default_ipv4" | grep address
```

---

## 💻 Comandos del sistema

```bash
# Uptime de todos los nodos
ansible k8s -m command -a "uptime"

# Uso de disco
ansible k8s -m command -a "df -h"

# Memoria disponible
ansible k8s -m command -a "free -h"

# Versión del kernel
ansible k8s -m command -a "uname -r"

# Quién está conectado
ansible k8s -m command -a "who"

# Fecha y hora de cada nodo
ansible k8s -m command -a "date"

# Últimas 5 líneas del syslog
ansible k8s -m command -a "tail -5 /var/log/messages"
```

---

## 📦 Paquetes (sin playbook)

```bash
# Instalar un paquete en todos los nodos
ansible k8s -m dnf -a "name=tree state=present"

# Desinstalar un paquete
ansible k8s -m dnf -a "name=tree state=absent"

# Verificar si un paquete está instalado
ansible k8s -m command -a "rpm -q htop"
```

---

## 👤 Usuarios

```bash
# Ver si el usuario devops existe en todos los nodos
ansible k8s -m command -a "id devops"

# Crear un usuario rápido
ansible k8s -m user -a "name=alumno state=present shell=/bin/bash"

# Eliminar un usuario
ansible k8s -m user -a "name=alumno state=absent remove=true"
```

---

## 📁 Archivos

```bash
# Copiar un archivo a todos los nodos
ansible k8s -m copy -a "src=/etc/hosts dest=/tmp/hosts-backup mode=0644"

# Ver contenido de un archivo
ansible k8s -m command -a "cat /etc/motd"

# Crear un directorio
ansible k8s -m file -a "path=/opt/devops state=directory mode=0755"

# Eliminar un archivo
ansible k8s -m file -a "path=/tmp/hosts-backup state=absent"

# Ver permisos de un archivo
ansible k8s -m stat -a "path=/etc/passwd"
```

---

## 🔧 Servicios

```bash
# Estado de un servicio
ansible k8s -m command -a "systemctl is-active containerd"

# Reiniciar un servicio (con cuidado en producción)
ansible k8s -m service -a "name=chronyd state=restarted"

# Listar servicios activos
ansible k8s -m command -a "systemctl list-units --type=service --state=active --no-pager"
```

---

## ☸️ Kubernetes (solo en master)

```bash
# Estado del cluster
ansible masters -m command -a "kubectl get nodes -o wide"

# Todos los pods
ansible masters -m command -a "kubectl get pods --all-namespaces"

# Conteo de pods por namespace
ansible masters -m shell -a "kubectl get pods --all-namespaces --no-headers | awk '{print $1}' | sort | uniq -c"

# Ver recursos del cluster
ansible masters -m command -a "kubectl top nodes"

# Últimas alertas de Falco
ansible masters -m shell -a "kubectl logs -n falco $(kubectl get pod -n falco -o name | head -1) --tail=5"
```

---

## 🚀 Tips para la demo en clase

```bash
# Ejecutar en paralelo con salida legible
ansible k8s -m command -a "hostname" -o

# Ver el tiempo de ejecución
time ansible k8s -m ping

# Dry-run (check mode) — sin ejecutar cambios
ansible k8s -m dnf -a "name=nano state=present" --check

# Limitar a un solo nodo
ansible k8s -m ping --limit k8s-worker01

# Aumentar verbosidad para diagnóstico
ansible k8s -m ping -v
ansible k8s -m ping -vvv  # muy detallado
```

---

## 📊 Comandos WOW para impresionar en clase

```bash
# Recolectar y mostrar RAM de todos los nodos en una línea
ansible k8s -m setup -a "filter=ansible_memtotal_mb" | grep memtotal

# Ver todos los IPs del cluster en 1 segundo
ansible k8s -m setup -a "filter=ansible_default_ipv4" -o | grep address

# Verificar que containerd está Running en todos a la vez
ansible k8s -m command -a "systemctl is-active containerd" -o

# Ver cuántos pods corre cada nodo (via crictl)
ansible k8s -m shell -a "crictl pods --state ready 2>/dev/null | tail -n +2 | wc -l" -o

# Ejecutar un comando en todos los nodos y contar líneas
ansible k8s -m shell -a "ps aux | wc -l" -o
```
