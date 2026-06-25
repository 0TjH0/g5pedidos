# Matriz de Dependencias — Grupo 5: Pedidos (Order Management)

Convención de la columna **Estado**:

- ✅ Contrato verificado e integración técnica confirmada en repositorio real.
- 🟡 Contrato definido de mutuo acuerdo, pero el servicio no está desplegado o requiere ajustes menores.
- 🔴 Dependencia bloqueada, riesgo crítico de integración o desalineación de esquemas.

---

## 5.1 — Quiénes dependen de Grupo 5 (Consumidores)

| Grupo | Qué consume | Protocolo | Detalle técnico | Estado |
|:---|:---|:---|:---|:---|
| **G4 — Carrito y Checkout** | Creación del registro definitivo del pedido | REST síncrono (entrante) | Invoca `POST /orders`. G4 tiene mapeado `ORDER_SERVICE_UNAVAILABLE` como error estructurado en su contrato. | 🔴 G4 envía montos en USD/float y omite `shippingAddress` — requiere mesa de diseño |
| **G1 — BFF / Frontend** | Consulta de pedidos históricos y estados en pantalla | REST síncrono | Consume `GET /orders/{orderId}` y `GET /users/{userId}/orders` | 🟡 Contrato listo; pendiente despliegue del BFF en cloud |
| **G7 — Reportería** | Ingesta de datos comerciales para dashboards en tiempo real | Evento async (Kafka) | Escucha `ORDER_CREATED` y `ORDER_STATUS_CHANGED`. Confirmado en `x-events.consumed` de su contrato. | ✅ Contrato alineado |
| **G8 — Notificaciones** | Alertas transaccionales al usuario final | Evento async (Kafka) | Escucha `ORDER_CREATED`, `ORDER_STATUS_CHANGED` y `ORDER_CANCELLED`. Confirmado en su enumerador de eventos válidos. | ✅ Contrato alineado |

---

## 5.2 — De quiénes depende Grupo 5 (Proveedores)

| Grupo | Qué necesita G5 | Protocolo | Detalle técnico | Estado |
|:---|:---|:---|:---|:---|
| **G2 — Identidad** | Validación centralizada de JWT y RBAC | REST síncrono (saliente) | Invoca `POST /auth/validate` con el token Bearer antes de resolver cualquier recurso de cliente. | ✅ Confirmado contra entorno real |
| **G8 — Pagos** | Procesamiento monetario y resultado transaccional | Híbrido REST + Evento | G5 invoca `POST /v1/payments` de forma síncrona; luego consume `PAYMENT_APPROVED` o `PAYMENT_REJECTED` de forma asíncrona. | ✅ Sincronizado en CLP e integers (int64) |
| **G6 — Despacho** | Creación de la orden física de envío y tracking | REST síncrono + polling | Invoca `POST /api/v1/shipments` para crear el paquete. Ejecuta polling periódico a `GET /api/v1/shipments?orderId=` inyectando headers obligatorios (`X-Request-Id`, `X-Correlation-Id`, `X-Consumer`). | 🔴 Eventos bloqueados (sin worker de Outbox); endpoint REST exige datos volumétricos — ver §5.4 |
| **G3 — Catálogo** | Dimensiones físicas de los ítems (peso, alto, ancho) | REST síncrono (saliente) | **Nueva dependencia.** Invoca `GET /products/{productId}` para armar el arreglo `packages` requerido por G6 antes de crear el shipment. | 🟡 Contrato existe en la malla; pendiente implementar cliente HTTP en G5 |

---

## 5.3 — Matriz cruzada de conectividad

| | G1 BFF | G2 Auth | G3 Catálogo | G4 Checkout | G6 Despacho | G7 Reportería | G8 Pagos | G8 Notif |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **G5 envía →** | — | ❌ | ❌ | ❌ | ✅ REST | ✅ Evento | ✅ REST | ✅ Evento |
| **G5 recibe ←** | ❌ | ✅ REST | 🟡 REST | 🔴 REST | 🔴 Polling | ❌ | ✅ Evento | ❌ |

---

## 5.4 — Riesgos priorizados de integración

### 🔴 Riesgo 1 — Datos volumétricos requeridos por G6 (Bloqueante crítico)

G6 exige el peso en gramos y las dimensiones en centímetros de cada ítem para
procesar `POST /api/v1/shipments`. G4 no arrastra estos datos desde el carrito,
por lo que G5 debe introducir una llamada síncrona previa a **G3 (Catálogo)**
para poblar el arreglo `packages` antes de solicitar el despacho. Esto rompe
el aislamiento de datos originalmente previsto para G5.

**Impacto:** flujo de creación de shipment queda como:
`PAID → GET /products/{id} (G3) → POST /api/v1/shipments (G6) → READY_TO_SHIP`

### 🔴 Riesgo 2 — Quiebre de esquema monetario con G4 (Bloqueante crítico)

El contrato de G4 procesa transacciones en `USD` con subtotales en `double`.
Esto colisiona directamente con el estándar del marketplace (G5 y G8 operan
exclusivamente en `CLP` con tipo `integer/int64`). Se requiere mesa de diseño
con G4 para corregir tipos antes de iniciar la codificación.

**Acción requerida:** G4 debe actualizar su `contrato-g4.yaml` para emitir
`currency: "CLP"` y `totalAmount: integer`.

### 🔴 Riesgo 3 — Ausencia de `shippingAddress` en Checkout (Bloqueante crítico)

El endpoint `/v1/checkout` de G4 no captura ni propaga el objeto
`shippingAddress` hacia G5. Como mitigación, G5 acepta el campo como
`nullable` en su `openapi.yaml`, delegando al BFF (G1) la responsabilidad de
resolver la dirección desde el perfil de usuario de G2 en fases posteriores.

**Deuda técnica:** esta mitigación debe documentarse como issue en el
repositorio de G4 y resolverse antes de E3.

### 🟡 Riesgo 4 — Polling sobre capa gratuita de Render (Riesgo de performance)

El polling periódico a G6 (cada 60 s) puede generar latencia acumulada o
despertar instancias dormidas en el tier gratuito de Render. Las llamadas
deben inyectar estrictamente los headers `X-Request-Id`, `X-Correlation-Id`
y `X-Consumer` para evitar rechazo por el middleware de G6. Este riesgo se
elimina cuando G6 active su worker de Outbox (upgrade a `events.md v1.1`).
