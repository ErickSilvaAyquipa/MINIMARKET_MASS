/* =====================================================================
   TIENDA MASS (Grupo Intercorp) - AREQUIPA
   SCRIPT: logica de negocio, datos iniciales y pruebas
   Motor: Oracle SQL 12c o superior

   Requisito: ejecutar ANTES tienda_mass_ddl.sql

   Contenido:
     A) Procedimientos, funcion, triggers y vista de control
     B) Datos iniciales (catalogos, tiendas, usuarios, productos, stock)
     C) Pruebas: ventas, pagos, anulacion, traslado, merma, cierre de caja
     D) Consultas de verificacion

   Todos los datos de B) y C) son EJEMPLOS ficticios (nombres, DNI, RUC,
   precios y direcciones) para probar el modelo.
   ===================================================================== */

SET SERVEROUTPUT ON
SET DEFINE OFF

/* =====================================================================
   A) LOGICA DE NEGOCIO
   ===================================================================== */

/* ---------------------------------------------------------------------
   A.1 sp_mover_stock
   Unico punto por donde cambia el stock (RN-09 a RN-12).
   - Salida: valida que alcance el stock (RN-10) y lo descuenta.
   - Entrada: suma al stock (crea la fila si no existe).
   - Siempre deja un registro en movimiento_stock (kardex).
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_mover_stock (
    p_id_tienda    IN NUMBER,
    p_id_producto  IN NUMBER,
    p_codigo_mov   IN VARCHAR2,
    p_cantidad     IN NUMBER,
    p_id_usuario   IN NUMBER,
    p_id_venta     IN NUMBER   DEFAULT NULL,
    p_id_traslado  IN NUMBER   DEFAULT NULL,
    p_id_merma     IN NUMBER   DEFAULT NULL,
    p_observacion  IN VARCHAR2 DEFAULT NULL
) AS
    v_id_tipo  tipo_movimiento.id_tipo_movimiento%TYPE;
    v_efecto   tipo_movimiento.efecto%TYPE;
    v_actual   stock.cantidad%TYPE;
BEGIN
    SELECT id_tipo_movimiento, efecto
      INTO v_id_tipo, v_efecto
      FROM tipo_movimiento
     WHERE codigo = p_codigo_mov;

    IF v_efecto = 'S' THEN
        BEGIN
            SELECT cantidad
              INTO v_actual
              FROM stock
             WHERE id_tienda = p_id_tienda
               AND id_producto = p_id_producto
               FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_actual := 0;
        END;

        IF v_actual < p_cantidad THEN
            RAISE_APPLICATION_ERROR(-20010,
                'Stock insuficiente del producto ' || p_id_producto ||
                ' en la tienda ' || p_id_tienda ||
                ' (disponible: ' || v_actual || ', solicitado: ' || p_cantidad || ').');
        END IF;

        UPDATE stock
           SET cantidad = cantidad - p_cantidad
         WHERE id_tienda = p_id_tienda
           AND id_producto = p_id_producto;

        v_actual := v_actual - p_cantidad;
    ELSE
        MERGE INTO stock s
        USING (SELECT p_id_tienda AS id_tienda, p_id_producto AS id_producto FROM dual) x
           ON (s.id_tienda = x.id_tienda AND s.id_producto = x.id_producto)
         WHEN MATCHED THEN
            UPDATE SET s.cantidad = s.cantidad + p_cantidad
         WHEN NOT MATCHED THEN
            INSERT (id_tienda, id_producto, cantidad)
            VALUES (x.id_tienda, x.id_producto, p_cantidad);

        SELECT cantidad
          INTO v_actual
          FROM stock
         WHERE id_tienda = p_id_tienda
           AND id_producto = p_id_producto;
    END IF;

    INSERT INTO movimiento_stock
        (id_tienda, id_producto, id_tipo_movimiento, id_usuario, cantidad,
         stock_resultante, id_venta, id_traslado, id_merma, observacion)
    VALUES
        (p_id_tienda, p_id_producto, v_id_tipo, p_id_usuario, p_cantidad,
         v_actual, p_id_venta, p_id_traslado, p_id_merma, p_observacion);
END sp_mover_stock;
/

/* ---------------------------------------------------------------------
   A.2 Funcion auxiliar: codigo del metodo de un pago
   --------------------------------------------------------------------- */
CREATE OR REPLACE FUNCTION fn_codigo_metodo_pago (p_id_pago IN NUMBER)
RETURN VARCHAR2 AS
    v_codigo metodo_pago.codigo%TYPE;
BEGIN
    SELECT m.codigo
      INTO v_codigo
      FROM pago_venta p
      JOIN metodo_pago m ON m.id_metodo_pago = p.id_metodo_pago
     WHERE p.id_pago = p_id_pago;
    RETURN v_codigo;
END fn_codigo_metodo_pago;
/

