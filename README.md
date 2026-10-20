# Sistema Minimarket Mass
Proyecto de base de datos y backend para la gestión de ventas e inventario de la tienda Mass.
Desarrollado para el curso Backend Developer Web en SENATI CFP Arequipa.

## Integrantes del Grupo
- ERICK SILVA AYQUIPA
- Gerald Anderson Condori Quispe
- Alexander Emmanuel Moreno Flores
- Jhon Alexandro Apaza Belizario
- Suhaily Luana Huaypar Quijhua
- Keymer Cesar Machaca Puma

## Archivos del Repositorio
- `README.md`: Documentación principal del repositorio.
- `Informe_Tienda_Mass.pdf`: Informe del proyecto con los diagramas UML (Casos de uso, Secuencia, Actividades, Componentes y Despliegue) y el tablero Kanban de la base de datos.
- `database/schema.sql`: Crea la base de datos `minimarket_mass` con sus 34 tablas, la vista de control, los procedimientos y los triggers de las reglas de negocio. No inserta datos.
- `database/datos_prueba.sql`: Inserta los datos de prueba, ejecuta las pruebas (ventas, pagos, anulación, pedido y recepción, merma, turnos y cierre de caja) y muestra las consultas de verificación.

## Tablas del Diseño
La base de datos tiene 34 tablas agrupadas en 8 módulos.

| Módulo | Tablas |
|---|---|
| Ubicación y personal | `distrito`, `tienda`, `rol`, `usuario`, `turno_empleado` |
| Clientes | `tipo_documento_identidad`, `cliente` |
| Catálogo | `categoria`, `marca`, `unidad_medida`, `producto` |
| Inventario | `stock`, `tipo_movimiento`, `movimiento_stock`, `merma`, `detalle_merma` |
| Distribución | `centro_distribucion`, `pedido_reposicion`, `detalle_pedido`, `recepcion_mercaderia` |
| Caja | `caja`, `caja_turno` |
| Ventas y comprobantes | `tipo_comprobante`, `serie_comprobante`, `venta`, `detalle_venta`, `anulacion_venta`, `comprobante` |
| Pagos | `metodo_pago`, `pago_venta`, `autorizacion_pago`, `efectivo`, `tarjeta`, `billetera_digital_sip` |

Características técnicas:
- MySQL 8.4, motor InnoDB, `utf8mb4` / `utf8mb4_0900_ai_ci`.
- Las tablas se crean en orden: primero las que no dependen de otras y al final las que tienen claves foráneas.
- Claves primarias `INT UNSIGNED AUTO_INCREMENT`; cada clave foránea tiene el mismo tipo exacto que la clave a la que apunta.
- `stock` usa clave primaria compuesta (tienda + producto), y `efectivo`, `tarjeta` y `billetera_digital_sip` usan como clave primaria el `id_pago` de `pago_venta` (un solo detalle por pago).
- Dinero en `DECIMAL(10,2)` y cantidades (incluidas las ventas por kilo) en `DECIMAL(10,3)`. No se usa FLOAT.
- `ENUM` en los estados y valores fijos que define el diseño (por ejemplo `EMITIDA`/`ANULADA`, `ABIERTO`/`CERRADO`, `AUTORIZADA`/`RECHAZADA`).
- `UNIQUE` en serie + correlativo de la venta, código de barras, DNI y login del usuario, y documento del cliente.

### Detalle de cada tabla

PK = clave primaria, FK = clave foránea.

### Módulo Ubicación y personal

#### `distrito`
Distritos de Arequipa donde estan las tiendas y el centro de distribucion.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_distrito | INT UNSIGNED | No |  | PK |
| nombre | VARCHAR(60) | No |  |  |

Únicos: (nombre)

#### `tienda`
Sedes de Tienda Mass, una por distrito (RN-01).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_tienda | INT UNSIGNED | No |  | PK |
| id_distrito | INT UNSIGNED | No |  | FK → distrito |
| codigo | VARCHAR(10) | No |  |  |
| nombre | VARCHAR(80) | No |  |  |
| direccion | VARCHAR(150) | No |  |  |
| estado | ENUM('ACTIVA', 'INACTIVA') | No | 'ACTIVA' |  |

