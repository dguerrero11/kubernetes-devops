#!/bin/bash
# promote-10-to-50.sh — Promover canary de 10% → 50%
#
# Cambia el split de réplicas:
#   ANTES: stable=9, canary=1  (90/10)
#   DESPUÉS: stable=5, canary=5  (50/50)
#
# NOTA: Esto hace kubectl scale directamente (bypasea GitOps).
# En producción, la forma correcta es editar el YAML en Git y hacer push.
# Para el método GitOps, ver la guía: 00-GUIA-CLASE-CANARY-CICD.md Fase 4.

NAMESPACE="canary-demo"

echo "========================================"
echo "  PROMOCIÓN CANARY: 10% → 50%"
echo "========================================"
echo ""

# Mostrar estado actual
echo "Estado ANTES de la promoción:"
kubectl get deployments -n $NAMESPACE
echo ""

# Confirmar acción
echo "Acción: stable=9→5 réplicas, canary=1→5 réplicas"
echo "Split resultante: 50% stable / 50% canary"
echo ""
read -p "¿Confirmar la promoción al 50%? (s/n): " CONFIRM

if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
  echo "Promoción cancelada."
  exit 0
fi

echo ""
echo "Escalando webapp-stable → 5 réplicas..."
kubectl scale deployment webapp-stable -n $NAMESPACE --replicas=5

echo "Escalando webapp-canary → 5 réplicas..."
kubectl scale deployment webapp-canary -n $NAMESPACE --replicas=5

echo ""
echo "Esperando que los pods estén listos..."
kubectl rollout status deployment/webapp-stable -n $NAMESPACE --timeout=60s
kubectl rollout status deployment/webapp-canary -n $NAMESPACE --timeout=60s

echo ""
echo "Estado DESPUÉS de la promoción:"
kubectl get deployments -n $NAMESPACE

echo ""
echo "========================================"
echo "  PROMOCIÓN COMPLETADA: 50/50"
echo "========================================"
echo ""
echo "El tráfico ahora está dividido 50/50 entre v1 y v2."
echo ""
echo "Verificar con:"
echo "  bash scripts/watch-traffic.sh 20"
echo ""
echo "Ver en Grafana:"
echo "  http://192.168.109.200:30093"
echo ""
echo "Próximo paso: Promover al 100% cuando la confianza en v2 sea alta:"
echo "  bash scripts/promote-50-to-100.sh"
echo ""
echo "IMPORTANTE: Si usas GitOps, actualiza también el manifest en Git:"
echo "  yq e '.spec.replicas = 5' -i 20-canary-cicd/manifests/03-stable-deployment.yaml"
echo "  yq e '.spec.replicas = 5' -i 20-canary-cicd/manifests/04-canary-deployment.yaml"
echo "  git add 20-canary-cicd/manifests/"
echo "  git commit -m 'canary: promote to 50/50 split'"
echo "  git push && argocd app sync webapp-canary"