/* ---------------------------------------------------------------------
   A.3 Clientes: el numero debe tener la longitud de su tipo (RN-04, RN-06)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_cliente_valida_documento
BEFORE INSERT OR UPDATE OF id_tipo_documento, numero_documento ON cliente
FOR EACH ROW
DECLARE
    v_longitud tipo_documento_identidad.longitud%TYPE;
BEGIN
    SELECT longitud
      INTO v_longitud
      FROM tipo_documento_identidad
     WHERE id_tipo_documento = :NEW.id_tipo_documento;

    IF LENGTH(:NEW.numero_documento) <> v_longitud THEN
        RAISE_APPLICATION_ERROR(-20001,
            'El numero de documento debe tener ' || v_longitud || ' digitos.');
    END IF;
END;
/

/* ---------------------------------------------------------------------
   A.4 Series: la serie empieza con la letra del tipo (B boleta, F factura)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_serie_valida_prefijo
BEFORE INSERT OR UPDATE OF serie, id_tipo_comprobante ON serie_comprobante
FOR EACH ROW
DECLARE
    v_prefijo tipo_comprobante.prefijo_serie%TYPE;
BEGIN
    SELECT prefijo_serie
      INTO v_prefijo
      FROM tipo_comprobante
     WHERE id_tipo_comprobante = :NEW.id_tipo_comprobante;

    IF SUBSTR(:NEW.serie, 1, 1) <> v_prefijo THEN
        RAISE_APPLICATION_ERROR(-20002,
            'La serie debe empezar con la letra ' || v_prefijo || '.');
    END IF;
END;
/

/* ---------------------------------------------------------------------
   A.5 Turnos: solo un CAJERO de la misma tienda abre la caja (RN-16, RN-17)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_turno_valida
BEFORE INSERT ON caja_turno
FOR EACH ROW
DECLARE
    v_tienda_caja     caja.id_tienda%TYPE;
    v_tienda_usuario  usuario.id_tienda%TYPE;
    v_rol_usuario     rol.nombre%TYPE;
BEGIN
    SELECT id_tienda
      INTO v_tienda_caja
      FROM caja
     WHERE id_caja = :NEW.id_caja;

    SELECT u.id_tienda, r.nombre
      INTO v_tienda_usuario, v_rol_usuario
      FROM usuario u
      JOIN rol r ON r.id_rol = u.id_rol
     WHERE u.id_usuario = :NEW.id_usuario;

    IF v_rol_usuario <> 'CAJERO' THEN
        RAISE_APPLICATION_ERROR(-20003, 'Solo un usuario con rol CAJERO puede abrir un turno de caja.');
    END IF;

    IF v_tienda_usuario <> v_tienda_caja THEN
        RAISE_APPLICATION_ERROR(-20004, 'El cajero debe pertenecer a la tienda de la caja.');
    END IF;
END;
/

/* ---------------------------------------------------------------------
   A.6 Ventas (RN-04, RN-16, RN-19, RN-21, RN-22)
   - La factura exige cliente con RUC.
   - Solo se vende con un turno ABIERTO del mismo cajero y de la misma
     tienda de la serie.
   - El correlativo se asigna solo, por serie (no se repite).
   - No se puede cambiar serie/correlativo ni reabrir una venta anulada.
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_venta_valida
BEFORE INSERT OR UPDATE ON venta
FOR EACH ROW
DECLARE
    v_cod_comprobante  tipo_comprobante.codigo%TYPE;
    v_tienda_serie     serie_comprobante.id_tienda%TYPE;
    v_cod_documento    tipo_documento_identidad.codigo%TYPE;
    v_estado_turno     caja_turno.estado%TYPE;
    v_usuario_turno    caja_turno.id_usuario%TYPE;
    v_tienda_turno     caja.id_tienda%TYPE;
BEGIN
    SELECT tc.codigo, s.id_tienda
      INTO v_cod_comprobante, v_tienda_serie
      FROM serie_comprobante s
      JOIN tipo_comprobante tc ON tc.id_tipo_comprobante = s.id_tipo_comprobante
     WHERE s.id_serie = :NEW.id_serie;

    -- RN-04: la factura exige cliente con RUC
    IF v_cod_comprobante = 'FACTURA' THEN
        IF :NEW.id_cliente IS NULL THEN
            RAISE_APPLICATION_ERROR(-20020, 'La factura exige un cliente con RUC.');
        END IF;

        SELECT td.codigo
          INTO v_cod_documento
          FROM cliente c
          JOIN tipo_documento_identidad td ON td.id_tipo_documento = c.id_tipo_documento
         WHERE c.id_cliente = :NEW.id_cliente;

        IF v_cod_documento <> 'RUC' THEN
            RAISE_APPLICATION_ERROR(-20021, 'El cliente de una factura debe tener RUC (11 digitos).');
        END IF;
    END IF;

    IF INSERTING THEN
        -- RN-16: turno abierto, del mismo cajero y de la misma tienda
        SELECT ct.estado, ct.id_usuario, c.id_tienda
          INTO v_estado_turno, v_usuario_turno, v_tienda_turno
          FROM caja_turno ct
          JOIN caja c ON c.id_caja = ct.id_caja
         WHERE ct.id_caja_turno = :NEW.id_caja_turno;

        IF v_estado_turno <> 'ABIERTO' THEN
            RAISE_APPLICATION_ERROR(-20022, 'No se puede vender sin un turno de caja abierto.');
        END IF;
        IF v_usuario_turno <> :NEW.id_usuario THEN
            RAISE_APPLICATION_ERROR(-20023, 'El turno de caja pertenece a otro cajero.');
        END IF;
        IF v_tienda_turno <> v_tienda_serie THEN
            RAISE_APPLICATION_ERROR(-20024, 'La serie y la caja deben ser de la misma tienda.');
        END IF;

        -- RN-19: correlativo propio de la serie (se asigna solo)
        UPDATE serie_comprobante
           SET ultimo_correlativo = ultimo_correlativo + 1
         WHERE id_serie = :NEW.id_serie
        RETURNING ultimo_correlativo INTO :NEW.correlativo;
    ELSE
        IF :NEW.id_serie <> :OLD.id_serie OR :NEW.correlativo <> :OLD.correlativo THEN
            RAISE_APPLICATION_ERROR(-20026, 'No se puede cambiar la serie ni el correlativo de un comprobante.');
        END IF;
        IF :OLD.estado = 'ANULADA' AND :NEW.estado <> 'ANULADA' THEN
            RAISE_APPLICATION_ERROR(-20027, 'Una venta anulada no puede volver a emitirse.');
        END IF;
    END IF;
END;
/

-- RN-22: las ventas no se borran
CREATE OR REPLACE TRIGGER trg_venta_no_delete
BEFORE DELETE ON venta
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR(-20025, 'Las ventas no se borran. Use sp_anular_venta.');
END;
/

/* ---------------------------------------------------------------------
   A.7 Cada linea de venta descuenta el stock de la tienda y deja un
       movimiento (RN-11)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_detalle_venta_ai
AFTER INSERT ON detalle_venta
FOR EACH ROW
DECLARE
    v_id_tienda  serie_comprobante.id_tienda%TYPE;
    v_id_usuario venta.id_usuario%TYPE;
    v_estado     venta.estado%TYPE;
BEGIN
    SELECT s.id_tienda, v.id_usuario, v.estado
      INTO v_id_tienda, v_id_usuario, v_estado
      FROM venta v
      JOIN serie_comprobante s ON s.id_serie = v.id_serie
     WHERE v.id_venta = :NEW.id_venta;

    IF v_estado <> 'EMITIDA' THEN
        RAISE_APPLICATION_ERROR(-20028, 'No se pueden agregar productos a una venta anulada.');
    END IF;

    sp_mover_stock(v_id_tienda, :NEW.id_producto, 'VENTA', :NEW.cantidad,
                   v_id_usuario, p_id_venta => :NEW.id_venta);
END;
/

/* ---------------------------------------------------------------------
   A.8 Traslado: descuenta del origen y suma al destino (RN-13)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_detalle_traslado_ai
AFTER INSERT ON detalle_traslado
FOR EACH ROW
DECLARE
    v_origen   traslado_mercaderia.id_tienda_origen%TYPE;
    v_destino  traslado_mercaderia.id_tienda_destino%TYPE;
    v_usuario  traslado_mercaderia.id_usuario%TYPE;
BEGIN
    SELECT id_tienda_origen, id_tienda_destino, id_usuario
      INTO v_origen, v_destino, v_usuario
      FROM traslado_mercaderia
     WHERE id_traslado = :NEW.id_traslado;

    sp_mover_stock(v_origen,  :NEW.id_producto, 'TRASLADO_SALIDA',  :NEW.cantidad,
                   v_usuario, p_id_traslado => :NEW.id_traslado);
    sp_mover_stock(v_destino, :NEW.id_producto, 'TRASLADO_ENTRADA', :NEW.cantidad,
                   v_usuario, p_id_traslado => :NEW.id_traslado);
END;
/

/* ---------------------------------------------------------------------
   A.9 Merma: descuenta stock con su motivo (RN-14)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_detalle_merma_ai
AFTER INSERT ON detalle_merma
FOR EACH ROW
DECLARE
    v_tienda   merma.id_tienda%TYPE;
    v_usuario  merma.id_usuario%TYPE;
    v_motivo   merma.motivo%TYPE;
BEGIN
    SELECT id_tienda, id_usuario, motivo
      INTO v_tienda, v_usuario, v_motivo
      FROM merma
     WHERE id_merma = :NEW.id_merma;

    sp_mover_stock(v_tienda, :NEW.id_producto, 'MERMA', :NEW.cantidad,
                   v_usuario, p_id_merma => :NEW.id_merma,
                   p_observacion => 'Merma por ' || v_motivo);
END;
/

/* ---------------------------------------------------------------------
   A.10 Pagos: cada pago tiene un solo detalle, segun su metodo (RN-26, RN-27)
   --------------------------------------------------------------------- */