Únicos: (codigo); (id_distrito)

#### `rol`
Roles del personal (RN-02, RN-03). ADMINISTRADOR = Jefe de tienda.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_rol | INT UNSIGNED | No |  | PK |
| nombre | VARCHAR(20) | No |  |  |

Únicos: (nombre)

#### `usuario`
Personal de una tienda con un rol (en el Kanban figura como "empleado") (RN-02).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_usuario | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| id_rol | INT UNSIGNED | No |  | FK → rol |
| nombres | VARCHAR(80) | No |  |  |
| apellidos | VARCHAR(80) | No |  |  |
| dni | CHAR(8) | No |  |  |
| login | VARCHAR(40) | No |  |  |
| clave_hash | VARCHAR(255) | No |  |  |
| estado | ENUM('ACTIVO', 'INACTIVO') | No | 'ACTIVO' |  |

Únicos: (dni); (login)

#### `turno_empleado`
Horario de trabajo que el administrador programa a su personal.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_turno_empleado | INT UNSIGNED | No |  | PK |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| id_programado_por | INT UNSIGNED | No |  | FK → usuario |
| fecha | DATE | No |  |  |
| hora_inicio | TIME | No |  |  |
| hora_fin | TIME | No |  |  |
| observacion | VARCHAR(200) | Sí |  |  |

Únicos: (id_usuario, fecha, hora_inicio)

### Módulo Clientes

#### `tipo_documento_identidad`
DNI (8 digitos) o RUC (11 digitos) (RN-04, RN-06).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_tipo_documento | INT UNSIGNED | No |  | PK |
| codigo | VARCHAR(5) | No |  |  |
| nombre | VARCHAR(60) | No |  |  |
| longitud | TINYINT UNSIGNED | No |  |  |

Únicos: (codigo)

#### `cliente`
Opcional en boleta, obligatorio (con RUC) en factura (RN-04, RN-05).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_cliente | INT UNSIGNED | No |  | PK |
| id_tipo_documento | INT UNSIGNED | No |  | FK → tipo_documento_identidad |
| numero_documento | VARCHAR(11) | No |  |  |
| nombre_razon_social | VARCHAR(150) | No |  |  |
| direccion | VARCHAR(150) | Sí |  |  |
| telefono | VARCHAR(15) | Sí |  |  |
| correo | VARCHAR(100) | Sí |  |  |
| estado | ENUM('ACTIVO', 'INACTIVO') | No | 'ACTIVO' |  |

Únicos: (id_tipo_documento, numero_documento)

### Módulo Catálogo

#### `categoria`
Categorias de producto.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_categoria | INT UNSIGNED | No |  | PK |
| nombre | VARCHAR(60) | No |  |  |
| descripcion | VARCHAR(150) | Sí |  |  |

Únicos: (nombre)

#### `marca`
Marcas de producto, propias (S) o de terceros (N).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_marca | INT UNSIGNED | No |  | PK |
| nombre | VARCHAR(60) | No |  |  |
| es_marca_propia | ENUM('S', 'N') | No | 'N' |  |

Únicos: (nombre)

#### `unidad_medida`
Unidades de venta (unidad, kilogramo, litro, paquete).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_unidad | INT UNSIGNED | No |  | PK |
| codigo | VARCHAR(5) | No |  |  |
| nombre | VARCHAR(40) | No |  |  |

Únicos: (codigo)

#### `producto`
Un solo precio para todas las tiendas, IGV incluido (RN-07, RN-08).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_producto | INT UNSIGNED | No |  | PK |
| id_categoria | INT UNSIGNED | No |  | FK → categoria |
| id_marca | INT UNSIGNED | No |  | FK → marca |
| id_unidad | INT UNSIGNED | No |  | FK → unidad_medida |
| codigo_barras | VARCHAR(20) | No |  |  |
| nombre | VARCHAR(120) | No |  |  |
| precio_venta | DECIMAL(10,2) | No |  |  |
| estado | ENUM('ACTIVO', 'INACTIVO') | No | 'ACTIVO' |  |

Únicos: (codigo_barras)

