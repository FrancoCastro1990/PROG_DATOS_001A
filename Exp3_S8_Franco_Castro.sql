-- ======================================================
-- Package Specification
-- Franco Castro
-- Fecha: 17-02-2025
-- Descripción: Package para gestión de liquidaciones
-- ======================================================
CREATE OR REPLACE PACKAGE PKG_LIQUIDACION IS
    -- Variable para almacenar promedio de ventas
    v_promedio_ventas NUMBER;
    
    -- Procedimiento para insertar errores en tabla ERROR_CALC
    PROCEDURE SP_INSERTAR_ERROR(
        p_subprograma IN VARCHAR2,    -- Nombre del subprograma donde ocurrió el error
        p_mensaje_error IN VARCHAR2,   -- Mensaje de error de Oracle
        p_descripcion IN VARCHAR2      -- Descripción personalizada del error
    );
    
    -- Función para obtener promedio de ventas del año anterior
    FUNCTION FN_PROMEDIO_VENTAS_ANTERIOR RETURN NUMBER;
END PKG_LIQUIDACION;
/

-- ======================================================
-- Package Body
-- ======================================================
CREATE OR REPLACE PACKAGE BODY PKG_LIQUIDACION IS
    -- Implementación del procedimiento de inserción de errores
    PROCEDURE SP_INSERTAR_ERROR(
        p_subprograma IN VARCHAR2,
        p_mensaje_error IN VARCHAR2,
        p_descripcion IN VARCHAR2
    ) IS
    BEGIN
        -- Insertar registro de error
        INSERT INTO ERROR_CALC (
            CORREL_ERROR,
            RUTINA_ERROR,
            DESCRIP_ERROR,
            DESCRIP_USER
        ) VALUES (
            SEQ_ERROR.NEXTVAL,
            p_subprograma,
            p_mensaje_error,
            p_descripcion
        );
        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- En caso de error al registrar el error, escribir en log del servidor
            DBMS_OUTPUT.PUT_LINE('Error al registrar error: ' || SQLERRM);
    END SP_INSERTAR_ERROR;

    -- Implementación de la función de cálculo de promedio de ventas
    FUNCTION FN_PROMEDIO_VENTAS_ANTERIOR RETURN NUMBER IS
        v_promedio NUMBER;
        v_year NUMBER;
    BEGIN
        -- Obtener año anterior
        v_year := EXTRACT(YEAR FROM SYSDATE) - 1;
        
        -- Calcular promedio de ventas
        SELECT NVL(AVG(MONTO_TOTAL_BOLETA), 0)
        INTO v_promedio
        FROM BOLETA
        WHERE EXTRACT(YEAR FROM FECHA) = v_year;
        
        RETURN v_promedio;
    EXCEPTION
        WHEN OTHERS THEN
            -- Registrar error y retornar 0
            SP_INSERTAR_ERROR(
                'FN_PROMEDIO_VENTAS_ANTERIOR',
                SQLERRM,
                'Error al calcular promedio de ventas del año ' || v_year
            );
            RETURN 0;
    END FN_PROMEDIO_VENTAS_ANTERIOR;
END PKG_LIQUIDACION;
/

-- ======================================================
-- Función para obtener porcentaje por antigüedad
-- ======================================================
CREATE OR REPLACE FUNCTION FN_OBTENER_PORC_ANTIGUEDAD(
    p_sueldo_base IN NUMBER,
    p_id_emp IN VARCHAR2
) RETURN NUMBER IS
    v_annos_trabajo NUMBER(4,2);
    v_porcentaje NUMBER;