CREATE OR REPLACE TRIGGER trg_efectivo_valida
BEFORE INSERT OR UPDATE ON efectivo
FOR EACH ROW
DECLARE
    v_monto pago_venta.monto%TYPE;
BEGIN
    IF fn_codigo_metodo_pago(:NEW.id_pago) <> 'EFECTIVO' THEN
        RAISE_APPLICATION_ERROR(-20030, 'El pago no es en efectivo.');
    END IF;

    SELECT monto INTO v_monto FROM pago_venta WHERE id_pago = :NEW.id_pago;

    -- RN-27: en efectivo cuenta el monto recibido menos el vuelto
    IF :NEW.monto_recibido - :NEW.vuelto <> v_monto THEN
        RAISE_APPLICATION_ERROR(-20031,
            'En efectivo, monto recibido - vuelto debe ser igual al monto del pago.');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_tarjeta_valida
BEFORE INSERT OR UPDATE ON tarjeta
FOR EACH ROW
BEGIN
    IF fn_codigo_metodo_pago(:NEW.id_pago) <> 'TARJETA' THEN
        RAISE_APPLICATION_ERROR(-20032, 'El pago no es con tarjeta.');
    END IF;
END;
/

CREATE OR REPLACE TRIGGER trg_billetera_sip_valida
BEFORE INSERT OR UPDATE ON billetera_digital_sip
FOR EACH ROW
BEGIN
    IF fn_codigo_metodo_pago(:NEW.id_pago) <> 'SIP' THEN
        RAISE_APPLICATION_ERROR(-20033, 'El pago no es con la billetera digital Sip.');
    END IF;