### Módulo Inventario

#### `stock`
Cantidad actual por tienda y producto; nunca negativa (RN-09, RN-10).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_tienda | INT UNSIGNED | No |  | PK, FK → tienda |
| id_producto | INT UNSIGNED | No |  | PK, FK → producto |
| cantidad | DECIMAL(10,3) | No | 0 |  |
| stock_minimo | DECIMAL(10,3) | No | 0 |  |

#### `tipo_movimiento`
Tipos de movimiento de stock, E = entrada, S = salida (RN-12).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_tipo_movimiento | INT UNSIGNED | No |  | PK |
| codigo | VARCHAR(20) | No |  |  |
| nombre | VARCHAR(60) | No |  |  |
| efecto | ENUM('E', 'S') | No |  |  |

Únicos: (codigo)

#### `movimiento_stock`
Kardex, cada entrada o salida de stock con su origen (RN-11, RN-12).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_movimiento | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| id_producto | INT UNSIGNED | No |  | FK → producto |
| id_tipo_movimiento | INT UNSIGNED | No |  | FK → tipo_movimiento |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| cantidad | DECIMAL(10,3) | No |  |  |
| stock_resultante | DECIMAL(10,3) | No |  |  |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| id_venta | INT UNSIGNED | Sí |  | FK → venta |
| id_recepcion | INT UNSIGNED | Sí |  | FK → recepcion_mercaderia |
| id_merma | INT UNSIGNED | Sí |  | FK → merma |
| observacion | VARCHAR(200) | Sí |  |  |

#### `merma`
Perdida de producto por vencimiento, deterioro, robo u otro motivo (RN-14).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_merma | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| motivo | ENUM('VENCIMIENTO', 'DETERIORO', 'ROBO', 'OTRO') | No |  |  |
| observacion | VARCHAR(200) | Sí |  |  |

#### `detalle_merma`
Productos y cantidades de cada merma.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_detalle_merma | INT UNSIGNED | No |  | PK |
| id_merma | INT UNSIGNED | No |  | FK → merma |
| id_producto | INT UNSIGNED | No |  | FK → producto |
| cantidad | DECIMAL(10,3) | No |  |  |

Únicos: (id_merma, id_producto)

### Módulo Distribución

#### `centro_distribucion`
Almacen que envia los pedidos a las tiendas (ServDistribucion).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_centro | INT UNSIGNED | No |  | PK |
| id_distrito | INT UNSIGNED | No |  | FK → distrito |
| codigo | VARCHAR(10) | No |  |  |
| nombre | VARCHAR(80) | No |  |  |
| direccion | VARCHAR(150) | No |  |  |
| estado | ENUM('ACTIVO', 'INACTIVO') | No | 'ACTIVO' |  |

Únicos: (codigo)

#### `pedido_reposicion`
Pedido de mercaderia de una tienda al centro de distribucion.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_pedido | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| id_centro | INT UNSIGNED | No |  | FK → centro_distribucion |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_pedido | DATETIME | No | CURRENT_TIMESTAMP |  |
| fecha_envio | DATETIME | Sí |  |  |
| estado | ENUM('PENDIENTE', 'ENVIADO', 'ENTREGADO', 'ANULADO') | No | 'PENDIENTE' |  |
| observacion | VARCHAR(200) | Sí |  |  |

#### `detalle_pedido`
Productos y cantidades pedidas, enviadas y recibidas de cada pedido.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_detalle_pedido | INT UNSIGNED | No |  | PK |
| id_pedido | INT UNSIGNED | No |  | FK → pedido_reposicion |
| id_producto | INT UNSIGNED | No |  | FK → producto |
| cantidad_solicitada | DECIMAL(10,3) | No |  |  |
| cantidad_enviada | DECIMAL(10,3) | Sí |  |  |
| cantidad_recibida | DECIMAL(10,3) | Sí |  |  |

Únicos: (id_pedido, id_producto)

#### `recepcion_mercaderia`
Llegada de un pedido a la tienda (Confirmar entrega / Recibir mercancia).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_recepcion | INT UNSIGNED | No |  | PK |
| id_pedido | INT UNSIGNED | No |  | FK → pedido_reposicion |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| observacion | VARCHAR(200) | Sí |  |  |

