/*
  Bloque PL/SQL para cálculo de asignaciones mensuales - Dolphin Consulting
  Autor: Franco Castro Villanueva
  Fecha: 27-01-2025
  Descripción: 
    - Procesa asesorías del mes especificado (paramétricamente)
    - Calcula: 
      * Asignación de movilización extra según comuna y honorarios
      * Incentivo por tipo de contrato
      * Asignación por profesión
    - Controla errores: 
      * Límite de asignaciones
      * Porcentajes no encontrados
    - Almacena resultados en tablas de detalle y resumen
    - Garantiza repetibilidad mediante truncado de tablas y manejo transaccional
*/

DECLARE
    -- ***********************
    -- Variables de configuración
    -- ***********************
    v_fecha_proceso DATE := TO_DATE('06-2021', 'MM-YYYY');  -- Fecha paramétrica
    v_limite_asignacion NUMBER := 250000;                   -- Límite según política
    
    -- ***********************
    -- Estructuras de datos
    -- ***********************
    TYPE t_porcentajes IS VARRAY(5) OF NUMBER;
    v_porcentajes_movil t_porcentajes := t_porcentajes(2, 4, 5, 7, 9);  -- Porcentajes movilización
    
    -- ***********************
    -- Excepciones personalizadas
    -- ***********************
    ex_limite_asignacion EXCEPTION;
    PRAGMA EXCEPTION_INIT(ex_limite_asignacion, -20001);
    
    -- ***********************
    -- Cursores
    -- ***********************
    -- Cursor con parámetro para flexibilidad
    CURSOR c_profesionales (p_fecha DATE) IS
        SELECT p.numrun_prof, p.dvrun_prof, p.appaterno, p.apmaterno, p.nombre, 
               pr.nombre_profesion, c.nom_comuna, p.cod_tpcontrato, p.sueldo, p.cod_profesion
        FROM profesional p
        JOIN comuna c ON p.cod_comuna = c.cod_comuna
        JOIN profesion pr ON p.cod_profesion = pr.cod_profesion
        WHERE EXISTS (
            SELECT 1 
            FROM asesoria a
            WHERE a.numrun_prof = p.numrun_prof
            AND TRUNC(a.inicio_asesoria, 'MM') = TRUNC(p_fecha, 'MM')
        )
        ORDER BY pr.nombre_profesion, p.appaterno, p.nombre;

    -- ***********************
    -- Variables de proceso
    -- ***********************
    v_nro_asesorias      NUMBER;
    v_total_honorarios   NUMBER;
    v_movil_extra        NUMBER;
    v_incentivo_contrato NUMBER;
    v_asignacion_profesion NUMBER;
    v_total_asignaciones NUMBER;
    
