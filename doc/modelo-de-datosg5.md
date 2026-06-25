# Modelo de Datos — Grupo 5 Pedidos

## Entidades principales

### `Order` (Pedido)

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `orderId` | string `ORD-YYYYMMDD-NNN` | ✅ | Identificador único del pedido |
| `userId` | string (uuid) | ✅ | Usuario dueño del pedido (referencia a G2) |
| `status` | enum `OrderStatus` | ✅ | Estado actual del pedido |
| `items` | `OrderItem[]` | ✅ | Líneas de producto (mínimo 1) |
| `shippingAddress` | `ShippingAddress` | ✅ | Dirección de despacho |
| `subtotal` | integer (CLP) | — | Suma de subtotales de ítems |
| `shippingCost` | integer (CLP) | — | Costo de envío |
| `totalAmount` | integer (CLP) | ✅ | Total a pagar |
| `currency` | enum `[CLP]` | ✅ | Siempre CLP |
| `notes` | string \| null | — | Notas adicionales del pedido |
| `createdAt` | datetime (ISO 8601) | ✅ | Fecha de creación |
| `updatedAt` | datetime (ISO 8601) | ✅ | Fecha de última actualización |

**Dueño del dato:** Grupo 5. Nadie más escribe en esta tabla.

---

### `OrderItem` (Línea de pedido)

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `productId` | string (uuid) | ✅ | Referencia al producto de G3 (snapshot) |
| `name` | string | ✅ | Nombre del producto al momento de la compra |
| `quantity` | integer (min: 1) | ✅ | Cantidad comprada |
| `unitPrice` | integer (CLP) | ✅ | Precio unitario al momento de la compra |
| `subtotal` | integer (CLP) | ✅ | `quantity × unitPrice` |

> **Importante:** `productId` y `name` son snapshots. Si G3 cambia el precio o nombre del producto después, el pedido ya registrado NO cambia.

---

### `ShippingAddress` (Dirección de despacho)

| Campo | Tipo | Requerido | Descripción |
|---|---|---|---|
| `street` | string | ✅ | Calle y número |
| `city` | string | ✅ | Ciudad |
| `region` | string | ✅ | Región |
| `country` | string | ✅ | País |
| `postalCode` | string \| null | — | Código postal |

---

## Máquina de estados del pedido

```
                    ┌─────────────────────────────┐
                    │                             │
                    ▼                             │
              [CREATED] ──────────────────► [CANCELLED]
                    │                             ▲
                    ▼                             │
          [PAYMENT_PENDING] ────────────────────►─┤
                    │                             │
                    ▼                             │
               [PAID] ──────────────────────────►─┤
                    │                             │
                    ▼                             │
          [STOCK_RESERVED] ─────────────────────►─┤
                    │                             │
                    ▼                             │
           [READY_TO_SHIP] ─────────────────────►─┤
                    │                             │
                    ▼                             │
             [SHIPPED] ─────────────────────────►─┘
                    │
                    ▼
            [DELIVERED] ──► (estado final, sin transición)

        [FAILED] ──► (estado final, sin transición)
```

### Transiciones válidas

| Desde | Hacia | Disparador |
|---|---|---|
| `CREATED` | `PAYMENT_PENDING` | G5 espera confirmación de pago |
| `PAYMENT_PENDING` | `PAID` | Evento `PaymentApproved` de G6 |
| `PAYMENT_PENDING` | `CANCELLED` | Evento `PaymentRejected` de G6 |
| `PAID` | `STOCK_RESERVED` | Evento `StockReserved` de G7 |
| `PAID` | `CANCELLED` | Evento `StockRejected` de G7 |
| `STOCK_RESERVED` | `READY_TO_SHIP` | G8 confirma preparación |
| `READY_TO_SHIP` | `SHIPPED` | G8 confirma despacho |
| `SHIPPED` | `DELIVERED` | G8 confirma entrega |
| Cualquiera | `CANCELLED` | Admin/operador logístico |
| Cualquiera | `FAILED` | Error irrecuperable |

---

## Datos propios vs. datos consultados

| Dato | Dueño | Cómo lo usa G5 |
|---|---|---|
| `orderId`, `status`, `totalAmount`, `createdAt` | **G5** (propio) | Lee y escribe |
| `userId` | G2 (Identidad) | Recibe en el request, no replica perfil |
| `productId`, `name`, `unitPrice` | G3 (Catálogo) | Snapshot al momento de crear el pedido |
| JWT / autenticación | G2 (Identidad) | Reenvía a `POST /auth/validate` para verificar |

---

## Evento publicado: `OrderCreated`

```json
{
  "eventId": "uuid",
  "eventType": "OrderCreated",
  "version": "1.0",
  "occurredAt": "2026-06-22T10:00:00Z",
  "producer": "order-service",
  "correlationId": "uuid",
  "payload": {
    "orderId": "ORD-20260622-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "totalAmount": 1599980,
    "currency": "CLP",
    "items": [
      {
        "productId": "f0e9d8c7-b6a5-4321-0987-fedcba098765",
        "quantity": 2,
        "unitPrice": 799990
      }
    ],
    "createdAt": "2026-06-22T10:00:00Z"
  }
}
```

**Consumidores:** G6 (Pago), G7 (Inventario), G9 (Notificaciones), G10 (Reportería)

---

## Formato de error estándar

```json
{
  "code": "MISSING_IDEMPOTENCY_KEY",
  "message": "El header Idempotency-Key es obligatorio.",
  "details": null,
  "correlationId": "22222222-2222-2222-2222-222222222222"
}
```

### Códigos de error definidos

| Código | HTTP | Descripción |
|---|---|---|
| `MISSING_IDEMPOTENCY_KEY` | 400 | Falta el header `Idempotency-Key` en POST /orders |
| `INVALID_REQUEST` | 400 | Body malformado o campos requeridos ausentes |
| `UNAUTHORIZED` | 401 | Token ausente o inválido |
| `FORBIDDEN` | 403 | Usuario no tiene acceso al recurso |
| `ORDER_NOT_FOUND` | 404 | El `orderId` no existe |
| `DUPLICATED_ORDER` | 409 | `Idempotency-Key` ya usada con body distinto |
| `INVALID_STATUS_TRANSITION` | 409 | Transición de estado no permitida |