END;
/

/* ---------------------------------------------------------------------
   A.11 sp_anular_venta (RN-22, RN-23, RN-28)
   - Registra quien, cuando y por que.
   - Marca la venta como ANULADA y sus pagos como ANULADO.
   - Devuelve el stock con un movimiento ANULACION.
   --------------------------------------------------------------------- */
CREATE OR REPLACE PROCEDURE sp_anular_venta (
    p_id_venta    IN NUMBER,
    p_id_usuario  IN NUMBER,
    p_motivo      IN VARCHAR2
) AS
    v_estado     venta.estado%TYPE;
    v_id_tienda  serie_comprobante.id_tienda%TYPE;
BEGIN
    SELECT v.estado, s.id_tienda
      INTO v_estado, v_id_tienda
      FROM venta v
      JOIN serie_comprobante s ON s.id_serie = v.id_serie
     WHERE v.id_venta = p_id_venta
       FOR UPDATE OF v.estado;

    IF v_estado = 'ANULADA' THEN
        RAISE_APPLICATION_ERROR(-20040, 'La venta ya esta anulada.');
    END IF;

    INSERT INTO anulacion_venta (id_venta, id_usuario, motivo)
    VALUES (p_id_venta, p_id_usuario, p_motivo);

    UPDATE venta       SET estado = 'ANULADA' WHERE id_venta = p_id_venta;
    UPDATE pago_venta  SET estado = 'ANULADO' WHERE id_venta = p_id_venta;

    FOR d IN (SELECT id_producto, cantidad
                FROM detalle_venta
               WHERE id_venta = p_id_venta) LOOP
        sp_mover_stock(v_id_tienda, d.id_producto, 'ANULACION', d.cantidad,
                       p_id_usuario, p_id_venta => p_id_venta,
                       p_observacion => 'Anulacion de venta');
    END LOOP;
END sp_anular_venta;
/

/* ---------------------------------------------------------------------
   A.12 Vista de control (RN-24): la suma de los pagos aplicados y la suma
   de las lineas deben ser iguales al total de la venta.
   Como los pagos se registran despues de la venta, esta regla se verifica
   al cerrar cada venta: control = 'OK' o 'DESCUADRE'.
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW vw_control_ventas AS
SELECT x.id_venta,
       x.comprobante,
       x.estado,
       x.total,
       x.total_pagado,
       x.total_detalle,
       CASE
           WHEN x.estado = 'ANULADA' THEN 'ANULADA'
           WHEN x.total = x.total_pagado AND x.total = x.total_detalle THEN 'OK'
           ELSE 'DESCUADRE'
       END AS control
  FROM (SELECT v.id_venta,
               s.serie || '-' || LPAD(v.correlativo, 8, '0') AS comprobante,
               v.estado,
               v.total,
               NVL((SELECT SUM(p.monto)
                      FROM pago_venta p
                     WHERE p.id_venta = v.id_venta
                       AND p.estado = 'APLICADO'), 0) AS total_pagado,
               NVL((SELECT SUM(d.total_linea)
                      FROM detalle_venta d
                     WHERE d.id_venta = v.id_venta), 0) AS total_detalle
          FROM venta v
          JOIN serie_comprobante s ON s.id_serie = v.id_serie) x;

/* =====================================================================
   B) DATOS INICIALES (EJEMPLOS FICTICIOS)
   ===================================================================== */

-- Distritos y tiendas (RN-01)
INSERT INTO distrito (nombre) VALUES ('Cayma');
INSERT INTO distrito (nombre) VALUES ('Cerro Colorado');
INSERT INTO distrito (nombre) VALUES ('Yanahuara');

INSERT INTO tienda (id_distrito, codigo, nombre, direccion)
VALUES ((SELECT id_distrito FROM distrito WHERE nombre = 'Cayma'),
        'MASS-CAY', 'Tienda Mass Cayma', 'Direccion de ejemplo - Cayma');
INSERT INTO tienda (id_distrito, codigo, nombre, direccion)
VALUES ((SELECT id_distrito FROM distrito WHERE nombre = 'Cerro Colorado'),
        'MASS-CCO', 'Tienda Mass Cerro Colorado', 'Direccion de ejemplo - Cerro Colorado');
INSERT INTO tienda (id_distrito, codigo, nombre, direccion)
VALUES ((SELECT id_distrito FROM distrito WHERE nombre = 'Yanahuara'),
        'MASS-YAN', 'Tienda Mass Yanahuara', 'Direccion de ejemplo - Yanahuara');

-- Roles (RN-02, RN-03)
INSERT INTO rol (nombre) VALUES ('ADMINISTRADOR');
INSERT INTO rol (nombre) VALUES ('CAJERO');
INSERT INTO rol (nombre) VALUES ('ALMACENERO');

-- Tipos de documento (RN-04, RN-06)
INSERT INTO tipo_documento_identidad (codigo, nombre, longitud) VALUES ('DNI', 'Documento Nacional de Identidad', 8);
INSERT INTO tipo_documento_identidad (codigo, nombre, longitud) VALUES ('RUC', 'Registro Unico de Contribuyentes', 11);

-- Tipos de comprobante (RN-18)
INSERT INTO tipo_comprobante (codigo, nombre, prefijo_serie) VALUES ('BOLETA',  'Boleta de venta', 'B');
INSERT INTO tipo_comprobante (codigo, nombre, prefijo_serie) VALUES ('FACTURA', 'Factura',         'F');

