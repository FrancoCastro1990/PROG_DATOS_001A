-- ********************************************
-- Autor: Franco Castro Villanueva
-- Fecha: 30-12-2024
-- ********************************************

-- ********************************************
-- CASO 1
-- Descripción: Bloque PL/SQL para el programa TODOSUMA
-- Este bloque calcula los pesos TODOSUMA para clientes según sus créditos
-- y tipo de cliente, siguiendo las reglas de negocio especificadas.
-- ********************************************
-- Variables bind
VAR b_run_cliente VARCHAR2(20);
VAR b_pesos_base NUMBER;
VAR b_pesos_extra1 NUMBER;
VAR b_pesos_extra2 NUMBER;
VAR b_pesos_extra3 NUMBER;
VAR b_tramo1 NUMBER;
VAR b_tramo2 NUMBER;

-- Asignar valores
--KAREN SOFIA PRADENAS MANDIOLA
EXEC :b_run_cliente := '22.176.845-2';
--SILVANA MARTINA VALENZUELA DUARTE
--EXEC :b_run_cliente := '21.242.003-4';
--DENISSE ALICIA DIAZ MIRANDA
--EXEC :b_run_cliente := '18.858.542-6';
--AMANDA ROMINA LIZANA MARAMBIO
--EXEC :b_run_cliente := '21.300.628-2';
--LUIS CLAUDIO LUNA JORQUERA
--EXEC :b_run_cliente := '22.558.061-8';
EXEC :b_pesos_base := 1200;
EXEC :b_pesos_extra1 := 100;
EXEC :b_pesos_extra2 := 300;
EXEC :b_pesos_extra3 := 550;
EXEC :b_tramo1 := 1000000;
EXEC :b_tramo2 := 3000000;

SET SERVEROUTPUT ON;

DECLARE
    --variables
    v_nro_cliente          NUMBER;
    v_tipo_cliente         VARCHAR2(50);
    v_nombre_completo      VARCHAR2(100);
    v_monto_total         NUMBER := 0;
    v_pesos_base          NUMBER := 0;
    v_pesos_extra         NUMBER := 0;
    v_total_pesos         NUMBER := 0;
    v_anno_proceso        NUMBER;
BEGIN
    v_anno_proceso := EXTRACT(YEAR FROM SYSDATE) - 1;

    -- Obtener datos del cliente usando las columnas correctas
    SELECT c.nro_cliente, tc.nombre_tipo_cliente, 
           c.pnombre || ' ' || c.appaterno || ' ' || c.appaterno
    INTO v_nro_cliente, v_tipo_cliente, v_nombre_completo
    FROM cliente c
    JOIN tipo_cliente tc ON c.cod_tipo_cliente = tc.cod_tipo_cliente
    WHERE c.numrun = TO_NUMBER(REPLACE(SUBSTR(:b_run_cliente, 1, INSTR(:b_run_cliente, '-') - 1), '.', ''))
    AND c.dvrun = SUBSTR(:b_run_cliente, INSTR(:b_run_cliente, '-') + 1);
    
    -- Obtener suma de montos de créditos
    SELECT NVL(SUM(monto_solicitado), 0)
    INTO v_monto_total
    FROM credito_cliente
    WHERE nro_cliente = v_nro_cliente
    AND EXTRACT(YEAR FROM fecha_solic_cred) = v_anno_proceso;
    
    -- Calcular pesos base
    v_pesos_base := FLOOR(v_monto_total/100000) * :b_pesos_base;
    -- Calcular pesos extra para trabajadores independientes
    IF v_tipo_cliente = 'Trabajadores independientes' THEN
        IF v_monto_total < :b_tramo1 THEN
            v_pesos_extra := FLOOR(v_monto_total/100000) * :b_pesos_extra1;
        ELSIF v_monto_total <= :b_tramo2 THEN
            v_pesos_extra := FLOOR(v_monto_total/100000) * :b_pesos_extra2;
        ELSE
            v_pesos_extra := FLOOR(v_monto_total/100000) * :b_pesos_extra3;
        END IF;
    END IF;
    
    v_total_pesos := v_pesos_base + v_pesos_extra;
    
    -- Eliminar registro previo si existe
    DELETE FROM cliente_todosuma WHERE nro_cliente = v_nro_cliente;
    
    -- Insertar en CLIENTE_TODOSUMA usando nombres correctos de columnas
    INSERT INTO cliente_todosuma (
        nro_cliente,
        run_cliente,
        nombre_cliente,
        tipo_cliente,
        monto_solic_creditos,
        monto_pesos_todosuma
    ) VALUES (
        v_nro_cliente,
        :b_run_cliente,
        v_nombre_completo,
        v_tipo_cliente,
        v_monto_total,
        v_total_pesos
    );
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Proceso completado para cliente: ' || v_nombre_completo);
    DBMS_OUTPUT.PUT_LINE('Monto total créditos: ' || TO_CHAR(v_monto_total,'999,999,999'));
    DBMS_OUTPUT.PUT_LINE('Total pesos TODOSUMA: ' || TO_CHAR(v_total_pesos,'999,999'));
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Cliente no encontrado con RUN: ' || :b_run_cliente);
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

--consultamos los datos
select * from cliente_todosuma ;

-- ********************************************
-- CASO 2
-- Descripción: Bloque PL/SQL para la postergación de cuotas de créditos
-- Este bloque gestiona la postergación de cuotas según el tipo de crédito,
-- aplicando las tasas correspondientes y manejando casos especiales.
-- ********************************************
-- Variables bind
VAR b_nro_cliente NUMBER;
VAR b_nro_solicitud NUMBER;
VAR b_cant_cuotas NUMBER;

