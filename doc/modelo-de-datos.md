# Modelo de Datos — Grupo 5: Pedidos (Order Management)

Este documento define la estructura lógica, las restricciones relacionales de persistencia y el comportamiento transaccional del dominio de Pedidos en una base de datos PostgreSQL con transaccionalidad ACID.

---

## 1. Entidades Principales y Atributos

### `Order` (Pedido)

Representa la cabecera inmutable de la compra una vez confirmada en el checkout.

| Campo | Tipo | Requerido | Descripción |
| --- | --- | --- | --- |
| `orderId` | string `ORD-YYYYMMDD-NNN` | ✅ | Llave Primaria (PK) de negocio. Formato unificado con G6 y G8. |
| `userId` | string (uuid) | ✅ | Identificador del comprador. FK lógica a Grupo 2 (Identidad). |
| `status` | enum `OrderStatus` | ✅ | Estado actual dentro del ciclo de vida del pedido. |
| `items` | `OrderItem[]` | ✅ | Relación 1:N hacia las líneas de productos adjuntas. |
| `shippingAddress` | `ShippingAddress` | ❌ | Dirección física. **Marcado como Nullable** debido a que Grupo 4 actualmente no captura esta data en su checkout. |
| `subtotal` | integer (int64) | ✅ | CLP. Sumatoria estricta de los subtotales de los ítems, sin decimales. |
| `shippingCost` | integer (int64) | ✅ | CLP. Costo de despacho calculado o provisto. |
| `totalAmount` | integer (int64) | ✅ | CLP. Monto total neto de la transacción (`subtotal + shippingCost`). |
| `currency` | enum `[CLP]` | ✅ | Restricción estricta. El sistema rechaza cualquier otra divisa. |
| `idempotencyKey` | string (uuid) | ✅ | Restricción de unicidad (`UNIQUE`). Evita duplicidad de cobros del G4. |
| `notes` | string | null | ❌ | Comentarios o aclaraciones de mitigación de datos. |
| `createdAt` | datetime (ISO 8601) | ✅ | Timestamp UTC de inserción del registro. |
| `updatedAt` | datetime (ISO 8601) | ✅ | Timestamp UTC de la última transición de estado. |

> **Dueño del dato:** Grupo 5. Ningún otro servicio externo tiene permisos de escritura sobre esta entidad.

---

### `OrderItem` (Línea de pedido)

Detalle individual de las mercancías adquiridas.

| Campo | Tipo | Requerido | Descripción |
| --- | --- | --- | --- |
| `id` | integer | ✅ | Llave Primaria autoincremental interna de persistencia. |
| `orderId` | string | ✅ | Llave Foránea (FK) relacional apuntando a `Order.orderId`. |
| `productId` | string (uuid) | ✅ | FK lógica al catálogo de productos de Grupo 3. |
| `name` | string | ✅ | *Snapshot* inmutable del nombre del producto al momento de comprar. |
| `quantity` | integer | ✅ | Cantidad física solicitada (mínimo: 1). |
| `unitPrice` | integer (int64) | ✅ | CLP. *Snapshot* del precio unitario bruto sin decimales. |
| `subtotal` | integer (int64) | ✅ | CLP. Cálculo matemático explícito (`quantity × unitPrice`). |

> ⚠️ **Regla de Consistencia:** `productId`, `name` y `unitPrice` operan como snapshots históricos. Modificaciones posteriores de precio o catálogo en la API del Grupo 3 **no alteran** el registro histórico del pedido de Grupo 5.

---

### `ShippingAddress` (Dirección de despacho)

Estructura embebida o JSONB relacional para almacenamiento geográfico.

| Campo | Tipo | Requerido | Descripción |
| --- | --- | --- | --- |
| `street` | string | ✅ | Nombre de calle, numeración de vivienda y departamento. |
| `city` | string | ✅ | Comuna / Ciudad. |
| `region` | string | ✅ | Región / Provincia. |
| `country` | string | ✅ | País (Por defecto: Chile). |
| `postalCode` | string | null | ❌ | Código postal opcional. |

---

## 2. Máquina de Estados del Pedido

El estado de un pedido se altera de manera secuencial a partir de los siguientes disparadores de eventos del ecosistema:

```text
  [G4 Checkout]
        │
        ▼
     CREATED ──► PAYMENT_PENDING ──► PAID ──► READY_TO_SHIP ──► SHIPPED ──► DELIVERED
        │                 │                                                   ▲
        ▼                 ▼                                                   │
    CANCELLED          FAILED ────────────────────────────────────────────────┘

```

### Transiciones Válidas y Disparadores Reales

| Estado Origen | Estado Destino | Componente / Evento Disparador | Lógica Operacional |
| --- | --- | --- | --- |
| `CREATED` | `PAYMENT_PENDING` | Lógica interna Grupo 5 | Ocurre inmediatamente al persistir el pedido tras recibir el `POST /orders` del Grupo 4. |
| `PAYMENT_PENDING` | `PAID` | **Grupo 8 (Pagos)**<br>