-- Metodos de pago (RN-24, RN-25)
INSERT INTO metodo_pago (codigo, nombre) VALUES ('EFECTIVO', 'Efectivo');
INSERT INTO metodo_pago (codigo, nombre) VALUES ('TARJETA',  'Tarjeta de debito o credito');
INSERT INTO metodo_pago (codigo, nombre) VALUES ('SIP',      'Billetera digital Sip');

-- Tipos de movimiento de stock (RN-12). E = entrada, S = salida
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('VENTA',            'Salida por venta',            'S');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('ANULACION',        'Entrada por anulacion',       'E');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('TRASLADO_SALIDA',  'Salida por traslado',         'S');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('TRASLADO_ENTRADA', 'Entrada por traslado',        'E');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('MERMA',            'Salida por merma',            'S');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('AJUSTE_ENTRADA',   'Entrada por ajuste',          'E');
INSERT INTO tipo_movimiento (codigo, nombre, efecto) VALUES ('AJUSTE_SALIDA',    'Salida por ajuste',           'S');

-- Unidades de medida
INSERT INTO unidad_medida (codigo, nombre) VALUES ('UND', 'Unidad');
INSERT INTO unidad_medida (codigo, nombre) VALUES ('KG',  'Kilogramo');
INSERT INTO unidad_medida (codigo, nombre) VALUES ('LT',  'Litro');
INSERT INTO unidad_medida (codigo, nombre) VALUES ('PQT', 'Paquete');

-- Categorias
INSERT INTO categoria (nombre, descripcion) VALUES ('Abarrotes',  'Productos de despensa');
INSERT INTO categoria (nombre, descripcion) VALUES ('Bebidas',    'Gaseosas, aguas y jugos');
INSERT INTO categoria (nombre, descripcion) VALUES ('Lacteos',    'Leches y derivados');
INSERT INTO categoria (nombre, descripcion) VALUES ('Limpieza',   'Articulos de limpieza del hogar');
INSERT INTO categoria (nombre, descripcion) VALUES ('Panaderia',  'Pan y derivados');
INSERT INTO categoria (nombre, descripcion) VALUES ('Congelados', 'Productos congelados');

-- Marcas de ejemplo
INSERT INTO marca (nombre, es_marca_propia) VALUES ('Gloria',                  'N');
INSERT INTO marca (nombre, es_marca_propia) VALUES ('Coca-Cola',               'N');
INSERT INTO marca (nombre, es_marca_propia) VALUES ('Alicorp',                 'N');
INSERT INTO marca (nombre, es_marca_propia) VALUES ('Marca Propia (ejemplo)',  'S');

-- Productos de ejemplo (precio con IGV incluido: RN-07)
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Lacteos'),
        (SELECT id_marca FROM marca WHERE nombre = 'Gloria'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000001', 'Leche evaporada 400 g', 4.50);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Bebidas'),
        (SELECT id_marca FROM marca WHERE nombre = 'Coca-Cola'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000002', 'Gaseosa 1.5 L', 7.90);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Abarrotes'),
        (SELECT id_marca FROM marca WHERE nombre = 'Alicorp'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000003', 'Aceite vegetal 1 L', 10.90);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Abarrotes'),
        (SELECT id_marca FROM marca WHERE nombre = 'Marca Propia (ejemplo)'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000004', 'Arroz extra 5 kg', 21.50);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Limpieza'),
        (SELECT id_marca FROM marca WHERE nombre = 'Marca Propia (ejemplo)'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000005', 'Detergente 800 g', 12.90);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Panaderia'),
        (SELECT id_marca FROM marca WHERE nombre = 'Marca Propia (ejemplo)'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'UND'),
        '9990000000006', 'Pan de molde', 6.50);
INSERT INTO producto (id_categoria, id_marca, id_unidad, codigo_barras, nombre, precio_venta)
VALUES ((SELECT id_categoria FROM categoria WHERE nombre = 'Congelados'),
        (SELECT id_marca FROM marca WHERE nombre = 'Marca Propia (ejemplo)'),
        (SELECT id_unidad FROM unidad_medida WHERE codigo = 'KG'),
        '9990000000007', 'Pollo congelado (por kg)', 11.90);

-- Usuarios de ejemplo: un administrador, un cajero y un almacenero por tienda (RN-02)
-- Los DNI y las claves son ficticios (la clave es solo un texto de ejemplo, no un hash real).
INSERT INTO usuario (id_tienda, id_rol, nombres, apellidos, dni, login, clave_hash)
SELECT t.id_tienda,
       r.id_rol,
       INITCAP(r.nombre),
       'Demo ' || SUBSTR(t.codigo, 6),
       '7000' || LPAD(ROW_NUMBER() OVER (ORDER BY t.id_tienda, r.id_rol), 4, '0'),
       LOWER(r.nombre) || '.' || LOWER(SUBSTR(t.codigo, 6)),
       'HASH_DE_EJEMPLO'
  FROM tienda t
 CROSS JOIN rol r;

-- Una caja por tienda (RN-15)
INSERT INTO caja (id_tienda, numero, descripcion)
SELECT id_tienda, 1, 'Caja 1' FROM tienda;

-- Series por tienda y tipo: B001..B003 y F001..F003 (RN-19)
INSERT INTO serie_comprobante (id_tienda, id_tipo_comprobante, serie)
SELECT t.id_tienda,
       tc.id_tipo_comprobante,
       tc.prefijo_serie || LPAD(ROW_NUMBER() OVER (PARTITION BY tc.id_tipo_comprobante
                                                   ORDER BY t.id_tienda), 3, '0')
  FROM tienda t
 CROSS JOIN tipo_comprobante tc;

