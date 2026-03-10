# Rúbrica de Evaluación — Proyectos Finales
# Diplomado: Seguridad en Infraestructura y Kubernetes

**Puntaje total:** 100 puntos
**Presentación:** 15 minutos por equipo + 5 minutos de preguntas
**Formato de entrega:** Repositorio Git + Demo en vivo

---

## Distribución de puntaje

```
┌──────────────────────────────────────────┬────────┐
│  Sección                                 │ Puntos │
├──────────────────────────────────────────┼────────┤
│  1. Implementación técnica               │  40    │
│  2. Controles de seguridad               │  25    │
│  3. Observabilidad (monitoring + logging)│  20    │
│  4. Documentación                        │  10    │
│  5. Presentación y demo en vivo          │   5    │
├──────────────────────────────────────────┼────────┤
│  TOTAL                                   │ 100    │
└──────────────────────────────────────────┴────────┘
```

---

## Sección 1 — Implementación técnica (40 puntos)

### Criterios por equipo

#### Equipo 1 — Análisis de Vulnerabilidades

| Criterio | Excelente (100%) | Suficiente (60%) | Insuficiente (0%) | Pts |
|---|---|---|---|---|
| kube-bench ejecutado | Job completado, resultados documentados con tabla PASS/FAIL/WARN | Job ejecutado pero sin análisis | No ejecutado | 8 |
| Trivy en imágenes | ≥3 imágenes escaneadas, CVEs clasificados, propuesta de remediación | Solo 1 imagen, sin clasificación | No ejecutado | 8 |
| kube-hunter | Reporte interno + externo, vulnerabilidades analizadas | Solo un tipo de escaneo | No ejecutado | 8 |
| Falco funcionando | DaemonSet running, ≥3 reglas disparadas con evidencia | Instalado pero sin demos | No instalado | 8 |
| Plan de remediación | Top 5 hallazgos con severidad, impacto y remediación concreta | Lista de hallazgos sin remediación | No presentado | 8 |

#### Equipo 2 — Aplicación Segura

| Criterio | Excelente (100%) | Suficiente (60%) | Insuficiente (0%) | Pts |
|---|---|---|---|---|
| WordPress + MySQL funcionando | App accesible en HTTPS, datos persisten al reiniciar pods | App funciona pero sin TLS o sin persistencia | App no corre | 8 |
| Storage (PV + PVC) | PVC Bound, datos persisten tras eliminar y recrear pod | PVC creado pero no verificada la persistencia | Sin storage | 8 |
| Ingress TLS | HTTPS funcional con certificado, HTTP redirige a HTTPS | HTTPS funciona pero sin redirect | Sin TLS | 8 |
| ResourceQuota + LimitRange | Ambos aplicados y verificados con `kubectl describe` | Solo uno aplicado | Ninguno | 8 |
| Secrets correctamente usados | Sin credenciales en texto en ningún YAML del repo | Secret creado pero también hardcoded en YAML | Credenciales en texto plano | 8 |

#### Equipo 3 — Keycloak + OIDC

| Criterio | Excelente (100%) | Suficiente (60%) | Insuficiente (0%) | Pts |
|---|---|---|---|---|
| Keycloak desplegado | Corriendo con Realm + Client + 3 Grupos + 3 Usuarios configurados | Keycloak corre pero configuración incompleta | No desplegado | 8 |
| kube-apiserver con OIDC | Flags OIDC configurados, API server reiniciado y funcional | Flags agregados pero con errores | Sin configuración OIDC | 8 |
| kubectl con kubelogin | Login OIDC funcional, token válido obtenido de Keycloak | Parcialmente funcional | No funciona | 8 |
| Demo cambio de grupo | Cambiar grupo en Keycloak → permisos cambian en K8s en tiempo real | Demo preparada pero sin cambio dinámico | No demo | 8 |
| RBAC mapeado a grupos | 3 RoleBindings con permisos diferenciados y verificados | 1-2 RoleBindings funcionando | Sin RBAC | 8 |

---

## Sección 2 — Controles de seguridad (25 puntos)

*Aplicable a todos los equipos — cada equipo debe aplicar controles en sus workloads*

| Criterio | Excelente (5 pts) | Suficiente (3 pts) | Insuficiente (0 pts) |
|---|---|---|---|
| **SecurityContext** | `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities: drop ALL` aplicados en todos los pods del proyecto | Aplicado parcialmente (algunos pods o solo algunos campos) | Sin SecurityContext en ningún pod |
| **NetworkPolicy** | Default-deny + reglas específicas. Demo de bloqueo funcional | Policies aplicadas pero sin demo de bloqueo | Sin NetworkPolicies |
| **Namespaces de aislamiento** | Proyecto en namespace dedicado, recursos separados de otros equipos | Namespace creado pero sin aislamiento real | Todo en namespace default |
| **RBAC del proyecto** | ServiceAccount con mínimos privilegios para los pods del proyecto | ServiceAccount creado pero con permisos excesivos | Sin ServiceAccount dedicado |
| **Gestión de Secrets** | Sin credenciales en texto plano en YAMLs, Secrets usados via env o volume | Secrets usados pero alguna credencial hardcoded | Credenciales en texto en YAMLs |