Únicos: (id_pedido)

### Módulo Caja

#### `caja`
Punto de cobro fisico de una tienda (RN-15).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_caja | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| numero | TINYINT UNSIGNED | No |  |  |
| descripcion | VARCHAR(60) | Sí |  |  |
| estado | ENUM('ACTIVA', 'INACTIVA') | No | 'ACTIVA' |  |

Únicos: (id_tienda, numero)

#### `caja_turno`
Apertura y cierre de una caja por un cajero (RN-16, RN-17).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_caja_turno | INT UNSIGNED | No |  | PK |
| id_caja | INT UNSIGNED | No |  | FK → caja |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_apertura | DATETIME | No | CURRENT_TIMESTAMP |  |
| monto_apertura | DECIMAL(10,2) | No | 0 |  |
| fecha_cierre | DATETIME | Sí |  |  |
| monto_cierre | DECIMAL(10,2) | Sí |  |  |
| estado | ENUM('ABIERTO', 'CERRADO') | No | 'ABIERTO' |  |

### Módulo Ventas y comprobantes

#### `tipo_comprobante`
Boleta (serie B) o factura (serie F) (RN-18).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_tipo_comprobante | INT UNSIGNED | No |  | PK |
| codigo | VARCHAR(10) | No |  |  |
| nombre | VARCHAR(40) | No |  |  |
| prefijo_serie | CHAR(1) | No |  |  |

Únicos: (codigo); (prefijo_serie)

#### `serie_comprobante`
Serie por tienda y tipo, con su ultimo correlativo (RN-19).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_serie | INT UNSIGNED | No |  | PK |
| id_tienda | INT UNSIGNED | No |  | FK → tienda |
| id_tipo_comprobante | INT UNSIGNED | No |  | FK → tipo_comprobante |
| serie | VARCHAR(4) | No |  |  |
| ultimo_correlativo | INT UNSIGNED | No | 0 |  |

Únicos: (serie); (id_tienda, id_tipo_comprobante)

#### `venta`
Cabecera de venta con serie, correlativo, subtotal, igv y total (RN-19 a RN-22). fecha_registro_central: cuando ServCentral confirma la venta (registrarVentaCentral()).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_venta | INT UNSIGNED | No |  | PK |
| id_serie | INT UNSIGNED | No |  | FK → serie_comprobante |
| correlativo | INT UNSIGNED | No | 0 |  |
| id_caja_turno | INT UNSIGNED | No |  | FK → caja_turno |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| id_cliente | INT UNSIGNED | Sí |  | FK → cliente |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| subtotal | DECIMAL(10,2) | No |  |  |
| igv | DECIMAL(10,2) | No |  |  |
| total | DECIMAL(10,2) | No |  |  |
| estado | ENUM('EMITIDA', 'ANULADA') | No | 'EMITIDA' |  |
| fecha_registro_central | DATETIME | Sí |  |  |

Únicos: (id_serie, correlativo)

#### `detalle_venta`
Productos, cantidad (por unidad o por kilo) y precio de cada venta.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_detalle_venta | INT UNSIGNED | No |  | PK |
| id_venta | INT UNSIGNED | No |  | FK → venta |
| id_producto | INT UNSIGNED | No |  | FK → producto |
| cantidad | DECIMAL(10,3) | No |  |  |
| precio_unitario | DECIMAL(10,2) | No |  |  |
| total_linea | DECIMAL(10,2) | No |  |  |

Únicos: (id_venta, id_producto)

#### `anulacion_venta`
Quien (solo el ADMINISTRADOR), cuando y por que se anulo una venta (RN-23).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_anulacion | INT UNSIGNED | No |  | PK |
| id_venta | INT UNSIGNED | No |  | FK → venta |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| motivo | VARCHAR(200) | No |  |  |

Únicos: (id_venta)

#### `comprobante`
Boleta o factura entregada al cliente; solo si la venta ya esta registrada en el central y totalmente pagada.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_comprobante | INT UNSIGNED | No |  | PK |
| id_venta | INT UNSIGNED | No |  | FK → venta |
| id_usuario | INT UNSIGNED | No |  | FK → usuario |
| fecha_emision | DATETIME | No | CURRENT_TIMESTAMP |  |

