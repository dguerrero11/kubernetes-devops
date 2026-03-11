#!/bin/bash
# promote-50-to-100.sh — Migración completa: 50% → 100% v2
#
# Cambia el split de réplicas:
#   ANTES: stable=5, canary=5  (50/50)
#   DESPUÉS: stable=0, canary=10  (100% v2)
#
# Esta es la fase final de la migración canary.
# Después de esto, todos los usuarios ven v2.
#
# Si hay problemas después de esto, usar rollback.sh para volver a v1.

NAMESPACE="canary-demo"

echo "========================================"
echo "  MIGRACIÓN COMPLETA: 50% → 100% v2"
echo "========================================"
echo ""
echo "ATENCIÓN: Esta acción llevará el 100% del tráfico a v2 (canary)."
echo "Si v2 tiene algún problema, usar: bash scripts/rollback.sh"
echo ""

# Mostrar estado actual
echo "Estado ANTES de la migración completa:"
kubectl get deployments -n $NAMESPACE
echo ""

# Confirmar acción (doble confirmación por ser más crítico)
read -p "¿Confirmar migración al 100% v2? (escribir 'SI' para confirmar): " CONFIRM

if [ "$CONFIRM" != "SI" ]; then
  echo "Migración cancelada. Respuesta requerida: 'SI' (mayúsculas)."
  exit 0
fi

echo ""
echo "Iniciando migración completa..."
echo ""

echo "Escalando webapp-canary → 10 réplicas..."
kubectl scale deployment webapp-canary -n $NAMESPACE --replicas=10

echo "Esperando que el canary tenga 10 réplicas listas..."
kubectl rollout status deployment/webapp-canary -n $NAMESPACE --timeout=90s

echo ""
echo "Escalando webapp-stable → 0 réplicas (retirando v1)..."
kubectl scale deployment webapp-stable -n $NAMESPACE --replicas=0

echo ""
echo "Estado DESPUÉS de la migración:"
kubectl get deployments -n $NAMESPACE
echo ""
kubectl get pods -n $NAMESPACE

echo ""
echo "========================================"
echo "  MIGRACIÓN COMPLETADA: 100% v2 ACTIVO"
echo "========================================"
echo ""
echo "Todo el tráfico ahora va a WebApp v2 (verde)."
echo ""
echo "Verificar con:"
echo "  bash scripts/watch-traffic.sh 20"
echo "  → Debería mostrar 100% v2 (verde)"
echo ""
echo "Ver en el browser:"
echo "  http://192.168.109.200:30099  → siempre verde"
echo ""
echo "En caso de problemas → ROLLBACK INMEDIATO:"
echo "  bash scripts/rollback.sh"
echo ""
echo "IMPORTANTE: Si usas GitOps, sincronizar con el estado en Git:"
echo "  yq e '.spec.replicas = 0'  -i 20-canary-cicd/manifests/03-stable-deployment.yaml"
echo "  yq e '.spec.replicas = 10' -i 20-canary-cicd/manifests/04-canary-deployment.yaml"
echo "  git add 20-canary-cicd/manifests/"
echo "  git commit -m 'canary: complete migration to v2 (100%)'"
echo "  git push && argocd app sync webapp-canary"
