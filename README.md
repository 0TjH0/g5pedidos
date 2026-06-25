# Grupo 5 — Pedidos / Order Management

Microservicio responsable de administrar, persistir y transicionar el ciclo de
vida de las órdenes de compra dentro del ecosistema **Mini Marketplace Cloud UTEM**.
Actúa como registro maestro de las transacciones comerciales confirmadas de la
plataforma.

---

## Estructura del repositorio

```
Grupo5-Pedidos/
├── contrato/
│   ├── openapi.yaml                  # Contrato REST oficial (fuente de verdad v1.1.0)
│   └── events.md                     # Esquemas y contratos de eventos Pub/Sub
├── app/
│   ├── main.py                       # Entry point FastAPI
│   ├── database.py                   # Configuración ORM y conexión PostgreSQL
│   ├── models.py                     # Esquemas relacionales SQLAlchemy
│   └── schemas.py                    # Validadores Pydantic v2 (camelCase)
├── tests/
│   └── G5_Orders_Collection.json     # Colección de pruebas (Bruno / Postman / Insomnia)
├── Dockerfile
└── README.md
```

---

## Stack tecnológico

| Capa | Tecnología |
|---|---|
| Runtime | Python 3.12+ |
| Framework API | FastAPI + Pydantic v2 |
| Persistencia | PostgreSQL (Render / Supabase) vía SQLAlchemy ORM |
| Contenedorización | Docker |
| CI/CD | GitHub Actions (lint + auto-deploy a Render) |

---

## URLs

| Entorno | URL |
|---|---|
| Mock (Prism / Render) | `https://grupo5-pedidos-mock.onrender.com` |
| Producción (E3) | `https://api-grupo5-pedidos.onrender.com/v1` *(pendiente E3)* |
| Local | `http://localhost:8050/v1` |

---

## Endpoints expuestos (v1.1.0)

| Método | Endpoint | Descripción | Consumidor primario |
|---|---|---|---|
| `POST` | `/orders` | Crear pedido (Idempotency-Key obligatorio) | Grupo 4 (Checkout) |
| `GET` | `/orders/{orderId}` | Obtener pedido por ID | Grupo 1 (BFF) |
| `GET` | `/users/{userId}/orders` | Listar pedidos de un usuario (paginado) | Grupo 1 (BFF / Frontend) |
| `PATCH` | `/orders/{orderId}/status` | Transicionar estado (uso interno / eventos) | Lógica interna |

---

## Máquina de estados del pedido

```
[G4 Checkout]
      │
      ▼
   CREATED → PAYMENT_PENDING → PAID → READY_TO_SHIP → SHIPPED → DELIVERED
                    │
                    ▼
                 FAILED → ORDER_CANCELLED
                    │
                 CANCELLED
```

Transiciones válidas:

| Desde | Hacia | Disparador |
|---|---|---|
| `CREATED` | `PAYMENT_PENDING` | Inmediato al crear la orden |
| `PAYMENT_PENDING` | `PAID` | Evento `PAYMENT_APPROVED` de G8 |
| `PAYMENT_PENDING` | `FAILED` | Evento `PAYMENT_REJECTED` de G8 |
| `PAID` | `READY_TO_SHIP` | Confirmación síncrona de G6 (`POST /api/v1/shipments`) |
| `READY_TO_SHIP` | `SHIPPED` | Polling a G6 devuelve `IN_TRANSIT` |
| `SHIPPED` | `DELIVERED` | Polling a G6 devuelve `DELIVERED` |
| `READY_TO_SHIP` / `SHIPPED` | `CANCELLED` | Polling a G6 devuelve `FAILED` |

Cualquier transición no listada devuelve `409 Conflict`.

---

## Eventos publicados

| Evento | Cuándo se emite | Consumidores |
|---|---|---|
| `ORDER_CREATED` | Al crear la orden exitosamente | G7 (Reportería), G8 (Notificaciones) |
| `ORDER_STATUS_CHANGED` | En cada transición de estado | G7 (Reportería), G8 (Notificaciones) |
| `ORDER_CANCELLED` | Por fallo de pago o despacho | G7 (Reportería), G8 (Notificaciones) |

Ver esquemas completos en `contrato/events.md`.

---

## Eventos consumidos

| Evento | Productor | Acción de G5 |
|---|---|---|
| `PAYMENT_APPROVED` | G8 (Pagos) | Transiciona a `PAID`; llama a G6 para crear shipment |
| `PAYMENT_REJECTED` | G8 (Pagos) | Transiciona a `FAILED`; emite `ORDER_CANCELLED` |
| `PAYMENT_PENDING` | G8 (Pagos) | Solo log; sin cambio de estado |
| `SHIPMENT_IN_TRANSIT` *(bloqueado)* | G6 (Despacho) | Mitigado vía polling REST — ver abajo |
| `SHIPMENT_DELIVERED` *(bloqueado)* | G6 (Despacho) | Mitigado vía polling REST — ver abajo |

---

## Integración con otros grupos

| Grupo | Rol | Tipo de integración |
|---|---|---|
| Grupo 2 (Identidad) | Valida JWT entrantes (`POST /auth/validate`) | REST síncrono |
| Grupo 4 (Checkout) | Invoca `POST /orders` al confirmar compra | REST síncrono |
| Grupo 6 (Despacho) | G5 llama `POST /api/v1/shipments` tras `PAID`; polling de estado | REST síncrono + polling |
| Grupo 7 (Reportería) | Consume `ORDER_CREATED`, `ORDER_STATUS_CHANGED` | Evento asíncrono |
| Grupo 8 (Pagos) | G5 consume `PAYMENT_APPROVED/REJECTED`; G8 consume eventos de G5 | Evento asíncrono (bidireccional) |

### Bloqueo temporal con Grupo 6

G6 tiene implementado el patrón Outbox pero **no tiene un worker activo** que
despache mensajes al broker. Mientras dure el bloqueo, G5 ejecuta polling
periódico (cada 60 s) a `GET /api/v1/shipments?orderId={orderId}`.

Las llamadas de este worker deben incluir:

| Header | Valor |
|---|---|
| `X-Request-Id` | UUIDv4 aleatorio generado por el worker en cada llamada |
| `X-Correlation-Id` | UUID original del pedido |
| `X-Consumer` | `"G5-Pedidos"` |

Cuando G6 active su worker, el polling se reemplaza por consumo real de eventos.
Ese cambio se documenta como versión `1.1` en `contrato/events.md`.

---

## Headers obligatorios (estándar ecosistema)

```http
Authorization: Bearer <token_jwt_grupo_2>
Idempotency-Key: <uuid_v4>        # obligatorio en POST /orders
X-Correlation-Id: <uuid_v4>       # recomendado en todas las requests
```

Headers adicionales requeridos en llamadas **salientes** hacia G6:

```http
X-Request-Id: <uuid_v4>           # nuevo UUID por cada llamada del worker
X-Consumer: G5-Pedidos
```

---

## Cómo probar el mock

```bash
# Instalar Prism globalmente
npm install -g @stoplight/prism-cli

# Levantar mock local apuntando al contrato
prism mock contrato/openapi.yaml -p 8050 -h 0.0.0.0
```

Para validar flujos, importar `tests/G5_Orders_Collection.json` en Bruno,
Postman o Insomnia y apuntar `baseUrl` a `http://localhost:8050/v1`.

Ver `mock/README.md` para más detalles de despliegue en Render.
