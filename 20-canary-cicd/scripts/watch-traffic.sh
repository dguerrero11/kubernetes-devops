#!/bin/bash
# watch-traffic.sh — Ver el split de tráfico en tiempo real
#
# Hace N peticiones al webapp y cuenta cuántas responde v1 vs v2
# Muestra un resumen visual del split real de tráfico.
#
# Uso:
#   bash scripts/watch-traffic.sh
#   bash scripts/watch-traffic.sh 50         # 50 peticiones
#   bash scripts/watch-traffic.sh 100 http://192.168.109.201:30110  # otro nodo

REQUESTS=${1:-20}
URL=${2:-"http://192.168.109.200:30110"}
NAMESPACE="canary-demo"

echo "========================================"
echo "  CANARY TRAFFIC WATCHER"
echo "========================================"
echo ""
echo "URL: $URL"
echo "Peticiones: $REQUESTS"
echo ""

# Verificar que el servicio responde
if ! curl -s --connect-timeout 3 "$URL" > /dev/null; then
  echo "ERROR: No se puede conectar a $URL"
  echo "Verificar: kubectl get svc webapp -n $NAMESPACE"
  echo "Verificar: kubectl get pods -n $NAMESPACE"
  exit 1
fi

echo "Enviando $REQUESTS peticiones a $URL ..."
echo ""

V1_COUNT=0
V2_COUNT=0
UNKNOWN_COUNT=0
ERRORS=0

for i in $(seq 1 $REQUESTS); do
  RESPONSE=$(curl -s --connect-timeout 2 "$URL" 2>/dev/null)
  EXIT_CODE=$?

  if [ $EXIT_CODE -ne 0 ]; then
    ERRORS=$((ERRORS + 1))
    printf "."
    continue
  fi

  if echo "$RESPONSE" | grep -q "VERSION 1.0"; then
    V1_COUNT=$((V1_COUNT + 1))
    printf "\033[34m1\033[0m"  # Azul para v1
  elif echo "$RESPONSE" | grep -q "VERSION 2.0"; then
    V2_COUNT=$((V2_COUNT + 1))
    printf "\033[32m2\033[0m"  # Verde para v2
  else
    UNKNOWN_COUNT=$((UNKNOWN_COUNT + 1))
    printf "?"
  fi
done

echo ""
echo ""

TOTAL=$((V1_COUNT + V2_COUNT))
if [ $TOTAL -eq 0 ]; then
  echo "No se recibieron respuestas válidas."
  exit 1
fi

V1_PCT=$(( V1_COUNT * 100 / TOTAL ))
V2_PCT=$(( V2_COUNT * 100 / TOTAL ))

# Barra de progreso visual
BAR_LENGTH=30
V1_BARS=$(( V1_COUNT * BAR_LENGTH / TOTAL ))
V2_BARS=$(( V2_COUNT * BAR_LENGTH / TOTAL ))
V1_EMPTY=$((BAR_LENGTH - V1_BARS))
V2_EMPTY=$((BAR_LENGTH - V2_BARS))

printf "\n\033[34mv1 (azul)   :\033[0m "
for j in $(seq 1 $V1_BARS); do printf "█"; done
for j in $(seq 1 $V1_EMPTY); do printf "░"; done
printf " %d/%d  (%s%%)\n" $V1_COUNT $TOTAL "$V1_PCT"

printf "\033[32mv2 (verde)  :\033[0m "
for j in $(seq 1 $V2_BARS); do printf "█"; done
for j in $(seq 1 $V2_EMPTY); do printf "░"; done
printf " %d/%d  (%s%%)\n" $V2_COUNT $TOTAL "$V2_PCT"

if [ $ERRORS -gt 0 ]; then
  printf "\n\033[31mErrores: %d/%d peticiones fallaron\033[0m\n" $ERRORS $REQUESTS
fi

echo ""
echo "========================================"

# Mostrar el estado actual de los deployments
echo ""
echo "Estado actual (kubectl get deployments -n $NAMESPACE):"
kubectl get deployments -n $NAMESPACE 2>/dev/null || \
  echo "(kubectl no disponible o namespace no existe)"

echo ""
echo "Para ver el split esperado:"
STABLE_REPS=$(kubectl get deployment webapp-stable -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
CANARY_REPS=$(kubectl get deployment webapp-canary -n $NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
echo "  Split actual: STABLE=$STABLE_REPS  CANARY=$CANARY_REPS"

echo ""
echo "Para observar logs en tiempo real:"
echo "  kubectl logs -n $NAMESPACE -l app=load-generator --tail=10 -f"
