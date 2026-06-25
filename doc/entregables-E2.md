# Entregables — Fase 2: Mock (Grupo 5 — Pedidos)

Mapeo de cada entregable exigido por la rúbrica oficial **E2 Mock** con su evidencia concreta.

## 1. Repositorio GitHub

**URL:** https://github.com/Mini-Marketplace-Cloud-UTEM/Grupo5-Pedidos  
**Estado:** ✅ Repositorio con estructura ordenada, historial de commits limpio, README ejecutable.

## 2. Mock público

**URL:** `https://grupo5-pedidos-mock.onrender.com`  
**Cómo se construyó:** Mock estático con [Prism](https://stoplight.io/open-source/prism) leyendo el `openapi.yaml` del contrato — sin lógica de negocio ni base de datos. Sirve los `example:` declarados en cada respuesta del contrato.  
**Estado:** ✅ Desplegado y verificado en vivo (2026-06-22). Los 4 endpoints responden correctamente.

Ver detalles técnicos en `mock/README.md`.

## 3. README inicial

**URL:** https://github.com/Mini-Marketplace-Cloud-UTEM/Grupo5-Pedidos/blob/main/README.md  
**Estado:** ✅ Explica el servicio, endpoints, estados, integración con otros grupos y cómo probar.

## 4. Colección de pruebas

**Herramienta:** Postman  
**Archivo:** `contrato/postman_collection.json`  
**Cobertura:** 6 requests totales:

| # | Request | Resultado esperado |
|---|---|---|
| 1 | POST `/orders` con Idempotency-Key | 201 Created |
| 2 | POST `/orders` sin Idempotency-Key | 400 MISSING_IDEMPOTENCY_KEY |
| 3 | GET `/orders/{orderId}` con token | 200 OK |
| 4 | GET `/orders/{orderId}` sin token | 401 Unauthorized |
| 5 | PATCH `/orders/{orderId}/status` | 200 OK |
| 6 | GET `/users/{userId}/orders?page=1&pageSize=10` | 200 OK paginado |

**Variables:** `{{baseUrl}}`, `{{authToken}}`, `{{orderId}}`, `{{userId}}` — fácil de cambiar cuando el servicio real de E3 reemplace al mock.  
**Estado:** ✅ Todas probadas contra el mock en vivo.

## 5. Modelo de datos actualizado

**Archivo:** `docs/modelo-de-datos.md`  
**Contenido:** Entidades (`Order`, `OrderItem`, `ShippingAddress`), máquina de estados completa con 9 estados y transiciones válidas, datos propios vs. consultados, formato del evento `OrderCreated` y códigos de error estándar.  
**Estado:** ✅ Consistente con el contrato OpenAPI y sin cambios estructurales respecto a E1.

---

## Resumen de cobertura vs. rúbrica grupal E2

| Criterio | Peso | Evidencia |
|---|---|---|
| Mock funcional | 25% | URL pública verificada, 4 endpoints responden con ejemplos reales del contrato |
| Repositorio y estructura base | 15% | Repo ordenado con carpetas `contrato/`, `docs/`, `mock/`, README ejecutable |
| Modelo de datos refinado | 20% | `docs/modelo-de-datos.md` — entidades, campos, máquina de estados y eventos |
| Pruebas de contrato | 15% | Colección Postman con 6 requests (4 happy path + 2 casos de error) |
| Alineación con otros grupos | 15% | Contrato adoptado en `marketplace-contracts`, URL del mock disponible para G4 y otros consumidores |
| Avance técnico inicial | 10% | Mock real desplegado en Render (no solo documentado) |