BEGIN
    -- ***********************
    -- Preparación inicial
    -- ***********************
    -- Limpieza de datos anteriores
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_asignacion_mes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_mes_profesion';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE errores_proceso';
    
    -- Reinicio de secuencia de errores
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE sq_errores';
    EXCEPTION
        WHEN OTHERS THEN NULL;  -- Ignorar error si no existe
    END;
    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_errores START WITH 1';

    -- ***********************
    -- Procesamiento principal
    -- ***********************
    FOR r_prof IN c_profesionales(v_fecha_proceso) LOOP
        BEGIN
            -- Paso 1: Obtener datos básicos
            SELECT COUNT(*), SUM(honorario)
            INTO v_nro_asesorias, v_total_honorarios
            FROM asesoria
            WHERE numrun_prof = r_prof.numrun_prof
            AND TRUNC(inicio_asesoria, 'MM') = TRUNC(v_fecha_proceso, 'MM');

            -- Paso 2: Calcular movilización extra
            v_movil_extra := 0;
            CASE 
                WHEN r_prof.nom_comuna = 'Santiago' AND v_total_honorarios < 350000 THEN
                    v_movil_extra := ROUND(v_total_honorarios * v_porcentajes_movil(1)/100);
                WHEN r_prof.nom_comuna = 'Nuñoa' THEN
                    v_movil_extra := ROUND(v_total_honorarios * v_porcentajes_movil(2)/100);
                WHEN r_prof.nom_comuna = 'La Reina' AND v_total_honorarios < 400000 THEN
                    v_movil_extra := ROUND(v_total_honorarios * v_porcentajes_movil(3)/100);
                WHEN r_prof.nom_comuna = 'La Florida' AND v_total_honorarios < 800000 THEN
                    v_movil_extra := ROUND(v_total_honorarios * v_porcentajes_movil(4)/100);
                WHEN r_prof.nom_comuna = 'Macul' AND v_total_honorarios < 680000 THEN
                    v_movil_extra := ROUND(v_total_honorarios * v_porcentajes_movil(5)/100);
            END CASE;

            -- Paso 3: Obtener incentivo por contrato
            SELECT incentivo 
            INTO v_incentivo_contrato
            FROM tipo_contrato
            WHERE cod_tpcontrato = r_prof.cod_tpcontrato;
            
            v_incentivo_contrato := ROUND(v_total_honorarios * v_incentivo_contrato/100);

            -- Paso 4: Obtener asignación por profesión
            BEGIN
                SELECT asignacion 
                INTO v_asignacion_profesion
                FROM porcentaje_profesion
                WHERE cod_profesion = r_prof.cod_profesion;
                
                v_asignacion_profesion := ROUND(r_prof.sueldo * v_asignacion_profesion/100);
                
            EXCEPTION
                WHEN NO_DATA_FOUND THEN  -- Excepción predefinida
                    v_asignacion_profesion := 0;
                    INSERT INTO errores_proceso VALUES (
                        sq_errores.NEXTVAL,
                        'ORA-01403',
                        'Error: No existe porcentaje para profesión '||r_prof.cod_profesion||' - RUN: '||r_prof.numrun_prof
                    );
                WHEN OTHERS THEN
                    RAISE;
            END;

            -- Paso 5: Calcular total y controlar límite
            v_total_asignaciones := ROUND(v_movil_extra + v_incentivo_contrato + v_asignacion_profesion);
            
            IF v_total_asignaciones > v_limite_asignacion THEN
                RAISE ex_limite_asignacion;  -- Excepción definida por usuario
            END IF;

            -- Paso 6: Insertar en detalle
            INSERT INTO detalle_asignacion_mes VALUES (
                EXTRACT(MONTH FROM v_fecha_proceso),
                EXTRACT(YEAR FROM v_fecha_proceso),
                r_prof.numrun_prof || '-' || r_prof.dvrun_prof,
                r_prof.nombre || ' ' || r_prof.appaterno || ' ' || r_prof.apmaterno,
                r_prof.nombre_profesion,
                v_nro_asesorias,
                v_total_honorarios,
                v_movil_extra,
                v_incentivo_contrato,
                v_asignacion_profesion,
                v_total_asignaciones
            );

        EXCEPTION
            WHEN ex_limite_asignacion THEN  -- Excepción personalizada
                INSERT INTO errores_proceso VALUES (
                    sq_errores.NEXTVAL,
                    'LIM-001',
                    'Profesional '||r_prof.numrun_prof||' excede límite. Original: '||v_total_asignaciones||' - Ajustado: '||v_limite_asignacion
                );
                v_total_asignaciones := v_limite_asignacion;
                
                -- Re-insertar con valor ajustado
                INSERT INTO detalle_asignacion_mes VALUES (
                    EXTRACT(MONTH FROM v_fecha_proceso),
                    EXTRACT(YEAR FROM v_fecha_proceso),
                    r_prof.numrun_prof || '-' || r_prof.dvrun_prof,
                    r_prof.nombre || ' ' || r_prof.appaterno || ' ' || r_prof.apmaterno,
                    r_prof.nombre_profesion,
                    v_nro_asesorias,
                    v_total_honorarios,
                    v_movil_extra,
                    v_incentivo_contrato,
                    v_asignacion_profesion,
                    v_total_asignaciones
                );
                
            WHEN OTHERS THEN
                INSERT INTO errores_proceso VALUES (
                    sq_errores.NEXTVAL,
                    SQLCODE,
                    'Error inesperado: '||SQLERRM||' - RUN: '||r_prof.numrun_prof
                );
        END;
    END LOOP;

    -- ***********************
    -- Generación de resumen
    -- ***********************
    INSERT INTO resumen_mes_profesion
    SELECT 
        EXTRACT(YEAR FROM v_fecha_proceso) * 100 + EXTRACT(MONTH FROM v_fecha_proceso),
        profesion,
        SUM(nro_asesorias),
        SUM(monto_honorarios),
        SUM(monto_movil_extra),
        SUM(monto_asig_tipocont),
        SUM(monto_asig_profesion),
        SUM(monto_total_asignaciones)
    FROM detalle_asignacion_mes
    GROUP BY profesion
    ORDER BY profesion ASC;  -- Orden explícito según pauta

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20000, 'Error general: '||SQLERRM);
END;
/