---

## Sección 3 — Observabilidad (20 puntos)

### 3.1 Monitoring (10 puntos)

| Criterio | Excelente (10 pts) | Suficiente (6 pts) | Insuficiente (0-3 pts) |
|---|---|---|---|
| **Stack desplegado** | Stack asignado corriendo completamente (todos los componentes) | Stack parcialmente desplegado (falta algún componente) | Stack no desplegado |
| **Métricas del proyecto** | Dashboard con métricas específicas del proyecto (no solo defaults) | Solo dashboard por defecto sin personalización | Sin dashboards |
| **Demo en vivo** | Demostración funcional durante la presentación | Demo preparada pero falla durante la presentación | Sin demo |

### Stack asignado por equipo:
```
Equipo 1 → Prometheus + Grafana (extender clase 10) + Loki + Promtail
Equipo 2 → EFK Stack: Elasticsearch + Fluentd + Kibana
Equipo 3 → Jaeger (tracing) + Fluent Bit + Loki + Grafana
```

### 3.2 Logging (10 puntos)

| Criterio | Excelente (10 pts) | Suficiente (6 pts) | Insuficiente (0-3 pts) |
|---|---|---|---|
| **Recolección de logs** | Logs de TODOS los pods del proyecto visibles en la UI | Logs de algunos pods solamente | Sin logging configurado |
| **Búsqueda/Filtrado** | Demostrar búsqueda por namespace, pod, nivel de error | Solo visualización básica sin filtros | Sin demostración |
| **Evento correlacionado** | Generar un evento en el proyecto → encontrar su log en la UI | Logs visibles pero sin correlación con eventos | Sin correlación |

---

## Sección 4 — Documentación (10 puntos)

| Criterio | Excelente (10 pts) | Suficiente (6 pts) | Insuficiente (0-3 pts) |
|---|---|---|---|
| **Diagrama de arquitectura** | Diagrama claro con todos los componentes, relaciones y controles de seguridad etiquetados | Diagrama presente pero incompleto | Sin diagrama |
| **Decisiones de seguridad** | Documento explicando POR QUÉ se eligió cada control, no solo qué se hizo | Lista de controles sin justificación | Sin documentación de decisiones |
| **Repositorio ordenado** | Archivos organizados por módulo, nombres descriptivos, README con instrucciones de despliegue | Archivos presentes pero desorganizados | Sin repositorio o sin commits |

---

## Sección 5 — Presentación y demo (5 puntos)

| Criterio | Excelente (5 pts) | Suficiente (3 pts) | Insuficiente (0-1 pts) |
|---|---|---|---|
| **Claridad de exposición** | Todos los integrantes participan, explican el problema y la solución con claridad | Solo un integrante expone, explicación confusa | No hay presentación coherente |
| **Demo en vivo funcional** | Demo ejecutada en tiempo real sin errores, se muestra el caso de uso de seguridad | Demo funciona pero con errores o improvisaciones | Demo no funciona |

---

## Tabla resumen de calificación

```
Puntaje    Calificación
─────────────────────────
90 - 100   Excelente
80 - 89    Muy Bueno
70 - 79    Bueno
60 - 69    Suficiente
< 60       Insuficiente
```

---

## Penalizaciones

| Situación | Penalización |
|---|---|
| Credenciales hardcoded en repositorio público | -20 puntos |
| Demo completamente no funcional | -15 puntos |
| Entrega fuera de fecha | -10 puntos por día |
| Menos de 2 integrantes participando en la presentación | -10 puntos |

---

## Bonificaciones (máximo +10 puntos)

| Situación | Bonificación |
|---|---|
| Integración entre 2 módulos del proyecto (ej: Falco → alertas en Grafana) | +5 puntos |
| Uso de Helm charts para despliegue (en lugar de YAMLs manuales) | +3 puntos |
| Script de despliegue automatizado (bash/makefile) | +2 puntos |
| Política PSA aplicada al namespace del proyecto | +2 puntos |
| Alertas configuradas en el stack de observabilidad | +3 puntos |

---

## Comparativa de stacks de observabilidad por equipo

```
┌─────────────────────────────────────────────────────────────────────────────┐
│         Equipo 1              Equipo 2              Equipo 3                │
│    PLG Stack                  EFK Stack          Jaeger + Fluent Bit        │
│   ─────────────             ─────────────        ─────────────────          │
│   Prometheus                Elasticsearch        Jaeger (tracing)           │
│   Loki + Promtail           Fluentd              Fluent Bit                 │
│   Grafana                   Kibana               Loki + Grafana             │
│                                                                             │
│   Puerto: 30093 (Grafana)   Puerto: 30099 (Kibana)  Puerto: 30100 (Jaeger) │
│                                                      Puerto: 30101 (Grafana)│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Fechas sugeridas

| Hito | Fecha |
|---|---|
| Entrega del plan de trabajo (qué va a hacer cada integrante) | Semana 1 — Día 2 |
| Revisión intermedia (avance técnico) | Semana 1 — Día 5 |
| Entrega de repositorio con todos los archivos | Semana 2 — Día 4 |
| Presentaciones y demos en vivo | Semana 2 — Día 5 |