Únicos: (id_venta)

### Módulo Pagos

#### `metodo_pago`
Efectivo, tarjeta o billetera digital Sip (RN-24, RN-25).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_metodo_pago | INT UNSIGNED | No |  | PK |
| codigo | VARCHAR(10) | No |  |  |
| nombre | VARCHAR(40) | No |  |  |
| estado | ENUM('ACTIVO', 'INACTIVO') | No | 'ACTIVO' |  |

Únicos: (codigo)

#### `pago_venta`
Un registro por cada pago de una venta; puede haber varios (RN-24, RN-28).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_pago | INT UNSIGNED | No |  | PK |
| id_venta | INT UNSIGNED | No |  | FK → venta |
| id_metodo_pago | INT UNSIGNED | No |  | FK → metodo_pago |
| monto | DECIMAL(10,2) | No |  |  |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |
| estado | ENUM('APLICADO', 'ANULADO') | No | 'APLICADO' |  |

#### `autorizacion_pago`
Respuesta de la pasarela de pago (autorizada o rechazada) para pagos con tarjeta o Sip; guarda tambien los rechazos.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_autorizacion | INT UNSIGNED | No |  | PK |
| id_venta | INT UNSIGNED | No |  | FK → venta |
| id_metodo_pago | INT UNSIGNED | No |  | FK → metodo_pago |
| codigo_operacion | VARCHAR(30) | No |  |  |
| monto | DECIMAL(10,2) | No |  |  |
| resultado | ENUM('AUTORIZADA', 'RECHAZADA') | No |  |  |
| motivo_rechazo | VARCHAR(200) | Sí |  |  |
| fecha_hora | DATETIME | No | CURRENT_TIMESTAMP |  |

Únicos: (codigo_operacion)

#### `efectivo`
Detalle de pago en efectivo; monto aplicado = recibido - vuelto (RN-27).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_pago | INT UNSIGNED | No |  | PK, FK → pago_venta |
| monto_recibido | DECIMAL(10,2) | No |  |  |
| vuelto | DECIMAL(10,2) | No | 0 |  |

#### `tarjeta`
Detalle de pago con tarjeta; solo se guardan los ultimos 4 digitos.

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_pago | INT UNSIGNED | No |  | PK, FK → pago_venta |
| tipo_tarjeta | ENUM('DEBITO', 'CREDITO') | No |  |  |
| marca | ENUM('VISA', 'MASTERCARD', 'AMERICAN_EXPRESS', 'DINERS', 'OTRA') | No |  |  |
| ultimos_4 | CHAR(4) | No |  |  |
| codigo_autorizacion | VARCHAR(30) | No |  | FK → autorizacion_pago |

Únicos: (codigo_autorizacion)

#### `billetera_digital_sip`
Detalle de pago con la billetera digital Sip (RN-25, RN-26).

| Columna | Tipo | Nulo | Default | Clave |
|---|---|---|---|---|
| id_pago | INT UNSIGNED | No |  | PK, FK → pago_venta |
| modalidad | ENUM('QR', 'TARJETA_SIP') | No |  |  |
| codigo_operacion | VARCHAR(30) | No |  | FK → autorizacion_pago |

Únicos: (codigo_operacion)

### Objetos de programación
| Objeto | Para qué sirve |
|---|---|
| `vw_control_ventas` | Compara el total de cada venta con sus pagos aplicados y sus líneas: `OK`, `DESCUADRE` o `ANULADA`. |
| `sp_mover_stock` | Único punto por donde cambia el stock: valida que alcance, actualiza y deja el movimiento en el kardex. |
| `sp_anular_venta` | Anula una venta: registra la anulación, anula los pagos y devuelve el stock. |
| `sp_registrar_venta_central` | Marca la venta como registrada en el servidor central. |
| 21 triggers | Aplican las reglas de negocio de la tabla siguiente. |

