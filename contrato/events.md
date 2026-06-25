# Contrato de Eventos — Grupo 5: Pedidos (Order Management)

Este documento define la estructura y el comportamiento de la comunicación
asíncrona del servicio de Pedidos (`order-service`). Todos los eventos
transmitidos a través del bus del ecosistema utilizan el sobre estándar
`EventEnvelope` definido en `marketplace-contracts/shared/components.yaml`:

```yaml
EventEnvelope:
  eventId: uuid            # Identificador único del evento (llave de idempotencia)
  eventType: string        # Tipo de evento en UPPER_SNAKE_CASE
  version: string          # Versión del contrato del evento (ej. "1.0")
  occurredAt: date-time    # Timestamp UTC en que se generó el evento
  producer: string         # Identificador del emisor: "group-5-pedidos"
  correlationId: uuid?     # UUID de trazabilidad transversal de la solicitud
  payload: object          # Contenido del evento en formato camelCase
```

> **Convención de `producer`:** todos los grupos deben usar el formato
> `group-N-nombre` (ej. `group-5-pedidos`, `group-6-despacho`,
> `group-7-reporteria`, `group-8-pagos`). El valor `g8-pagos` que aparece
> en los payloads de ejemplo de G8 está pendiente de estandarización con
> ese equipo.

> **Unidad monetaria:** todos los montos (`totalAmount`, `amount`,
> `unitPrice`, `subtotal`) se expresan como **enteros en CLP sin
> decimales** (ej. `1599980` = $1.599.980 CLP). No se usan centavos.

Tecnología del curso: contratos JSON Pub/Sub vía Upstash Kafka Free /
Cloudflare Queues / Supabase Realtime (confirmar cuál usa el equipo).

---

## 1. Eventos que PUBLICA Grupo 5

### `ORDER_CREATED`

Se publica inmediatamente después de registrar un pedido de forma exitosa
(`POST /orders` → `201 Created`). Consumido de manera asíncrona por
**Grupo 7 (Reportería)** y **Grupo 8 (Notificaciones)** — confirmado en
sus propios contratos (`services/group-7-reporteria/openapi.yaml`,
sección `x-events.consumed`).

```json
{
  "eventId": "evt-3f2a1b00-0000-4000-8000-000000000001",
  "eventType": "ORDER_CREATED",
  "version": "1.0",
  "occurredAt": "2026-06-20T10:00:00Z",
  "producer": "group-5-pedidos",
  "correlationId": "99999999-8888-4777-9666-555555555555",
  "payload": {
    "orderId": "ORD-20260620-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "status": "CREATED",
    "totalAmount": 1599980,
    "currency": "CLP",
    "items": [
      {
        "productId": "f0e9d8c7-b6a5-4321-0987-fedcba098765",
        "name": "Notebook Lenovo IdeaPad",
        "quantity": 2,
        "unitPrice": 799990,
        "subtotal": 1599980
      }
    ]
  }
}
```

### `ORDER_STATUS_CHANGED`

Se emite tras cada transición válida dentro de la máquina de estados del
pedido: `PAYMENT_PENDING → PAID → READY_TO_SHIP → SHIPPED → DELIVERED`.
También se emite para la transición a `FAILED` cuando el pago es
rechazado (ver lógica de consumo en §2). Consumido por G8 para alertar
al cliente y por G7 para el control analítico en tiempo casi real.

> **Nota:** la transición a `READY_TO_SHIP` la dispara G5 directamente
> tras confirmar con G6 la creación del shipment (llamada síncrona
> `POST /api/v1/shipments`). Mientras G6 no tenga su worker de Outbox
> activo, las transiciones `SHIPPED` y `DELIVERED` se derivan del
> polling descrito en §2.

```json
{
  "eventId": "evt-3f2a1b00-0000-4000-8000-000000000002",
  "eventType": "ORDER_STATUS_CHANGED",
  "version": "1.0",
  "occurredAt": "2026-06-20T10:05:00Z",
  "producer": "group-5-pedidos",
  "correlationId": "99999999-8888-4777-9666-555555555555",
  "payload": {
    "orderId": "ORD-20260620-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "previousStatus": "PAYMENT_PENDING",
    "status": "PAID"
  }
}
```

### `ORDER_CANCELLED`

Caso de uso exclusivo para cancelaciones de pedidos. Se separa de
`ORDER_STATUS_CHANGED` porque dispara un flujo distinto en
Notificaciones (cancelación ≠ avance normal) y permite a otros servicios
ejecutar rollbacks de stock. Consumido por G7 y G8.

```json
{
  "eventId": "evt-3f2a1b00-0000-4000-8000-000000000003",
  "eventType": "ORDER_CANCELLED",
  "version": "1.0",
  "occurredAt": "2026-06-20T10:10:00Z",
  "producer": "group-5-pedidos",
  "correlationId": "99999999-8888-4777-9666-555555555555",
  "payload": {
    "orderId": "ORD-20260620-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "status": "CANCELLED",
    "reason": "PAYMENT_REJECTED"
  }
}
```

---

## 2. Eventos que CONSUME Grupo 5

### `PAYMENT_APPROVED` / `PAYMENT_REJECTED` / `PAYMENT_PENDING` (Grupo 8 — Pagos)