-- Clientes de ejemplo (DNI de 8 digitos y RUC de 11 digitos ficticios)
INSERT INTO cliente (id_tipo_documento, numero_documento, nombre_razon_social)
VALUES ((SELECT id_tipo_documento FROM tipo_documento_identidad WHERE codigo = 'DNI'),
        '45678912', 'Cliente Persona de Ejemplo');
INSERT INTO cliente (id_tipo_documento, numero_documento, nombre_razon_social, direccion)
VALUES ((SELECT id_tipo_documento FROM tipo_documento_identidad WHERE codigo = 'RUC'),
        '20000000001', 'Empresa de Ejemplo S.A.C.', 'Direccion de ejemplo - Arequipa');

COMMIT;

-- Stock inicial: 100 unidades de cada producto en cada tienda, cargado como
-- AJUSTE_ENTRADA por el almacenero (asi queda en el kardex).
BEGIN
    FOR a IN (SELECT u.id_tienda, u.id_usuario
                FROM usuario u
                JOIN rol r ON r.id_rol = u.id_rol
               WHERE r.nombre = 'ALMACENERO') LOOP
        FOR p IN (SELECT id_producto FROM producto) LOOP
            sp_mover_stock(a.id_tienda, p.id_producto, 'AJUSTE_ENTRADA', 100,
                           a.id_usuario, p_observacion => 'Stock inicial');
        END LOOP;
    END LOOP;
    COMMIT;
END;
/

/* =====================================================================
   C) PRUEBAS
   ===================================================================== */

/* ---------------------------------------------------------------------
   C.1 Venta 1: boleta sin cliente, pagada con efectivo y Sip (RN-04, RN-24)
       2 leches (4.50) + 1 gaseosa (7.90) = 16.90
       Efectivo: recibe 20.00, vuelto 10.00 -> aplica 10.00
       Sip (QR): 6.90
   --------------------------------------------------------------------- */
DECLARE
    v_usuario   usuario.id_usuario%TYPE;
    v_caja      caja.id_caja%TYPE;
    v_turno     caja_turno.id_caja_turno%TYPE;
    v_serie     serie_comprobante.id_serie%TYPE;
    v_venta     venta.id_venta%TYPE;
    v_pago      pago_venta.id_pago%TYPE;
    v_leche     producto.id_producto%TYPE;
    v_gaseosa   producto.id_producto%TYPE;
    v_p_leche   producto.precio_venta%TYPE;
    v_p_gaseosa producto.precio_venta%TYPE;
    v_total     venta.total%TYPE;
    v_subtotal  venta.subtotal%TYPE;
BEGIN
    SELECT id_usuario INTO v_usuario FROM usuario WHERE login = 'cajero.cay';

    SELECT c.id_caja INTO v_caja
      FROM caja c JOIN tienda t ON t.id_tienda = c.id_tienda
     WHERE t.codigo = 'MASS-CAY' AND c.numero = 1;

    -- Apertura de turno (RN-16)
    INSERT INTO caja_turno (id_caja, id_usuario, monto_apertura)
    VALUES (v_caja, v_usuario, 100.00)
    RETURNING id_caja_turno INTO v_turno;

    SELECT s.id_serie INTO v_serie
      FROM serie_comprobante s
      JOIN tienda t ON t.id_tienda = s.id_tienda
      JOIN tipo_comprobante tc ON tc.id_tipo_comprobante = s.id_tipo_comprobante
     WHERE t.codigo = 'MASS-CAY' AND tc.codigo = 'BOLETA';

    SELECT id_producto, precio_venta INTO v_leche, v_p_leche
      FROM producto WHERE codigo_barras = '9990000000001';
    SELECT id_producto, precio_venta INTO v_gaseosa, v_p_gaseosa
      FROM producto WHERE codigo_barras = '9990000000002';

    -- El precio ya incluye IGV (18 %): subtotal = total / 1.18; igv = total - subtotal
    v_total    := 2 * v_p_leche + 1 * v_p_gaseosa;
    v_subtotal := ROUND(v_total / 1.18, 2);

    INSERT INTO venta (id_serie, id_caja_turno, id_usuario, id_cliente, subtotal, igv, total)
    VALUES (v_serie, v_turno, v_usuario, NULL, v_subtotal, v_total - v_subtotal, v_total)
    RETURNING id_venta INTO v_venta;

    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, total_linea)
    VALUES (v_venta, v_leche, 2, v_p_leche, ROUND(2 * v_p_leche, 2));
    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, total_linea)
    VALUES (v_venta, v_gaseosa, 1, v_p_gaseosa, ROUND(1 * v_p_gaseosa, 2));

    -- Pago 1: efectivo (aplica 10.00; recibe 20.00 y devuelve 10.00)
    INSERT INTO pago_venta (id_venta, id_metodo_pago, monto)
    VALUES (v_venta, (SELECT id_metodo_pago FROM metodo_pago WHERE codigo = 'EFECTIVO'), 10.00)
    RETURNING id_pago INTO v_pago;
    INSERT INTO efectivo (id_pago, monto_recibido, vuelto) VALUES (v_pago, 20.00, 10.00);

    -- Pago 2: billetera digital Sip por el saldo
    INSERT INTO pago_venta (id_venta, id_metodo_pago, monto)
    VALUES (v_venta, (SELECT id_metodo_pago FROM metodo_pago WHERE codigo = 'SIP'), v_total - 10.00)
    RETURNING id_pago INTO v_pago;
    INSERT INTO billetera_digital_sip (id_pago, modalidad, codigo_operacion)
    VALUES (v_pago, 'QR', 'SIP-EJEMPLO-0001');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Venta 1 registrada (boleta sin cliente). Turno: ' || v_turno);
