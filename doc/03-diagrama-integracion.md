# Diagrama de Integración — Grupo 5: Pedidos

## 1. Diagrama de componentes (C1 — contexto del sistema)

```mermaid
flowchart LR
    U[Usuario] --> FE[G1 · Frontend/BFF]
    FE --> G4[G4 · Carrito/Checkout]

    G4 -->|"POST /orders"| G5[G5 · Pedidos]
    G5 -->|"POST /auth/validate"| G2[G2 · Auth]
    G4 -->|"POST /auth/validate"| G2
    G6 -->|"POST /auth/validate"| G2

    G5 -->|"POST /v1/payments"| G8P[G8 · Pagos]
    G8P -- "evento PAYMENT_APPROVED / PAYMENT_REJECTED" --> G5

    G5 -->|"GET /products/{id} (dimensiones para G6)"| G3[G3 · Catálogo]
    G5 -->|"POST /api/v1/shipments"| G6[G6 · Despacho]
    G5 -.->|"GET /shipments?orderId= (polling temporal)"| G6

    G5 -- "evento ORDER_CREATED / ORDER_STATUS_CHANGED / ORDER_CANCELLED" --> G7[G7 · Reportería]
    G5 -- "evento ORDER_CREATED / ORDER_STATUS_CHANGED / ORDER_CANCELLED" --> G8N[G8 · Notificaciones]

    style G5 fill:#2563eb,color:#fff,stroke:#1d4ed8,stroke-width:2px
```

---

## 2. Diagrama de secuencia (C2 — flujo end-to-end del pedido)

```mermaid
sequenceDiagram
    autonumber
    participant U  as Usuario
    participant FE as G1 Frontend/BFF
    participant G4 as G4 Carrito/Checkout
    participant G5 as G5 Pedidos
    participant G2 as G2 Auth
    participant G8P as G8 Pagos
    participant G3 as G3 Catálogo
    participant G6 as G6 Despacho
    participant G7 as G7 Reportería
    participant G8N as G8 Notificaciones

    U->>FE: Confirmar compra
    FE->>G4: POST /v1/checkout (Idempotency-Key)
    G4->>G4: valida stock, reserva inventario

    G4->>G5: POST /orders (items en CLP, stock ya reservado)
    G5->>G2: POST /auth/validate (Bearer token)
    G2-->>G5: 200 {valid, userId, role}
    G5-->>G4: 201 Order {status: CREATED}
    G4-->>FE: 201 CheckoutIntent {orderId}

    G5--)G7: evento ORDER_CREATED
    G5--)G8N: evento ORDER_CREATED

    Note over G5,G8P: G5 orquesta el pago (decisión v1.1)
    G5->>G8P: POST /v1/payments (orderId, totalAmount CLP)
    G8P-->>G5: 201 Payment {status: PENDING}
    G5->>G5: PATCH interno status → PAYMENT_PENDING

    G8P--)G5: evento PAYMENT_APPROVED (async)
    G5->>G5: PATCH interno status → PAID
    G5--)G7: evento ORDER_STATUS_CHANGED (PAID)
    G5--)G8N: evento ORDER_STATUS_CHANGED (PAID)

    Note over G5,G3: Mitigación volumétrica — G6 exige peso y dimensiones
    loop Por cada ítem del pedido
        G5->>G3: GET /products/{productId}
        G3-->>G5: 200 Product {weightGrams, heightCm, widthCm, depthCm}
    end

    G5->>G6: POST /api/v1/shipments (packages con volumen, X-Headers)
    G6-->>G5: 201 Shipment {status: PENDING}
    G5->>G5: PATCH interno status → READY_TO_SHIP
    G5--)G7: evento ORDER_STATUS_CHANGED (READY_TO_SHIP)
    G5--)G8N: evento ORDER_STATUS_CHANGED (READY_TO_SHIP)

    loop Polling temporal (mientras G6 no tenga worker de Outbox)
        G5->>G6: GET /shipments?orderId= (X-Request-Id, X-Correlation-Id, X-Consumer)
        G6-->>G5: 200 Shipment {status: IN_TRANSIT | DELIVERED | FAILED}
    end

    G5->>G5: PATCH interno status → SHIPPED
    G5--)G7: evento ORDER_STATUS_CHANGED (SHIPPED)
    G5--)G8N: evento ORDER_STATUS_CHANGED (SHIPPED)

    G5->>G5: PATCH interno status → DELIVERED
    G5--)G7: evento ORDER_STATUS_CHANGED (DELIVERED)
    G5--)G8N: evento ORDER_STATUS_CHANGED (DELIVERED)
    G8N->>U: Notificación "tu pedido fue entregado"
```

---

## 3. Caso alternativo: pago rechazado

```mermaid
sequenceDiagram
    autonumber
    participant G8P as G8 Pagos
    participant G5  as G5 Pedidos
    participant G7  as G7 Reportería
    participant G8N as G8 Notificaciones

    G8P--)G5: evento PAYMENT_REJECTED
    G5->>G5: PATCH interno status → FAILED
    G5--)G7: evento ORDER_STATUS_CHANGED (FAILED)
    G5--)G8N: evento ORDER_STATUS_CHANGED (FAILED)
    G5--)G7: evento ORDER_CANCELLED (reason: PAYMENT_REJECTED)
    G5--)G8N: evento ORDER_CANCELLED (reason: PAYMENT_REJECTED)
    G8N->>G8N: genera notificación de fallo al usuario
```

---

## 4. Caso alternativo: fallo en despacho

```mermaid
sequenceDiagram
    autonumber
    participant G5  as G5 Pedidos
    participant G6  as G6 Despacho
    participant G7  as G7 Reportería
    participant G8N as G8 Notificaciones

    G5->>G6: GET /shipments?orderId= (polling)
    G6-->>G5: 200 Shipment {status: FAILED}
    G5->>G5: PATCH interno status → CANCELLED
    G5--)G7: evento ORDER_CANCELLED (reason: SHIPMENT_FAILED)
    G5--)G8N: evento ORDER_CANCELLED (reason: SHIPMENT_FAILED)
```

---

## 5. Notas de lectura

- Las flechas `-->` / `->>` son llamadas REST síncronas; las `--)` son
  eventos asíncronos (Pub/Sub).
- La validación JWT contra G2 ocurre en cada request entrante a G5. Se
  omite del diagrama C2 principal por legibilidad, pero está representada
  en C1 y en `01-documento-arquitectura.md §7`.
- El bloque de **polling temporal** hacia G6 es una mitigación documentada
  en `contrato/events.md` (v1.0) mientras G6 no tenga un worker activo
  despachando `outbox_events` a un broker real. Cuando G6 lo active, este
  polling se reemplaza por consumo directo de eventos — ese cambio se
  documenta como `events.md v1.1`.
- La consulta a G3 (Catálogo) por dimensiones es una dependencia nueva
  introducida en v1.1 para satisfacer el esquema `packages` requerido por
  `POST /api/v1/shipments` de G6. No estaba en el diseño original de G5.
- `SHIPPED` y `DELIVERED` son **dos transiciones separadas**, cada una con
  su propio `ORDER_STATUS_CHANGED`. No se colapsan en una sola operación.
