# Usamos una imagen liviana de Node.js basada en Alpine Linux
FROM node:18-alpine

# Instalamos la CLI de Prism de forma global para simular la API
RUN npm install -g @stoplight/prism-cli

# Establecemos el directorio de trabajo dentro del contenedor
WORKDIR /app

# Copiamos el contrato OpenAPI unificado v1.1.0 respetando la estructura
COPY contrato/openapi.yaml ./contrato/openapi.yaml

# Informamos el puerto que se va a exponer (Render usa el 10000 por defecto si no detecta la variable)
EXPOSE 10000

# Comando para ejecutar el Mock.
# Se usa 'sh -c' para que mapée dinámicamente el puerto asignado por Render ($PORT).
# El flag '--multiprocess=false' evita sobrecargar la memoria de la capa gratuita.
CMD ["sh", "-c", "prism mock contrato/openapi.yaml -h 0.0.0.0 -p ${PORT:-10000} --multiprocess=false"]