END;
/

/* ---------------------------------------------------------------------
   C.2 Venta 2: factura a cliente con RUC, pagada con tarjeta; luego se
       anula (RN-04, RN-23, RN-28)
       1 arroz (21.50) + 2.5 kg de pollo (11.90)
   --------------------------------------------------------------------- */
DECLARE
    v_usuario   usuario.id_usuario%TYPE;
    v_turno     caja_turno.id_caja_turno%TYPE;
    v_serie     serie_comprobante.id_serie%TYPE;
    v_cliente   cliente.id_cliente%TYPE;
    v_venta     venta.id_venta%TYPE;
    v_pago      pago_venta.id_pago%TYPE;
    v_arroz     producto.id_producto%TYPE;
    v_pollo     producto.id_producto%TYPE;
    v_p_arroz   producto.precio_venta%TYPE;
    v_p_pollo   producto.precio_venta%TYPE;
    v_total     venta.total%TYPE;
    v_subtotal  venta.subtotal%TYPE;
BEGIN
    SELECT id_usuario INTO v_usuario FROM usuario WHERE login = 'cajero.cay';

    SELECT id_caja_turno INTO v_turno
      FROM caja_turno
     WHERE id_usuario = v_usuario AND estado = 'ABIERTO';

    SELECT s.id_serie INTO v_serie
      FROM serie_comprobante s
      JOIN tienda t ON t.id_tienda = s.id_tienda
      JOIN tipo_comprobante tc ON tc.id_tipo_comprobante = s.id_tipo_comprobante
     WHERE t.codigo = 'MASS-CAY' AND tc.codigo = 'FACTURA';

    SELECT id_cliente INTO v_cliente FROM cliente WHERE numero_documento = '20000000001';

    SELECT id_producto, precio_venta INTO v_arroz, v_p_arroz
      FROM producto WHERE codigo_barras = '9990000000004';
    SELECT id_producto, precio_venta INTO v_pollo, v_p_pollo
      FROM producto WHERE codigo_barras = '9990000000007';

    v_total    := ROUND(1 * v_p_arroz + 2.5 * v_p_pollo, 2);
    v_subtotal := ROUND(v_total / 1.18, 2);

    INSERT INTO venta (id_serie, id_caja_turno, id_usuario, id_cliente, subtotal, igv, total)
    VALUES (v_serie, v_turno, v_usuario, v_cliente, v_subtotal, v_total - v_subtotal, v_total)
    RETURNING id_venta INTO v_venta;

    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, total_linea)
    VALUES (v_venta, v_arroz, 1, v_p_arroz, ROUND(1 * v_p_arroz, 2));
    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_unitario, total_linea)
    VALUES (v_venta, v_pollo, 2.5, v_p_pollo, ROUND(2.5 * v_p_pollo, 2));

    INSERT INTO pago_venta (id_venta, id_metodo_pago, monto)
    VALUES (v_venta, (SELECT id_metodo_pago FROM metodo_pago WHERE codigo = 'TARJETA'), v_total)
    RETURNING id_pago INTO v_pago;
    INSERT INTO tarjeta (id_pago, tipo_tarjeta, marca, ultimos_4, codigo_autorizacion)
    VALUES (v_pago, 'CREDITO', 'VISA', '1234', 'AUT-EJEMPLO-0001');

    COMMIT;

    -- Anulacion: devuelve el stock y anula los pagos
    sp_anular_venta(v_venta, v_usuario, 'Prueba: error en los datos del cliente');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Venta 2 (factura) registrada y anulada.');
END;
/

/* ---------------------------------------------------------------------
   C.3 Traslado de Yanahuara a Cayma: 10 leches (RN-13)
   --------------------------------------------------------------------- */
DECLARE
    v_origen    tienda.id_tienda%TYPE;
    v_destino   tienda.id_tienda%TYPE;
    v_usuario   usuario.id_usuario%TYPE;
    v_traslado  traslado_mercaderia.id_traslado%TYPE;
    v_leche     producto.id_producto%TYPE;
BEGIN
    SELECT id_tienda INTO v_origen  FROM tienda WHERE codigo = 'MASS-YAN';
    SELECT id_tienda INTO v_destino FROM tienda WHERE codigo = 'MASS-CAY';
    SELECT id_usuario INTO v_usuario FROM usuario WHERE login = 'almacenero.yan';
    SELECT id_producto INTO v_leche FROM producto WHERE codigo_barras = '9990000000001';

    INSERT INTO traslado_mercaderia (id_tienda_origen, id_tienda_destino, id_usuario, observacion)
    VALUES (v_origen, v_destino, v_usuario, 'Reposicion de ejemplo')
    RETURNING id_traslado INTO v_traslado;

    INSERT INTO detalle_traslado (id_traslado, id_producto, cantidad)
    VALUES (v_traslado, v_leche, 10);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Traslado registrado.');
END;
/

/* ---------------------------------------------------------------------
   C.4 Merma en Cerro Colorado: 2 panes de molde vencidos (RN-14)
   --------------------------------------------------------------------- */
DECLARE
    v_tienda   tienda.id_tienda%TYPE;
    v_usuario  usuario.id_usuario%TYPE;
    v_merma    merma.id_merma%TYPE;
    v_pan      producto.id_producto%TYPE;