## Reglas de Negocio
| Regla | Cómo la cumple la base de datos |
|---|---|
| **Cobro seguro:** no se puede procesar ni cerrar una venta si la pasarela de pago rechaza la tarjeta. | Cada respuesta de la pasarela queda en `autorizacion_pago` (también los rechazos). `tarjeta` y `billetera_digital_sip` solo se guardan con una autorización `AUTORIZADA` de la misma venta y el mismo monto, y el comprobante no se emite si los pagos no cubren el total. |
| **Control de anulaciones:** toda anulación exige la autorización del Jefe de tienda. | El trigger de `anulacion_venta` solo acepta a un usuario con rol `ADMINISTRADOR` (Jefe de tienda) de la tienda de la venta. |
| **Emisión de comprobantes:** no se emite boleta o factura hasta que la venta esté registrada en el servidor central. | `comprobante` solo se inserta si la venta está `EMITIDA`, tiene `fecha_registro_central` y está totalmente pagada. |
| **Descuento de stock al vender.** | Cada línea de `detalle_venta` descuenta el stock de la tienda y deja el movimiento en el kardex; si no alcanza, la venta se rechaza. |
| **Factura con RUC.** | Una venta con serie de factura exige un cliente con RUC; el DNI tiene 8 dígitos y el RUC 11. |
| **Turno de caja.** | Solo un cajero de la tienda abre la caja; no se vende sin turno abierto; una caja o un cajero no tienen dos turnos abiertos a la vez. |
| **Comprobantes correlativos.** | Cada tienda tiene su serie (B001, F001…) y el correlativo se asigna solo y no se repite ni se modifica. |
| **Las ventas no se borran.** | Solo se anulan con `sp_anular_venta`, que anula los pagos y devuelve el stock. |
| **Pagos.** | En efectivo, monto recibido menos vuelto debe ser igual al pago; cada pago tiene un solo detalle según su método. |
| **Merma y recepción.** | La merma descuenta stock; recibir un pedido del centro de distribución suma al stock y lo marca `ENTREGADO`. |
| **Turnos del personal.** | Solo el `ADMINISTRADOR` programa los turnos del personal de su tienda. |

## Cómo Crear la Base de Datos
Para implementar la base de datos en Windows utilizando PowerShell y Laragon (MySQL 8.4 en el puerto 3307), ejecuta los siguientes comandos. Reemplaza `C:/ruta/al/repo` con la ruta exacta de tu repositorio local.

1. Crear la base de datos, las tablas y las reglas:

```powershell
mysql -u root -h 127.0.0.1 -P 3307 -e "source C:/ruta/al/repo/database/schema.sql"
```

2. Cargar los datos de prueba y ver las consultas de verificación:

```powershell
mysql -u root -h 127.0.0.1 -P 3307 -e "source C:/ruta/al/repo/database/datos_prueba.sql"
```

3. Comprobar que se creó:

```powershell
mysql -u root -h 127.0.0.1 -P 3307 -e "USE minimarket_mass; SHOW TABLES;"
```

## Decisiones de Diseño
- La base parte del DDL original del grupo (Oracle, 29 tablas) pasado a MySQL con los mismos nombres de tablas y columnas.
- Según la tabla "Correcciones" del informe se agregaron `turno_empleado`, `comprobante`, `autorizacion_pago` y el módulo Distribución (`centro_distribucion`, `pedido_reposicion`, `detalle_pedido`, `recepcion_mercaderia`), que reemplaza a `traslado_mercaderia` y `detalle_traslado`.
- Por ese cambio, `movimiento_stock.id_traslado` pasó a ser `id_recepcion`, y los tipos de movimiento `TRASLADO_SALIDA` / `TRASLADO_ENTRADA` se reemplazaron por `RECEPCION`.
- Se agregó `venta.fecha_registro_central` para cumplir la regla de emisión de comprobantes.
- La tabla de personal se llama `usuario` (como en el DDL); en el tablero Kanban figura como `empleado`. El rol `ADMINISTRADOR` corresponde al Jefe de tienda.
- Se mantienen `tipo_documento_identidad` y `detalle_merma` del DDL, aunque no figuran en el Kanban.
- El IGV (18 %) está incluido en el precio; la venta guarda subtotal, igv y total.