--SEBASTIAN PATRICIO QUINTANA BERRIOS
--EXEC :b_nro_cliente := 5;
--EXEC :b_nro_solicitud := 2001;
--EXEC :b_cant_cuotas := 2;

--KAREN SOFIA PRADENAS MANDIOLA
--EXEC :b_nro_cliente := 67;
--EXEC :b_nro_solicitud := 3004;
--EXEC :b_cant_cuotas := 1;

--JULIAN PAUL ARRIAGADA LUJAN
EXEC :b_nro_cliente := 13;
EXEC :b_nro_solicitud := 2004;
EXEC :b_cant_cuotas := 1;

SET SERVEROUTPUT ON;

DECLARE
    -- Constantes
    c_tasa_hip_2cuotas CONSTANT NUMBER := 0.005;
    c_tasa_consumo CONSTANT NUMBER := 0.01;
    c_tasa_auto CONSTANT NUMBER := 0.02;
    
    -- Variables 
    v_tipo_credito VARCHAR2(500);  
    v_ultima_cuota NUMBER;
    v_valor_cuota NUMBER(10,2);   
    v_fecha_ultima_cuota DATE;
    v_tasa_interes NUMBER(4,3);   
    v_creditos_year NUMBER := 0;
    v_anno_proceso NUMBER;
BEGIN
    IF :b_cant_cuotas <= 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'La cantidad de cuotas debe ser mayor a 0');
    END IF;
    DBMS_OUTPUT.PUT_LINE('numero de cliente: ' || :b_nro_cliente);
    DBMS_OUTPUT.PUT_LINE('numero solicitud: ' ||  :b_nro_solicitud);
    DBMS_OUTPUT.PUT_LINE('cantidad cuotas: ' || :b_cant_cuotas);
    v_anno_proceso := EXTRACT(YEAR FROM SYSDATE) - 1;
    -- Obtener información del crédito usando los nombres correctos de columnas
    SELECT c.desc_credito,
           MAX(cu.nro_cuota),
           MAX(cu.valor_cuota),
           MAX(cu.fecha_venc_cuota)
    INTO v_tipo_credito, v_ultima_cuota, v_valor_cuota, v_fecha_ultima_cuota
    FROM credito_cliente cr
    JOIN credito c ON cr.cod_credito = c.cod_credito
    JOIN cuota_credito_cliente cu ON cr.nro_solic_credito = cu.nro_solic_credito
    WHERE cr.nro_solic_credito = :b_nro_solicitud
    GROUP BY c.desc_credito;
    
    DBMS_OUTPUT.PUT_LINE('Tipo de crédito obtenido: ' || v_tipo_credito);
    DBMS_OUTPUT.PUT_LINE('Última cuota: ' || v_ultima_cuota);
    DBMS_OUTPUT.PUT_LINE('Valor cuota: ' || v_valor_cuota);
    
    -- Determinar tasa según tipo de crédito
    CASE v_tipo_credito
        WHEN 'Crédito hipotecario' THEN
            IF :b_cant_cuotas = 1 THEN
                v_tasa_interes := 0;
            ELSE
                v_tasa_interes := c_tasa_hip_2cuotas;
            END IF;
        WHEN 'Crédito de consumo' THEN
            v_tasa_interes := c_tasa_consumo;
        WHEN 'Crédito automotriz' THEN
            v_tasa_interes := c_tasa_auto;
        ELSE
            v_tasa_interes := 0;
    END CASE;
    
    -- Verificar créditos en el año
    SELECT COUNT(*)
    INTO v_creditos_year
    FROM credito_cliente
    WHERE nro_cliente = :b_nro_cliente
    AND EXTRACT(YEAR FROM fecha_solic_cred) = v_anno_proceso;
    
    -- Marcar última cuota como pagada si aplica
    IF v_creditos_year > 1 THEN
        UPDATE cuota_credito_cliente
        SET fecha_pago_cuota = fecha_venc_cuota,
            monto_pagado = valor_cuota,
            saldo_por_pagar = 0
        WHERE nro_solic_credito = :b_nro_solicitud
        AND nro_cuota = v_ultima_cuota;
    END IF;
    
    -- Insertar nuevas cuotas
    FOR i IN 1..:b_cant_cuotas LOOP
        INSERT INTO cuota_credito_cliente (
            nro_solic_credito,
            nro_cuota,
            fecha_venc_cuota,
            valor_cuota,
            fecha_pago_cuota,
            monto_pagado,
            saldo_por_pagar,
            cod_forma_pago
        )
        VALUES (
            :b_nro_solicitud,
            v_ultima_cuota + i,
            ADD_MONTHS(v_fecha_ultima_cuota, i),
            v_valor_cuota * (1 + v_tasa_interes),
            NULL,
            NULL,
            NULL,
            NULL
        );
    END LOOP;
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Proceso completado para crédito: ' || :b_nro_solicitud);
    DBMS_OUTPUT.PUT_LINE('Cuotas postergadas: ' || :b_cant_cuotas);
    DBMS_OUTPUT.PUT_LINE('Tasa aplicada: ' || TO_CHAR(v_tasa_interes * 100) || '%');
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('Crédito no encontrado: ' || :b_nro_solicitud);
        ROLLBACK;
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
        ROLLBACK;
END;
/

--consultamos los datos
select * from cuota_credito_cliente WHERE cuota_credito_cliente.nro_solic_credito = 2004;
select * from cuota_credito_cliente WHERE cuota_credito_cliente.nro_solic_credito = 3004;
select * from cuota_credito_cliente WHERE cuota_credito_cliente.nro_solic_credito = 2001;
