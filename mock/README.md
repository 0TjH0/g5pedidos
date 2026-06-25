# Mock — Grupo 5 Pedidos

## URL pública

```
https://grupo5-pedidos-mock.onrender.com
```

Estado: ✅ Desplegado y verificado (2026-06-22)

## Cómo funciona

El mock está construido con **Prism** (Stoplight), apuntando directamente al `openapi.yaml` del contrato. No tiene lógica de negocio ni base de datos — sirve los `example:` declarados en cada respuesta del contrato.

## Nota técnica importante

Requiere el flag `--multiprocess=false` en el Start Command de Render:

```bash
npx @stoplight/prism-cli mock openapi.yaml --host 0.0.0.0 --port $PORT --multiprocess=false
```

La versión actual de Prism falla con Node.js 24.x si se usa `--multiprocess=true` (valor por defecto), por un bug de compatibilidad con el módulo `cluster` de Node. Documentado aquí para que no se pierda si alguien redespliega.

## Cómo probar

### Opción 1 — Postman (recomendado)

1. Importar `contrato/postman_collection.json`
2. La variable `{{baseUrl}}` ya apunta a `https://grupo5-pedidos-mock.onrender.com`
3. Ejecutar las 6 requests en orden

### Opción 2 — curl

```bash
# POST /orders — Crear pedido
curl -X POST https://grupo5-pedidos-mock.onrender.com/orders \
  -H "Authorization: Bearer test-token-123" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 11111111-1111-1111-1111-111111111111" \
  -d '{
    "userId": "e9d8c7b6-a543-2109-8765-fedcba098765",
    "items": [{"productId": "f0e9d8c7-b6a5-4321-0987-fedcba098765", "name": "Notebook Lenovo IdeaPad", "quantity": 2, "unitPrice": 799990, "subtotal": 1599980}],
    "shippingAddress": {"street": "Av. Libertador 1234", "city": "Santiago", "region": "Metropolitana", "country": "Chile"}
  }'

# GET /orders/{orderId}
curl https://grupo5-pedidos-mock.onrender.com/orders/ORD-20260622-001 \
  -H "Authorization: Bearer test-token-123"

# Sin token — debe retornar 401
curl https://grupo5-pedidos-mock.onrender.com/orders/ORD-20260622-001

# PATCH /orders/{orderId}/status
curl -X PATCH https://grupo5-pedidos-mock.onrender.com/orders/ORD-20260622-001/status \
  -H "Authorization: Bearer test-token-123" \
  -H "Content-Type: application/json" \
  -d '{"status": "PAID"}'

# GET /users/{userId}/orders
curl "https://grupo5-pedidos-mock.onrender.com/users/e9d8c7b6-a543-2109-8765-fedcba098765/orders?page=1&pageSize=10" \
  -H "Authorization: Bearer test-token-123"
```

## Endpoints disponibles en el mock

| Método | Endpoint | Respuesta mock |
|---|---|---|
| POST | `/orders` | 201 Created con `orderId: ORD-20260622-001` |
| GET | `/orders/{orderId}` | 200 OK con pedido de ejemplo |
| PATCH | `/orders/{orderId}/status` | 200 OK con estado actualizado |
| GET | `/users/{userId}/orders` | 200 OK con lista paginada |

## Reemplazar el mock por el servicio real (E3)

Cuando se despliegue el servicio real en E3, solo cambiar la variable `{{baseUrl}}` en Postman:

```
https://grupo5-pedidos-mock.onrender.com  →  https://api-grupo5-pedidos.onrender.com/v1
```
