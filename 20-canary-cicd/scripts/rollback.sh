#!/bin/bash
# rollback.sh — Rollback de emergencia: cualquier fase → 100% v1
#
# Restaura el estado estable original:
#   stable=9 réplicas (100% tráfico)
#   canary=0 réplicas (desactivado)
#
# Tiempo estimado de rollback: < 30 segundos
#
# Cuándo usar:
#   - v2 tiene un error crítico en producción
#   - Las métricas de v2 muestran degradación
#   - Decisión de negocio de pausar la migración

NAMESPACE="canary-demo"

echo "========================================"
echo "  ROLLBACK DE EMERGENCIA"
echo "========================================"
echo ""
echo "Acción: Retirar todo el tráfico de v2 (canary)"
echo "        Restaurar 100% de tráfico a v1 (stable)"
echo ""

# Mostrar estado actual
echo "Estado ACTUAL:"
kubectl get deployments -n $NAMESPACE 2>/dev/null
echo ""

# No pedir confirmación para emergencias — el rollback debe ser RÁPIDO
echo "Ejecutando rollback..."
echo ""

# Primero escalar stable (para que haya capacidad inmediata)
echo "[1/2] Restaurando webapp-stable → 9 réplicas..."
kubectl scale deployment webapp-stable -n $NAMESPACE --replicas=9

# Luego apagar canary
echo "[2/2] Apagando webapp-canary → 0 réplicas..."
kubectl scale deployment webapp-canary -n $NAMESPACE --replicas=0

echo ""
echo "Esperando que webapp-stable esté listo..."
kubectl rollout status deployment/webapp-stable -n $NAMESPACE --timeout=60s

echo ""
echo "========================================"
echo "  ROLLBACK COMPLETADO"
echo "========================================"
echo ""
echo "Estado DESPUÉS del rollback:"
kubectl get deployments -n $NAMESPACE

echo ""
echo "Verificar que el tráfico volvió a v1:"
echo "  curl http://192.168.109.200:30099"
echo "  → Debe mostrar la página AZUL (v1)"
echo ""
echo "Verificar pods:"
kubectl get pods -n $NAMESPACE -l app=webapp

echo ""
echo "Para ver los logs durante el incidente:"
echo "  kubectl logs -n $NAMESPACE -l version=canary --previous"
echo ""
echo "IMPORTANTE: Revertir también en Git para mantener consistencia GitOps:"
echo "  yq e '.spec.replicas = 9' -i 20-canary-cicd/manifests/03-stable-deployment.yaml"
echo "  yq e '.spec.replicas = 0' -i 20-canary-cicd/manifests/04-canary-deployment.yaml"
echo "  git add 20-canary-cicd/manifests/"
echo "  git commit -m 'ROLLBACK: revert to v1 stable after canary incident'"
echo "  git push && argocd app sync webapp-canary"
echo ""
echo "Argo CD al sincronizar puede intentar sobrescribir el rollback."
echo "Si Argo CD tiene auto-sync, deshabilitarlo temporalmente:"
echo "  argocd app set webapp-canary --sync-policy none"
echo "  (Re-habilitar con: argocd app set webapp-canary --sync-policy automated)"