Confirmado contra el contrato real de G8
(`services/group-8-pagos/openapi.yaml`).

```json
{
  "eventId": "evt-550e8400-e29b-41d4-a716-446655440001",
  "eventType": "PAYMENT_APPROVED",
  "version": "1.0",
  "occurredAt": "2026-06-20T10:04:00Z",
  "producer": "group-8-pagos",
  "correlationId": "99999999-8888-4777-9666-555555555555",
  "payload": {
    "paymentId": "PAY-a1b2c3d4-e5f6-7890-1234-56789abcdef0",
    "orderId": "ORD-20260620-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "amount": 1599980,
    "currency": "CLP"
  }
}
```

**Lógica de G5 al consumir:**

- `PAYMENT_APPROVED` → `PATCH /orders/{orderId}/status` interno a `PAID`,
  luego llamada síncrona a G6 (`POST /api/v1/shipments`) para crear el
  shipment y transicionar a `READY_TO_SHIP`. Publica
  `ORDER_STATUS_CHANGED` para cada transición.
- `PAYMENT_REJECTED` → transición a `FAILED`, publica `ORDER_STATUS_CHANGED`
  con `status: FAILED` y a continuación `ORDER_CANCELLED` con
  `reason: PAYMENT_REJECTED`.
- `PAYMENT_PENDING` → no cambia de estado (el pedido ya nace en
  `PAYMENT_PENDING`); solo se loguea.

**Idempotencia obligatoria:** si el mismo `eventId` llega dos veces
(reintento del bus), G5 debe ignorar la segunda entrega sin re-disparar
la transición ni la llamada a G6. Se recomienda un `UNIQUE constraint`
sobre `eventId` en la tabla de eventos procesados — mismo patrón que usa
G8 para sus propias notificaciones.

---

### `SHIPMENT_IN_TRANSIT` / `SHIPMENT_DELIVERED` (Grupo 6 — Despacho) — ⚠️ BLOQUEADO

G6 implementó el patrón Outbox (`outbox_events`) pero **no tiene un
worker activo que despache mensajes al broker real** (confirmado en
`services/group-6-despacho/README.md`).

**Mitigación temporal — Polling REST con headers obligatorios:**

G5 implementará un worker de fondo (cronjob o proceso repetitivo) que
consultará periódicamente la API REST de G6 para pedidos en estado
`READY_TO_SHIP` o `SHIPPED` (intervalo sugerido: 60 s):

```
GET /api/v1/shipments?orderId={orderId}   (Grupo 6)
```

Las llamadas de este worker **deben incluir** las siguientes cabeceras,
requeridas por el API Gateway de G6:

| Header | Valor |
|---|---|
| `X-Request-Id` | UUIDv4 aleatorio generado por el worker en cada llamada |
| `X-Correlation-Id` | UUID original guardado en el pedido (`correlationId`) |
| `X-Consumer` | `"G5-Pedidos"` |

**Mapeo de respuesta → estado de G5:**

| `status` devuelto por G6 | Acción en G5 |
|---|---|
| `IN_TRANSIT` | Transicionar pedido a `SHIPPED`; publicar `ORDER_STATUS_CHANGED` |
| `DELIVERED` | Transicionar pedido a `DELIVERED`; publicar `ORDER_STATUS_CHANGED` |
| `FAILED` | Publicar `ORDER_CANCELLED` con `reason: SHIPMENT_FAILED` |

Cuando G6 active su worker de Outbox, este polling se reemplaza por
consumo real de los eventos `SHIPMENT_IN_TRANSIT` y `SHIPMENT_DELIVERED`.
Documentar ese cambio como **versión `1.1`** de este contrato.
**Responsable del upgrade:** coordinador de G5, en conjunto con G6, al
momento en que `services/group-6-despacho/README.md` confirme el worker
activo.

---

## 3. Tabla resumen de conectividad asíncrona

| Evento | Dirección | Origen / Destino | Estado | Acción de G5 |
|---|---|---|---|---|
| `ORDER_CREATED` | Publica | → G7 Reportería / G8 Notificaciones | ✅ Listo | Emitido al crear la orden |
| `ORDER_STATUS_CHANGED` | Publica | → G7 Reportería / G8 Notificaciones | ✅ Listo | Emitido en cada transición de estado |
| `ORDER_CANCELLED` | Publica | → G7 Reportería / G8 Notificaciones | ✅ Listo | Emitido por fallo de pago o despacho |
| `PAYMENT_APPROVED` | Consume | ← G8 Pagos | ✅ Confirmado | Transiciona a `PAID`; genera shipment en G6 |
| `PAYMENT_REJECTED` | Consume | ← G8 Pagos | ✅ Confirmado | Transiciona a `FAILED`; emite `ORDER_CANCELLED` |
| `PAYMENT_PENDING` | Consume | ← G8 Pagos | ✅ Confirmado | Solo log; sin cambio de estado |
| `SHIPMENT_IN_TRANSIT` | Consume | ← G6 Despacho | 🔴 Bloqueado | Mitigado vía polling REST con headers |
| `SHIPMENT_DELIVERED` | Consume | ← G6 Despacho | 🔴 Bloqueado | Mitigado vía polling REST con headers |