BEGIN
    -- Calcular años de servicio del empleado
    SELECT FLOOR(MONTHS_BETWEEN(SYSDATE, FECHA_CONTRATO)/12)
    INTO v_annos_trabajo
    FROM EMPLEADO
    WHERE RUN_EMPLEADO = p_id_emp;
    
    -- Obtener porcentaje según años de antigüedad
    SELECT PORC_ANTIGUEDAD
    INTO v_porcentaje
    FROM PCT_ANTIGUEDAD
    WHERE v_annos_trabajo BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP;
    
    RETURN v_porcentaje;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- No se encontró porcentaje para los años de antigüedad
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'FN_OBTENER_PORC_ANTIGUEDAD',
            'NO_DATA_FOUND',
            'No existe porcentaje definido para ' || v_annos_trabajo || ' años de antigüedad'
        );
        RETURN 0;
    WHEN OTHERS THEN
        -- Otros errores
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'FN_OBTENER_PORC_ANTIGUEDAD',
            SQLERRM,
            'Error al calcular porcentaje por antigüedad para empleado: ' || p_id_emp
        );
        RETURN 0;
END FN_OBTENER_PORC_ANTIGUEDAD;
/

-- ======================================================
-- Función para obtener porcentaje por nivel de estudios
-- ======================================================
CREATE OR REPLACE FUNCTION FN_OBTENER_PORC_ESCOLARIDAD(
    p_id_emp IN VARCHAR2 
) RETURN NUMBER IS
    v_porcentaje NUMBER;
BEGIN
    -- Obtener porcentaje de escolaridad solo para empleados con FONASA
    SELECT NVL(pne.PORC_ESCOLARIDAD, 0)
    INTO v_porcentaje
    FROM EMPLEADO e
    JOIN PCT_NIVEL_ESTUDIOS pne ON e.COD_ESCOLARIDAD = pne.COD_ESCOLARIDAD
    WHERE e.RUN_EMPLEADO = p_id_emp
    AND e.COD_SALUD = 1; -- FONASA
    
    RETURN v_porcentaje;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'FN_OBTENER_PORC_ESCOLARIDAD',
            'NO_DATA_FOUND',
            'No se encontró nivel de estudios para el empleado: ' || p_id_emp
        );
        RETURN 0;
    WHEN OTHERS THEN
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'FN_OBTENER_PORC_ESCOLARIDAD',
            SQLERRM,
            'Error al obtener porcentaje por escolaridad para empleado: ' || p_id_emp
        );
        RETURN 0;
END FN_OBTENER_PORC_ESCOLARIDAD;
/

-- ======================================================
-- Procedimiento principal de cálculo de liquidaciones
-- ======================================================
CREATE OR REPLACE PROCEDURE SP_CALCULAR_LIQUIDACION(
    p_mes IN NUMBER,
    p_anno IN NUMBER
) IS
    v_promedio_ventas NUMBER;
    v_asig_especial NUMBER;
    v_asig_estudios NUMBER;
    v_total_haberes NUMBER;
    v_ventas_empleado NUMBER;
