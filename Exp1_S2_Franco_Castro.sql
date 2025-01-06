-- ********************************************
-- Autor: Franco Castro Villanueva
-- Fecha: 06-01-2025
-- ********************************************
-- Este bloque PL/SQL implementa un proceso de categorización de clientes que:
-- 1. Procesa todos los clientes de la base de datos
-- 2. Calcula puntajes según reglas de negocio específicas
-- 3. Genera correos corporativos
-- 4. Almacena resultados en la tabla DETALLE_DE_CLIENTES
-- ********************************************

-- Variable BIND para periodo (ingreso sin formato)
VARIABLE g_periodo VARCHAR2(6);
EXEC :g_periodo := '032024';

DECLARE
    -- Variables usando %TYPE para mantener consistencia con la base de datos
    v_total_clientes NUMBER := 0;
    v_procesados NUMBER := 0;
    v_rut_cli cliente.numrun_cli%TYPE;
    v_nombre_cli cliente.pnombre_cli%TYPE;
    v_apepat_cli cliente.appaterno_cli%TYPE;
    v_edad NUMBER;
    v_puntaje NUMBER := 0;
    v_correo VARCHAR2(100);
    v_renta cliente.renta%TYPE;
    v_comuna cliente.id_comuna%TYPE;
    v_tipo_cli cliente.id_tipo_cli%TYPE;
    v_fecha_nac cliente.fecha_nac_cli%TYPE;
    v_porcentaje NUMBER;
    v_comuna_exclusiva NUMBER := 0;
    v_periodo_formato VARCHAR2(7);
    
    -- Cursor para recorrer todos los clientes de manera eficiente
    CURSOR c_clientes IS 
        SELECT 
            id_cli,
            numrun_cli,
            pnombre_cli,
            appaterno_cli,
            apmaterno_cli,
            fecha_nac_cli,
            renta,
            id_comuna,
            id_tipo_cli
        FROM cliente;

BEGIN
    -- [SQL Dinámico] Trunca la tabla para permitir múltiples ejecuciones
    -- Esta sentencia usa SQL dinámico para mayor flexibilidad y reusabilidad
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_DE_CLIENTES';
    
    -- [SQL] Obtiene el total de clientes para verificación de procesamiento completo
    -- Esta consulta es crucial para garantizar la integridad del proceso
    SELECT COUNT(*) INTO v_total_clientes FROM cliente;
    
    -- Formatear el periodo (de '032024' a '03/2024')
    v_periodo_formato := SUBSTR(:g_periodo, 1, 2) || '/' || SUBSTR(:g_periodo, 3);
    
    -- Mensaje inicial
    DBMS_OUTPUT.PUT_LINE('PROCESANDO CLIENTES ...');
    
    -- [PL/SQL] Ciclo principal de procesamiento usando cursor FOR
    -- Este ciclo garantiza un procesamiento eficiente de memoria
    FOR r_cliente IN c_clientes LOOP
        -- Calcular edad del cliente
        v_edad := EXTRACT(YEAR FROM SYSDATE) - EXTRACT(YEAR FROM r_cliente.fecha_nac_cli);
        
        -- Inicializar puntaje
        v_puntaje := 0;
        
        -- [PL/SQL] Bloque de reglas de negocio para cálculo de puntajes
        -- Este bloque implementa la lógica central del proceso de categorización
        SELECT COUNT(*)
        INTO v_comuna_exclusiva
        FROM comuna 
        WHERE id_comuna = r_cliente.id_comuna 
        AND UPPER(nombre_comuna) IN ('LA REINA', 'LAS CONDES', 'VITACURA');
        
        -- Regla d) Renta > 700000 y no vive en comunas específicas
        IF r_cliente.renta > 700000 AND v_comuna_exclusiva = 0 THEN
            v_puntaje := ROUND(r_cliente.renta * 0.03);
            
        -- Regla e) Cliente Internacional o VIP
        ELSIF r_cliente.id_tipo_cli IN ('B', 'D') THEN
            v_puntaje := v_edad * 30;
            
        -- Regla f) Si puntaje sigue en 0, usar tabla TRAMO_EDAD
        ELSIF v_puntaje = 0 THEN
            SELECT NVL(porcentaje, 0) 
            INTO v_porcentaje
            FROM tramo_edad 
            WHERE anno_vig = EXTRACT(YEAR FROM SYSDATE)
            AND v_edad BETWEEN tramo_inf AND tramo_sup;
            
            v_puntaje := ROUND(r_cliente.renta * (v_porcentaje/100));
        END IF;
        
        -- Generar correo según formato especificado
        v_correo := LOWER(r_cliente.appaterno_cli) || 
                    v_edad || 
                    '*' || 
                    SUBSTR(r_cliente.pnombre_cli, 1, 1) ||
                    TO_CHAR(r_cliente.fecha_nac_cli, 'DD') ||
                    SUBSTR(:g_periodo, 1, 2) ||
                    '@LogiCarg.cl';
        
        -- [SQL] Inserción de resultados en tabla final
        -- Esta sentencia almacena los resultados del procesamiento
        INSERT INTO DETALLE_DE_CLIENTES(
            IDC,
            RUT,
            CLIENTE,
            EDAD,
            PUNTAJE,
            CORREO_CORP,
            PERIODO
        ) VALUES (
            r_cliente.id_cli,
            r_cliente.numrun_cli,
            INITCAP(r_cliente.appaterno_cli) || ' ' || 
            INITCAP(r_cliente.apmaterno_cli) || ' ' || 
            INITCAP(r_cliente.pnombre_cli),
            v_edad,
            v_puntaje,
            v_correo,
            v_periodo_formato
        );
        
        v_procesados := v_procesados + 1;
    END LOOP;
    
    -- Verificar que se procesaron todos los clientes
    IF v_procesados = v_total_clientes THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Proceso Finalizado Exitosamente');
        DBMS_OUTPUT.PUT_LINE('Se Procesaron : ' || v_procesados || ' CLIENTES');
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: No se procesaron todos los clientes');
        DBMS_OUTPUT.PUT_LINE('Clientes procesados: ' || v_procesados || ' de ' || v_total_clientes);
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error en el proceso: ' || SQLERRM);
END;
/

-- ********************************************
-- Verificamos el resultado
SELECT * FROM DETALLE_DE_CLIENTES ORDER BY IDC;
-- ********************************************