BEGIN
    SELECT id_tienda INTO v_tienda FROM tienda WHERE codigo = 'MASS-CCO';
    SELECT id_usuario INTO v_usuario FROM usuario WHERE login = 'almacenero.cco';
    SELECT id_producto INTO v_pan FROM producto WHERE codigo_barras = '9990000000006';

    INSERT INTO merma (id_tienda, id_usuario, motivo, observacion)
    VALUES (v_tienda, v_usuario, 'VENCIMIENTO', 'Merma de ejemplo')
    RETURNING id_merma INTO v_merma;

    INSERT INTO detalle_merma (id_merma, id_producto, cantidad)
    VALUES (v_merma, v_pan, 2);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Merma registrada.');
END;
/

/* ---------------------------------------------------------------------
   C.5 Cierre del turno de caja de Cayma (RN-17)
       Monto de cierre de ejemplo: apertura 100.00 + efectivo aplicado 10.00
   --------------------------------------------------------------------- */
UPDATE caja_turno
   SET fecha_cierre = SYSTIMESTAMP,
       monto_cierre = 110.00,
       estado       = 'CERRADO'
 WHERE estado = 'ABIERTO'
   AND id_usuario = (SELECT id_usuario FROM usuario WHERE login = 'cajero.cay');
COMMIT;

/* ---------------------------------------------------------------------
   C.6 Pruebas de reglas (descomentar de a una; cada una debe dar error)
   ---------------------------------------------------------------------
-- RN-04: factura sin cliente (ORA-20020)
-- INSERT INTO venta (id_serie, id_caja_turno, id_usuario, id_cliente, subtotal, igv, total)
-- VALUES ((SELECT id_serie FROM serie_comprobante WHERE serie = 'F001'),
--         1, (SELECT id_usuario FROM usuario WHERE login = 'cajero.cay'), NULL, 8.47, 1.53, 10.00);

-- RN-16: vender con el turno cerrado (ORA-20022): usar el id del turno cerrado.

-- RN-10: stock negativo (ORA-20010): vender mas de lo que hay.
-- BEGIN
--     sp_mover_stock((SELECT id_tienda FROM tienda WHERE codigo = 'MASS-CAY'),
--                    (SELECT id_producto FROM producto WHERE codigo_barras = '9990000000001'),
--                    'MERMA', 99999, (SELECT id_usuario FROM usuario WHERE login = 'almacenero.cay'));
-- END;
-- /

-- RN-22: borrar una venta (ORA-20025)
-- DELETE FROM venta;
   --------------------------------------------------------------------- */

/* =====================================================================
   D) CONSULTAS DE VERIFICACION
   ===================================================================== */

-- D.1 Control de ventas: total = pagos = detalle (RN-24). Esperado: OK y ANULADA
SELECT * FROM vw_control_ventas ORDER BY id_venta;

-- D.2 Comprobantes emitidos con su tienda, cliente y estado (RN-19, RN-22)
SELECT s.serie || '-' || LPAD(v.correlativo, 8, '0') AS comprobante,
       t.nombre   AS tienda,
       NVL(c.nombre_razon_social, 'Publico general') AS cliente,
       v.subtotal, v.igv, v.total, v.estado
  FROM venta v
  JOIN serie_comprobante s ON s.id_serie = v.id_serie
  JOIN tienda t            ON t.id_tienda = s.id_tienda
  LEFT JOIN cliente c      ON c.id_cliente = v.id_cliente
 ORDER BY v.id_venta;

-- D.3 Pagos por venta con su metodo (RN-24, RN-26)
SELECT s.serie || '-' || LPAD(v.correlativo, 8, '0') AS comprobante,
       m.nombre AS metodo, p.monto, p.estado
  FROM pago_venta p
  JOIN venta v        ON v.id_venta = p.id_venta
  JOIN serie_comprobante s ON s.id_serie = v.id_serie
  JOIN metodo_pago m  ON m.id_metodo_pago = p.id_metodo_pago
 ORDER BY p.id_pago;

-- D.4 Stock por tienda (RN-09)
SELECT t.nombre AS tienda, pr.nombre AS producto, st.cantidad
  FROM stock st
  JOIN tienda t    ON t.id_tienda = st.id_tienda
  JOIN producto pr ON pr.id_producto = st.id_producto
 ORDER BY t.nombre, pr.nombre;

-- D.5 Kardex de un producto en Cayma (RN-11, RN-12)
SELECT m.fecha_hora, tm.nombre AS movimiento, m.cantidad, m.stock_resultante, m.observacion
  FROM movimiento_stock m
  JOIN tipo_movimiento tm ON tm.id_tipo_movimiento = m.id_tipo_movimiento
  JOIN tienda t           ON t.id_tienda = m.id_tienda
  JOIN producto pr        ON pr.id_producto = m.id_producto
 WHERE t.codigo = 'MASS-CAY'
   AND pr.codigo_barras = '9990000000001'
 ORDER BY m.id_movimiento;

-- D.6 Turnos de caja (RN-17)
SELECT t.nombre AS tienda, ca.numero AS caja, u.login AS cajero,
       ct.fecha_apertura, ct.monto_apertura, ct.fecha_cierre, ct.monto_cierre, ct.estado
  FROM caja_turno ct
  JOIN caja ca    ON ca.id_caja = ct.id_caja
  JOIN tienda t   ON t.id_tienda = ca.id_tienda
  JOIN usuario u  ON u.id_usuario = ct.id_usuario;