<br>Evento async: `PAYMENT_APPROVED` | El pago fue procesado con éxito en la pasarela. G5 libera el flujo logístico. |
| `PAYMENT_PENDING` | `FAILED` | **Grupo 8 (Pagos)**<br>

<br>Evento async: `PAYMENT_REJECTED` | Fondos insuficientes o rechazo bancario. El pedido frena su ciclo. |
| `PAID` | `READY_TO_SHIP` | **Grupo 6 (Despachos)**<br>

<br>REST síncrono: `201 Created` | G5 realiza un `POST /api/v1/shipments` inyectando dimensiones volumétricas obtenidas previamente de G3. |
| `READY_TO_SHIP` | `SHIPPED` | **Grupo 6 (Despachos)**<br>

<br>REST Polling: `status: "IN_TRANSIT"` | El worker de G5 detecta en las consultas periódicas que el camión de logística salió del hub. |
| `SHIPPED` | `DELIVERED` | **Grupo 6 (Despachos)**<br>

<br>REST Polling: `status: "DELIVERED"` | El worker detecta la entrega física exitosa. Estado final de ciclo exitoso. |
| `CREATED` / `PAID` | `CANCELLED` | Administrador / Servicio | Cancelación manual por contingencia del marketplace. |

---

## 3. Origen y Gobierno de Datos (Map de Fronteras)

| Entidad / Atributo | Microservicio Origen | Mecanismo de Consumo en G5 | Política de Persistencia en G5 |
| --- | --- | --- | --- |
| `orderId`, `status`, `totalAmount` | **Grupo 5** (Propio) | Interno nativo | Dueño absoluto (Escritura/Lectura en PostgreSQL). |
| `userId` | **Grupo 2** (Identidad) | Token JWT entrante | Almacena solo el UUID como FK lógica (No replica perfil). |
| `productId`, `name`, `unitPrice` | **Grupo 3** (Catálogo) | `GET /products/{productId}` | Almacena copia persistente (*Snapshot*) en `OrderItem`. |
| Medidas (`weight`, `dimensions`) | **Grupo 3** (Catálogo) | `GET /products/{productId}` | **Memoria Volátil**. Solo se consulta en caliente para estructurar el POST hacia G6. |

---

## 4. Estructura de Mensajería: Evento `ORDER_CREATED`

Publicado en el broker de mensajería bajo el formato estándar de la organización (Envelope completo en `UPPER_SNAKE_CASE`):

```json
{
  "eventId": "evt-3f2a1b00-0000-4000-8000-000000000001",
  "eventType": "ORDER_CREATED",
  "version": "1.0",
  "occurredAt": "2026-06-22T10:00:00Z",
  "producer": "group-5-pedidos",
  "correlationId": "99999999-8888-4777-9666-555555555555",
  "payload": {
    "orderId": "ORD-20260622-001",
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
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
    ],
    "createdAt": "2026-06-22T10:00:00Z"
  }
}

```

* **Consumidores:** Grupo 7 (Reportería Analítica) y Grupo 8 (Módulo de Notificaciones).

---

## 5. Matriz de Errores Técnicos y Errores de Sincronización

Formato unificado JSON ante fallos de capa REST:

```json
{
  "code": "INVALID_CURRENCY",
  "message": "El marketplace opera exclusivamente con CLP. Se rechazó el intento de pago en USD.",
  "details": null,
  "correlationId": "99999999-8888-4777-9666-555555555555"
}

```

### Catálogo de Códigos de Error HTTP

| Código de Error | Estado HTTP | Motivo / Causa de Activación |
| --- | --- | --- |
| `MISSING_IDEMPOTENCY_KEY` | 400 Bad Request | Petición `POST /orders` omitió la cabeceras obligatoria `Idempotency-Key`. |
| `INVALID_CURRENCY` | 400 Bad Request | **Blindaje G4:** Intento de empujar payloads configurados en `USD` u otras divisas. |
| `INVALID_AMOUNT` | 400 Bad Request | **Blindaje G4:** Envío de precios o subtotales con formato decimal o float. |
| `INVALID_REQUEST` | 400 Bad Request | Faltan campos estructurales mandatorios (ej: `userId`, array de `items` vacío). |
| `UNAUTHORIZED` | 401 Unauthorized | Token Bearer ausente o rechazado por la API centralizada del Grupo 2. |
| `FORBIDDEN` | 403 Forbidden | El usuario autenticado pretende consultar un `orderId` de otro cliente. |
| `ORDER_NOT_FOUND` | 404 Not Found | Búsqueda directa de un identificador de orden que no existe en PostgreSQL. |
| `DUPLICATED_ORDER` | 409 Conflict | Reintento de red con la misma `Idempotency-Key` pero alterando el body del JSON. |
| `INVALID_STATUS_TRANSITION` | 409 Conflict | Intento de saltar estados prohibidos por la máquina (ej: transicionar de `DELIVERED` a `PAID`). |

---