BEGIN
    -- Obtener promedio de ventas del año anterior
    PKG_LIQUIDACION.v_promedio_ventas := PKG_LIQUIDACION.FN_PROMEDIO_VENTAS_ANTERIOR();
    
    -- Procesar todos los empleados
    FOR emp IN (SELECT * FROM EMPLEADO) LOOP
        -- Inicializar variables
        v_asig_especial := 0;
        v_asig_estudios := 0;
        
        -- Obtener total de ventas del empleado
        SELECT NVL(SUM(b.MONTO_TOTAL_BOLETA), 0)
        INTO v_ventas_empleado
        FROM BOLETA b
        WHERE b.RUN_EMPLEADO = emp.RUN_EMPLEADO
        AND EXTRACT(YEAR FROM b.FECHA) = p_anno;
        
        -- Verificar si califica para asignación especial
        IF (v_ventas_empleado * 0.07) > PKG_LIQUIDACION.v_promedio_ventas THEN
            v_asig_especial := (emp.SUELDO_BASE * FN_OBTENER_PORC_ANTIGUEDAD(emp.SUELDO_BASE, emp.RUN_EMPLEADO)) / 100;
        END IF;
        
        -- Calcular asignación por estudios si tiene FONASA
        IF emp.COD_SALUD = 1 THEN
            v_asig_estudios := (emp.SUELDO_BASE * FN_OBTENER_PORC_ESCOLARIDAD(emp.RUN_EMPLEADO)) / 100;
        END IF;
        
        -- Calcular total de haberes
        v_total_haberes := emp.SUELDO_BASE + v_asig_especial + v_asig_estudios;
        
        -- Insertar liquidación
        INSERT INTO LIQUIDACION_EMPLEADO (
            MES,
            ANNO,
            RUN_EMPLEADO,
            NOMBRE_EMPLEADO,
            SUELDO_BASE,
            ASIG_ESPECIAL,
            ASIG_ESTUDIOS,
            TOTAL_HABERES
        ) VALUES (
            p_mes,
            p_anno,
            emp.RUN_EMPLEADO,
            emp.NOMBRE || ' ' || emp.paterno || ' ' || emp.materno,
            emp.SUELDO_BASE,
            v_asig_especial,
            v_asig_estudios,
            v_total_haberes
        );
    END LOOP;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'SP_CALCULAR_LIQUIDACION',
            SQLERRM,
            'Error en el proceso de cálculo de liquidaciones para el periodo ' || p_mes || '/' || p_anno
        );
END SP_CALCULAR_LIQUIDACION;
/

-- ======================================================
-- Trigger para protección de tabla PRODUCTO
-- ======================================================
CREATE OR REPLACE TRIGGER TRG_PROTEGER_PRODUCTOS
BEFORE INSERT OR DELETE OR UPDATE OF VALOR_UNITARIO ON PRODUCTO
FOR EACH ROW
DECLARE
    v_dia VARCHAR2(15);
    v_promedio_ventas NUMBER;
BEGIN
    -- Obtener día actual
    SELECT TO_CHAR(SYSDATE, 'DY') INTO v_dia FROM DUAL;
    
    -- Validar operaciones INSERT y DELETE
    IF INSERTING OR DELETING THEN
        IF v_dia IN ('MON', 'TUE', 'WED', 'THU', 'FRI') THEN
            IF INSERTING THEN
                RAISE_APPLICATION_ERROR(-20501, 'TABLA DE PRODUCTO PROTEGIDA - No se permiten inserciones de lunes a viernes');
            ELSE
                RAISE_APPLICATION_ERROR(-20500, 'TABLA DE PRODUCTO PROTEGIDA - No se permiten eliminaciones de lunes a viernes');
            END IF;
        END IF;
    END IF;
    
    -- Validar actualizaciones de VALOR_UNITARIO
    IF UPDATING AND v_dia IN ('MON', 'TUE', 'WED', 'THU', 'FRI') THEN
        -- Obtener promedio de ventas
        v_promedio_ventas := PKG_LIQUIDACION.FN_PROMEDIO_VENTAS_ANTERIOR();
        
        -- Si el nuevo valor supera el 10% del promedio
        IF :NEW.VALOR_UNITARIO > (v_promedio_ventas * 1.1) THEN
            -- Actualizar valores totales en detalles de boleta
            UPDATE DETALLE_BOLETA
            SET VALOR_TOTAL = CANTIDAD * :NEW.VALOR_UNITARIO
            WHERE COD_PRODUCTO = :OLD.COD_PRODUCTO;
        END IF;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        PKG_LIQUIDACION.SP_INSERTAR_ERROR(
            'TRG_PROTEGER_PRODUCTOS',
            SQLERRM,
            'Error en trigger de protección de productos'
        );
        RAISE;
END;
/

-- Ejecutamos el script
EXEC SP_CALCULAR_LIQUIDACION(6, 2024);

-- Validamos los datos
SELECT * FROM LIQUIDACION_EMPLEADO ORDER BY MES, ANNO, RUN_EMPLEADO;

-- Validamos los errores
SELECT * FROM ERROR_CALC ORDER BY CORREL_ERROR;
