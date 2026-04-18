CREATE OR REPLACE PACKAGE BODY SIPAI."PKG_SIPAI_REGISTRO_NOMINAL" 
AS

--Funcion movida al inicio para evitar not declare in this scope
FUNCTION FN_OBT_TIPVACREL_ID (pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE) RETURN NUMBER AS
  vTipVacunaId SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE := NULL;
  vConteo      SIMPLE_INTEGER := 0;
  BEGIN
    SELECT COUNT (1)
      INTO vConteo
      FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
     WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
           NVL(TIPO_VACUNA_ID,0) > 0;

     CASE
     WHEN vConteo > 0 THEN
          BEGIN
            SELECT TIPO_VACUNA_ID
              INTO vTipVacunaId
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
             WHERE CONTROL_VACUNA_ID = pControlVacunaId;
          END;
     ELSE NULL;
     END CASE;
     RETURN vTipVacunaId;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vTipVacunaId;

  END FN_OBT_TIPVACREL_ID;

--Ajuste 04/ 2026  Valdar dosis para casos de registros por Actualizacion
FUNCTION FN_VALIDAR_FECHA_DOSIS(
    pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
    pIdRelTipoVacunaEdad   IN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD.REL_TIPO_VACUNA_EDAD_ID%TYPE,
    pFechaDosis            IN DATE
) RETURN VARCHAR2 AS
    vFechaAnterior     DATE;
    vCodigoDosisActual VARCHAR2(20);
    vCodigoAnterior    VARCHAR2(20);
    vExpedienteId      NUMBER(10);
    vTipVacunaId  SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE; 
BEGIN
    --obtener ExpedienteId desde el control vacuna
    SELECT EXPEDIENTE_ID  
     INTO   vExpedienteId
     FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
     WHERE CONTROL_VACUNA_ID = pControlVacunaId;
     --Obtener rel_tipo_vacuna_id
      vTipVacunaId :=FN_OBT_TIPVACREL_ID (pControlVacunaId);
     
    -- Obtener código de dosis actual
    SELECT CODIGO_NUM_DOSIS
    INTO vCodigoDosisActual
    FROM SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD
    WHERE REL_TIPO_VACUNA_EDAD_ID = pIdRelTipoVacunaEdad;
    
    -- Determinar código de dosis anterior
    vCodigoAnterior := CASE vCodigoDosisActual
        WHEN 'CODINTVAL-10' THEN 'CODINTVAL-9'
        WHEN 'CODINTVAL-11' THEN 'CODINTVAL-10'
    END;
    
    -- Si es 1ra dosis o Única, no valida
    IF vCodigoAnterior IS NULL THEN
        RETURN 'OK';
    END IF;
    
    -- Buscar fecha de dosis anterior
    SELECT DV.FECHA_VACUNACION
    INTO vFechaAnterior
    FROM SIPAI.SIPAI_DET_VACUNACION DV
    JOIN SIPAI.SIPAI_MST_CONTROL_VACUNA CV
        ON CV.CONTROL_VACUNA_ID = DV.CONTROL_VACUNA_ID
    JOIN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD RTVE
        ON RTVE.REL_TIPO_VACUNA_EDAD_ID = DV.REL_TIPO_VACUNA_EDAD_ID
    WHERE CV.EXPEDIENTE_ID = vExpedienteId
      AND RTVE.CODIGO_NUM_DOSIS = vCodigoAnterior
      AND CV.TIPO_VACUNA_ID=vTipVacunaId
      AND DV.ESTADO_REGISTRO_ID = 6869;
    
    IF pFechaDosis < vFechaAnterior THEN
        RETURN 'ERROR: La fecha de la ' || 
               CASE vCodigoDosisActual
                   WHEN 'CODINTVAL-10' THEN '2da.'
                   WHEN 'CODINTVAL-11' THEN '3ra.'
               END || ' dosis no puede ser menor a la dosis anterior (' || 
               TO_CHAR(vFechaAnterior, 'DD-MON-YYYY') || ')';
    END IF;
    
    RETURN 'OK';
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN 'ERROR: Debe registrar primero la dosis anterior (' || 
               REPLACE(vCodigoAnterior, 'CODINTVAL-', 'Dosis ') || ')';
END FN_VALIDAR_FECHA_DOSIS;

FUNCTION FN_CALCULAR_ESTADO_ACTUALIZACION ( pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,					  
											pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
											pNoAplicada		   IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
											pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,	
											pIdRelTipoVacunaEdad  IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
                                            pResultado          OUT VARCHAR2,
											pMsgError           OUT VARCHAR2) 
                                            RETURN NUMBER AS
 vCatalogoId CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE;
 v_grupo_edad NUMBER;  
 v_edad_vacuna NUMBER;
 pExpedienteId NUMBER;

vFirma          VARCHAR2(250) := 'PKG_SIPAI_REGISTRO_NOMINAL.FN_CALCULAR_ESTADO_ACTUALIZACION => ';    

 -- NUEVOS CAMPOS
 v_dias_vacuna NUMBER;
 v_dias_vacuna_dias_aportuno NUMBER;
 v_dias_actuales NUMBER;
 v_anio_actuales NUMBER;
 -------------------------------------------------------------------------------
 f_nacimiento date; --fecha de nacimiento de la persona
 f_calculo date:=pFecVacuna; --fecha a la cual deseamos saber la edad
 v_meses_paciente_edad NUMBER;
 v_estado_edad NUMBER:=0;

-----------Variables para definir estados Oportuno / Aplicada (En Tiempo) EST_APL_VAC||01	Aplicada (En Tiempo)---------
  vDosisAdicional PLS_INTEGER;
  vDosisRefuerzo PLS_INTEGER;
  vEdadHasta       PLS_INTEGER;
---------------------------------------------------------------------------------

 BEGIN
    vCatalogoId:=NULL;

    IF NVL(pIdRelTipoVacunaEdad, 0 ) > 0   THEN
        SELECT B.GRUPO_EDAD_MES ,B.EDAD_DESDE,B.EDAD_HASTA,A.ES_ADICIONAL, ES_REFUERZO
         INTO    v_grupo_edad ,v_edad_vacuna,vEdadHasta,vDosisRefuerzo,vDosisAdicional
        FROM  SIPAI_REL_TIPO_VACUNA_EDAD A JOIN SIPAI_PRM_RANGO_EDAD B  ON A.EDAD_ID=B.EDAD_ID
        WHERE REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad;
    END IF;

    /*
     DBMS_OUTPUT.PUT_LINE('v_grupo_edad = '  || v_grupo_edad);
     DBMS_OUTPUT.PUT_LINE('v_edad_vacuna = ' || v_edad_vacuna);
     DBMS_OUTPUT.PUT_LINE('vEdadHasta = '    || vEdadHasta);
     DBMS_OUTPUT.PUT_LINE('vDosisRefuerzo = '|| vDosisRefuerzo);
     DBMS_OUTPUT.PUT_LINE('vDosisAdicional = '||vDosisAdicional);
    */

      IF vEdadHasta >=720 OR vDosisRefuerzo=1 OR vDosisAdicional=1 THEN
        vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||01');--Aplicada (En Tiempo)
         DBMS_OUTPUT.PUT_LINE('Aplicada por DEFAULT  Aplicada (En Tiempo)');
     ELSE 
        SELECT DISTINCT EXPEDIENTE_ID  
        INTO   pExpedienteId
        FROM   sipai_mst_control_vacuna 
        WHERE  CONTROL_VACUNA_ID=pControlVacunaId;
        --DBMS_OUTPUT.PUT_LINE('pExpedienteId = ' || pExpedienteId);

        SELECT FECHA_NACIMIENTO  
        INTO f_nacimiento
        FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
        WHERE  expediente_id=pExpedienteId;
        --DBMS_OUTPUT.PUT_LINE('f_nacimiento = ' || f_nacimiento);

        v_meses_paciente_edad := round(months_between(f_calculo, f_nacimiento));
        -- DBMS_OUTPUT.PUT_LINE('v_meses_paciente_edad = ' || v_meses_paciente_edad);

        -- ASIGNACION NUEVOS CAMPOS
        v_dias_vacuna := (v_edad_vacuna * 30); 
        --v_dias_vacuna_dias_aportuno:= (v_dias_vacuna + 29);
         v_dias_vacuna_dias_aportuno:= (vEdadHasta *30)+30 + 29;

        DBMS_OUTPUT.PUT_LINE('v_dias_vacuna = ' || v_dias_vacuna);
        --DBMS_OUTPUT.PUT_LINE('v_dias_vacuna_dias_aportuno = ' || v_dias_vacuna_dias_aportuno);

        --SELECT (TO_DATE(pFecVacuna,'DD/MM/YY') - TO_DATE(f_nacimiento,'DD/MM/YY'))

        select ROUND(months_between(pFecVacuna, f_nacimiento)) * 30 
        INTO v_dias_actuales
        FROM DUAL;
         --DBMS_OUTPUT.PUT_LINE('v_dias_actuales = ' || v_dias_actuales);
        SELECT TRUNC(months_between(TO_DATE(pFecVacuna,'DD/MM/YY'),dob)/12)
        INTO v_anio_actuales
        FROM (Select to_date(f_nacimiento,'DD/MM/YY') DOB FROM DUAL);
        -- DBMS_OUTPUT.PUT_LINE('v_anio_actuales = ' || v_anio_actuales);

        IF f_nacimiento IS NOT NULL THEN
            CASE
                WHEN (v_edad_vacuna = 12 or v_edad_vacuna = 18) AND  v_anio_actuales >= 2 THEN  
                     v_estado_edad:=3;  --Atrasado / Aplicada (Tardía) 
                WHEN v_edad_vacuna < 12 AND  v_anio_actuales >= 1 THEN  
                     v_estado_edad:=3;  --Atrasado / Aplicada (Tardía) 
                WHEN v_dias_actuales <= v_dias_vacuna_dias_aportuno THEN
                    v_estado_edad:=1;  --Oportuno / Aplicada (En Tiempo)
                WHEN v_dias_actuales > v_dias_vacuna_dias_aportuno AND v_dias_actuales < (v_dias_vacuna + 365)  THEN
                    v_estado_edad:=2;  --No oportuno / Aplicada Tiempo (No Oportuno) 
                ELSE
                 v_estado_edad:=0;
            END CASE; 
        END IF;

        CASE
            WHEN NVL(pUniSaludActualizacionId, 0 ) > 0 AND  v_estado_edad = 1 THEN
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||08');

            WHEN NVL(pUniSaludActualizacionId, 0 ) > 0 AND  v_estado_edad = 2 THEN
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||09'); 

             WHEN NVL(pUniSaludActualizacionId, 0 ) > 0 AND  v_estado_edad = 3 THEN
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||09');    


            WHEN NVL(pNoAplicada,0) > 0 THEN 
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||04');
           -- 7636	7632	EST_APL_VAC||04	No Aplicada
	       WHEN  v_estado_edad = 1     THEN 
            vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||01');
            --7633	7632	EST_APL_VAC||01	Aplicada (En Tiempo)
          WHEN  v_estado_edad = 2     THEN 
           vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||07');
           -- 7704	7632	*Aplicada Tiempo (No Oportuno)
            WHEN  v_estado_edad = 3     THEN 
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||02');
            --  7634	7632	EST_APL_VAC||02	Aplicada (Tardía)
        ELSE    vCatalogoId:=FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||01');

       END CASE;
   END IF;
   RETURN  vCatalogoId;

    EXCEPTION  
	  WHEN OTHERS THEN
       pResultado := 'error ';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;   

 END FN_CALCULAR_ESTADO_ACTUALIZACION;



PROCEDURE PR_ACT_FECHA_INICIO_VAC_MASTER (pControlId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
											pResultado          OUT VARCHAR2,
											pMsgError           OUT VARCHAR2) 
IS

	vFecha_minima_det   DATE;
	vFirma          VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_C_DET_VACUNA => ';         

  BEGIN

	     SELECT MIN(fecha_vacunacion) into vFecha_minima_det
         FROM  SIPAI.sipai_det_vacunacion A
         WHERE  CONTROL_VACUNA_ID=pControlId AND ESTADO_REGISTRO_ID =  vGLOBAL_ESTADO_ACTIVO; -- 6869 vGLOBAL_ESTADO_ACTIVO;

		-- IF TRUNC(vFecha_master) > TRUNC(vFecha_minima_det) THEN 
			 UPDATE sipai_mst_control_vacuna 
			 SET  FECHA_INICIO_VACUNA=vFecha_minima_det
			 WHERE  CONTROL_VACUNA_ID=pControlId;  

    EXCEPTION  
	  WHEN OTHERS THEN
       pResultado := 'Error no controlado';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;   

 END PR_ACT_FECHA_INICIO_VAC_MASTER;

 FUNCTION FN_EXISTE_DOSIS_ANTERIOR (pControlVacunaId  IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
								     pDetVacunacionId  IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE

)RETURN BOOLEAN AS
  vContador SIMPLE_INTEGER := 0;
  vExiste BOOLEAN  := FALSE;
  vFechaMaxDosis   DATE;
  vFechaDosis   DATE;
  BEGIN


         SELECT MAX(FECHA_VACUNACION) INTO vFechaMaxDosis
         FROM  SIPAI.sipai_det_vacunacion 
         WHERE  CONTROL_VACUNA_ID=pControlVacunaId 
         AND ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO;

		 SELECT FECHA_VACUNACION INTO vFechaDosis
         FROM  SIPAI.sipai_det_vacunacion 
         WHERE  DET_VACUNACION_ID=pDetVacunacionId ; 


    CASE
    WHEN vFechaMaxDosis > vFechaDosis THEN
         vExiste := TRUE;
    ELSE NULL;
    END CASE; 
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_EXISTE_DOSIS_ANTERIOR; 

  FUNCTION FN_EXISTE_FECHA_VACUNA_CRTID (pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
									    pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
										pDetVacunacionId    IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE

										)RETURN BOOLEAN AS
  vContador SIMPLE_INTEGER := 0;
  vExiste BOOLEAN  := FALSE;

  BEGIN
  dbms_output.put_line(vContador);

    IF   NVL(pDetVacunacionId,0)=0 THEN 
         SELECT COUNT (1)
         INTO vContador
         FROM  SIPAI.sipai_det_vacunacion 
         WHERE  CONTROL_VACUNA_ID=pControlVacunaId
		 AND TRUNC(FECHA_VACUNACION) = TRUNC(pFecVacuna)
		 --AND    TO_CHAR(FECHA_VACUNACION,'DD/MM/YYYY') = TO_CHAR(pFecVacuna,'DD/MM/YYYY' )
         AND     ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO;
  ELSE
       SELECT COUNT (1)
         INTO vContador
         FROM  SIPAI.sipai_det_vacunacion 
         WHERE  CONTROL_VACUNA_ID=pControlVacunaId
		 AND TRUNC(FECHA_VACUNACION) = TRUNC(pFecVacuna)
		 AND   DET_VACUNACION_ID NOT IN (pDetVacunacionId)
         AND     ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO;

    END IF;

	CASE
    WHEN vContador > 0 THEN
         vExiste := TRUE;
    ELSE NULL;
      END CASE; 

dbms_output.put_line(vContador);
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_EXISTE_FECHA_VACUNA_CRTID; 



FUNCTION FN_VALIDA_EXPEDIENTE_ID (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE)RETURN BOOLEAN AS
  vContador SIMPLE_INTEGER := 0;
  vExiste BOOLEAN  := FALSE;
  BEGIN
   SELECT COUNT (1)
     INTO vContador
     FROM HOSPITALARIO.SNH_MST_CODIGO_EXPEDIENTE
    WHERE EXPEDIENTE_ID = pExpedienteId;

    CASE
    WHEN vContador > 0 THEN
         vExiste := TRUE;
    ELSE NULL;
    END CASE; 
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_VALIDA_EXPEDIENTE_ID; 

 FUNCTION FN_VAL_REGISTRO_ACTIVO (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE, 
                                   pProgVacuna   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.PROGRAMA_VACUNA_ID%TYPE) RETURN BOOLEAN AS
  vConteo SIMPLE_INTEGER := 0;
  vExiste BOOLEAN := FALSE;
  BEGIN
     SELECT COUNT (1)
       INTO vConteo
       FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
      WHERE EXPEDIENTE_ID = pExpedienteId AND 
            PROGRAMA_VACUNA_ID = pProgVacuna AND
            ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO;
      CASE
      WHEN vConteo > 0 THEN
           vExiste := TRUE;
      ELSE NULL;
      END CASE;

      RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       vExiste := TRUE;
       RETURN vExiste;      
  END FN_VAL_REGISTRO_ACTIVO; 

 FUNCTION FN_OBT_NOM_PROGRAMA_VACUNA (pProgVacuna IN CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE) RETURN VARCHAR2 AS
  vConteo SIMPLE_INTEGER := 0;
  vValor CATALOGOS.SBC_CAT_CATALOGOS.VALOR%TYPE;
  BEGIN
    SELECT COUNT (1)
      INTO vConteo
      FROM CATALOGOS.SBC_CAT_CATALOGOS
     WHERE CATALOGO_ID = pProgVacuna AND 
           PASIVO = 0;
     CASE
     WHEN vConteo > 0 THEN
          BEGIN
            SELECT VALOR
              INTO vValor
              FROM CATALOGOS.SBC_CAT_CATALOGOS
             WHERE CATALOGO_ID = pProgVacuna;
          END;
     ELSE NULL;
     END CASE;

     RETURN vValor;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vValor; 
  END FN_OBT_NOM_PROGRAMA_VACUNA;

   FUNCTION FN_OBT_CANT_DOSIS_APLICADAS (pTipVacuna IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE) RETURN NUMBER AS
  vContador      SIMPLE_INTEGER := 0;
  vCantidadDosis SIMPLE_INTEGER := 0;
  BEGIN
       SELECT COUNT (1)
         INTO vContador
         FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
        WHERE REL_TIPO_VACUNA_ID = pTipVacuna AND
              ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO AND
              CANTIDAD_DOSIS IS NOT NULL;

        CASE
        WHEN vContador > 0 THEN
             BEGIN
               SELECT CANTIDAD_DOSIS
                 INTO vCantidadDosis
                 FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
                WHERE REL_TIPO_VACUNA_ID = pTipVacuna;              
             END;
        ELSE NULL;
        END CASE;
        RETURN vCantidadDosis;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vCantidadDosis;
  END FN_OBT_CANT_DOSIS_APLICADAS;

  FUNCTION FN_VALIDA_ES_CRONICO (pProgVacuna IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE) RETURN BOOLEAN AS
  vExiste BOOLEAN := FALSE;
  vConteo SIMPLE_INTEGER := 0;
  BEGIN
    DBMS_OUTPUT.PUT_LINE ('Valida programa crónico: '||pProgVacuna);
    SELECT COUNT (1)
      INTO vConteo 
      FROM CATALOGOS.SBC_CAT_CATALOGOS
     WHERE CATALOGO_ID = pProgVacuna AND
           CODIGO = 'GRP_PRI_VAC || 03' AND
           PASIVO = 0;
    CASE
    WHEN vConteo > 0 THEN
         DBMS_OUTPUT.PUT_LINE ('Es programa crónico');
         vExiste := TRUE;
    ELSE NULL;
    END CASE;
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;

  END FN_VALIDA_ES_CRONICO;

  PROCEDURE PR_I_CONTROL_VACUNA (pControlVacunaId OUT SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                 pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                 pProgVacuna      IN SIPAI.SIPAI_MST_CONTROL_VACUNA.PROGRAMA_VACUNA_ID%TYPE,
                                 pGrpPrioridad    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                 pTipVacuna       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE,
                                 pCantVacunaApli  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_APLICADA%TYPE,
                                 pCantVacunaProg  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_PROGRAMADA%TYPE,
                                 pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                 pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                 pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,
                                 pResultado       OUT VARCHAR2,
                                 pMsgError        OUT VARCHAR2) IS
  vFirma        VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_I_CONTROL_VACUNA => ';                               
  vCantVacProg  SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE;
  vProgramaId   NUMBER;
  vFabricanteId NUMBER;
  BEGIN

   vCantVacProg := FN_OBT_CANT_DOSIS_APLICADAS (pTipVacuna);
   vProgramaId     := FN_SIPAI_CATALOGO_ESTADO_Id('PRO_VAC || 02');

   SELECT FABRICANTE_VACUNA_ID 
   INTO   vFabricanteId 
   FROM   SIPAI_REL_TIP_VACUNACION_DOSIS
   WHERE  REL_TIPO_VACUNA_ID=pTipVacuna;

   INSERT INTO SIPAI.SIPAI_MST_CONTROL_VACUNA (EXPEDIENTE_ID, 
                                               PROGRAMA_VACUNA_ID, 
                                               GRUPO_PRIORIDAD_ID, 
                                               TIPO_VACUNA_ID, 
                                               FABRICANTE_VACUNA_ID,
                                               CANTIDAD_VACUNA_PROGRAMADA,
                                               ESTADO_REGISTRO_ID,
                                               SISTEMA_ID,
                                               UNIDAD_SALUD_ID,
                                               USUARIO_REGISTRO)
         VALUES(pExpedienteId,
               vProgramaId,
               pGrpPrioridad,
               pTipVacuna,
               vFabricanteId,
               vCantVacProg,
               vGLOBAL_ESTADO_ACTIVO,
               pSistemaId,
               pUniSaludId,
               pUsuario)
        RETURNING CONTROL_VACUNA_ID INTO pControlVacunaId;
        pResultado := 'Registro creado con exito';
        DBMS_OUTPUT.PUT_LINE('Despues del Insert de Master');
  EXCEPTION
  WHEN OTHERS THEN
       pResultado := 'Error al insertar en control vacuna';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;
  END PR_I_CONTROL_VACUNA; 

 FUNCTION FN_VALIDA_CONTROL_VACUNA (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                     pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                     pTipoPaginacion  OUT NUMBER) RETURN BOOLEAN AS


 vExiste   BOOLEAN :=  FALSE;
 vContador SIMPLE_INTEGER := 0;
 BEGIN
     CASE
     WHEN (NVL (pControlVacunaId,0) > 0) AND (NVL(pExpedienteId,0) > 0) THEN
          BEGIN
             SELECT COUNT (1)
               INTO vContador 
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
              WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
                    EXPEDIENTE_ID = pExpedienteId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
					AND  ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO;
          pTipoPaginacion := 1;          
          END;
     WHEN NVL(pControlVacunaId,0) > 0 THEN
        BEGIN
         SELECT COUNT (1)
           INTO vContador 
           FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
          WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
                ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
				AND  ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO;
        pTipoPaginacion := 2;
        END;
      WHEN NVL(pExpedienteId,0) > 0 THEN
        BEGIN
         SELECT COUNT (1)
           INTO vContador 
           FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
          WHERE EXPEDIENTE_ID = pExpedienteId AND
                ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
				AND  ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO;
        pTipoPaginacion := 3;
        END;       
     ELSE 
        BEGIN
         SELECT COUNT (1)
           INTO vContador 
          FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
         WHERE CONTROL_VACUNA_ID > 0 AND
               ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
			   AND  ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO;
        pTipoPaginacion := 4;
        END; 
     END CASE;

     CASE
     WHEN vContador > 0 THEN
          vExiste := TRUE;
     ELSE NULL;
     END CASE;

  RETURN vExiste;
 EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
 END FN_VALIDA_CONTROL_VACUNA;

 FUNCTION FN_OBT_X_ID_Y_EXPID (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE, 
                               pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE) RETURN var_refcursor AS 
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,
			  -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------	  
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,   			   

			   A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID                                      DETVACUSALUD_US_ENTADMIN,
			   DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID , 
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID      DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                   DETVACUSALUD_ACT_NOMBRE
               ,TIENE_FRECUENCIA_ANUALES
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        --JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        --LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        --LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
		  --
       LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID	
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
          ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID		 

    WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
          A.EXPEDIENTE_ID = pExpedienteId AND 
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		  AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
          AND CATPROG.CODIGO != 'PRO_VAC || 01'
         ORDER BY A.CONTROL_VACUNA_ID;  

--     DBMS_OUTPUT.PUT_LINE (vQuery);   
--     DBMS_OUTPUT.PUT_LINE (vQuery1); 
     RETURN vRegistro;

 END FN_OBT_X_ID_Y_EXPID ;

 FUNCTION FN_OBT_X_ID (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
               -----  PEDIDOS POR EL FRONTED 			  
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
			   ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,  	   
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID  DETVACUSALUD_US_ENTADMIN,
			    -------
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID      DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                    DETVACUSALUD_ACT_NOMBRE
               ,RELTIP.TIENE_FRECUENCIA_ANUALES 
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
          ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID  

   WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
         A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO  
         AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		 AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
          AND CATPROG.CODIGO != 'PRO_VAC || 01'
   ORDER BY A.CONTROL_VACUNA_ID;

--     DBMS_OUTPUT.PUT_LINE (vQuery);   
--     DBMS_OUTPUT.PUT_LINE (vQuery1);          
     RETURN vRegistro;
 END FN_OBT_X_ID;

FUNCTION FN_OBT_X_EXPID (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,  
               -----  PEDIDOS POR EL FRONTED 			   
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------

               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID    DETVACUSALUD_US_ENTADMIN,
			   ----------------
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE
               ,RELTIP.TIENE_FRECUENCIA_ANUALES
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID   
          --08 2024 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        LEFT JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		  ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	  

    WHERE A.EXPEDIENTE_ID = pExpedienteId AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
           AND CATPROG.CODIGO != 'PRO_VAC || 01'
         ORDER BY A.CONTROL_VACUNA_ID; 
--     DBMS_OUTPUT.PUT_LINE (vQuery);   
         DBMS_OUTPUT.PUT_LINE ('SOY LA FUNCION  FN_OBT_X_EXPID FILTRO 2 ');          
     RETURN vRegistro;
 END FN_OBT_X_EXPID;

  FUNCTION FN_OBT_CONTROL_TODOS (pPgnAct IN NUMBER, 
                                pPgnTmn IN NUMBER) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
       SELECT 
       A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
       A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
       PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
       PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
       PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
       PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
       PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
       NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
       NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
       PERNOM.TELEFONO                                                    TEL_PACIENTE,         
       PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
       PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
       PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
       NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
       PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
       PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
       NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
       NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
       NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
       NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
       NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
       NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
       NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
       NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
       NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
       NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
       NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
       NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
       NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
       NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
       NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
       PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
       PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
       PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
       -----  PEDIDOS POR EL FRONTED 					 
       PERNOM.PAIS_NACIMIENTO_ID,
       PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
     ------------

       NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
       PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
       PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
       NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
       NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
       PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
       PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
       PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
       PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
       PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
       PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
       PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
       NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
       NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
       PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
       SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
       SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
       SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
       PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
-----------------
       PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PER_COMUNIDAD_ID,                          -- PERRES_COMUNIDAD_ID,        -- 
       PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PER_COMUNIDAD_NOMBRE,                      -- PERRES_NOMBRE,              -- 
       NULL  /*COMUS.CODIGO*/                                             PER_COMUNIDAD_CODIGO,                      -- PERRES_CODIGO,              -- 
       NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
       NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
       NULL  /*COMUS.PASIVO */                                            PER_COMUNIDAD_PASIVO,                      -- PERRES_PASIVO,              -- 
       NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

       PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PER_COM_MUNI_ID,                           -- PERRES_MUNICIPIO_ID,          --    
       PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_COM_MUNI_NOMBRE,                       -- PER_MUNI_NOMBRE,              -- 
       NULL  /*MUNUS.CODIGO*/                                             PER_COM_MUN_CODIGO,                        -- PER_MUN_CODIGO,               -- 
       NULL  /*MUNUS.CODIGO_CSE*/                                         PER_COM_MUN_CODIGO_CSE,                    -- PER_MUN_CODIGO_CSE,           -- 
       NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_COM_MUN_CSEREG,                        -- PER_MUN_CSEREG,               -- 
       NULL  /*MUNUS.LATITUD*/                                            PER_COM_MUN_LATITUD,                       -- PER_MUN_LATITUD,              -- 
       NULL  /*MUNUS.LONGITUD*/                                           PER_COM_MUN_LONGITUD,                      -- PER_MUN_LONGITUD,             -- 
       NULL  /*MUNUS.PASIVO*/                                             PER_COM_MUN_PASIVO,                        -- PER_MUN_PASIVO,               -- 
       NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_COM_MUN_FEC_PASIVO,                    -- PER_MUN_FEC_PASIVO,           -- 

       PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_COM_MUN_DEP_ID,                        -- PER_MUN_DEP_ID,               -- 
       PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_COM_MUN_DEP_NOMBRE,                    -- PER_MUN_DEP_NOMBRE,           -- 
       NULL  /*DEPUS.CODIGO*/                                             PER_COM_MUN_DEP_CODIGO,                    -- PER_MUN_DEP_CODIGO,           -- 
       NULL  /*DEPUS.CODIGO_ISO*/                                         PER_COM_MUN_DEP_CODISO,                    -- PER_MUN_DEP_CODISO,           -- 
       NULL  /*DEPUS.CODIGO_CSE*/                                         PER_COM_MUN_DEP_COD_CSE,                   -- PER_MUN_DEP_COD_CSE,          -- 
       NULL  /*DEPUS.LATITUD*/                                            PER_COM_MUN_DEP_LATITUD,                   -- PER_MUN_DEP_LATITUD,          -- 
       NULL  /*DEPUS.LONGITUD*/                                           PER_COM_MUN_DEP_LONGITUD,                  -- PER_MUN_DEP_LONGITUD,         -- 
       NULL  /*DEPUS.PASIVO*/                                             PER_COM_MUN_DEP_PASIVO,                    -- PER_MUN_DEP_PASIVO,           -- 
       NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_COM_MUN_DEP_FEC_PASIVO,                -- PER_MUN_DEP_FEC_PASIVO,       -- 
       NULL  /*DEPUS.PAIS_ID*/                                            PER_COM_MUN_DEP_PAIS_ID,                   -- PER_MUNDEP_PAIS_ID,           -- 
       NULL  /*PAUS.NOMBRE*/                                              PER_COM_MUN_DEP_PAIS_NOMBRE,               -- PER_MUNDEP_PAIS_NOMBRE,       -- 
       NULL  /*PAUS.CODIGO*/                                              PER_COM_MUN_DEP_PAIS_COD,                  -- PER_MUNDEP_PAIS_COD,          -- 
       NULL  /*PAUS.CODIGO_ISO*/                                          PER_COM_MUN_DEP_PAIS_CODISO,               -- PER_MUNDEP_PAIS_CODISO,       -- 
       NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_COM_MUN_DEP_PAIS_CODALF,               -- PER_MUNDEP_PAIS_CODALF,       -- 
       NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_COM_MUN_DEP_PAIS_CODALFTR,             -- PER_MUNDEP_PAIS_CODALFTR,     -- 
       NULL  /*PAUS.PREFIJO_TELF*/                                        PER_COM_MUN_DEP_PAIS_PREFTELF,             -- PER_MUNDEP_PAIS_PREFTELF,     -- 
       NULL  /*PAUS.PASIVO*/                                              PER_COM_MUN_DEP_PAIS_PASIVO,               -- PER_MUNDEP_PAIS_PASIVO,       -- 
       NULL  /*PAUS.FECHA_PASIVO*/                                        PER_COM_MUN_DEP_PAIS_FECPASIVO,            -- PER_MUNDEP_PAIS_FECPASIVO,    -- 
       PERNOM.REGION_RESIDENCIA_ID                                        PER_COM_MUN_DEP_REG_ID,                    -- PER_MUNDEP_REG_ID,            -- 
       PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_COM_MUN_DEP_REG_NOMBRE,                -- PER_MUNDEP_REG_NOMBRE,        -- 
       NULL  /*REGUS.CODIGO*/                                             PER_COM_MUN_DEP_REG_CODIGO,                -- PER_MUNDEP_REG_CODIGO,        -- 
       NULL  /*REGUS.PASIVO*/                                             PER_COM_MUN_DEP_REG_PASIVO,                -- PER_MUNDEP_REG_PASIVO,        -- 
       NULL  /*REGUS.FECHA_PASIVO*/                                       PER_COM_MUN_DEP_REG_FEC_PASIVO,            -- PER_MUNDEP_REG_FEC_PASIVO,    -- 

       PERNOM.DISTRITO_RESIDENCIA_ID                                      PER_COM_DIS_ID,                            -- PERRES_DIS_ID,                -- 
       PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PER_COM_DIS_NOMBRE,                        -- PERRES_COMDIS_NOMBRE,         -- 
       NULL  /*DISUS.CODIGO*/                                             PER_COM_DIS_CODIGO,                        -- PERRES_COMDIS_CODIGO,         -- 
       NULL  /*DISUS.PASIVO*/                                             PER_COM_DIS_PASIVO,                        -- PERRES_COMDIS_PASIVO,         -- 
       NULL  /*DISUS.FECHA_PASIVO*/                                       PER_COM_DIS_FEC_PASIVO,                    -- PERRES_COMDIS_FEC_PASIVO,     -- 
       NULL  /*DISUS.MUNICIPIO_ID*/                                       PER_COM_DIS_MUN_ID,                        -- PERRES_COMDIS_MUN_ID,         -- 
       NULL  /*MUNUS1.NOMBRE*/                                            PER_COM_DIS_MUN_NOMBRE,                    -- PER_COMDIS_MUN_NOMBRE,        -- 
       NULL  /*MUNUS1.CODIGO*/                                            PER_COM_DIS_MUN_CODIGO,                    -- PER_COMDIS_MUN_CODIGO,        -- 
       NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COM_DIS_MUN_COD_CSE,                   -- PER_COMDIS_MUN_COD_CSE,       -- 
       NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COM_DIS_MUN_CODCSEREG,                 -- PER_COMDIS_MUN_CODCSEREG,     -- 
       NULL  /*MUNUS1.LATITUD*/                                           PER_COM_DIS_MUN_LATITUD,                   -- PER_COMDIS_MUN_LATITUD,       -- 
       NULL  /*MUNUS1.LONGITUD*/                                          PER_COM_DIS_MUN_LONGITUD,                  -- PER_COMDIS_MUN_LONGITUD,      -- 
       NULL  /*MUNUS1.PASIVO*/                                            PER_COM_DIS_MUN_PASIVO,                    -- PER_COMDIS_MUN_PASIVO,        -- 
       NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COM_DIS_MUN_FECPASIVO,                 -- PER_COMDIS_MUN_FECPASIVO,     -- 

       NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COM_DIS_MUN_DEP_ID,                    -- PER_COMDISMUN_DEP_ID,         -- 
       NULL  /*DEPUS1.NOMBRE*/                                            PER_COM_DIS_MUN_DEP_NOMBRE,                -- PER_COMDISMUN_DEP_NOMBRE,     -- 
       NULL  /*DEPUS1.CODIGO*/                                            PER_COM_DIS_MUN_DEP_COD,                   -- PER_COMDISMUN_DEP_COD,        -- 
       NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COM_DIS_MUN_DEP_CODISO,                -- PER_COMDISMUN_DEP_CODISO,     -- 
       NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COM_DIS_MUN_DEP_CODCSE,                -- PER_COMDISMUN_DEP_CODCSE,     -- 
       NULL  /*DEPUS1.LATITUD*/                                           PER_COM_DIS_MUN_DEP_LATITUD,               -- PER_COMDISMUN_DEP_LATITUD,    -- 
       NULL  /*DEPUS1.LONGITUD*/                                          PER_COM_DIS_MUN_DEP_LONGITUD,              -- PER_COMDISMUN_DEP_LONGITUD,   -- 
       NULL  /*DEPUS1.PASIVO*/                                            PER_COM_DIS_MUN_DEP_PASIVO,                -- PER_COMDISMUN_DEP_PASIVO,     -- 
       NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COM_DIS_MUN_DEP_FECPASIVO,             -- PER_COMDISMUN_DEP_FECPASIVO,  -- 
       NULL  /*DEPUS1.PAIS_ID*/                                           PER_COM_DIS_MUN_DEP_PA_ID,                 -- PER_COMDISMUN_DEP_PA_ID,      -- 
       NULL  /*PAUS1.NOMBRE*/                                             PER_COM_DIS_MUN_DEP_PA_NOMBRE,             -- PER_COMDISMUNDEP_PA_NOMBRE,   -- 
       NULL  /*PAUS1.CODIGO*/                                             PER_COM_DIS_MUN_DEP_PA_COD,                -- PER_COMDISMUNDEP_PA_COD,      -- 
       NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COM_DIS_MUN_DEP_PA_CODISO,             -- PER_COMDISMUNDEP_PA_CODISO,   -- 
       NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COM_DIS_MUN_DEP_PA_CODALFA,            -- PER_COMDISMUNDEP_PA_CODALFA,  -- 
       NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COM_DIS_MUN_DEP_PA_ALFTRES,            -- PER_COMDISMUNDEP_PA_ALFTRES,  -- 
       NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COM_DIS_MUN_DEP_PA_PREFTEL,            -- PER_COMDISMUNDEP_PA_PREFTEL,  -- 
       NULL  /*PAUS1.PASIVO*/                                             PER_COM_DIS_MUN_DEP_PA_PASIVO,             -- PER_COMDISMUNDEP_PA_PASIVO,   -- 
       NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COM_DIS_MUN_DEP_PA_FECPASI,            -- PER_COMDISMUNDEP_PA_FECPASI,  -- 
       NULL  /*DEPUS1.REGION_ID*/                                         PER_COM_DIS_MUN_DEP_REG_ID,                -- PER_COMDISMUNDEP_REG_ID,      -- 
       NULL  /*REGUS1.NOMBRE*/                                            PER_COM_DIS_MUN_DEP_REG_NOMBRE,            -- PER_COMDISMUNDEP_REG_NOMBRE,  -- 
       NULL  /*REGUS1.CODIGO*/                                            PER_COM_DIS_MUN_DEP_REG_COD,               -- PER_COMDISMUNDEP_REG_COD,     -- 
       NULL  /*REGUS1.PASIVO*/                                            PER_COM_DIS_MUN_DEP_REG_PASIVO,            -- PER_COMDISMUNDEP_REG_PASIVO,  -- 
       NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COM_DIS_MUN_DEP_REG_FECPAS,            -- PER_COMDISMUNDEP_REG_FECPAS,  -- 
       PERNOM.LOCALIDAD_ID                                                PER_COM_LOCALIDAD_ID,                      -- PERRES_LOCALIDAD_ID,          -- 
       PERNOM.LOCALIDAD_CODIGO                                            PER_COM_LOCALIDAD_CODIGO,                  -- CATPERLOCAL_CODIGO,           -- 
       PERNOM.LOCALIDAD_NOMBRE                                            PER_COM_LOCALIDAD_VALOR,                   -- CATPERLOCAL_VALOR,            -- 
       NULL  /*.DESCRIPCION*/                                             PER_COM_LOCALIDAD_DESC,                    -- CATPERLOCAL_DESCRIPCION,      -- 
       NULL  /*Dd.PASIVO*/                                                PER_COM_LOCALIDAD_PASIVO,                  -- CATPERLOCAL_PASIVO,           -- 
-----                                                                   
       A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
       CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
       CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
       CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
       CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
       A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
       CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
       CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
       CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
       CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
       ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
       ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
       CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
       CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
       CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
       CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
       ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
       CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
       CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
       CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
       CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
       ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
       ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
       A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
       RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
       CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
       CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
       CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
       CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
       RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
       CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
       CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
       CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
       CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
       RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
       RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
       CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
       CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
       CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
       CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
       RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
       RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
       RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
       RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
       RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
       RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
       RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
       RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
       RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
       RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
       RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
       RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
       RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
       RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
       RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
       RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
       RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
       RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
       A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
       CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
       CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
       CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
       CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
       A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
       A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
       A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
       A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
       A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
       A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
       A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
       A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
       A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
       A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
       A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
       CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
       CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
       CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
       CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
       A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
       CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
       CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
       CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
       CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
       CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
       CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
       CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
       CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
       ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
       ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
       ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
       DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
       DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
       DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
       DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
       LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
       LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
       LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
       CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
       CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
       CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
       CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
       DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
       DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
       DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
       DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
       DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
       DETPER.CODIGO                                                      DETPER_CODIGO,
       DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
       CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
       CATDETPER.VALOR                                                    CATDETPER_VALOR,              
       CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
       CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
       DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
       DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
       DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
       SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
       SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
       SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
       SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
       DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
       DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
       DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
       DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
       DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
       DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
       DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
       DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
       DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
       DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
       CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
       CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
       CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
       CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
       DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
       CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
       CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
       CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
       CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
       DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
       DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
       DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
       DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
       DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
       DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
       DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
       DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
       DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
       DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
       DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
       DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
       DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
       DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
       DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
       DETVACUSALUD.ENTIDAD_ADTVA_ID   DETVACUSALUD_US_ENTADMIN,
       -----
        DETVAC.ES_REFUERZO,
        DETVAC.CASO_EMBARAZO,
        DETVAC.REL_TIPO_VACUNA_EDAD_ID,
        DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
        DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE		
        ,TIENE_FRECUENCIA_ANUALES
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --   ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        LEFT JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		  ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID  

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
            AND CATPROG.CODIGO != 'PRO_VAC || 01'
         ORDER BY A.CONTROL_VACUNA_ID; 

--     DBMS_OUTPUT.PUT_LINE (vQuery);   
 

     RETURN vRegistro;
 END FN_OBT_CONTROL_TODOS;

 FUNCTION FN_OBT_DATOS_CONTROL(pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                               pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                               pPgnAct          IN NUMBER, 
                               pPgnTmn          IN NUMBER,
                               pTipoPaginacion  IN NUMBER) RETURN var_refcursor AS
 vDatos var_refcursor;
 BEGIN
    CASE
    WHEN (NVL (pControlVacunaId,0) > 0) AND (NVL(pExpedienteId,0) > 0) THEN
          vDatos := FN_OBT_X_ID_Y_EXPID (pControlVacunaId, pExpedienteId);
    WHEN NVL(pControlVacunaId,0) > 0 THEN
         vDatos := FN_OBT_X_ID (pControlVacunaId);
    WHEN NVL(pExpedienteId,0) > 0 THEN
         DBMS_OUTPUT.PUT_LINE(' FN_OBT_X_EXPID (pExpedienteId)');
         vDatos := FN_OBT_X_EXPID (pExpedienteId);
         
    ELSE 
         vDatos := FN_OBT_CONTROL_TODOS (pPgnAct, pPgnTmn);
    END CASE;

 RETURN vDatos;

 END FN_OBT_DATOS_CONTROL;

PROCEDURE PR_C_CONTROL_VACUNA (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                 pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                 pPgnAct          IN NUMBER,
                                 pPgnTmn          IN NUMBER,
                                 pRegistro        OUT var_refcursor,
                                 pResultado       OUT VARCHAR2,    
                                 pMsgError        OUT VARCHAR2) IS
  vTipoPaginacion NUMBER; 
  vFirma VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_C_CONTROL_VACUNA => ';                      
  BEGIN
      CASE
      WHEN (FN_VALIDA_CONTROL_VACUNA (pControlVacunaId, pExpedienteId, vTipoPaginacion)) = TRUE THEN 
            pRegistro := FN_OBT_DATOS_CONTROL(pControlVacunaId, pExpedienteId, vTipoPaginacion,
                                              pPgnAct, pPgnTmn);
      ELSE 
          CASE 
          WHEN (NVL(pControlVacunaId,0) > 0 AND
                NVL(pExpedienteId,0) > 0) THEN
                pResultado := 'No se encontraron registros de control vacuna con los parámetros [[Id: '||pControlVacunaId||'] y [ExpedienteId: '||pExpedienteId||']';
                RAISE eRegistroNoExiste;
          WHEN NVL(pControlVacunaId,0) > 0 THEN
               pResultado := 'No se encontraron registros de control vacuna relacionadas al  [Id: '||pControlVacunaId||']';
               RAISE eRegistroNoExiste;
          WHEN NVL(pExpedienteId,0) > 0 THEN
               pResultado := 'No se encontraron registros de control vacuna relacionadas al  [ExpedienteId: '||pExpedienteId||']';
               RAISE eRegistroNoExiste; 
          ELSE
              pResultado := 'No se encontraron control de vacunas registradas';
              RAISE eRegistroNoExiste;             
          END CASE;
      END CASE;
      CASE
      WHEN NVL(pControlVacunaId,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con exito para el id: '||pControlVacunaId;
      WHEN NVL(pExpedienteId,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con exito para el Expediente Id: '||pExpedienteId;
      ELSE
         pResultado := 'Busqueda de registros realizada con éxito';
      END CASE;    
  EXCEPTION
  WHEN eparametrosinvalidos THEN
       pResultado := pResultado;
       pMsgError  := vFirma ||'Parametros invalidos: ' || pResultado;
  WHEN eRegistroNoExiste THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;
  WHEN OTHERS THEN
       pResultado := ' Hubo un error inesperado en la Base de Datos. Id de consultas: [ControlId: '||pControlVacunaId||'] o [ExpedienteId: '||pExpedienteId||']';
       pMsgError  := vFirma ||pResultado||' - '||SQLERRM;   
  END PR_C_CONTROL_VACUNA;

/*  
PROCEDURE ELIMINAR_VACUNACION_X_CONTROL_PERIODO(
    pControlVacunaId IN NUMBER,
    pNoEliminados OUT NUMBER
) AS
BEGIN
    -- Borrar los registros válidos
    DELETE FROM SIPAI.SIPAI_DET_VACUNACION_SECTOR
    WHERE DET_VACUNACION_ID IN (
        SELECT DVS.DET_VACUNACION_ID
        FROM SIPAI_DET_VACUNACION DVS
        WHERE DVS.CONTROL_VACUNA_ID = pControlVacunaId
          AND EXISTS (
              SELECT 1
              FROM SIPAI_CTRL_PERIODO_VACUNACION P
              WHERE P.ES_PERIODO_VIGENTE = 1
                AND DVS.FECHA_VACUNACION BETWEEN P.FECHA_INICIAL AND P.FECHA_FINAL
          )
    );

    -- Contar los no eliminados por estar fuera de período
    SELECT COUNT(*)
    INTO pNoEliminados
    FROM SIPAI_DET_VACUNACION DVS
    WHERE DVS.CONTROL_VACUNA_ID = pControlVacunaId
      AND NOT EXISTS (
          SELECT 1
          FROM SIPAI_CTRL_PERIODO_VACUNACION P
          WHERE P.ES_PERIODO_VIGENTE = 1
            AND DVS.FECHA_VACUNACION BETWEEN P.FECHA_INICIAL AND P.FECHA_FINAL
      );

EXCEPTION
    WHEN OTHERS THEN
        pNoEliminados := -1;
        RAISE;
END;
  
*/
  

 PROCEDURE PR_U_CONTROL_VACUNA (pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                 pExpedienteId     IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                 pProgVacuna       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.PROGRAMA_VACUNA_ID%TYPE,
                                 pGrpPrioridad     IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                 pTipVacuna        IN SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE,
                                 pCantVacunaApli   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_APLICADA%TYPE,
                                 pCantVacunaProg   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_PROGRAMADA%TYPE,
                                 pFechaPrimVacuna  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_INICIO_VACUNA%TYPE,
                                 pFechaUltVacuna   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_FIN_VACUNA%TYPE,
                                 pEstadoRegistroId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.ESTADO_REGISTRO_ID%TYPE,
                                 pUsuario          IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,
                                 pResultado        OUT VARCHAR2,
                                 pMsgError         OUT VARCHAR2) IS
  vFirma   VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_U_CONTROL_VACUNA => ';  
  vContarEsavi NUMBER;
  vExistePeriodoCerrado NUMBER; 
  
  BEGIN
      CASE
      WHEN pEstadoRegistroId = vGLOBAL_ESTADO_PASIVO THEN       
          <<PasivaRegistro>>
          BEGIN
          --ANTES DE BORRAR VERIFICAR SI TIENE ESAVI 
         -- SIPAI_ESAVI_DET_VACUNAS
          -- IMPLEMENTAR BORRADO FISICO  ELIMINAR LOS DETALLES Y LOS DETALLES SECTORES DEL CONTROL

          SELECT COUNT(*)  
          INTO vContarEsavi 
          FROM SIPAI_ESAVI_DET_VACUNAS
          WHERE   CONTROL_VACUNA_ID=pControlVacunaId
          AND     ESTADO_REGISTRO_ID=6869;

          IF vContarEsavi > 0 THEN 
               pResultado := 'No se puede eliminar el registros de control de vacuna por que tiene relacion con la ficha ESAVI';   
              RAISE  eParametrosInvalidos;
          END IF;
          
        -- Verificar si el master control a eliminar esta en períodos cerrados
        SELECT COUNT(*)
        INTO vExistePeriodoCerrado
        FROM SIPAI_DET_VACUNACION DVS
        WHERE DVS.CONTROL_VACUNA_ID = pControlVacunaId
        AND   DVS.ESTADO_REGISTRO_ID=6869 --Solo estado activos se implemto borrado logico
          AND NOT EXISTS (
              SELECT 1
              FROM SIPAI_CTRL_PERIODO_VACUNACION P
              WHERE P.ES_PERIODO_VIGENTE = 1
                AND DVS.FECHA_VACUNACION BETWEEN P.FECHA_INICIAL AND P.FECHA_FINAL
          );

           -- Si hay registros en período cerrado, no permitir eliminar
            IF vExistePeriodoCerrado > 0 THEN
                pResultado := 'No se puede eliminar el registros de control de vacuna por que existen registros en períodos cerrados. ';
                RAISE  eParametrosInvalidos;
            
            END IF;
          
          --Proceder a borrar o pasivar
          
               /*Quitar el borrado logico del master
          
                  DELETE SIPAI.SIPAI_DET_VACUNACION_SECTOR
                  WHERE  DET_VACUNACION_ID IN(SELECT DET_VACUNACION_ID 
                                              FROM SIPAI_DET_VACUNACION
                                              WHERE CONTROL_VACUNA_ID = pControlVacunaId
                                              );

                    DELETE  SIPAI.SIPAI_DET_VACUNACION  
                    WHERE   CONTROL_VACUNA_ID = pControlVacunaId;

                    DELETE  SIPAI.SIPAI_MST_CONTROL_VACUNA
                    WHERE   CONTROL_VACUNA_ID = pControlVacunaId; 
                    
                    
                */
                
                --Borrado logico  
                UPDATE  SIPAI_DET_VACUNACION
                SET     ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ELIMINADO,
                        USUARIO_PASIVA       = pUsuario,
                        FECHA_PASIVO         =SYSDATE,     
                        USUARIO_MODIFICACION =pUsuario,
                        FECHA_MODIFICACION   =SYSDATE 
                WHERE   CONTROL_VACUNA_ID = pControlVacunaId;

                 UPDATE  SIPAI_MST_CONTROL_VACUNA
                 SET     ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ELIMINADO,
                         USUARIO_PASIVA       = pUsuario,
                         FECHA_PASIVO         =SYSDATE,     
                         USUARIO_MODIFICACION =pUsuario,
                         FECHA_MODIFICACION   =SYSDATE       
                WHERE   CONTROL_VACUNA_ID = pControlVacunaId;

                       --Eliminar las proximas citas generadas en el expediente de este detalle 
                    DELETE  SIPAI.SIPAI_DET_PROXIMA_CITA WHERE EXPEDIENTE_ID=PExpedienteId;
                     --Generar de nuevo las citas del registro al ultimo registro.
                     PKG_SIPAI_UTILITARIOS.PR_REGISTRO_DET_ROXIMA_CITA(pExpedienteId,pResultado,pMsgError);

                     pResultado := 'El registro se elimino correctamente';   
         
          END PasivaRegistro;


       WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN
          <<ActivarRegistro>>
          BEGIN
             UPDATE SIPAI.SIPAI_MST_CONTROL_VACUNA
                SET ESTADO_REGISTRO_ID   = pEstadoRegistroId, 
                    USUARIO_MODIFICACION = pUsuario,    
                    USUARIO_PASIVA       = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN USUARIO_PASIVA IS NULL THEN pUsuario
                                           ELSE USUARIO_PASIVA
                                           END,    
                    FECHA_PASIVO         = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN FECHA_PASIVO IS NULL THEN CURRENT_TIMESTAMP
                                           ELSE FECHA_PASIVO
                                           END
              WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 
          END ActivarRegistro;
        ELSE 
          <<ActualizarRegistros>>
          BEGIN
             UPDATE SIPAI.SIPAI_MST_CONTROL_VACUNA
                SET PROGRAMA_VACUNA_ID         = NVL(pProgVacuna,PROGRAMA_VACUNA_ID),
                    GRUPO_PRIORIDAD_ID         = NVL(pGrpPrioridad,GRUPO_PRIORIDAD_ID),
                    TIPO_VACUNA_ID             = NVL(pTipVacuna,TIPO_VACUNA_ID),
                    CANTIDAD_VACUNA_APLICADA   = NVL(pCantVacunaApli,CANTIDAD_VACUNA_APLICADA),
                    CANTIDAD_VACUNA_PROGRAMADA = NVL(pCantVacunaProg,CANTIDAD_VACUNA_PROGRAMADA),
                    FECHA_INICIO_VACUNA        = NVL(pFechaPrimVacuna,FECHA_INICIO_VACUNA),
                    FECHA_FIN_VACUNA           = NVL(pFechaUltVacuna,FECHA_FIN_VACUNA), 
                    USUARIO_MODIFICACION       = pUsuario    
              WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 
          END ActualizarRegistros;
        END CASE;
  EXCEPTION

   WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;

  WHEN OTHERS THEN
       pResultado := 'Error no controlado';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;   
  END PR_U_CONTROL_VACUNA;


--PROCEDURE CRUD REGISTRO NOMINAL
PROCEDURE SIPAI_CRUD_CONTROL_VACUNA (pControlVacunaId    IN OUT SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                       pExpedienteId       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pProgVacuna         IN SIPAI.SIPAI_MST_CONTROL_VACUNA.PROGRAMA_VACUNA_ID%TYPE,
                                       pGrpPrioridad       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                       pEnfCronicaId       IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,
                                       pTipVacuna          IN SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE,
                                       pCantVacunaApli     IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_APLICADA%TYPE,
                                       pCantVacunaProg     IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_PROGRAMADA%TYPE,
                                       pFechaPrimVacuna    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_INICIO_VACUNA%TYPE,
                                       pFechaUltVacuna     IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_FIN_VACUNA%TYPE,
                                       pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                       pHrVacunacion       IN SIPAI.SIPAI_DET_VACUNACION.HORA_VACUNACION%TYPE,
                                       pDetVacLoteFecvenId IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE,                          
									   pPerVacunaId        IN SIPAI.SIPAI_DET_VACUNACION.PERSONAL_VACUNA_ID%TYPE,
                                       pViaAdmin           IN SIPAI.SIPAI_DET_VACUNACION.VIA_ADMINISTRACION_ID%TYPE,
                                       ------NUEVOS CAMPOS-------------------------------------------------------------
									   pObservacion		    IN SIPAI.SIPAI_DET_VACUNACION.OBSERVACION%TYPE,
									   pFechaProximaVacuna  IN SIPAI.SIPAI_DET_VACUNACION.FECHA_PROXIMA_VACUNA%TYPE, 
									   pNoAplicada		    IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
									   pMotivoNoAplicada    IN SIPAI.SIPAI_DET_VACUNACION.MOTIVO_NO_APLICADA%TYPE,  
									   pTipoEstrategia	    IN SIPAI.SIPAI_DET_VACUNACION.TIPO_ESTRATEGIA_ID%TYPE,
									   pEsRefuerzo           IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,	
                                       pCasoEmbarazo         IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,
									   pIdRelTipoVacunaEdad    IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,	
									   pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,

									  ------------------------------------------------------------------------------------ 
									   pUniSaludId         IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                       pSistemaId          IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                       pUsuario            IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                       pAccionEstado       IN VARCHAR2,
                                       --------------Datos de Sectorizacion Residencia-----------------
                                       pSectorResidenciaNombre	                IN   	VARCHAR2,
                                       pSectorResidenciaId	                    IN   	NUMBER, 
                                       pUnidadSaludResidenciaId	                IN   	NUMBER, 
                                       pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaResidenciaId       IN   	NUMBER, 
                                       pEntidadAdministrativaResidenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudResidencia	                IN   	VARCHAR2,
                                       pSectorLongitudResidencia	            IN   	VARCHAR2,
                                       --------------Datos de Sectorizacion Ocurrencia-----------------	
                                       pSectorOcurrenciaId	                    IN   	NUMBER, 
                                       pSectorOcurrenciaNombre	                IN   	VARCHAR2,
                                       pUnidadSaludOcurrenciaId	                IN   	NUMBER, 
                                       pUnidadSaludOcurrenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaOcurrenciaId	    IN   	NUMBER, 
                                       pEntidadAdministrativaOcurrenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudOcurrencia	                IN   	VARCHAR2,
                                       pSectorLongitudOcurrencia	            IN   	VARCHAR2,
                                       --2024 Agregar Comunidad-----------------------------------------
                                       pComunidadResidenciaId                   IN   	NUMBER,  
                                       pComunidadResidenciaNombre               IN   	VARCHAR2,
                                       pComunidadoOcurrenciaId                  IN   	NUMBER,  
                                       pComunidadOcurrrenciaNombre              IN   	VARCHAR2,
                                       pEsAplicadaNacional                      IN      NUMBER,   
                                       -----------------------------------------------------------------
                                       pTipoAccion         IN VARCHAR2,
                                       ----------------Parametros de Salidas ---------------------------
                                       pRegistro           OUT var_refcursor,
                                       pResultado          OUT VARCHAR2,
                                       pMsgError            OUT VARCHAR2) IS

  vFirma            VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.SIPAI_CRUD_CONTROL_VACUNA => '; 
  vRegistro         var_refcursor;   
  vDetVacunacionId  SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE;   
  vEstadoRegistroId SIPAI.SIPAI_DET_VACUNACION.ESTADO_REGISTRO_ID%TYPE;   
  vFechaPrimVacuna  SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_INICIO_VACUNA%TYPE;
  vFechaUltVacuna   SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_FIN_VACUNA%TYPE;
  vNomPrograma      CATALOGOS.SBC_CAT_CATALOGOS.VALOR%TYPE;
  vTipoPaginacion   NUMBER;
  vTieneFrecuenciaAnual NUMBER;

  vPgnAct NUMBER;
  vPgnTmn NUMBER;  
  vDetPerXEnfCronId SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE;  
 -- pEnfCronicaId     SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE;   
 vContador PLS_INTEGER;

  BEGIN
      CASE
      WHEN pTipoAccion IS NULL THEN 
           pResultado := 'El párametro pTipoOperacion no puede venir NULL';
           pMsgError  := pResultado;
           RAISE eParametroNull;
      ELSE NULL;
      END CASE;
      CASE
      WHEN pTipoAccion = kINSERT THEN
           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;
           CASE
           WHEN NVL(pSistemaId,0) = 0  THEN
              pResultado := 'El Id sistema no puede venir nulo';
              pMsgError  := pResultado;
              RAISE eParametroNull;                  
           ELSE NULL;
           END CASE;
           dbms_output.put_line ('Sale de validar sistema');
           CASE
           WHEN NVL(pExpedienteId,0) = 0  THEN
                pResultado := 'El tipo de persona no puede venir nulo';
                pMsgError  := pResultado;
                RAISE eParametroNull;                  
           ELSE 
               CASE
               WHEN (FN_VALIDA_EXPEDIENTE_ID (pExpedienteId)) = FALSE THEN
                    pResultado := 'El expedienteId no es un registro valido. [pExpedienteId: '||pExpedienteId||']';
                    pMsgError  := pResultado;  
                    RAISE eRegistroExiste;
               ELSE NULL;
               END CASE;
           END CASE;


         --POST PROD VALIDAR UNICIDAD DE VACUNA Y NUEMERO DE DOSIS PARA QUE NO SE DUPLIQUE EN CASO DE SE PEGUE UNA SESSION DE USUARIOS

          --Validar unicidad tomando en cuenta la frecuencia anual puede repetirse
         /* SELECT FRECUENCIA_ANUAL INTO vTieneFrecuenciaAnual
          FROM SIPAI_REL_TIPO_VACUNA_EDAD 
          WHERE REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad AND ESTADO_REGISTRO_ID=6869;
          */
           SELECT COUNT(*) 
           INTO   vContador
           FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA      MST
           JOIN   SIPAI.SIPAI_DET_VACUNACION          DETVAC    ON  MST.CONTROL_VACUNA_ID = DETVAC.CONTROL_VACUNA_ID 
           WHERE  MST.EXPEDIENTE_ID=pExpedienteId
           AND    DETVAC.REL_TIPO_VACUNA_ID=pTipVacuna
           AND    DETVAC.REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad
           AND    DETVAC.ESTADO_REGISTRO_ID=6869
           AND    DETVAC.FECHA_VACUNACION=pFecVacuna
           AND    TRUNC(DETVAC.FECHA_REGISTRO)=TRUNC(SYSDATE); 

           IF  vContador >0  THEN
                pResultado := 'La vacuna y dosis  ya existe' ;
                pMsgError  := pResultado;
                RAISE eParametroNull;  
           END IF;



           CASE
           WHEN (FN_VAL_REGISTRO_ACTIVO (pExpedienteId, pProgVacuna)= TRUE) THEN
                 vNomPrograma := FN_OBT_NOM_PROGRAMA_VACUNA (pProgVacuna);
                 pResultado := 'Ya existe un registro en estado activo para el. [pExpedienteId: '||pExpedienteId||'] y el Programa : ['||pProgVacuna||'- '||vNomPrograma||']';
                 pMsgError  := pResultado;
                -- RAISE eRegistroExiste;
           ELSE NULL;
           END CASE;


               PR_I_CONTROL_VACUNA (pControlVacunaId => pControlVacunaId,
                                    pExpedienteId    => pExpedienteId,   
                                    pProgVacuna      => pProgVacuna,     
                                    pGrpPrioridad    => pGrpPrioridad,   
                                    pTipVacuna       => pTipVacuna,      
                                    pCantVacunaApli  => pCantVacunaApli, 
                                    pCantVacunaProg  => pCantVacunaProg,
                                    pUniSaludId      => pUniSaludId,
                                    pSistemaId       => pSistemaId, 
                                    pUsuario         => pUsuario,        
                                    pResultado       => pResultado,      
                                    pMsgError        => pMsgError);  
                IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                   RAISE eSalidaConError;
                END IF; 
           CASE -- Validamos que el grupo prioridad sea crónico.
           WHEN (FN_VALIDA_ES_CRONICO (pGrpPrioridad) = TRUE AND
                 NVL(pEnfCronicaId,0) > 0) THEN
                 DBMS_OUTPUT.PUT_LINE ('Llama a crud enfermedades crónicas');
                 SIPAI_CRUD_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => vDetPerXEnfCronId,  
                                                pControlVacunaId  => pControlVacunaId,
                                                pExpedienteId     => pExpedienteId,     
                                                pEnfCronicaId     => pEnfCronicaId,     
                                                pUsuario          => pUsuario,          
                                                pAccionEstado     => pAccionEstado,
                                                pTipoAccion       => kINSERT,    
                                                pRegistro         => vRegistro,         
                                                pResultado        => pResultado,        
                                                pMsgError         => pMsgError);        
                 IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                    RAISE eSalidaConError;
                 END IF;            

           ELSE NULL;
           END CASE;                                                                      
           CASE
           WHEN NVL(pControlVacunaId,0) > 0 THEN
                CASE
                WHEN pFecVacuna IS NOT NULL THEN
                     <<CrearDetalleVacuna>>
                     BEGIN

                        SIPAI_CRUD_DET_VACUNACION (pDetVacunacionId => vDetVacunacionId,  
                                                   pControlVacunaId => pControlVacunaId, 
                                                   pFecVacuna       => pFecVacuna,       
                                                   pPerVacunaId     => pPerVacunaId,     
                                                   pViaAdmin        => pViaAdmin,        
                                                   pHrVacunacion    => pHrVacunacion,    
                                                   pDetVacLoteFecvenId => pDetVacLoteFecvenId,
												   ------NUEVOS CAMPOS-------------------------------------------------------------
												   pObservacion		 => pObservacion,
												   pFechaProximaVacuna => pFechaProximaVacuna, 
												   pNoAplicada		 => pNoAplicada, 
												   pMotivoNoAplicada   => pMotivoNoAplicada,  
												   pTipoEstrategia	 => pTipoEstrategia,

												   pEsRefuerzo          => pEsRefuerzo,
                                                   pCasoEmbarazo        => pCasoEmbarazo,
												   pIdRelTipoVacunaEdad => pIdRelTipoVacunaEdad,
												   pUniSaludActualizacionId  => pUniSaludActualizacionId,

												  ------------------------------------------------------------------------------------            												   
                                                   pUniSaludId      => pUniSaludId,      
                                                   pSistemaId       => pSistemaId,       
                                                   pUsuario         => pUsuario,         
                                                   pAccionEstado    => pAccionEstado,
                                                   --sectores por residencia
                                                    pSectorResidenciaNombre	      => pSectorResidenciaNombre,
                                                    pSectorResidenciaId	          => pSectorResidenciaId,
                                                    pUnidadSaludResidenciaId	  => pUnidadSaludResidenciaId,
                                                    pUnidadSaludResidenciaNombre  => pUnidadSaludResidenciaNombre,
                                                    pEntidadAdministrativaResidenciaId	     =>	pEntidadAdministrativaResidenciaId,
                                                    pEntidadAdministrativaResidenciaNombre	 =>	pEntidadAdministrativaResidenciaNombre,
                                                    pSectorLatitudResidencia	             =>	pSectorLatitudResidencia,
                                                    pSectorLongitudResidencia	             =>	pSectorLongitudResidencia,
                                                    --sectores por ocurrencia
                                                    pSectorOcurrenciaId	                     =>	pSectorOcurrenciaId,
                                                    pSectorOcurrenciaNombre	                 =>	pSectorOcurrenciaNombre,
                                                    pUnidadSaludOcurrenciaId	             =>	pUnidadSaludOcurrenciaId,
                                                    pUnidadSaludOcurrenciaNombre	         =>	pUnidadSaludOcurrenciaNombre,
                                                    pEntidadAdministrativaOcurrenciaId	     =>	pEntidadAdministrativaOcurrenciaId,
                                                    pEntidadAdministrativaOcurrenciaNombre	 =>	pEntidadAdministrativaOcurrenciaNombre,
                                                    pSectorLatitudOcurrencia	             =>	pSectorLatitudOcurrencia,
                                                    pSectorLongitudOcurrencia	             =>	pSectorLongitudOcurrencia,
                                                    -----------------------------------------------------------------------
                                                    pComunidadResidenciaId                   => pComunidadResidenciaId,  
                                                    pComunidadResidenciaNombre               => pComunidadResidenciaNombre,
                                                    pComunidadoOcurrenciaId                  => pComunidadoOcurrenciaId,  
                                                    pComunidadOcurrrenciaNombre              => pComunidadOcurrrenciaNombre,
                                                    pEsAplicadaNacional                      => pEsAplicadaNacional,
                                                    pGrpPrioridad                            => pGrpPrioridad,
                                                    -----------------------------------------------------------------------
                                                    pTipoAccion      => kINSERT,
                                                    -----------------------------------------------------------------------
                                                    pRegistro        => vRegistro,        
                                                    pResultado       => pResultado,       
                                                    pMsgError        => pMsgError);    

                                                      DBMS_OUTPUT.PUT_LINE('fin de crear detalle = ');
                       IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                          RAISE eSalidaConError;
                       END IF; 
                     END CrearDetalleVacuna;
                ELSE NULL;
                END CASE;
           ELSE NULL;
           END CASE;
           CASE
           WHEN (NVL(pControlVacunaId,0) > 0 OR
                 NVL(pExpedienteId,0) > 0) THEN
           PR_C_CONTROL_VACUNA (pControlVacunaId => pControlVacunaId,  
                                pExpedienteId    => pExpedienteId,
                                pPgnAct          => vPgnAct,
                                pPgnTmn          => vPgnTmn,
                                pRegistro        => pRegistro,   
                                pResultado       => pResultado,       
                                pMsgError        => pMsgError);
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;
           pResultado := 'Registro creado exitosamente';             
           ELSE NULL;
           END CASE;
      WHEN pTipoAccion = kUPDATE THEN
           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;
           CASE
           WHEN NVL(pControlVacunaId,0) = 0 THEN
                    pResultado := 'IdControl no pueden venir NULL';
                    pMsgError  := pResultado;
                    RAISE eParametroNull;
           ELSE NULL; 
           END CASE;            
           CASE
           WHEN pAccionEstado = 0 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_ACTIVO;
           WHEN pAccionEstado = 1 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_PASIVO;
           ELSE NULL;
           END CASE; 
           PR_U_CONTROL_VACUNA (pControlVacunaId  => pControlVacunaId,  
                                pExpedienteId     => pExpedienteId,    
                                pProgVacuna       => pProgVacuna,      
                                pGrpPrioridad     => pGrpPrioridad,    
                                pTipVacuna        => pTipVacuna,       
                                pCantVacunaApli   => pCantVacunaApli,  
                                pCantVacunaProg   => pCantVacunaProg,  
                                pFechaPrimVacuna  => pFechaPrimVacuna,          -- vFechaPrimVacuna, 
                                pFechaUltVacuna   => pFechaUltVacuna,           -- vFechaUltVacuna,   
                                pEstadoRegistroId => vEstadoRegistroId,
                                pUsuario          => pUsuario,         
                                pResultado        => pResultado,       
                                pMsgError         => pMsgError) ;       
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF; 
           CASE
           WHEN ((NVL(pControlVacunaId,0) > 0 OR NVL(pExpedienteId,0) > 0) AND pAccionEstado = 0) THEN	   

           PR_C_CONTROL_VACUNA (pControlVacunaId => pControlVacunaId,  
                                pExpedienteId    => pExpedienteId,
                                pPgnAct          => vPgnAct,
                                pPgnTmn          => vPgnTmn,
                                pRegistro        => pRegistro,   
                                pResultado       => pResultado,       
                                pMsgError        => pMsgError);
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;
           pResultado := 'Registro actualizado exitosamente';             
           ELSE NULL;
           END CASE;           
      WHEN pTipoAccion = kCONSULTAR THEN

	    --Verificar que control vacuna esta activo con uno o mas detalle
		   --IF FN_VALIDAR_MASTER_PASIVADO(pControlVacunaId pExpedienteId, vTipoPaginacion)THEN
		   IF FN_VALIDA_CONTROL_VACUNA (pControlVacunaId, pExpedienteId, vTipoPaginacion)=TRUE THEN 
           PR_C_CONTROL_VACUNA (pControlVacunaId => pControlVacunaId,  
                                pExpedienteId    => pExpedienteId,
                                pPgnAct          => vPgnAct,
                                pPgnTmn          => vPgnTmn,
                                pRegistro        => pRegistro,   
                                pResultado       => pResultado,       
                                pMsgError        => pMsgError);								
			END IF;

           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF; 
           pResultado := 'Consulta realizada con éxito';                               
      WHEN pTipoAccion = kDelete THEN
           NULL;
      ELSE NULL;
      END CASE;
      EXCEPTION
      WHEN eUpdateInvalido THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;      
      WHEN eParametroNull THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroNoExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;                       
      WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;
      WHEN eSalidaConError THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;  --vMsgError;
      WHEN OTHERS THEN
           pResultado := 'Error no controlado';
           pMsgError  := vFirma||pResultado||' - fecha ultima: '||pFechaUltVacuna||' - '||SQLERRM;       
  END SIPAI_CRUD_CONTROL_VACUNA; 

  FUNCTION FN_VAL_EXPID_ENFERMEDAD (pExpedienteId IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE, 
                                    pEnfCronicaId IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE) RETURN BOOLEAN AS
  vConteo SIMPLE_INTEGER := 0;
  vExiste BOOLEAN := FALSE;
  BEGIN
      SELECT COUNT (1)
        INTO vConteo
        FROM SIPAI.SIPAI_PER_VACUNADA_ENF_CRON
       WHERE EXPEDIENTE_ID = pExpedienteId AND
             ENF_CRONICA_ID = pEnfCronicaId;
       CASE
       WHEN vConteo > 0 THEN
            vExiste := TRUE;
       ELSE NULL;
       END CASE;
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_VAL_EXPID_ENFERMEDAD; 

   PROCEDURE PR_I_PER_X_ENF_CRONICAS (pDetPerXEnfCronId   OUT SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE,
                                     pExpedienteId       IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,       
                                     pEnfCronicaId       IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,            
                                     pUsuario            IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,    
                                     pRegistro           OUT var_refcursor,
                                     pResultado          OUT VARCHAR2,
                                     pMsgError           OUT VARCHAR2) IS
  vFirma            VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_I_PER_X_ENF_CRONICAS => '; 
  BEGIN
       CASE
       WHEN (FN_VAL_EXPID_ENFERMEDAD (pExpedienteId, pEnfCronicaId)) != TRUE THEN
       BEGIN
       INSERT INTO SIPAI.SIPAI_PER_VACUNADA_ENF_CRON (EXPEDIENTE_ID,
                                                      ENF_CRONICA_ID,
                                                      ESTADO_REGISTRO_ID,
                                                      USUARIO_REGISTRO)
                                              VALUES (pExpedienteId,
                                                      pEnfCronicaId,
                                                      vGLOBAL_ESTADO_ACTIVO,
                                                      pUsuario)
                                              RETURNING DET_PER_X_ENFCRON_ID INTO pDetPerXEnfCronId;
                                              pResultado := 'Registro creado con exito';
       END;
       ELSE NULL;
       END CASE; 
  EXCEPTION
  WHEN OTHERS THEN
       pResultado := 'Error al insertar enfermedad crónica';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;                                                     
  END PR_I_PER_X_ENF_CRONICAS; 

FUNCTION FN_VALIDA_PER_X_ENFRCRONICAS (pDetPerXEnfCronId IN SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE, 
                                         pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                         pExpedienteId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,   
                                         pEnfCronicaId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE) RETURN BOOLEAN AS
  vExiste BOOLEAN := FALSE;
  vConteo SIMPLE_INTEGER := 0;
  BEGIN
   CASE 
   WHEN (NVL(pControlVacunaId,0) > 0 AND
         NVL(pExpedienteId,0) > 0) THEN
            BEGIN
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
                ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
                   B.EXPEDIENTE_ID = pExpedienteId
             WHERE CONTROL_VACUNA_ID = pControlVacunaId;
            END;         
   WHEN NVL(pControlVacunaId,0) > 0 THEN
            BEGIN
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
                ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
                   B.DET_PER_X_ENFCRON_ID > 0
             WHERE CONTROL_VACUNA_ID = pControlVacunaId;
            END;  
   WHEN NVL(pExpedienteId,0) > 0 THEN
            BEGIN
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
                ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
                   B.EXPEDIENTE_ID = pExpedienteId AND
                   B.DET_PER_X_ENFCRON_ID > 0
             WHERE A.CONTROL_VACUNA_ID > 0;                   
            END;  
   WHEN NVL(pDetPerXEnfCronId,0) > 0 THEN
        BEGIN
        SELECT COUNT (1)
          INTO vConteo
          FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
          JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
            ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
               DET_PER_X_ENFCRON_ID = pDetPerXEnfCronId
         WHERE A.CONTROL_VACUNA_ID > 0;
        END;
   WHEN NVL(pEnfCronicaId,0) > 0 THEN
            BEGIN
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
                ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
                   B.ENF_CRONICA_ID = pEnfCronicaId AND
                   B.DET_PER_X_ENFCRON_ID > 0
             WHERE A.CONTROL_VACUNA_ID > 0;
            END;           
   ELSE 
            BEGIN
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON B
                ON B.EXPEDIENTE_ID = A.EXPEDIENTE_ID AND
                   B.DET_PER_X_ENFCRON_ID > 0
             WHERE A.CONTROL_VACUNA_ID > 0;
            END; 
   END CASE;  
   CASE
   WHEN vConteo > 0 THEN
        vExiste := TRUE;
   ELSE NULL;
   END CASE;
  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_VALIDA_PER_X_ENFRCRONICAS;

 FUNCTION FN_OBT_PER_ENFER_ID (pDetPerXEnfCronId IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
               -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
               ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID    DETVACUSALUD_US_ENTADMIN,                                  
			    -----
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
               RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         AND ENFERCRONI.DET_PER_X_ENFCRON_ID = pDetPerXEnfCronId
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		  ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID  

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO		 
         ORDER BY A.CONTROL_VACUNA_ID;    

--    DBMS_OUTPUT.PUT_LINE (vQuery);   
--    DBMS_OUTPUT.PUT_LINE (vQuery1);  
   RETURN vRegistro;
  END FN_OBT_PER_ENFER_ID; 

  FUNCTION FN_OBT_PER_ENFER_CTRL_EXP_ID (pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                         pExpedienteId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,
     		  -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID DETVACUSALUD_US_ENTADMIN,
			   -----
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
                RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  JOIN CATALOGOS.SBC_MST_PERSONAS PER
      --    ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
      --    ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
      --    ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         AND ENFERCRONI.EXPEDIENTE_ID = pExpedienteId          
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		  ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID  

    WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

--    DBMS_OUTPUT.PUT_LINE (vQuery);   
--    DBMS_OUTPUT.PUT_LINE (vQuery1);  
   RETURN vRegistro;
  END FN_OBT_PER_ENFER_CTRL_EXP_ID; 

  FUNCTION FN_OBT_PER_ENFER_CTRL_ID (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
				-----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID    DETVACUSALUD_US_ENTADMIN,  
			    -------
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
               RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  JOIN CATALOGOS.SBC_MST_PERSONAS PER
      --    ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
      --    ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
      --    ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	  

    WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 
--    DBMS_OUTPUT.PUT_LINE (vQuery);   
--    DBMS_OUTPUT.PUT_LINE (vQuery1);  

   RETURN vRegistro;
  END FN_OBT_PER_ENFER_CTRL_ID; 


  FUNCTION FN_OBT_PER_ENFER_EXP_ID (pExpedienteId IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,  
			     -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID    DETVACUSALUD_US_ENTADMIN,
			    ----
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
                RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  JOIN CATALOGOS.SBC_MST_PERSONAS PER
      --    ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
      --    ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
      --    ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         AND ENFERCRONI.EXPEDIENTE_ID = pExpedienteId          
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		  ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID 
          

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

--    DBMS_OUTPUT.PUT_LINE (vQuery);   
--    DBMS_OUTPUT.PUT_LINE (vQuery1);  
   RETURN vRegistro;
  END FN_OBT_PER_ENFER_EXP_ID;

  FUNCTION FN_OBT_PER_ENFER_X_ENFER_ID (pEnfCronicaId IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR

   SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,
                 -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID   DETVACUSALUD_US_ENTADMIN,
			    -----
               DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
               RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  JOIN CATALOGOS.SBC_MST_PERSONAS PER
      --    ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
      --    ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
      --    ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
         AND ENFERCRONI.ENF_CRONICA_ID = pEnfCronicaId          
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
	   LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	  

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

   -- DBMS_OUTPUT.PUT_LINE (vQuery);   
   -- DBMS_OUTPUT.PUT_LINE (vQuery1);  

   RETURN vRegistro;
  END FN_OBT_PER_ENFER_X_ENFER_ID; 

   FUNCTION FN_OBT_PER_ENFER_TODOS RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,
                 -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID     DETVACUSALUD_US_ENTADMIN,  
			    -----
                DETVAC.ES_REFUERZO,
                DETVAC.CASO_EMBARAZO,
			    DETVAC.REL_TIPO_VACUNA_EDAD_ID,
				DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			    DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
                 RELTIP.TIENE_FRECUENCIA_ANUALES

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  JOIN CATALOGOS.SBC_MST_PERSONAS PER
      --    ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
      --    ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
      --  LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
      --    ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	  

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		   AND  DETVAC.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

   RETURN vRegistro;
  END FN_OBT_PER_ENFER_TODOS;  


  FUNCTION FN_OBT_PER_X_ENFRCRONICAS (pDetPerXEnfCronId IN SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE, 
                                      pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                      pExpedienteId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,   
                                      pEnfCronicaId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
   CASE 
   WHEN NVL(pDetPerXEnfCronId,0) > 0 THEN
        vRegistro := FN_OBT_PER_ENFER_ID (pDetPerXEnfCronId);
   WHEN (NVL(pControlVacunaId,0) > 0 AND
         NVL(pExpedienteId,0) > 0) THEN
         vRegistro := FN_OBT_PER_ENFER_CTRL_EXP_ID (pControlVacunaId, pExpedienteId);
   WHEN NVL(pControlVacunaId,0) > 0 THEN
        vRegistro := FN_OBT_PER_ENFER_CTRL_ID (pControlVacunaId);
   WHEN NVL(pExpedienteId,0) > 0 THEN
        vRegistro := FN_OBT_PER_ENFER_EXP_ID (pExpedienteId);
   WHEN NVL(pEnfCronicaId,0) > 0 THEN
        vRegistro := FN_OBT_PER_ENFER_X_ENFER_ID (pEnfCronicaId);          
   ELSE 
        vRegistro := FN_OBT_PER_ENFER_TODOS;
   END CASE;
   RETURN vRegistro;
  END FN_OBT_PER_X_ENFRCRONICAS; 

  PROCEDURE PR_C_PER_X_ENF_CRONICAS (pDetPerXEnfCronId IN SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE,
                                     pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                     pExpedienteId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,       
                                     pEnfCronicaId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,
                                     pRegistro        OUT var_refcursor,
                                     pResultado       OUT VARCHAR2,
                                     pMsgError        OUT VARCHAR2) IS
  vTipoPaginacion NUMBER; 
  vFirma VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_C_PER_X_ENF_CRONICAS => ';                      
  BEGIN
      CASE
      WHEN (FN_VALIDA_PER_X_ENFRCRONICAS (pDetPerXEnfCronId, pControlVacunaId, pExpedienteId, pEnfCronicaId)) = TRUE THEN 
            pRegistro := FN_OBT_PER_X_ENFRCRONICAS(pDetPerXEnfCronId, pControlVacunaId, pExpedienteId, pEnfCronicaId);
      ELSE 
       CASE 
       WHEN (NVL(pControlVacunaId,0) > 0 AND
             NVL(pExpedienteId,0) > 0) THEN
             pResultado := 'No se encontraron registros con ControlVacuna Id: '||pControlVacunaId||', y expediente id: '||pExpedienteId;
             RAISE eRegistroNoExiste; 
       WHEN NVL(pControlVacunaId,0) > 0 THEN
            pResultado := 'No se encontraron registros con ControlVacuna Id: '||pControlVacunaId;
            RAISE eRegistroNoExiste; 
       WHEN NVL(pExpedienteId,0) > 0 THEN
            pResultado := 'No se encontraron registros con expediente id: '||pExpedienteId;
            RAISE eRegistroNoExiste; 
       WHEN NVL(pDetPerXEnfCronId,0) > 0 THEN
             pResultado := 'No se encontraron registros con Id: '||pDetPerXEnfCronId;
             RAISE eRegistroNoExiste; 
       WHEN NVL(pEnfCronicaId,0) > 0 THEN
            pResultado := 'No se encontraron registros con Enfermedad id: '||pEnfCronicaId; 
            RAISE eRegistroNoExiste;   
       ELSE 
           pResultado := 'No se encontraron registros';
           RAISE eRegistroNoExiste;    
       END CASE;      
      END CASE;
       CASE 
       WHEN NVL(pDetPerXEnfCronId,0) > 0 THEN
             pResultado := 'Se encontraron registros con Id: '||pDetPerXEnfCronId;
       WHEN (NVL(pControlVacunaId,0) > 0 AND
             NVL(pExpedienteId,0) > 0) THEN
             pResultado := 'Se encontraron registros con ControlVacuna Id: '||pControlVacunaId||', y expediente id: '||pExpedienteId;
       WHEN NVL(pControlVacunaId,0) > 0 THEN
            pResultado := 'Se encontraron registros con ControlVacuna Id: '||pControlVacunaId;
       WHEN NVL(pExpedienteId,0) > 0 THEN
            pResultado := 'Se encontraron registros con expediente id: '||pExpedienteId;
       WHEN NVL(pEnfCronicaId,0) > 0 THEN
            pResultado := 'Se encontraron registros con Enfermedad id: '||pEnfCronicaId; 
       ELSE 
           pResultado := 'Se encontraron registros';
       END CASE;       
  EXCEPTION
  WHEN eparametrosinvalidos THEN
       pResultado := pResultado;
       pMsgError  := vFirma ||'Parametros invalidos: ' || pResultado;
  WHEN eRegistroNoExiste THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;
  WHEN OTHERS THEN
       pResultado := ' Hubo un error inesperado en la Base de Datos. Id de consultas: [ControlId: '||pControlVacunaId||'] o [ExpedienteId: '||pExpedienteId||']';
       pMsgError  := vFirma ||pResultado||' - '||SQLERRM;
  END PR_C_PER_X_ENF_CRONICAS; 

   PROCEDURE PR_U_PER_X_ENF_CRONICAS (pDetPerXEnfCronId   IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE,
                                     pExpedienteId       IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,       
                                     pEnfCronicaId       IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,            
                                     pEstadoRegistroId   IN SIPAI_PER_VACUNADA_ENF_CRON.ESTADO_REGISTRO_ID%TYPE,
                                     pUsuario            IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,    
                                     pRegistro           OUT var_refcursor,
                                     pResultado          OUT VARCHAR2,
                                     pMsgError           OUT VARCHAR2) IS
  vFirma            VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_U_PER_X_ENF_CRONICAS => '; 
 BEGIN
      CASE
      WHEN pEstadoRegistroId = vGLOBAL_ESTADO_PASIVO THEN       
          <<PasivaRegistro>>
          BEGIN
             UPDATE SIPAI.SIPAI_PER_VACUNADA_ENF_CRON
                SET ESTADO_REGISTRO_ID   = pEstadoRegistroId, 
                    USUARIO_MODIFICACION = pUsuario,    
                    USUARIO_PASIVA       = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN USUARIO_PASIVA IS NULL THEN pUsuario
                                           ELSE USUARIO_PASIVA
                                           END,    
                    FECHA_PASIVO         = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN FECHA_PASIVO IS NULL THEN CURRENT_TIMESTAMP
                                           ELSE FECHA_PASIVO
                                           END
             WHERE DET_PER_X_ENFCRON_ID     =  pDetPerXEnfCronId AND
                   ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;
                   pResultado := 'Registro pasivado con éxito';  
          END PasivaRegistro;
       WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN
          <<ActivarRegistro>>
          BEGIN
             UPDATE SIPAI.SIPAI_PER_VACUNADA_ENF_CRON
                SET ESTADO_REGISTRO_ID   = pEstadoRegistroId, 
                    USUARIO_MODIFICACION = pUsuario,    
                    USUARIO_PASIVA       = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN USUARIO_PASIVA IS NULL THEN pUsuario
                                           ELSE USUARIO_PASIVA
                                           END,    
                    FECHA_PASIVO         = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN FECHA_PASIVO IS NULL THEN CURRENT_TIMESTAMP
                                           ELSE FECHA_PASIVO
                                           END
              WHERE DET_PER_X_ENFCRON_ID     =  pDetPerXEnfCronId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;
                    pResultado := 'Registro activado con éxito';   
          END ActivarRegistro;
        ELSE 
          <<ActualizarRegistros>>
          BEGIN
             UPDATE SIPAI.SIPAI_PER_VACUNADA_ENF_CRON
                SET EXPEDIENTE_ID        = NVL(pExpedienteId,EXPEDIENTE_ID),
                    ENF_CRONICA_ID       = NVL(pEnfCronicaId,ENF_CRONICA_ID),
                    USUARIO_MODIFICACION = pUsuario   
              WHERE DET_PER_X_ENFCRON_ID =  pDetPerXEnfCronId AND
                    ESTADO_REGISTRO_ID  != vGLOBAL_ESTADO_ELIMINADO;
                    pResultado := 'Registro actualizado con éxito';  
          END ActualizarRegistros;
        END CASE;
  EXCEPTION
  WHEN OTHERS THEN
       pResultado := 'Error no controlado';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;                                                      
  END PR_U_PER_X_ENF_CRONICAS;


  --CRUD PERSONAS ENFERMEDADES CRONINCAS
   PROCEDURE SIPAI_CRUD_PER_X_ENF_CRONICAS (pDetPerXEnfCronId IN OUT SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE,
                                           pControlVacunaId  IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                           pExpedienteId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,       
                                           pEnfCronicaId     IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,            
                                           pUsuario          IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                     
                                           pAccionEstado     IN VARCHAR2,
                                           pTipoAccion       IN VARCHAR2,
                                           pRegistro         OUT var_refcursor,
                                           pResultado        OUT VARCHAR2,
                                           pMsgError         OUT VARCHAR2) IS
  vFirma            VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.SIPAI_CRUD_PER_X_ENF_CRONICAS => ';  
  vEstadoRegistroId SIPAI.SIPAI_DET_VACUNACION.ESTADO_REGISTRO_ID%TYPE;
  BEGIN
      CASE
      WHEN pTipoAccion IS NULL THEN 
           pResultado := 'El párametro pTipoOperacion no puede venir NULL';
           pMsgError  := pResultado;
           RAISE eParametroNull;
      ELSE NULL;
      END CASE;
      CASE
      WHEN pTipoAccion = kINSERT THEN
           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;
           PR_I_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => pDetPerXEnfCronId,
                                    pExpedienteId     => pExpedienteId,    
                                    pEnfCronicaId     => pEnfCronicaId,    
                                    pUsuario          => pUsuario,         
                                    pRegistro         => pRegistro,        
                                    pResultado        => pResultado,       
                                    pMsgError         => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;

           PR_C_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => pDetPerXEnfCronId,
                                    pControlVacunaId  => pControlVacunaId, 
                                    pExpedienteId     => pExpedienteId,    
                                    pEnfCronicaId     => pEnfCronicaId,    
                                    pRegistro         => pRegistro,        
                                    pResultado        => pResultado,       
                                    pMsgError         => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;           
           pResultado := 'Registro creado con éxito';
      WHEN pTipoAccion = kUPDATE THEN
           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;
           CASE
           WHEN (NVL(pExpedienteId,0) = 0 OR 
                 NVL(pEnfCronicaId,0) = 0) THEN  --NVL(pExpedienteId,0) = 0 THEN
                    pResultado := 'Exp Id y Id enfermedad crónica no puede venir NULL';
                    pMsgError  := pResultado;
                    RAISE eParametroNull;
           ELSE NULL; 
           END CASE;            
           CASE
           WHEN pAccionEstado = 0 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_ACTIVO;
           WHEN pAccionEstado = 1 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_PASIVO;
           ELSE NULL;
           END CASE; 
           PR_U_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => pDetPerXEnfCronId,
                                    pExpedienteId     => pExpedienteId,    
                                    pEnfCronicaId     => pEnfCronicaId,    
                                    pEstadoRegistroId => vEstadoRegistroId,
                                    pUsuario          => pUsuario,         
                                    pRegistro         => pRegistro,        
                                    pResultado        => pResultado,       
                                    pMsgError         => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;

           PR_C_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => pDetPerXEnfCronId,
                                    pControlVacunaId  => pControlVacunaId, 
                                    pExpedienteId     => pExpedienteId,    
                                    pEnfCronicaId     => pEnfCronicaId,    
                                    pRegistro         => pRegistro,        
                                    pResultado        => pResultado,       
                                    pMsgError         => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;           
           pResultado := 'Registro actualizado con éxito';           
      WHEN pTipoAccion = kCONSULTAR THEN
           PR_C_PER_X_ENF_CRONICAS (pDetPerXEnfCronId => pDetPerXEnfCronId,
                                    pControlVacunaId  => pControlVacunaId, 
                                    pExpedienteId     => pExpedienteId,    
                                    pEnfCronicaId     => pEnfCronicaId,    
                                    pRegistro         => pRegistro,        
                                    pResultado        => pResultado,       
                                    pMsgError         => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;           
           pResultado := 'Registro consultado con éxito';
      ELSE NULL;
      END CASE;                      
  EXCEPTION
      WHEN eUpdateInvalido THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;      
      WHEN eParametroNull THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroNoExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;                       
      WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;
      WHEN eSalidaConError THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;  --vMsgError;
      WHEN OTHERS THEN
           pResultado := 'Error no controlado';
           pMsgError  := vFirma||pResultado||' - '||SQLERRM;      
  END SIPAI_CRUD_PER_X_ENF_CRONICAS;

   FUNCTION FN_OBT_DOSIS_VACUNA (pTipoVacunaIdRel IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE) RETURN NUMBER AS
  vContador  SIMPLE_INTEGER := 0;
  vCantDosis SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE;
  BEGIN
    SELECT COUNT (1)
      INTO vContador
      FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
     WHERE REL_TIPO_VACUNA_ID = pTipoVacunaIdRel AND
           CANTIDAD_DOSIS > 0 AND
           ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;

     CASE
     WHEN vContador > 0 THEN
          BEGIN
            SELECT CANTIDAD_DOSIS
              INTO vCantDosis
              FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE REL_TIPO_VACUNA_ID = pTipoVacunaIdRel;
          END;
     ELSE NULL;
     END CASE;
     RETURN vCantDosis;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vCantDosis;
  END FN_OBT_DOSIS_VACUNA;


 FUNCTION FN_OBT_TIPO_VACUNA_REL_ID (pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE) RETURN NUMBER AS
  vContador        SIMPLE_INTEGER := 0;
  vTipoVacunaIdRel SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE;
  BEGIN
      SELECT COUNT (1)
        INTO vContador
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
       WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
             TIPO_VACUNA_ID > 0 AND
             ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;
       CASE
       WHEN vContador > 0 THEN
            BEGIN
              SELECT TIPO_VACUNA_ID
                INTO vTipoVacunaIdRel
                FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
               WHERE CONTROL_VACUNA_ID = pControlVacunaId;            
            END;
       ELSE NULL;
       END CASE;
       RETURN vTipoVacunaIdRel;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vTipoVacunaIdRel;
  END FN_OBT_TIPO_VACUNA_REL_ID;


 PROCEDURE PR_U_CTRL_VACUNAS_APLICADAS ( pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                                         pIdRelTipoVacunaEdad    IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
                                         pFecVacuna       IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                         pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                         pResultado       OUT VARCHAR2,
                                         pMsgError        OUT VARCHAR2) IS
  vContador           SIMPLE_INTEGER := 0;
  vFecPrimVacuna      DATE := NULL;
  vFecUltVacuna       vFecPrimVacuna%TYPE;
  vRegistro           var_refcursor;
  vFirma              VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_U_CTRL_VACUNAS_APLICADAS => '||pFecVacuna||' - '; 
  vExpedienteId       SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE;
  vControlVacunaId    SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE;
  vTipoVacuna         SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE;
  vCantDosis          SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE;
  vAccionEstado       SIMPLE_INTEGER := 0;
  vDetVacLoteFecvenId SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE;
  
   vFrecuenciaAnual PLS_INTEGER;  
  
  BEGIN
      SELECT COUNT (1)
        INTO vContador
        FROM SIPAI.SIPAI_DET_VACUNACION
       WHERE CONTROL_VACUNA_ID = pControlVacunaId AND
             ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
			 AND ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
			 ;

      CASE
      WHEN vContador > 0 THEN
           CASE
           WHEN vContador = 1 THEN
                vFecPrimVacuna := pFecVacuna;
           ELSE
              vTipoVacuna := FN_OBT_TIPO_VACUNA_REL_ID (pControlVacunaId);
              CASE
              WHEN NVL(vTipoVacuna,0) > 0 THEN
                   vCantDosis :=  FN_OBT_DOSIS_VACUNA (vTipoVacuna);
                   CASE
                   WHEN NVL(vCantDosis,0) > 0 THEN
                        CASE
                        WHEN vContador >= vCantDosis THEN
                             vFecUltVacuna := pFecVacuna;
                             --vAccionEstado := 1; -- Se pasiva registro
                        ELSE NULL;
                        END CASE;
                   ELSE NULL;
                   END CASE;
              ELSE NULL;
              END CASE;
           END CASE;
           --verificar si la dosis tiene frecuencia anual 
           SELECT NVL(FRECUENCIA_ANUAL,0)
           INTO  vFrecuenciaAnual
           FROM SIPAI_REL_TIPO_VACUNA_EDAD
           WHERE REL_TIPO_VACUNA_EDAD_ID= pIdRelTipoVacunaEdad--641
           AND ESTADO_REGISTRO_ID = 6869;
           
           IF vFrecuenciaAnual>0 THEN
              vFecUltVacuna :=NULL; --
           END IF;
           
           
           
           vControlVacunaId := pControlVacunaId;
           SIPAI_CRUD_CONTROL_VACUNA (pControlVacunaId => vControlVacunaId,
                                      pExpedienteId    => vExpedienteId,   
                                      pProgVacuna      => NULL,     
                                      pGrpPrioridad    => NULL,   
                                      pEnfCronicaId    => NULL,
                                      pTipVacuna       => NULL,      
                                      pCantVacunaApli  => vContador, 
                                      pCantVacunaProg  => NULL, 
                                      pFechaPrimVacuna => vFecPrimVacuna,
                                      pFechaUltVacuna  => vFecUltVacuna, 
                                      pFecVacuna       => NULL,      
                                      pHrVacunacion    => NULL,          
                                      pDetVacLoteFecvenId => NULL, -- vDetVacLoteFecvenId,
                                      pPerVacunaId     => NULL,    
                                      pViaAdmin        => NULL,       
                                      pUniSaludId      => NULL,  
									  --NUEVOS CAMPOS
									  pObservacion     => NULL,  
									  pFechaProximaVacuna=> NULL,  
									  pNoAplicada       => NULL,  
									  pMotivoNoAplicada=> NULL,  
									  pTipoEstrategia   => NULL,  
									  pEsRefuerzo          => NULL,	
                                      pCasoEmbarazo         => NULL,
									  pIdRelTipoVacunaEdad => NULL,	
									  pUniSaludActualizacionId=> NULL,	
									 -----------------------------						   
                                      pSistemaId       => NULL,      
                                      pUsuario         => pUsuario,        
                                      pAccionEstado    => NULL, 
                                       --sectores por residencia
                                        pSectorResidenciaNombre	      => NULL,
                                        pSectorResidenciaId	          => NULL,
                                        pUnidadSaludResidenciaId	  => NULL,
                                        pUnidadSaludResidenciaNombre  => NULL,
                                        pEntidadAdministrativaResidenciaId	     =>	NULL,
                                        pEntidadAdministrativaResidenciaNombre	 =>	NULL,
                                        pSectorLatitudResidencia	             =>	NULL,
                                        pSectorLongitudResidencia	             =>	NULL,
                                        --sectores por ocurrencia
                                        pSectorOcurrenciaId	                     =>	NULL,
                                        pSectorOcurrenciaNombre	                 =>	NULL,
                                        pUnidadSaludOcurrenciaId	             =>	NULL,
                                        pUnidadSaludOcurrenciaNombre	         =>	NULL,
                                        pEntidadAdministrativaOcurrenciaId	     =>	NULL,
                                        pEntidadAdministrativaOcurrenciaNombre	 =>	NULL,
                                        pSectorLatitudOcurrencia	             =>	NULL,
                                        pSectorLongitudOcurrencia	             =>	NULL,
                                        --2024 Agregar Comunidad-----------------------------------------
                                       pComunidadResidenciaId                   =>	NULL, 
                                       pComunidadResidenciaNombre               =>	NULL,
                                       pComunidadoOcurrenciaId                  =>	NULL, 
                                       pComunidadOcurrrenciaNombre              =>	NULL,
                                       pEsAplicadaNacional                      =>	NULL,
                                      ---------------------------------------------------------------
                                      pTipoAccion      => kUPDATE,      							   						   
                                      pRegistro        => vRegistro,       
                                      pResultado       => pResultado,      
                                      pMsgError        => pMsgError );      

                IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                   RAISE eSalidaConError;
                END IF;  
                CASE
                WHEN vAccionEstado = kACCIONESTADO_PASIVO_TRUE THEN
                     SIPAI_CRUD_CONTROL_VACUNA (pControlVacunaId => vControlVacunaId,
                                                pExpedienteId    => vExpedienteId,   
                                                pProgVacuna      => NULL,     
                                                pGrpPrioridad    => NULL,   
                                                pEnfCronicaId    => NULL,
                                                pTipVacuna       => NULL,      
                                                pCantVacunaApli  => NULL, 
                                                pCantVacunaProg  => NULL, 
                                                pFechaPrimVacuna => NULL,
                                                pFechaUltVacuna  => NULL, 
                                                pFecVacuna       => NULL,                                                 
                                                pHrVacunacion    => NULL,                                                       
                                                pDetVacLoteFecvenId => NULL, -- vDetVacLoteFecvenId,
                                                pPerVacunaId     => NULL,    
                                                pViaAdmin        => NULL,       
                                                pUniSaludId      => NULL, 
												--NUEVOS CAMPOS
												pObservacion     => NULL,  
												pFechaProximaVacuna=> NULL,  
												pNoAplicada       => NULL,  
												pMotivoNoAplicada=> NULL,  
												pTipoEstrategia   => NULL, 
												pEsRefuerzo          => NULL,
                                                pCasoEmbarazo       => NULL,
												pIdRelTipoVacunaEdad => NULL,
												pUniSaludActualizacionId => NULL,
										        -------------------------------
                                                pSistemaId       => NULL,      
                                                pUsuario         => pUsuario,        
                                                pAccionEstado    => vAccionEstado,   
                                                 --sectores por residencia
                                                pSectorResidenciaNombre	      => NULL,
                                                pSectorResidenciaId	          => NULL,
                                                pUnidadSaludResidenciaId	  => NULL,
                                                pUnidadSaludResidenciaNombre  => NULL,
                                                pEntidadAdministrativaResidenciaId	     =>	NULL,
                                                pEntidadAdministrativaResidenciaNombre	 =>	NULL,
                                                pSectorLatitudResidencia	             =>	NULL,
                                                pSectorLongitudResidencia	             =>	NULL,
                                                --sectores por ocurrencia
                                                pSectorOcurrenciaId	                     =>	NULL,
                                                pSectorOcurrenciaNombre	                 =>	NULL,
                                                pUnidadSaludOcurrenciaId	             =>	NULL,
                                                pUnidadSaludOcurrenciaNombre	         =>	NULL,
                                                pEntidadAdministrativaOcurrenciaId	     =>	NULL,
                                                pEntidadAdministrativaOcurrenciaNombre	 =>	NULL,
                                                pSectorLatitudOcurrencia	             =>	NULL,
                                                pSectorLongitudOcurrencia	             =>	NULL,
                                                 --2024 Agregar Comunidad-----------------------------------------
                                               pComunidadResidenciaId                   =>	NULL, 
                                               pComunidadResidenciaNombre               =>	NULL,
                                               pComunidadoOcurrenciaId                  =>	NULL, 
                                               pComunidadOcurrrenciaNombre              =>	NULL,
                                               pEsAplicadaNacional                      =>	NULL,
                                               ------------------------------------------------------
                                                pTipoAccion      => kUPDATE, 										 
                                                pRegistro        => vRegistro,       
                                                pResultado       => pResultado,      
                                                pMsgError        => pMsgError );
                     IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                        RAISE eSalidaConError;
                     END IF;  
                ELSE NULL;
                END CASE;          
      ELSE NULL;
      END CASE;

  EXCEPTION
  WHEN eSalidaConError THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pMsgError;  
  WHEN OTHERS THEN
       pResultado := 'Error al insertar detalle de vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;               
  END PR_U_CTRL_VACUNAS_APLICADAS;

   FUNCTION FN_VAL_DET_VACU_LOTE_FECVEN (pDetVacLoteFecvenId IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE, 
                                        pTipVacunaId        IN SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE) RETURN BOOLEAN AS
  vExiste BOOLEAN := FALSE;
  vConteo SIMPLE_INTEGER := 0;
  BEGIN 
     SELECT COUNT (1)
       INTO vConteo
       FROM SIPAI_DET_TIPVAC_X_LOTE
      WHERE DETALLE_VACUNA_X_LOTE_ID = pDetVacLoteFecvenId AND
            REL_TIPO_VACUNA_ID = pTipVacunaId;
       CASE
       WHEN vConteo > 0 THEN
            vExiste := TRUE;
       ELSE NULL;
       END CASE;

     RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_VAL_DET_VACU_LOTE_FECVEN;

  PROCEDURE PR_I_DET_VACUNACION_SECTOR ( pDetVacunacionId    IN SIPAI.SIPAI_DET_VACUNACION_SECTOR.DET_VACUNACION_ID%TYPE,
                                       --------------Datos de Sectorizacion Residencia-----------------
									   pSectorResidenciaNombre	                IN   	VARCHAR2,
									   pSectorResidenciaId	                    IN   	NUMBER, 
									   pUnidadSaludResidenciaId	                IN   	NUMBER, 
									   pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
									   pEntidadAdminResidenciaId                IN   	NUMBER, 
									   pEntidadAdminResidenciaNombre	        IN   	VARCHAR2,
									   pSectorLatitudResidencia	                IN   	VARCHAR2,
									   pSectorLongitudResidencia	            IN   	VARCHAR2,
									   --------------Datos de Sectorizacion Ocurrencia-----------------	
									   pSectorOcurrenciaId	                    IN   	NUMBER, 
									   pSectorOcurrenciaNombre	                IN   	VARCHAR2,
									   pUnidadSaludOcurrenciaId	                IN   	NUMBER, 
									   pUnidadSaludOcurrenciaNombre	            IN   	VARCHAR2,
									   pEntidadAdminOcurrenciaId	            IN   	NUMBER, 
									   pEntidadAdminOcurrenciaNombre	        IN   	VARCHAR2,
									   pSectorLatitudOcurrencia	                IN   	VARCHAR2,
									   pSectorLongitudOcurrencia	            IN   	VARCHAR2,
									   --2024 08------------------------------------------------------
                                       pComunidadResidenciaId                   IN   	NUMBER,  
                                       pComunidadResidenciaNombre               IN   	VARCHAR2,
                                       pComunidadOcurrenciaId                  IN   	NUMBER,  
                                       pComunidadOcurrrenciaNombre              IN   	VARCHAR2,
                                       ---------------------------------------------------------------
									   pResultado          OUT VARCHAR2,
                                       pMsgError           OUT VARCHAR2) IS


  vFirma       VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_I_DET_VACUNACION_SECTOR => '; 
  --Variables
    registro  SIPAI.SIPAI_DET_VACUNACION_SECTOR%ROWTYPE;
	vPeriodo VARCHAR2(100);
	vCodigoPeriodo  VARCHAR2(30);

    --OCURRENCIA
     vEntidadAdminOcurrenciaCodigo	VARCHAR2(30);
      ---2 nuevas variable para no usar las del parametros pEntidadAdminOcurrenciaId y pEntidadAdminOcurrenciaNombre
    vEntidadAdminOcurrenciaId	       	NUMBER;
    vEntidadAdminOcurrenciaNombre	  	VARCHAR2(100);

	vDepartamentoOcurrenciaId	    NUMBER;
	vDepartamentoOcurrenciaCodigo	VARCHAR2(30);
	vDepartamentoOcurrenciaNombre	VARCHAR2(100);

	vMunicipioOcurrenciaId			NUMBER;
	vMunicipioOcurrenciaCodigo	    VARCHAR2(30);
	vMunicipioOcurrenciaNombre	    VARCHAR2(100);

    vSectorOcurrenciaCodigo			VARCHAR2(30);
	vUnidadSaludOcurrenciaCodigo	VARCHAR2(30);

    ----RESIDENCIA-------
    vEntidadAdminResidenciaCodigo	VARCHAR2(30);
    ---2 nuevas variable para no usar las del parametros pEntidadAdminResidenciaId y pEntidadAdminResidenciaNombre
	vEntidadAdminResidenciaId          	NUMBER;
    vEntidadAdminResidenciaNombre	   	VARCHAR2(100);

    vDepartamentoResidenciaId	    NUMBER;
	vDepartamentoResidenciaCodigo	VARCHAR2(30);
	vDepartamentoResidenciaNombre	VARCHAR2(100);

	vMunicipioResidenciaId			NUMBER;
	vMunicipioResidenciaCodigo		VARCHAR2(30);
	vMunicipioResidenciaNombre		VARCHAR2(100);
    vSectorResidenciaCodigo			VARCHAR2(30);
	vUnidadSaludResidenciaCodigo	VARCHAR2(30);

    vContador  NUMBER;
    
    --2024 NOV declarar dos variabls de para el periodo residencia y ocurrencia 
    vPeriodoOcurrencia  VARCHAR2(4);
    vPeriodoResidencia  VARCHAR2(4);
    
  BEGIN

     -- PERIODO ACTUAL DE SECTORIZACION 
	SELECT CODIGO,VALOR 
	INTO   vCodigoPeriodo, vPeriodo  
	FROM   CATALOGOS.SBC_CAT_CATALOGOS 
	WHERE  CATALOGO_SUP = (SELECT CATALOGO_ID FROM CATALOGOS.SBC_CAT_CATALOGOS
						 WHERE CODIGO = 'PRDSCTRZCN' AND CATALOGO_SUP IS NULL AND PASIVO = 0)
	AND PASIVO = 0;
    
    --El periodo asociado basado en el periodo ultimo de la comunidad
    SELECT MAX(PERIODO)
    INTO   vPeriodoOcurrencia  --PERIODO_OCR 
    FROM CATALOGOS.SBC_REL_SECTOR_COMUNIDADES 
    WHERE COMUNIDAD_ID=pComunidadOcurrenciaId;
    
    SELECT MAX(PERIODO)
    INTO   vPeriodoResidencia  --PERIODO_RSD
    FROM CATALOGOS.SBC_REL_SECTOR_COMUNIDADES 
    WHERE COMUNIDAD_ID=pComunidadResidenciaId;
 
	--RESIDENCIA-----------------
	IF NVL(pSectorResidenciaId,0) > 0 THEN 
        --validar el SECTOR_ID
        SELECT COUNT(*)
		INTO   vContador	
		FROM   CATALoGOS.SBC_CAT_SECTORES
		WHERE  SECTOR_ID= pSectorResidenciaId 
		AND PASIVO=0;

       IF vContador !=0 THEN
        --Obtener el codigo del sector 
            SELECT CODIGO
            INTO   vSectorResidenciaCodigo	
            FROM   CATALoGOS.SBC_CAT_SECTORES
            WHERE  SECTOR_ID= pSectorResidenciaId 
            AND PASIVO=0;
       END IF;

	END IF;

	IF NVL(pUnidadSaludResidenciaId,0) > 0 THEN
        --Validar que el id de la unidad de salud recibido exista en el catalogo unidad de salud del minsa
        SELECT COUNT(*)
		INTO  vContador
		FROM CATALOGOS.SBC_CAT_UNIDADES_SALUD usa 
		WHERE usa.PASIVO=0
		AND   usa.UNIDAD_SALUD_ID=pUnidadSaludResidenciaId;

        --Obtener los datos de silais, departamento y municipio relacionado a la unidad administrativa
        IF vContador !=0 THEN  --con la ua obtendremos datos del silais, dpto, y municipio
            SELECT usa.CODIGO,
                   usa.ENTIDAD_ADTVA_ID,entidad.CODIGO,entidad.NOMBRE,
                   mun.MUNICIPIO_ID,mun.CODIGO,mun.NOMBRE,
                   dep.DEPARTAMENTO_ID,dep.CODIGO,dep.NOMBRE
            INTO   vUnidadSaludResidenciaCodigo,
                   vEntidadAdminResidenciaId,vEntidadAdminResidenciaCodigo,vEntidadAdminResidenciaNombre,
                   vMunicipioResidenciaId,vMunicipioResidenciaCodigo,vMunicipioResidenciaNombre,
                   vDepartamentoResidenciaId,vDepartamentoResidenciaCodigo,vDepartamentoResidenciaNombre
            FROM CATALOGOS.SBC_CAT_UNIDADES_SALUD usa 
            JOIN CATALOGOS.SBC_CAT_COMUNIDADES      comu    ON usa.COMUNIDAD_ID=comu.COMUNIDAD_ID AND comu.PASIVO=0
            JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS entidad ON usa.ENTIDAD_ADTVA_ID = entidad.ENTIDAD_ADTVA_ID AND entidad.PASIVO = 0 
            JOIN CATALOGOS.SBC_CAT_MUNICIPIOS     mun ON comu.MUNICIPIO_ID=mun.MUNICIPIO_ID AND mun.PASIVO=0
            JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS  dep ON mun.DEPARTAMENTO_ID=dep.DEPARTAMENTO_ID AND dep.PASIVO=0
            WHERE usa.PASIVO=0
            AND   usa.UNIDAD_SALUD_ID=pUnidadSaludResidenciaId;
        END IF; 
    END IF;


/*  Este codigo se comenta por que el Api aveces manda en 0 el codigo del SILAIS y ya se ajusto para que se obtenga por consulta y no por parametro
    IF NVL(pEntidadAdminResidenciaId,0) > 0 THEN

        SELECT COUNT(*)
		INTO   vContador
		FROM CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS 
		WHERE ENTIDAD_ADTVA_ID=pEntidadAdminResidenciaId
		AND PASIVO=0;

       IF vContador !=0 THEN

		SELECT CODIGO 
		INTO   vEntidadAdminResidenciaCodigo
		FROM CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS 
		WHERE ENTIDAD_ADTVA_ID=pEntidadAdminResidenciaId
		AND PASIVO=0;

      END IF;
	END IF;
    */

    --OCURRENCIA-----------------
	IF NVL(pSectorOcurrenciaId,0) > 0 THEN 

        SELECT COUNT(*)
		INTO   vContador	
		FROM   CATALoGOS.SBC_CAT_SECTORES
		WHERE  SECTOR_ID= pSectorOcurrenciaId 
		AND PASIVO=0;

      IF vContador !=0 THEN

		SELECT CODIGO
		INTO   vSectorOcurrenciaCodigo	
		FROM   CATALoGOS.SBC_CAT_SECTORES
		WHERE  SECTOR_ID= pSectorOcurrenciaId 
		AND PASIVO=0;

     END IF;
	END IF;

	IF NVL(pUnidadSaludOcurrenciaId,0) > 0 THEN

        SELECT COUNT(*)
		INTO  vContador
		FROM CATALOGOS.SBC_CAT_UNIDADES_SALUD usa 
		WHERE usa.PASIVO=0
		AND   usa.UNIDAD_SALUD_ID=pUnidadSaludOcurrenciaId;

      IF vContador !=0 THEN

        SELECT usa.CODIGO,
               usa.ENTIDAD_ADTVA_ID,entidad.CODIGO,entidad.NOMBRE,
               mun.MUNICIPIO_ID,mun.CODIGO,mun.NOMBRE,
               dep.DEPARTAMENTO_ID,dep.CODIGO,dep.NOMBRE
        INTO   vUnidadSaludOcurrenciaCodigo,
               vEntidadAdminOcurrenciaId,vEntidadAdminOcurrenciaCodigo,vEntidadAdminOcurrenciaNombre,
               vMunicipioOcurrenciaId,vMunicipioOcurrenciaCodigo,vMunicipioOcurrenciaNombre,
               vDepartamentoOcurrenciaId,vDepartamentoOcurrenciaCodigo,vDepartamentoOcurrenciaNombre
        FROM CATALOGOS.SBC_CAT_UNIDADES_SALUD usa 
        JOIN CATALOGOS.SBC_CAT_COMUNIDADES      comu    ON usa.COMUNIDAD_ID=comu.COMUNIDAD_ID AND comu.PASIVO=0
        JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS entidad ON usa.ENTIDAD_ADTVA_ID = entidad.ENTIDAD_ADTVA_ID AND entidad.PASIVO = 0 
        JOIN CATALOGOS.SBC_CAT_MUNICIPIOS     mun ON comu.MUNICIPIO_ID=mun.MUNICIPIO_ID AND mun.PASIVO=0
        JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS  dep ON mun.DEPARTAMENTO_ID=dep.DEPARTAMENTO_ID AND dep.PASIVO=0
        WHERE usa.PASIVO=0
        AND   usa.UNIDAD_SALUD_ID=pUnidadSaludOcurrenciaId;
     END IF;

	END IF;


    /*
    IF NVL(pEntidadAdminOcurrenciaId,0) > 0 THEN

        SELECT COUNT(*)
        INTO   vContador
		FROM CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS 
		WHERE ENTIDAD_ADTVA_ID=pEntidadAdminOcurrenciaId
		AND PASIVO=0 ;

     IF vContador !=0 THEN
		SELECT CODIGO 
		INTO   vEntidadAdminOcurrenciaCodigo
		FROM CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS 
		WHERE ENTIDAD_ADTVA_ID=pEntidadAdminOcurrenciaId
		AND PASIVO=0 ;
     END IF;

	END IF;
    */


    registro.DET_VACUNACION_ID:=pDetVacunacionId;

	registro.DEPARTAMENTO_OCURRENCIA_ID:=vDepartamentoOcurrenciaId;
	registro.DEPARTAMENTO_OCURRENCIA_CODIGO:=vDepartamentoOcurrenciaCodigo;
	registro.DEPARTAMENTO_OCURRENCIA_NOMBRE:=vDepartamentoOcurrenciaNombre;
	registro.MUNICIPIO_OCURRENCIA_ID:=vMunicipioOcurrenciaId;
	registro.MUNICIPIO_OCURRENCIA_NOMBRE:=vMunicipioOcurrenciaNombre;
	registro.MUNICIPIO_OCURRENCIA_CODIGO:=vMunicipioOcurrenciaCodigo;
	registro.UNIDAD_SALUD_OCURRENCIA_ID:=pUnidadSaludOcurrenciaId;
	registro.UNIDAD_SALUD_OCURRENCIA_CODIGO:=vUnidadSaludOcurrenciaCodigo;
	registro.UNIDAD_SALUD_OCURRENCIA_NOMBRE:=pUnidadSaludOcurrenciaNombre;
	registro.ENTIDAD_ADMIN_OCURRENCIA_ID:=vEntidadAdminOcurrenciaId;
	registro.ENTIDAD_ADMIN_OCURRENCIA_CODIGO:=vEntidadAdminOcurrenciaCodigo;
	registro.ENTIDAD_ADMIN_OCURRENCIA_NOMBRE:=vEntidadAdminOcurrenciaNombre;
	registro.SECTOR_OCURRENCIA_ID:=pSectorOcurrenciaId;
	registro.SECTOR_OCURRENCIA_CODIGO:=vSectorOcurrenciaCodigo;
	registro.SECTOR_OCURRENCIA_NOMBRE:=pSectorOcurrenciaNombre;
	registro.SECTOR_LATITUD_OCURRENCIA:=pSectorLatitudOcurrencia;
	registro.SECTOR_LONGITUD_OCURRENCIA:=pSectorLongitudOcurrencia;

	registro.DEPARTAMENTO_RESIDENCIA_ID:=vDepartamentoResidenciaId;
	registro.DEPARTAMENTO_RESIDENCIA_CODIGO:=vDepartamentoResidenciaCodigo;
	registro.DEPARTAMENTO_RESIDENCIA_NOMBRE:=vDepartamentoResidenciaNombre;
	registro.MUNICIPIO_RESIDENCIA_ID:=vMunicipioResidenciaId;
	registro.MUNICIPIO_RESIDENCIA_NOMBRE:=vMunicipioResidenciaNombre;
	registro.MUNICIPIO_RESIDENCIA_CODIGO:=vMunicipioResidenciaCodigo;
	registro.UNIDAD_SALUD_RESIDENCIA_ID:=pUnidadSaludResidenciaId;
	registro.UNIDAD_SALUD_RESIDENCIA_CODIGO:=vUnidadSaludResidenciaCodigo;
	registro.UNIDAD_SALUD_RESIDENCIA_NOMBRE:=pUnidadSaludResidenciaNombre;
	registro.ENTIDAD_ADMIN_RESIDENCIA_ID:=vEntidadAdminResidenciaId;
	registro.ENTIDAD_ADMIN_RESIDENCIA_CODIGO:=vEntidadAdminResidenciaCodigo;
	registro.ENTIDAD_ADMIN_RESIDENCIA_NOMBRE:=vEntidadAdminResidenciaNombre;
	registro.SECTOR_RESIDENCIA_ID:=pSectorResidenciaId;
	registro.SECTOR_RESIDENCIA_CODIGO:=vSectorResidenciaCodigo;
	registro.SECTOR_RESIDENCIA_NOMBRE:=pSectorResidenciaNombre;
	registro.SECTOR_LATITUD_RESIDENCIA:=pSectorLatitudResidencia;
	registro.SECTOR_LONGITUD_RESIDENCIA:=pSectorLongitudResidencia;
    ---2024 08 -------------
    registro.COMUNIDAD_RESIDENCIA_ID:=pComunidadResidenciaId;
    registro.COMUNIDAD_RESIDENCIA_NOMBRE:=pComunidadResidenciaNombre;
    registro.COMUNIDAD_OCURRENCIA_ID:=pComunidadOcurrenciaId;
    registro.COMUNIDAD_OCURRENCIA_NOMBRE:=pComunidadOcurrrenciaNombre;
   -----------------------------------------------------------------
	registro.PERIODO:=vPeriodo;
	registro.CODIGO_PERIODO:=vCodigoPeriodo;
    --2024 -NOV periodo por comunidad
    registro.PERIODO_OCR:=vPeriodoOcurrencia;
    registro.PERIODO_RSD:=vPeriodoResidencia;
    DBMS_OUTPUT.PUT_LINE('insert sectores');

	 INSERT INTO SIPAI_DET_VACUNACION_SECTOR VALUES registro;


  EXCEPTION
  WHEN eParametrosInvalidos THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;  
   WHEN eRegistroExiste THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;  
  WHEN eSalidaConError THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pMsgError; 
  WHEN OTHERS THEN
       pResultado := 'Error al insertar detalle de vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;
  END PR_I_DET_VACUNACION_SECTOR;

  PROCEDURE PR_I_DET_VACUNACION (pDetVacunacionId    OUT SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE,
                                 pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                                 pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                 pPerVacunaId        IN SIPAI.SIPAI_DET_VACUNACION.PERSONAL_VACUNA_ID%TYPE,
                                 pViaAdmin           IN SIPAI.SIPAI_DET_VACUNACION.VIA_ADMINISTRACION_ID%TYPE,
                                 pHrVacunacion       IN SIPAI.SIPAI_DET_VACUNACION.HORA_VACUNACION%TYPE,
                                 pDetVacLoteFecvenId IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE,           
								------NUEVOS CAMPOS-------------------------------------------------------------
								  pObservacion		   IN SIPAI.SIPAI_DET_VACUNACION.OBSERVACION%TYPE,
								  pFechaProximaVacuna  IN SIPAI.SIPAI_DET_VACUNACION.FECHA_PROXIMA_VACUNA%TYPE, 
								  pNoAplicada		   IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
								  pMotivoNoAplicada    IN SIPAI.SIPAI_DET_VACUNACION.MOTIVO_NO_APLICADA%TYPE,  
							      pTipoEstrategia	   IN SIPAI.SIPAI_DET_VACUNACION.TIPO_ESTRATEGIA_ID%TYPE,
								  pEsRefuerzo          IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,		
                                  pCasoEmbarazo        IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,
								  pIdRelTipoVacunaEdad    IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
								  pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,
                                  --------------Datos de Sectorizacion Residencia-----------------
                                       pSectorResidenciaNombre	                IN   	VARCHAR2,
                                       pSectorResidenciaId	                    IN   	NUMBER, 
                                       pUnidadSaludResidenciaId	                IN   	NUMBER, 
                                       pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaResidenciaId       IN   	NUMBER, 
                                       pEntidadAdministrativaResidenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudResidencia	                IN   	VARCHAR2,
                                       pSectorLongitudResidencia	            IN   	VARCHAR2,
                                       --------------Datos de Sectorizacion Ocurrencia-----------------	
                                       pSectorOcurrenciaId	                    IN   	NUMBER, 
                                       pSectorOcurrenciaNombre	                IN   	VARCHAR2,
                                       pUnidadSaludOcurrenciaId	                IN   	NUMBER, 
                                       pUnidadSaludOcurrenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaOcurrenciaId	    IN   	NUMBER, 
                                       pEntidadAdministrativaOcurrenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudOcurrencia	                IN   	VARCHAR2,
                                       pSectorLongitudOcurrencia	            IN   	VARCHAR2,
                                       --2024 Agregar Comunidad-----------------------------------------
                                       pComunidadResidenciaId                   IN   	NUMBER,  
                                       pComunidadResidenciaNombre               IN   	VARCHAR2,
                                       pComunidadoOcurrenciaId                  IN   	NUMBER,  
                                       pComunidadOcurrrenciaNombre              IN   	VARCHAR2,
                                       pEsAplicadaNacional                      IN      NUMBER,  
                                       pGrpPrioridad                            IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
								------------------------------------------------------------------------------------ 
                                 pUniSaludId         IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                 pSistemaId          IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                 pUsuario            IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE, 
                                 pResultado          OUT VARCHAR2,
                                 pMsgError           OUT VARCHAR2)  IS


  vFirma       VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_I_DET_VACUNACION => '; 
  vTipVacunaId  SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE := NULL; 
  v_Estado_VacunacionId SIPAI.SIPAI_DET_VACUNACION.ESTADO_VACUNACION_ID%TYPE;

  --Edad de Vacunacion
  vExpedienteId NUMBER(10);
  vTextoEdad VARCHAR(250);
  vAnio NUMBER;
  vMes  NUMBER;
  vDia  NUMBER;

  vVacunasProximaCita   VARCHAR2(600);
  vContador PLS_INTEGER;

   --Ajuste de VacunaDt 2024 2doEsquema 5 dosis despues de 21anios
   vTipoVacunadT  NUMBER:=FN_SIPAI_CATALOGO_ESTADO_ID('SIPAI026');
   vRelTipoVacunadT  NUMBER;
   vCodigoEdad VARCHAR2(30);
   
  BEGIN
  
     SELECT EXPEDIENTE_ID  
     INTO   vExpedienteId
     FROM SIPAI.SIPAI_MST_CONTROL_VACUNA
     WHERE CONTROL_VACUNA_ID = pControlVacunaId;

     vTipVacunaId :=FN_OBT_TIPVACREL_ID (pControlVacunaId);

   --POST PROD VALIDAR UNICIDAD DE VACUNA Y NUEMERO DE DOSIS PARA QUE NO SE DUPLIQUE EN CASO DE SE PEGUE UNA SESSION DE USUARIOS

--DBMS_OUTPUT.PUT_LINE('validando unicidad vTipVacunaId ' ||vExpedienteId);
--DBMS_OUTPUT.PUT_LINE('validando unicidad pIdRelTipoVacunaEdad ' ||pIdRelTipoVacunaEdad);
--DBMS_OUTPUT.PUT_LINE('validando unicidad vTipVacunaId ' ||vTipVacunaId);
           SELECT COUNT(*) 
           INTO   vContador
           FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA      MST
           JOIN   SIPAI.SIPAI_DET_VACUNACION          DETVAC    ON  MST.CONTROL_VACUNA_ID = DETVAC.CONTROL_VACUNA_ID 
           WHERE  MST.EXPEDIENTE_ID=vExpedienteId
           AND    DETVAC.REL_TIPO_VACUNA_ID=vTipVacunaId
           AND    DETVAC.REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad
           AND    DETVAC.ESTADO_REGISTRO_ID=6869
           AND    DETVAC.FECHA_VACUNACION=pFecVacuna
           AND    TRUNC(DETVAC.FECHA_REGISTRO)=TRUNC(SYSDATE); 

           IF  vContador >0  THEN
                pResultado := 'La vacuna y dosis  ya existe' ;
                pMsgError  := pResultado;
                RAISE eParametrosInvalidos;  
           END IF;

   --Validar programa Esquema
     v_Estado_VacunacionId:= FN_CALCULAR_ESTADO_ACTUALIZACION ( pControlVacunaId, pFecVacuna ,pNoAplicada,pUniSaludActualizacionId,pIdRelTipoVacunaEdad ,pResultado,pMsgError);

   CASE
   WHEN (NVL(pDetVacLoteFecvenId,0) > 0 AND
         NVL(vTipVacunaId,0) > 0) THEN
         CASE
         WHEN (FN_VAL_DET_VACU_LOTE_FECVEN (pDetVacLoteFecvenId, vTipVacunaId) != TRUE) THEN
               pResultado := 'Parámetros de lote y fecha vencimiento no corresponden a lo parametrizado en la tabla maestro: Tip Vacuna Id: '||vTipVacunaId;
               RAISE eParametrosInvalidos;
         ELSE NULL;
         END CASE;
   ELSE NULL;
   END CASE;

   --Validar Fechas  Programada en ves INDEX uniq_idx_det_x_fecha control_vacuna_id FECHA_VACUNACION
	  --que es infuncional por registro pasivo

   IF FN_EXISTE_FECHA_VACUNA_CRTID (pControlVacunaId,pFecVacuna,pDetVacunacionId)  THEN
			   pResultado := 'Existe una dosis aplicada en fecha de vacunacion '||pFecVacuna ;
			   pMsgError  := pResultado;
			   RAISE eRegistroExiste;
   END IF;

      --Edad de Vacunacion
     vTextoEdad :=PKG_SIPAI_UTILITARIOS.FN_OBT_EDAD(vExpedienteId,pFecVacuna);
     vAnio:=JSON_VALUE(vTextoEdad, '$.anio');
     vMes:=JSON_VALUE(vTextoEdad, '$.mes');
     vDia:=JSON_VALUE(vTextoEdad, '$.dia');

   INSERT INTO SIPAI.SIPAI_DET_VACUNACION (CONTROL_VACUNA_ID, 
                                           FECHA_VACUNACION, 
                                           HORA_VACUNACION,
                                           DETALLE_VACUNA_X_LOTE_ID, 
                                           VIA_ADMINISTRACION_ID,
                                           PERSONAL_VACUNA_ID,
                                           ESTADO_REGISTRO_ID,
										   ------NUEVOS CAMPOS---
										   OBSERVACION,
										   FECHA_PROXIMA_VACUNA,
										   NO_APLICADA,
										   MOTIVO_NO_APLICADA,
										   TIPO_ESTRATEGIA_ID,
                                           ES_REFUERZO,
                                           CASO_EMBARAZO,
						                   REL_TIPO_VACUNA_EDAD_ID, 
										   UNIDAD_SALUD_ACTUALIZACION_ID,
										   ESTADO_VACUNACION_ID,
                                           ---Rel y Edad Vacunacion
                                           REL_TIPO_VACUNA_ID,
                                           EDAD_ANIO,
                                           EDAD_MES_EXTRA,
                                           EDAD_DIA_EXTRA,
                                           EXPEDIENTE_ID,
                                           -----------------------
                                            ES_APLICADA_NACIONAL,
                                           ------------------------
                                           SISTEMA_ID,
                                           UNIDAD_SALUD_ID,
                                           USUARIO_REGISTRO)
                                   VALUES (pControlVacunaId,
                                           pFecVacuna,
                                           pHrVacunacion,                                    
                                           pDetVacLoteFecvenId,
                                           pViaAdmin,
                                           pPerVacunaId, 
                                           vGLOBAL_ESTADO_ACTIVO,
										   ------NUEVOS CAMPOS---
										   pObservacion,
										   pFechaProximaVacuna,
										   pNoAplicada	,								
										   pMotivoNoAplicada,								
										   pTipoEstrategia,	
										   pEsRefuerzo,	
                                           pCasoEmbarazo,
						                   pIdRelTipoVacunaEdad,
										   pUniSaludActualizacionId,
										   v_Estado_VacunacionId,
										    ---Rel y Edad Vacunacion
                                           vTipVacunaId,
                                           vAnio,
                                           vMes,
                                           vDia,
                                           vExpedienteId,
                                           -----------------------
                                           pEsAplicadaNacional,
                                           -----------------------
                                           pSistemaId,
                                           pUniSaludId,
                                           pUsuario)
                                RETURNING DET_VACUNACION_ID INTO pDetVacunacionId;

                             DBMS_OUTPUT.PUT_LINE('Despues de insert detalle ' );   

                                --Insert Sectorizacion----
                                 PR_I_DET_VACUNACION_SECTOR
                                 (     pDetVacunacionId,
                                       --------------Datos de Sectorizacion Residencia-----------------
									   pSectorResidenciaNombre,
									   pSectorResidenciaId, 
									   pUnidadSaludResidenciaId, 
									   pUnidadSaludResidenciaNombre,
									   pEntidadAdministrativaResidenciaId, 
									   pEntidadAdministrativaResidenciaNombre,
									   pSectorLatitudResidencia,
									   pSectorLongitudResidencia,
									   --------------Datos de Sectorizacion Ocurrencia-----------------	
									   pSectorOcurrenciaId, 
									   pSectorOcurrenciaNombre,
									   pUnidadSaludOcurrenciaId, 
									   pUnidadSaludOcurrenciaNombre,
									   pEntidadAdministrativaOcurrenciaId, 
									   pEntidadAdministrativaOcurrenciaNombre,
									   pSectorLatitudOcurrencia,
									   pSectorLongitudOcurrencia,
									   --2024 08-------------------------------------------------
                                       pComunidadResidenciaId, 
                                       pComunidadResidenciaNombre,
                                       pComunidadoOcurrenciaId,
                                       pComunidadOcurrrenciaNombre,
                                       -----------------------------------------------------------
									   pResultado,
                                       pMsgError
                                       );
                                       
                  --cambio 18/08/2025 Actualizar el gruopo de priridad del master
                 UPDATE SIPAI_MST_CONTROL_VACUNA
                 SET    GRUPO_PRIORIDAD_ID =pGrpPrioridad, 
                        FECHA_MODIFICACION=SYSDATE,
                        USUARIO_MODIFICACION=pUsuario
                 WHERE  CONTROL_VACUNA_ID=pControlVacunaId; 
                                       
                                       
                                       
                   PR_U_CTRL_VACUNAS_APLICADAS ( pControlVacunaId => pControlVacunaId,
                                                 pIdRelTipoVacunaEdad => pIdRelTipoVacunaEdad,  --para validar Frecuencia Anual
                                                 pFecVacuna       => pFecVacuna,
                                                 pUsuario         => pUsuario,                                  
                                                 pResultado       => pResultado,
                                                 pMsgError        => pMsgError);


                IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                   RAISE eSalidaConError;
                END IF;    
                          
           
                                 --  REGISTROS DE DATOS PARA PROXIMA CITA-----------------------------
                                PKG_SIPAI_UTILITARIOS.PR_REGISTRO_DET_ROXIMA_CITA(vExpedienteId,pResultado,pMsgError);

                                --EMR-082024 Pasivar las citas que estan como proxima cita de esta vacuna y esta dosis

                                 UPDATE SIPAI_DET_PROXIMA_CITA
                                 SET    pasivo=1
                                 WHERE  EXPEDIENTE_ID =	vExpedienteId
                                 AND    REL_TIPO_VACUNA_ID=vTipVacunaId
                                 AND 	REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad;


                                --Regitrar el lista tag de  Nombre de Vacunas de Proxima Citas en el cambo VACUNAS_PROXIMA_CITA de  datalle
                                 SELECT PKG_SIPAI_UTILITARIOS.FN_OBT_VACUNA_PROXIMA_CITA(vExpedienteId) 
                                 INTO   vVacunasProximaCita 
                                 FROM DUAL;

                                 UPDATE  SIPAI.SIPAI_DET_VACUNACION
                                 SET     VACUNAS_PROXIMA_CITA=JSON_VALUE(vVacunasProximaCita, '$.VacunasUltimaCita'),
                                         USUARIO_MODIFICACION=pUsuario,
                                         FECHA_MODIFICACION=SYSDATE
                                WHERE    DET_VACUNACION_ID=pDetVacunacionId;

								PR_ACT_FECHA_INICIO_VAC_MASTER(pControlVacunaId,pResultado,pMsgError);

         --dT 2024  dosis dt
          --contar antes del into
                 SELECT   count(*)
                 INTO     vContador
                 FROM     sipai_rel_tip_vacunacion_dosis rtvac 
                 JOIN     SIPAI_REL_TIPO_VACUNA_EDAD rtve ON rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
                          AND   rtvac.estado_registro_id = 6869   AND   rtve.ESTADO_REGISTRO_ID = 6869
                JOIN  SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID 
                AND   PRME.ESTADO_REGISTRO_ID = 6869
                WHERE rtvac.tipo_vacuna_id=vTipoVacunadT  
                AND   rtve.REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad;

           IF vContador >0 THEN

                 SELECT   rtvac.rel_tipo_vacuna_id,PRME.CODIGO_EDAD
                 INTO     vRelTipoVacunadT,vCodigoEdad 
                 FROM     sipai_rel_tip_vacunacion_dosis rtvac 
                 JOIN     SIPAI_REL_TIPO_VACUNA_EDAD rtve ON rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
                          AND   rtvac.estado_registro_id = 6869   AND   rtve.ESTADO_REGISTRO_ID = 6869
                JOIN  SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID 
                AND   PRME.ESTADO_REGISTRO_ID = 6869
                WHERE rtvac.tipo_vacuna_id=vTipoVacunadT  
                AND   rtve.REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad;

                IF  vTipVacunaId= vRelTipoVacunadT AND vCodigoEdad='COD_INT_EDAD_7786' OR vCodigoEdad ='COD_INT_EDAD_7787' THEN
                    --CANTIDAD PROGRAMADA 1ER. ESQUEMA 

                    UPDATE SIPAI_MST_CONTROL_VACUNA
                    SET    CANTIDAD_VACUNA_PROGRAMADA =2, 
                           FECHA_MODIFICACION=SYSDATE,
                           USUARIO_MODIFICACION=pUsuario
                    WHERE  CONTROL_VACUNA_ID=pControlVacunaId;

                ELSIF  vTipVacunaId= vRelTipoVacunadT AND vCodigoEdad='COD_INT_EDAD_7917' OR vCodigoEdad ='COD_INT_EDAD_7919' 
                       OR vCodigoEdad='COD_INT_EDAD_7919' OR vCodigoEdad ='COD_INT_EDAD_7920' OR vCodigoEdad ='COD_INT_EDAD_7921' THEN
                -- CANTIDAD PROGRAMADA 2DO ESQUEMA
                    UPDATE SIPAI_MST_CONTROL_VACUNA
                    SET    CANTIDAD_VACUNA_PROGRAMADA =5, 
                           FECHA_MODIFICACION=SYSDATE,
                           USUARIO_MODIFICACION=pUsuario
                    WHERE  CONTROL_VACUNA_ID=pControlVacunaId;
                END IF;
        END IF;


              
  EXCEPTION
  WHEN eParametrosInvalidos THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;  
   WHEN eRegistroExiste THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;  
  WHEN eSalidaConError THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pMsgError; 
  WHEN OTHERS THEN
       pResultado := 'Error al insertar detalle de vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;
  END PR_I_DET_VACUNACION;

 FUNCTION FN_VALIDA_DET_VACUNA (pDetVacunacionId IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE, 
                                 pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                                 pTipoPaginacion  OUT NUMBER) RETURN BOOLEAN AS

  vExiste   BOOLEAN :=  FALSE;
  vContador SIMPLE_INTEGER := 0;
  BEGIN
     CASE
     WHEN (NVL (pDetVacunacionId,0) > 0) AND (NVL(pControlVacunaId,0) > 0) THEN
          BEGIN
             SELECT COUNT (1)
               INTO vContador 
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              LEFT JOIN SIPAI.SIPAI_DET_VACUNACION B
                ON B.CONTROL_VACUNA_ID  = A.CONTROL_VACUNA_ID AND
                   B.DET_VACUNACION_ID  = pDetVacunacionId
				    AND  B.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
              WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
                    A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
					 AND A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
					;
          pTipoPaginacion := 1;          
          END;
     WHEN NVL(pDetVacunacionId,0) > 0 THEN
        BEGIN
             SELECT COUNT (1)
               INTO vContador 
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              LEFT JOIN SIPAI.SIPAI_DET_VACUNACION B
                ON B.CONTROL_VACUNA_ID  = A.CONTROL_VACUNA_ID AND
                   B.DET_VACUNACION_ID  = pDetVacunacionId
				    AND  B.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
              WHERE A.CONTROL_VACUNA_ID > 0 AND
                    A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO
					 AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
					;
        pTipoPaginacion := 2;
        END;
      WHEN NVL(pControlVacunaId,0) > 0 THEN
        BEGIN
             SELECT COUNT (1)
               INTO vContador 
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              LEFT JOIN SIPAI.SIPAI_DET_VACUNACION B
                ON B.CONTROL_VACUNA_ID  = A.CONTROL_VACUNA_ID
				AND  B.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
              WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
			           A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
                   AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;
        pTipoPaginacion := 3;
        END;       
     ELSE 
        BEGIN
             SELECT COUNT (1)
               INTO vContador 
              FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
              LEFT JOIN SIPAI.SIPAI_DET_VACUNACION B
                ON B.CONTROL_VACUNA_ID  = A.CONTROL_VACUNA_ID
				AND  B.ESTADO_REGISTRO_ID!= vGLOBAL_ESTADO_PASIVO
              WHERE A.CONTROL_VACUNA_ID > 0 AND
                    A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO;
        pTipoPaginacion := 4;
        END; 
     END CASE;

     CASE
     WHEN vContador > 0 THEN
          vExiste := TRUE;
     ELSE NULL;
     END CASE;

  RETURN vExiste;
  EXCEPTION
  WHEN OTHERS THEN
       RETURN vExiste;
  END FN_VALIDA_DET_VACUNA;

 FUNCTION FN_OBT_X_DETID_Y_CTRL_ID (pDetVacunacionId IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE, 
                                    pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE) RETURN var_refcursor AS 
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,  
			     -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.USUARIO_MODIFICACION                                        DETVAC_USR_MODIFICACION,
               DETVAC.FECHA_MODIFICACION                                          DETVAC_FEC_MODIFICACION,
               DETVAC.USUARIO_PASIVA                                              DETVAC_USR_PASIVA, 
               DETVAC.FECHA_PASIVO                                                DETVAC_FEC_PASIVA,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID                                      DETVACUSALUD_US_ENTADMIN,
			   --NUEVOS CAMPOS--- 
               DETVAC.OBSERVACION   			DETV_OBSERVACION,
			   DETVAC.FECHA_PROXIMA_VACUNA 		DETV_FECHA_PROXIMA_VACUNA,
			   DETVAC.NO_APLICADA				DETV_NO_APLICADA,
			   DETVAC.MOTIVO_NO_APLICADA		DETV_MOTIVO_NO_APLICADA,
               DETVAC.TIPO_ESTRATEGIA_ID		DETV_TIPO_ESTRATEGIA_ID,
			   CTESTRATEG.CODIGO				DETV_CODIGO,
			   CTESTRATEG.VALOR					DETV_VALOR,
			   CTESTRATEG.DESCRIPCION			DETV_DESCRIPCION,
				-----------------------
			   DETVAC.ES_REFUERZO,	
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE,
               DETVAC.ES_APLICADA_NACIONAL

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
         AND DETVAC.DET_VACUNACION_ID = pDetVacunacionId
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		 --NUEVO CAMPO ESTRATEGIA
		LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CTESTRATEG
         ON CTESTRATEG.CATALOGO_ID = DETVAC.TIPO_ESTRATEGIA_ID 
	    LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	 	 
		---
    WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		  AND  DETVAC.ESTADO_REGISTRO_ID!= vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

--     DBMS_OUTPUT.PUT_LINE (vQuery);   
--     DBMS_OUTPUT.PUT_LINE (vQuery1); 
 RETURN vRegistro;

 END FN_OBT_X_DETID_Y_CTRL_ID ;

 FUNCTION FN_OBT_X_DETID (pDetVacunacionId IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID,
                 -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.USUARIO_MODIFICACION                                        DETVAC_USR_MODIFICACION,
               DETVAC.FECHA_MODIFICACION                                          DETVAC_FEC_MODIFICACION,
               DETVAC.USUARIO_PASIVA                                              DETVAC_USR_PASIVA, 
               DETVAC.FECHA_PASIVO                                                DETVAC_FEC_PASIVA,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID                                      DETVACUSALUD_US_ENTADMIN,
				--NUEVOS CAMPOS--- 
               DETVAC.OBSERVACION   			DETV_OBSERVACION,
			   DETVAC.FECHA_PROXIMA_VACUNA 		DETV_FECHA_PROXIMA_VACUNA,
			   DETVAC.NO_APLICADA				DETV_NO_APLICADA,
			   DETVAC.MOTIVO_NO_APLICADA		DETV_MOTIVO_NO_APLICADA,
               DETVAC.TIPO_ESTRATEGIA_ID		DETV_TIPO_ESTRATEGIA_ID,
			   CTESTRATEG.CODIGO				DETV_CODIGO,
			   CTESTRATEG.VALOR					DETV_VALOR,
			   CTESTRATEG.DESCRIPCION			DETV_DESCRIPCION,
				 -------------------
			   DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID ,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE

		FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
         AND DETVAC.DET_VACUNACION_ID = pDetVacunacionId
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		 --NUEVO CAMPO ESTRATEGIA
		LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CTESTRATEG
         ON CTESTRATEG.CATALOGO_ID = DETVAC.TIPO_ESTRATEGIA_ID   
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID	  

		-------  
    WHERE A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
	        AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
			AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		    AND  DETVAC.ESTADO_REGISTRO_ID!= vGLOBAL_ESTADO_PASIVO 
         ORDER BY A.CONTROL_VACUNA_ID;
--     DBMS_OUTPUT.PUT_LINE (vQuery);   
--     DBMS_OUTPUT.PUT_LINE (vQuery1);          
     RETURN vRegistro;
 END FN_OBT_X_DETID;

 FUNCTION FN_OBT_X_CTROLID (pControlVacunaId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
                 -----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.USUARIO_MODIFICACION                                        DETVAC_USR_MODIFICACION,
               DETVAC.FECHA_MODIFICACION                                          DETVAC_FEC_MODIFICACION,
               DETVAC.USUARIO_PASIVA                                              DETVAC_USR_PASIVA, 
               DETVAC.FECHA_PASIVO                                                DETVAC_FEC_PASIVA, 
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID                                      DETVACUSALUD_US_ENTADMIN,
			   --NUEVOS CAMPOS--- 
               DETVAC.OBSERVACION   			DETV_OBSERVACION,
			   DETVAC.FECHA_PROXIMA_VACUNA 		DETV_FECHA_PROXIMA_VACUNA,
			   DETVAC.NO_APLICADA				DETV_NO_APLICADA,
			   DETVAC.MOTIVO_NO_APLICADA		DETV_MOTIVO_NO_APLICADA,
               DETVAC.TIPO_ESTRATEGIA_ID		DETV_TIPO_ESTRATEGIA_ID,
			   CTESTRATEG.CODIGO				DETV_CODIGO,
			   CTESTRATEG.VALOR					DETV_VALOR,
			   CTESTRATEG.DESCRIPCION			DETV_DESCRIPCION ,  
				------------------------
			   DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
       LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		--NUEVO CAMPO ESTRATEGIA  
		LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CTESTRATEG
         ON CTESTRATEG.CATALOGO_ID = DETVAC.TIPO_ESTRATEGIA_ID   
		LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID 

    WHERE A.CONTROL_VACUNA_ID = pControlVacunaId AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 		  
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		  AND  DETVAC.ESTADO_REGISTRO_ID!= vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 
--     DBMS_OUTPUT.PUT_LINE (vQuery);   
--     DBMS_OUTPUT.PUT_LINE (vQuery1);          
     RETURN vRegistro;
 END FN_OBT_X_CTROLID;

FUNCTION FN_OBT_DET_VACUNAS_TODOS (pPgnAct IN NUMBER, 
                                    pPgnTmn IN NUMBER) RETURN var_refcursor AS
 vRegistro var_refcursor;
 BEGIN
  OPEN vRegistro FOR
        SELECT A.CONTROL_VACUNA_ID                                                CTRL_VACUNA_ID, 
               A.EXPEDIENTE_ID                                                    CTRL_EXPEDIENTE_ID,
               PERNOM.PACIENTE_ID                                                 CAPT_PACIENTE_ID,
               PERNOM.PACIENTE_ID                                                 PER_PACIENTE_ID,
               PERNOM.ETNIA_ID                                                    PER_ETNIA_ID,
               PERNOM.ETNIA_CODIGO                                                CATETNIA_CODIGO,
               PERNOM.ETNIA_VALOR                                                 CATETNIA_VALOR,
               NULL   /*CATETNIA.DESCRIPCION*/                                    CATETNIA_DESCRIPCION,
               NULL   /*CATETNIA.PASIVO*/                                         CATETNIA_PASIVO,
               PERNOM.TELEFONO                                                    TEL_PACIENTE,         
               PERNOM.CODIGO_EXPEDIENTE_ELECTRONICO                               CTRL_COD_EXP_ELECTRONICO,
               PERNOM.TIPO_EXPEDIENTE_CODIGO                                      CTRL_CODEXP_CODIGO,               -- catálogo codigo expediente
               PERNOM.TIPO_EXPEDIENTE_NOMBRE                                      CTRL_CODEXP_VALOR,        
               NULL   /*TIPEXP.PASIVO*/                                           CTRL_CODEXP_PASIVO,        
               PERNOM.SISTEMA_ORIGEN_ID                                           CTRL_CODEXP_SISTEMA_ID,           -- sistema de codigo de expediente
               PERNOM.SISTEMA_ORIGEN_NOMBRE                                       CTRL_CODEXP_SIST_NOMBRE, 
               NULL   /*SIST.DESCRIPCION*/                                        CTRL_CODEXP_SIST_DESCRIPCION, 
               NULL   /*SIST.CODIGO*/                                             CTRL_CODEXP_SIST_CODIGO,     
               NULL   /*SIST.PASIVO*/                                             CTRL_CODEXP_SIST_PASIVO,     
               NULL   /*PER.UNIDAD_SALUD_ID*/                                     CTRL_COD_EXP_UNSALUD_ID,          -- unidad de salud de codigo de expediente
               NULL   /*USALUD.NOMBRE*/                                           CTRL_CODEXP_US_NOMBRE,    
               NULL   /*USALUD.CODIGO*/                                           CTRL_CODEXP_US_CODIGO,    
               NULL   /*USALUD.RAZON_SOCIAL*/                                     CTRL_CODEXP_US_RSOCIAL, 
               NULL   /*USALUD.DIRECCION*/                                        CTRL_CODEXP_US_DIREC,   
               NULL   /*USALUD.EMAIL*/                                            CTRL_CODEXP_US_EMAIL,   
               NULL   /*USALUD.ABREVIATURA*/                                      CTRL_CODEXP_US_ABREV,   
               NULL   /*USALUD.PASIVO*/                                           CTRL_CODEXP_US_PASIVO,
               NULL   /*USALUD.ENTIDAD_ADTVA_ID*/                                 CTRL_CODEXP_US_ENTADMIN,
               NULL   /*ENTADPER.NOMBRE*/                                         CTRL_CODEXP_US_ENTAD_NOMBRE,
               NULL   /*ENTADPER.CODIGO*/                                         CTRL_CODEXP_US_ENTAD_CODIGO,
               NULL   /*ENTADPER.PASIVO*/                                         CTRL_CODEXP_US_ENTAD_PASIVO, 
               PERNOM.PERSONA_ID                                                  PER_PERSONA_ID,   
               PERNOM.IDENTIFICACION_NUMERO                                       PER_IDENTIFICACION,
               PERNOM.TIPO_IDENTIFICACION_ID                                      PER_CODIGOTIP_ID, 
			-----  PEDIDOS POR EL FRONTED 
			   PERNOM.PAIS_NACIMIENTO_ID,
			   PERNOM.DEPARTAMENTO_NACIMIENTO_ID,
             ------------			   
               NULL /*CATID.CATALOGO_ID*/                                         PER_CATID_ID,                     -- catálogo de tipo de identificación.
               PERNOM.IDENTIFICACION_CODIGO                                       PER_CATID_CODIGO,
               PERNOM.IDENTIFICACION_NOMBRE                                       PER_CATID_VALOR,          
               NULL /*CATID.DESCRIPCION*/                                         PER_CATID_DESCRIPCION,    
               NULL /*CATID.PASIVO*/                                              PER_CATID_PASIVO,
               PERNOM.PRIMER_NOMBRE                                               PER_PRIMER_NOMBRE,
               PERNOM.SEGUNDO_NOMBRE                                              PER_SEGUNDO_NOMBRE,
               PERNOM.PRIMER_APELLIDO                                             PER_PRIMER_APELLIDO,
               PERNOM.SEGUNDO_APELLIDO                                            PER_SEGUNDO_APELLIDO,   
               PERNOM.SEXO_ID                                                     PER_CATSEXO_ID,                   -- catálogo de sexo persona
               PERNOM.SEXO_CODIGO                                                 PER_CATSEXO_CODIGO,      
               PERNOM.SEXO_VALOR                                                  PER_CATSEXO_VALOR,       
               NULL /*CATSEXO.DESCRIPCION*/                                       PER_CATSEXO_DESCRIPCION, 
               NULL /*CATSEXO.PASIVO*/                                            PER_CATSEXO_PASIVO,                         
               PERNOM.FECHA_NACIMIENTO                                            PER_FEC_NACIMIENTO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),0,3) PER_EDAD_ANIO,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),4,2) PER_EDAD_MES,
               SUBSTR (HOSPITALARIO.PKG_CATALOGOS_UTIL.FN_FECHA_NACIMIENTO (PERNOM.FECHA_NACIMIENTO),6,2) PER_EDAD_DIA,
               PERNOM.DIRECCION_RESIDENCIA                                        PER_DIRECCION_DOMICILIO,
        -----------------
               PERNOM.COMUNIDAD_RESIDENCIA_ID                                     PERRES_COMUNIDAD_ID,        --     PER_COMUNIDAD_ID,     
               PERNOM.COMUNIDAD_RESIDENCIA_NOMBRE                                 PERRES_NOMBRE,              --     PER_COMUNIDAD_NOMBRE,
               NULL  /*COMUS.CODIGO*/                                             PERRES_CODIGO,              --     PER_COMUNIDAD_CODIGO,
               NULL  /*COMUS.LATITUD*/                                            PER_COMUNIDAD_LATITUD,
               NULL  /*COMUS.LONGITUD*/                                           PER_COMUNIDAD_LONGITUD,
               NULL  /*COMUS.PASIVO */                                            PERRES_PASIVO,              --     PER_COMUNIDAD_PASIVO, 
               NULL  /*COMUS.FECHA_PASIVO*/                                       PER_COMUNIDAD_FEC_PASIVO,

               PERNOM.MUNICIPIO_RESIDENCIA_ID                                     PERRES_MUNICIPIO_ID,          --   PER_COM_MUNI_ID,            
               PERNOM.MUNICIPIO_RESIDENCIA_NOMBRE                                 PER_MUNI_NOMBRE,              --   PER_COM_MUNI_NOMBRE,       
               NULL  /*MUNUS.CODIGO*/                                             PER_MUN_CODIGO,               --   PER_COM_MUN_CODIGO,        
               NULL  /*MUNUS.CODIGO_CSE*/                                         PER_MUN_CODIGO_CSE,           --   PER_COM_MUN_CODIGO_CSE,    
               NULL  /*MUNUS.CODIGO_CSE_REG*/                                     PER_MUN_CSEREG,               --   PER_COM_MUN_CSEREG,        
               NULL  /*MUNUS.LATITUD*/                                            PER_MUN_LATITUD,              --   PER_COM_MUN_LATITUD,       
               NULL  /*MUNUS.LONGITUD*/                                           PER_MUN_LONGITUD,             --   PER_COM_MUN_LONGITUD,      
               NULL  /*MUNUS.PASIVO*/                                             PER_MUN_PASIVO,               --   PER_COM_MUN_PASIVO,        
               NULL  /*MUNUS.FECHA_PASIVO*/                                       PER_MUN_FEC_PASIVO,           --   PER_COM_MUN_FEC_PASIVO,    

               PERNOM.DEPARTAMENTO_RESIDENCIA_ID                                  PER_MUN_DEP_ID,               --   PER_COM_MUN_DEP_ID,                  
               PERNOM.DEPARTAMENTO_RESIDENCIA_NOMBRE                              PER_MUN_DEP_NOMBRE,           --   PER_COM_MUN_DEP_NOMBRE,              
               NULL  /*DEPUS.CODIGO*/                                             PER_MUN_DEP_CODIGO,           --   PER_COM_MUN_DEP_CODIGO,              
               NULL  /*DEPUS.CODIGO_ISO*/                                         PER_MUN_DEP_CODISO,           --   PER_COM_MUN_DEP_CODISO,              
               NULL  /*DEPUS.CODIGO_CSE*/                                         PER_MUN_DEP_COD_CSE,          --   PER_COM_MUN_DEP_COD_CSE,             
               NULL  /*DEPUS.LATITUD*/                                            PER_MUN_DEP_LATITUD,          --   PER_COM_MUN_DEP_LATITUD,             
               NULL  /*DEPUS.LONGITUD*/                                           PER_MUN_DEP_LONGITUD,         --   PER_COM_MUN_DEP_LONGITUD,            
               NULL  /*DEPUS.PASIVO*/                                             PER_MUN_DEP_PASIVO,           --   PER_COM_MUN_DEP_PASIVO,              
               NULL  /*DEPUS.FECHA_PASIVO*/                                       PER_MUN_DEP_FEC_PASIVO,       --   PER_COM_MUN_DEP_FEC_PASIVO,          
               NULL  /*DEPUS.PAIS_ID*/                                            PER_MUNDEP_PAIS_ID,           --   PER_COM_MUN_DEP_PAIS_ID,             
               NULL  /*PAUS.NOMBRE*/                                              PER_MUNDEP_PAIS_NOMBRE,       --   PER_COM_MUN_DEP_PAIS_NOMBRE,         
               NULL  /*PAUS.CODIGO*/                                              PER_MUNDEP_PAIS_COD,          --   PER_COM_MUN_DEP_PAIS_COD,            
               NULL  /*PAUS.CODIGO_ISO*/                                          PER_MUNDEP_PAIS_CODISO,       --   PER_COM_MUN_DEP_PAIS_CODISO,         
               NULL  /*PAUS.CODIGO_ALFADOS*/                                      PER_MUNDEP_PAIS_CODALF,       --   PER_COM_MUN_DEP_PAIS_CODALF,         
               NULL  /*PAUS.CODIGO_ALFATRES*/                                     PER_MUNDEP_PAIS_CODALFTR,     --   PER_COM_MUN_DEP_PAIS_CODALFTR,       
               NULL  /*PAUS.PREFIJO_TELF*/                                        PER_MUNDEP_PAIS_PREFTELF,     --   PER_COM_MUN_DEP_PAIS_PREFTELF,       
               NULL  /*PAUS.PASIVO*/                                              PER_MUNDEP_PAIS_PASIVO,       --   PER_COM_MUN_DEP_PAIS_PASIVO,         
               NULL  /*PAUS.FECHA_PASIVO*/                                        PER_MUNDEP_PAIS_FECPASIVO,    --   PER_COM_MUN_DEP_PAIS_FECPASIVO,      
               PERNOM.REGION_RESIDENCIA_ID                                        PER_MUNDEP_REG_ID,            --   PER_COM_MUN_DEP_REG_ID,              
               PERNOM.REGION_RESIDENCIA_NOMBRE                                    PER_MUNDEP_REG_NOMBRE,        --   PER_COM_MUN_DEP_REG_NOMBRE,          
               NULL  /*REGUS.CODIGO*/                                             PER_MUNDEP_REG_CODIGO,        --   PER_COM_MUN_DEP_REG_CODIGO,          
               NULL  /*REGUS.PASIVO*/                                             PER_MUNDEP_REG_PASIVO,        --   PER_COM_MUN_DEP_REG_PASIVO,          
               NULL  /*REGUS.FECHA_PASIVO*/                                       PER_MUNDEP_REG_FEC_PASIVO,    --   PER_COM_MUN_DEP_REG_FEC_PASIVO,      

               PERNOM.DISTRITO_RESIDENCIA_ID                                      PERRES_DIS_ID,                --   PER_COM_DIS_ID,                      
               PERNOM.DISTRITO_RESIDENCIA_NOMBRE                                  PERRES_COMDIS_NOMBRE,         --   PER_COM_DIS_NOMBRE,                  
               NULL  /*DISUS.CODIGO*/                                             PERRES_COMDIS_CODIGO,         --   PER_COM_DIS_CODIGO,                  
               NULL  /*DISUS.PASIVO*/                                             PERRES_COMDIS_PASIVO,         --   PER_COM_DIS_PASIVO,                  
               NULL  /*DISUS.FECHA_PASIVO*/                                       PERRES_COMDIS_FEC_PASIVO,     --   PER_COM_DIS_FEC_PASIVO,              
               NULL  /*DISUS.MUNICIPIO_ID*/                                       PERRES_COMDIS_MUN_ID,         --   PER_COM_DIS_MUN_ID,                  
               NULL  /*MUNUS1.NOMBRE*/                                            PER_COMDIS_MUN_NOMBRE,        --   PER_COM_DIS_MUN_NOMBRE,              
               NULL  /*MUNUS1.CODIGO*/                                            PER_COMDIS_MUN_CODIGO,        --   PER_COM_DIS_MUN_CODIGO,              
               NULL  /*MUNUS1.CODIGO_CSE*/                                        PER_COMDIS_MUN_COD_CSE,       --   PER_COM_DIS_MUN_COD_CSE,             
               NULL  /*MUNUS1.CODIGO_CSE_REG*/                                    PER_COMDIS_MUN_CODCSEREG,     --   PER_COM_DIS_MUN_CODCSEREG,           
               NULL  /*MUNUS1.LATITUD*/                                           PER_COMDIS_MUN_LATITUD,       --   PER_COM_DIS_MUN_LATITUD,             
               NULL  /*MUNUS1.LONGITUD*/                                          PER_COMDIS_MUN_LONGITUD,      --   PER_COM_DIS_MUN_LONGITUD,            
               NULL  /*MUNUS1.PASIVO*/                                            PER_COMDIS_MUN_PASIVO,        --   PER_COM_DIS_MUN_PASIVO,              
               NULL  /*MUNUS1.FECHA_PASIVO*/                                      PER_COMDIS_MUN_FECPASIVO,     --   PER_COM_DIS_MUN_FECPASIVO,           

               NULL  /*MUNUS1.DEPARTAMENTO_ID*/                                   PER_COMDISMUN_DEP_ID,         --   PER_COM_DIS_MUN_DEP_ID,              
               NULL  /*DEPUS1.NOMBRE*/                                            PER_COMDISMUN_DEP_NOMBRE,     --   PER_COM_DIS_MUN_DEP_NOMBRE,          
               NULL  /*DEPUS1.CODIGO*/                                            PER_COMDISMUN_DEP_COD,        --   PER_COM_DIS_MUN_DEP_COD,             
               NULL  /*DEPUS1.CODIGO_ISO*/                                        PER_COMDISMUN_DEP_CODISO,     --   PER_COM_DIS_MUN_DEP_CODISO,          
               NULL  /*DEPUS1.CODIGO_CSE*/                                        PER_COMDISMUN_DEP_CODCSE,     --   PER_COM_DIS_MUN_DEP_CODCSE,          
               NULL  /*DEPUS1.LATITUD*/                                           PER_COMDISMUN_DEP_LATITUD,    --   PER_COM_DIS_MUN_DEP_LATITUD,         
               NULL  /*DEPUS1.LONGITUD*/                                          PER_COMDISMUN_DEP_LONGITUD,   --   PER_COM_DIS_MUN_DEP_LONGITUD,        
               NULL  /*DEPUS1.PASIVO*/                                            PER_COMDISMUN_DEP_PASIVO,     --   PER_COM_DIS_MUN_DEP_PASIVO,          
               NULL  /*DEPUS1.FECHA_PASIVO*/                                      PER_COMDISMUN_DEP_FECPASIVO,  --   PER_COM_DIS_MUN_DEP_FECPASIVO,       
               NULL  /*DEPUS1.PAIS_ID*/                                           PER_COMDISMUN_DEP_PA_ID,      --   PER_COM_DIS_MUN_DEP_PA_ID,           
               NULL  /*PAUS1.NOMBRE*/                                             PER_COMDISMUNDEP_PA_NOMBRE,   --   PER_COM_DIS_MUN_DEP_PA_NOMBRE,       
               NULL  /*PAUS1.CODIGO*/                                             PER_COMDISMUNDEP_PA_COD,      --   PER_COM_DIS_MUN_DEP_PA_COD,          
               NULL  /*PAUS1.CODIGO_ISO*/                                         PER_COMDISMUNDEP_PA_CODISO,   --   PER_COM_DIS_MUN_DEP_PA_CODISO,       
               NULL  /*PAUS1.CODIGO_ALFADOS*/                                     PER_COMDISMUNDEP_PA_CODALFA,  --   PER_COM_DIS_MUN_DEP_PA_CODALFA,      
               NULL  /*PAUS1.CODIGO_ALFATRES*/                                    PER_COMDISMUNDEP_PA_ALFTRES,  --   PER_COM_DIS_MUN_DEP_PA_ALFTRES,      
               NULL  /*PAUS1.PREFIJO_TELF*/                                       PER_COMDISMUNDEP_PA_PREFTEL,  --   PER_COM_DIS_MUN_DEP_PA_PREFTEL,      
               NULL  /*PAUS1.PASIVO*/                                             PER_COMDISMUNDEP_PA_PASIVO,   --   PER_COM_DIS_MUN_DEP_PA_PASIVO,       
               NULL  /*PAUS1.FECHA_PASIVO*/                                       PER_COMDISMUNDEP_PA_FECPASI,  --   PER_COM_DIS_MUN_DEP_PA_FECPASI,      
               NULL  /*DEPUS1.REGION_ID*/                                         PER_COMDISMUNDEP_REG_ID,      --   PER_COM_DIS_MUN_DEP_REG_ID,          
               NULL  /*REGUS1.NOMBRE*/                                            PER_COMDISMUNDEP_REG_NOMBRE,  --   PER_COM_DIS_MUN_DEP_REG_NOMBRE,      
               NULL  /*REGUS1.CODIGO*/                                            PER_COMDISMUNDEP_REG_COD,     --   PER_COM_DIS_MUN_DEP_REG_COD,         
               NULL  /*REGUS1.PASIVO*/                                            PER_COMDISMUNDEP_REG_PASIVO,  --   PER_COM_DIS_MUN_DEP_REG_PASIVO,      
               NULL  /*REGUS1.FECHA_PASIVO*/                                      PER_COMDISMUNDEP_REG_FECPAS,  --   PER_COM_DIS_MUN_DEP_REG_FECPAS,      
               PERNOM.LOCALIDAD_ID                                                PERRES_LOCALIDAD_ID,          --   PER_COM_LOCALIDAD_ID,                
               PERNOM.LOCALIDAD_CODIGO                                            CATPERLOCAL_CODIGO,           --   PER_COM_LOCALIDAD_CODIGO,            
               PERNOM.LOCALIDAD_NOMBRE                                            CATPERLOCAL_VALOR,            --   PER_COM_LOCALIDAD_VALOR,             
               NULL  /*.DESCRIPCION*/                                             CATPERLOCAL_DESCRIPCION,      --   PER_COM_LOCALIDAD_DESC,              
               NULL  /*Dd.PASIVO*/                                                CATPERLOCAL_PASIVO,           --   PER_COM_LOCALIDAD_PASIVO,            
        -----                                                                   
               A.PROGRAMA_VACUNA_ID                                               CTRL_PROGRAMA_VACUNA_ID,
               CATPROG.CODIGO                                                     CTRL_CATPROG_CODIGO,
               CATPROG.VALOR                                                      CTRL_CATPROG_VALOR,               
               CATPROG.DESCRIPCION                                                CTRL_CATPROG_DESCRIPCION, 
               CATPROG.PASIVO                                                     CTRL_CATPROG_PASIVO,             
               A.GRUPO_PRIORIDAD_ID                                               CTRL_GRP_PRIORIDAD_ID,
               CATGRPPRIOR.CODIGO                                                 CTRL_CATGRPPRIOR_CODIGO,
               CATGRPPRIOR.VALOR                                                  CTRL_CATGRPPRIOR_VALOR,               
               CATGRPPRIOR.DESCRIPCION                                            CTRL_CATGRPPRIOR_DESCRIPCION,    
               CATGRPPRIOR.PASIVO                                                 CTRL_CCATGRPPRIOR_PASIVO,
               ENFERCRONI.DET_PER_X_ENFCRON_ID                                    ENFERCRONI_ID,               --- Datos enfermedades crónicas
               ENFERCRONI.ENF_CRONICA_ID                                          ENFERCRONI_ENF_CRONICA_ID, 
               CATENFCRON.CODIGO                                                  CATENFCRON_CODIGO,
               CATENFCRON.VALOR                                                   CATENFCRON_VALOR, 
               CATENFCRON.DESCRIPCION                                             CATENFCRON_DESCRIPCION,
               CATENFCRON.PASIVO                                                  CATENFCRON_PASIVO,
               ENFERCRONI.ESTADO_REGISTRO_ID                                      ENFERCRONI_ESTADO_REG_ID,  -- estado registro enfermedades crónicas
               CATESTADOENFERCRO.CODIGO                                           CATESTADOENFERCRO_CODIGO,
               CATESTADOENFERCRO.VALOR                                            CATESTADOENFERCRO_VALOR,
               CATESTADOENFERCRO.DESCRIPCION                                      CATESTADOENFERCRO_DESCRIPCION,
               CATESTADOENFERCRO.PASIVO                                           CATESTADOENFERCRO_PASIVO, 
               ENFERCRONI.USUARIO_REGISTRO                                        ENFERCRONI_USR_REGISTRO,
               ENFERCRONI.FECHA_REGISTRO                                          ENFERCRONI_FEC_REGISTRO,
               A.TIPO_VACUNA_ID                                                   CTRL_REL_TIP_VACUNA,
               RELTIP.TIPO_VACUNA_ID                                              RELTIP_TIPO_VACUNA_ID,
               CATTIPVAC.CODIGO                                                   CTRL_CATTIPVAC_CODIGO,
               CATTIPVAC.VALOR                                                    CTRL_CATTIPVAC_VALOR,          
               CATTIPVAC.DESCRIPCION                                              CTRL_CATTIPVAC_DESCRIPCION,    
               CATTIPVAC.PASIVO                                                   CTRL_CATTIPVAC_PASIVO,         
               RELTIP.FABRICANTE_VACUNA_ID                                        RELTIP_FABRICANTE_VACUNA_ID,               -- catálogo de fabricante vacuna
               CATFABVAC.CODIGO                                                   RELTIP_CATFABVAC_CODIGO,
               CATFABVAC.VALOR                                                    RELTIP_CATFABVAC_VALOR,         
               CATFABVAC.DESCRIPCION                                              RELTIP_CATFABVAC_DESCRIPCION,   
               CATFABVAC.PASIVO                                                   RELTIP_CATFABVAC_PASIVO,                  
               RELTIP.CANTIDAD_DOSIS                                              RELTIP_CANTIDAD_DOSIS,
               RELTIP.ESTADO_REGISTRO_ID                                          RELTIP_CATRELESTREG_ESTADO_ID,             -- catálogo de estado registro rel tipo vacuna dosis
               CATRELESTREG.CODIGO                                                RELTIP_CATRELESTREG_CODIGO,
               CATRELESTREG.VALOR                                                 RELTIP_CATRELESTREG_VALOR,        
               CATRELESTREG.DESCRIPCION                                           RELTIP_CATRELESTREG_DESC,  
               CATRELESTREG.PASIVO                                                RELTIP_CATRELESTREG_PASIVO,             
               RELTIP.NUMERO_LOTE                                                 RELTIP_NUMERO_LOTE,
               RELTIP.FECHA_VENCIMIENTO                                           RELTIP_FECHA_VENCIMIENTO,
               RELTIP.USUARIO_REGISTRO                                            RELTIP_USUARIO_REGISTRO,
               RELTIP.FECHA_REGISTRO                                              RELTIP_FECHA_REGISTRO,
               RELTIP.SISTEMA_ID                                                  RELTIP_SISTEMA_ID,                          -- sistema rel tipo vacuna dosis
               RELTIPSIST.NOMBRE                                                  RELTIPSIST_NOMBRE, 
               RELTIPSIST.DESCRIPCION                                             RELTIPSIST_DESCRIPCION, 
               RELTIPSIST.CODIGO                                                  RELTIPSIST_CODIGO,     
               RELTIPSIST.PASIVO                                                  RELTIPSIST_PASIVO,  
               RELTIP.UNIDAD_SALUD_ID                                             RELTIP_UNIDAD_SALUD_ID,                     -- unidad salud tipo vacuna dosis
               RELTIPSALUD.NOMBRE                                                 RELTIPSALUD_US_NOMBRE,    
               RELTIPSALUD.CODIGO                                                 RELTIPSALUD_US_CODIGO,    
               RELTIPSALUD.RAZON_SOCIAL                                           RELTIPSALUD_US_RSOCIAL, 
               RELTIPSALUD.DIRECCION                                              RELTIPSALUD_US_DIREC,   
               RELTIPSALUD.EMAIL                                                  RELTIPSALUD_US_EMAIL,   
               RELTIPSALUD.ABREVIATURA                                            RELTIPSALUD_US_ABREV,   
               RELTIPSALUD.ENTIDAD_ADTVA_ID                                       RELTIPSALUD_US_ENTADMIN,
               RELTIPSALUD.PASIVO                                                 RELTIPSALUD_US_PASIVO, 
               A.ESTADO_REGISTRO_ID                                               CTRL_ESTADO_REGISTRO_ID,
               CATCTRLESTREG.CODIGO                                               CATCTRLESTREG_CODIGO,
               CATCTRLESTREG.VALOR                                                CATCTRLESTREG_VALOR,              
               CATCTRLESTREG.DESCRIPCION                                          CATCTRLESTREG_DESCRIPCION,    
               CATCTRLESTREG.PASIVO                                               CATCTRLESTREG_PASIVO,     
               A.CANTIDAD_VACUNA_APLICADA                                         CTRL_CANTIDAD_VACUNA_APLICADA,
               A.CANTIDAD_VACUNA_PROGRAMADA                                       CTRL_CANTIDAD_VACUNA_PROG, 
               A.FECHA_INICIO_VACUNA                                              CTRL_FECHA_INICIO_VACUNA,
               A.FECHA_FIN_VACUNA                                                 CTRL_FECHA_FIN_VACUNA,
               A.USUARIO_REGISTRO                                                 CTRL_USUARIO_REGISTRO,
               A.FECHA_REGISTRO                                                   CTRL_FECHA_REGISTRO,
               A.USUARIO_MODIFICACION                                             CTRL_USUARIO_MODIFICACION,
               A.FECHA_MODIFICACION                                               CTRL_FECHA_MODIFICACION,
               A.USUARIO_PASIVA                                                   CTRL_USUARIO_PASIVA,
               A.FECHA_PASIVO                                                     CTRL_FECHA_PASIVO,
               A.SISTEMA_ID                                                       CTRL_SISTEMA_ID,    
               CTRLSIST.NOMBRE                                                    CTRLSIST_NOMBRE, 
               CTRLSIST.DESCRIPCION                                               CTRLSIST_DESCRIPCION, 
               CTRLSIST.CODIGO                                                    CTRLSIST_CODIGO,     
               CTRLSIST.PASIVO                                                    CTRLSIST_PASIVO,  
               A.UNIDAD_SALUD_ID                                                  CTRL_UNI_SALUD_ID,         
               CTRLUSALUD.NOMBRE                                                  CTRLUSALUD_US_NOMBRE,    
               CTRLUSALUD.CODIGO                                                  CTRLUSALUD_US_CODIGO,    
               CTRLUSALUD.RAZON_SOCIAL                                            CTRLUSALUD_US_RSOCIAL, 
               CTRLUSALUD.DIRECCION                                               CTRLUSALUD_US_DIREC,   
               CTRLUSALUD.EMAIL                                                   CTRLUSALUD_US_EMAIL,   
               CTRLUSALUD.ABREVIATURA                                             CTRLUSALUD_US_ABREV,   
               CTRLUSALUD.PASIVO                                                  CTRLUSALUD_US_PASIVO, 
               CTRLUSALUD.ENTIDAD_ADTVA_ID                                        CTRLUSALUD_US_ENTADMIN,
               ENTADMIN_VACUNA.NOMBRE                                             ENTADMIN_VACUNA_NOMBRE,
               ENTADMIN_VACUNA.CODIGO                                             ENTADMIN_VACUNA_CODIGO,
               ENTADMIN_VACUNA.PASIVO                                             ENTADMIN_VACUNA_PASIVO,   
               DETVAC.DET_VACUNACION_ID                                           DETVAC_ID,
               DETVAC.FECHA_VACUNACION                                            DETVAC_FEC_VACUNACION,
               DETVAC.HORA_VACUNACION                                             DETVAC_HORA_VACUNACION,
               DETVAC.DETALLE_VACUNA_X_LOTE_ID                                    LOTE_X_FECVEN_ID,     
               LOTE.NUM_LOTE                                                      DETVAC_NUM_LOTE,                 
               LOTE.FECHA_VENCIMIENTO                                             DETVAC_FEC_VENCIMIENTO,
               LOTE.ESTADO_REGISTRO_ID                                            LOTE_ESTADO_REGISTRO_ID,
               CATLOTESTADO.CODIGO                                                CATLOTESTADO_CODIGO,
               CATLOTESTADO.VALOR                                                 CATLOTESTADO_VALOR,
               CATLOTESTADO.DESCRIPCION                                           CATLOTESTADO_DESCRIPCION,
               CATLOTESTADO.PASIVO                                                CATLOTESTADO_PASIVO,       
               DETVAC.PERSONAL_VACUNA_ID                                          DETVAC_PERSONAL_VACUNA_ID,  
               DETPER.PRIMER_NOMBRE                                               DETPER_PRIMER_NOMBRE,
               DETPER.SEGUNDO_NOMBRE                                              DETPER_SEGUNDO_NOMBRE,
               DETPER.PRIMER_APELLIDO                                             DETPER_PRIMER_APELLIDO,
               DETPER.SEGUNDO_APELLIDO                                            DETPER_SEGUNDO_APELLIDO,
               DETPER.CODIGO                                                      DETPER_CODIGO,
               DETPER.ESTADO_REGISTRO_ID                                          DETPER_ESTADO_REG_ID,                             -- catalogo de estado de registro de detalle personal vacuna
               CATDETPER.CODIGO                                                   CATDETPER_CODIGO,
               CATDETPER.VALOR                                                    CATDETPER_VALOR,              
               CATDETPER.DESCRIPCION                                              CATDETPER_DESCRIPCION,    
               CATDETPER.PASIVO                                                   CATDETPER_PASIVO,               
               DETPER.USUARIO_REGISTRO                                            DETPER_USUARIO_REGISTRO,
               DETPER.FECHA_REGISTRO                                              DETPER_FECHA_REGISTRO,
               DETPER.SISTEMA_ID                                                  DETPER_SISTEMA_ID,                                -- sistema de detalle personal vacuna
               SISTDETPER.NOMBRE                                                  SISTDETPER_SIST_NOMBRE, 
               SISTDETPER.DESCRIPCION                                             SISTDETPER_SIST_DESCRIPCION, 
               SISTDETPER.CODIGO                                                  SISTDETPER_SIST_CODIGO,     
               SISTDETPER.PASIVO                                                  SISTDETPER_SIST_PASIVO, 
               DETPER.UNIDAD_SALUD_ID                                             DETPER_UNIDAD_SALUD_ID,                           -- unidad de salud de detalle personal vacuna
               DETPERUSALUD.NOMBRE                                                DETPERUSALUD_US_NOMBRE,    
               DETPERUSALUD.CODIGO                                                DETPERUSALUD_US_CODIGO,    
               DETPERUSALUD.RAZON_SOCIAL                                          DETPERUSALUD_US_RSOCIAL, 
               DETPERUSALUD.DIRECCION                                             DETPERUSALUD_US_DIREC,   
               DETPERUSALUD.EMAIL                                                 DETPERUSALUD_US_EMAIL,   
               DETPERUSALUD.ABREVIATURA                                           DETPERUSALUD_US_ABREV,   
               DETPERUSALUD.PASIVO                                                DETPERUSALUD_US_PASIVO,
               DETPERUSALUD.ENTIDAD_ADTVA_ID                                      DETPERUSALUD_US_ENTADMIN,
               DETVAC.VIA_ADMINISTRACION_ID                                       DETVAC_VIA_ADMINISTRACION_ID,
               CATVIAADMIN.CODIGO                                                 CATVIAADMIN_CODIGO,
               CATVIAADMIN.VALOR                                                  CATVIAADMIN_VALOR,              
               CATVIAADMIN.DESCRIPCION                                            CATVIAADMIN_DESCRIPCION,    
               CATVIAADMIN.PASIVO                                                 CATVIAADMIN_PASIVO,               
               DETVAC.ESTADO_REGISTRO_ID                                          DETVAC_ESTADO_REGISTRO_ID,                        -- catálogo de estado registro de detalle vacuna
               CATDETVACESTADO.CODIGO                                             CATDETVACESTADO_CODIGO,
               CATDETVACESTADO.VALOR                                              CATDETVACESTADO_VALOR,              
               CATDETVACESTADO.DESCRIPCION                                        CATDETVACESTADO_DESCRIPCION,    
               CATDETVACESTADO.PASIVO                                             CATDETVACESTADO_PASIVO, 
               DETVAC.USUARIO_REGISTRO                                            DETVAC_USUARIO_REGISTRO,
               DETVAC.FECHA_REGISTRO                                              DETVAC_FECHA_REGISTRO,
               DETVAC.USUARIO_MODIFICACION                                        DETVAC_USR_MODIFICACION,
               DETVAC.FECHA_MODIFICACION                                          DETVAC_FEC_MODIFICACION,
               DETVAC.USUARIO_PASIVA                                              DETVAC_USR_PASIVA, 
               DETVAC.FECHA_PASIVO                                                DETVAC_FEC_PASIVA,
               DETVAC.SISTEMA_ID                                                  DETVAC_SISTEMA_ID, 
               DETVACSIST.NOMBRE                                                  DETVACSIST_NOMBRE, 
               DETVACSIST.DESCRIPCION                                             DETVACSIST_DESCRIPCION, 
               DETVACSIST.CODIGO                                                  DETVACSIST_CODIGO,     
               DETVACSIST.PASIVO                                                  DETVACSIST_PASIVO,        
               DETVAC.UNIDAD_SALUD_ID                                             DETVAC_UNIDAD_SALUD_ID, 
               DETVACUSALUD.NOMBRE                                                DETVACUSALUD_US_NOMBRE,    
               DETVACUSALUD.CODIGO                                                DETVACUSALUD_US_CODIGO,    
               DETVACUSALUD.RAZON_SOCIAL                                          DETVACUSALUD_US_RSOCIAL, 
               DETVACUSALUD.DIRECCION                                             DETVACUSALUD_US_DIREC,   
               DETVACUSALUD.EMAIL                                                 DETVACUSALUD_US_EMAIL,   
               DETVACUSALUD.ABREVIATURA                                           DETVACUSALUD_US_ABREV,   
               DETVACUSALUD.PASIVO                                                DETVACUSALUD_US_PASIVO,                 
               DETVACUSALUD.ENTIDAD_ADTVA_ID                                      DETVACUSALUD_US_ENTADMIN,
			    --NUEVOS CAMPOS--- 
               DETVAC.OBSERVACION   			DETV_OBSERVACION,
			   DETVAC.FECHA_PROXIMA_VACUNA 		DETV_FECHA_PROXIMA_VACUNA,
			   DETVAC.NO_APLICADA				DETV_NO_APLICADA,
			   DETVAC.MOTIVO_NO_APLICADA		DETV_MOTIVO_NO_APLICADA,
               DETVAC.TIPO_ESTRATEGIA_ID		DETV_TIPO_ESTRATEGIA_ID,
			   CTESTRATEG.CODIGO				DETV_CODIGO,
			   CTESTRATEG.VALOR					DETV_VALOR,
			   CTESTRATEG.DESCRIPCION			DETV_DESCRIPCION , 	   	   
				 --------------------------
			   DETVAC.ES_REFUERZO,
               DETVAC.CASO_EMBARAZO,
			   DETVAC.REL_TIPO_VACUNA_EDAD_ID,
			   DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID        DETVACUSALUD_ACT_ID,
			   DETVACUSALUD_ACT.NOMBRE                     DETVACUSALUD_ACT_NOMBRE

        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA A
        JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL PERNOM
          ON PERNOM.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- JOIN CATALOGOS.SBC_MST_PERSONAS PER
        --  ON PER.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USALUD
        --  ON USALUD.UNIDAD_SALUD_ID = PER.UNIDAD_SALUD_ID
        -- LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADPER
        --  ON ENTADPER.ENTIDAD_ADTVA_ID = USALUD.ENTIDAD_ADTVA_ID
         JOIN CATALOGOS.SBC_CAT_CATALOGOS CATPROG
          ON CATPROG.CATALOGO_ID = A.PROGRAMA_VACUNA_ID
      LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATGRPPRIOR
          ON CATGRPPRIOR.CATALOGO_ID = A.GRUPO_PRIORIDAD_ID 
        LEFT JOIN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON ENFERCRONI
          ON ENFERCRONI.EXPEDIENTE_ID = A.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATENFCRON
          ON CATENFCRON.CATALOGO_ID = ENFERCRONI.ENF_CRONICA_ID  
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADOENFERCRO
          ON CATESTADOENFERCRO.CATALOGO_ID = ENFERCRONI.ESTADO_REGISTRO_ID 
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS RELTIP
          ON RELTIP.REL_TIPO_VACUNA_ID = A.TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
          ON CATTIPVAC.CATALOGO_ID = RELTIP.TIPO_VACUNA_ID      
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
          ON CATFABVAC.CATALOGO_ID = RELTIP.FABRICANTE_VACUNA_ID   
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATRELESTREG
          ON CATRELESTREG.CATALOGO_ID = RELTIP.ESTADO_REGISTRO_ID   
        JOIN SEGURIDAD.SCS_CAT_SISTEMAS RELTIPSIST
          ON RELTIPSIST.SISTEMA_ID = RELTIP.SISTEMA_ID                      
        JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELTIPSALUD
          ON RELTIPSALUD.UNIDAD_SALUD_ID = RELTIP.UNIDAD_SALUD_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
          ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID                     
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
          ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID                      
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD
          ON CTRLUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN_VACUNA
          ON ENTADMIN_VACUNA.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID 
        LEFT JOIN SIPAI.SIPAI_DET_VACUNACION DETVAC
          ON DETVAC.CONTROL_VACUNA_ID = A.CONTROL_VACUNA_ID  
        LEFT JOIN SIPAI.SIPAI_DET_TIPVAC_X_LOTE LOTE
          ON LOTE.DETALLE_VACUNA_X_LOTE_ID = DETVAC.DETALLE_VACUNA_X_LOTE_ID 
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATLOTESTADO
          ON CATLOTESTADO.CATALOGO_ID = LOTE.ESTADO_REGISTRO_ID  
        JOIN SIPAI.SIPAI_DET_PERSONAL_VACUNA DETPER
          ON DETPER.PERSONAL_VACUNA_ID = DETVAC.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETPERUSALUD
          ON DETPERUSALUD.UNIDAD_SALUD_ID = DETPER.UNIDAD_SALUD_ID  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETPER
          ON CATDETPER.CATALOGO_ID = DETPER.ESTADO_REGISTRO_ID   
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS SISTDETPER
          ON SISTDETPER.SISTEMA_ID = DETPER.SISTEMA_ID 
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVIAADMIN
          ON CATVIAADMIN.CATALOGO_ID = DETVAC.VIA_ADMINISTRACION_ID                                  
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATDETVACESTADO
          ON CATDETVACESTADO.CATALOGO_ID = DETVAC.ESTADO_REGISTRO_ID 
        LEFT JOIN SEGURIDAD.SCS_CAT_SISTEMAS DETVACSIST
          ON DETVACSIST.SISTEMA_ID = DETVAC.SISTEMA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD
          ON DETVACUSALUD.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ID
		  --NUEVO CAMPO ESTRATEGIA
		LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CTESTRATEG
         ON CTESTRATEG.CATALOGO_ID = DETVAC.TIPO_ESTRATEGIA_ID   
       LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD DETVACUSALUD_ACT
		 ON DETVACUSALUD_ACT.UNIDAD_SALUD_ID = DETVAC.UNIDAD_SALUD_ACTUALIZACION_ID  

    WHERE A.CONTROL_VACUNA_ID > 0 AND
          A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO 
		  AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO
		  AND  DETVAC.ESTADO_REGISTRO_ID!= vGLOBAL_ESTADO_PASIVO
         ORDER BY A.CONTROL_VACUNA_ID; 

     RETURN vRegistro;
 END FN_OBT_DET_VACUNAS_TODOS;

  FUNCTION FN_OBT_DATOS_DET_VACUNACION (pDetVacunacionId IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE,
                                       pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE, 
                                       pTipoPaginacion  IN NUMBER,
                                       pPgnAct          IN NUMBER, 
                                       pPgnTmn          IN NUMBER) RETURN var_refcursor AS
  vDatos var_refcursor;
 BEGIN
    CASE
    WHEN (NVL(pDetVacunacionId,0) > 0 AND 
          NVL(pControlVacunaId,0) > 0) THEN
          vDatos := FN_OBT_X_DETID_Y_CTRL_ID (pDetVacunacionId, pControlVacunaId);
    WHEN NVL(pDetVacunacionId,0) > 0 THEN
         vDatos := FN_OBT_X_DETID (pDetVacunacionId);
    WHEN NVL(pControlVacunaId,0) > 0 THEN
         vDatos := FN_OBT_X_CTROLID (pControlVacunaId);
    ELSE 
         vDatos := FN_OBT_DET_VACUNAS_TODOS (pPgnAct, pPgnTmn);
    END CASE;

  RETURN vDatos;
 END FN_OBT_DATOS_DET_VACUNACION;

 PROCEDURE PR_C_DET_VACUNA (pDetVacunacionId IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE,
                             pControlVacunaId IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                             pPgnAct          IN NUMBER,
                             pPgnTmn          IN NUMBER,
                             pRegistro        OUT var_refcursor,
                             pResultado       OUT VARCHAR2,
                             pMsgError        OUT VARCHAR2) IS
  vFirma          VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_C_DET_VACUNA => ';                            
  vTipoPaginacion NUMBER; 
  BEGIN
      CASE
      WHEN (FN_VALIDA_DET_VACUNA (pDetVacunacionId, pControlVacunaId, vTipoPaginacion)) = TRUE THEN 
            pRegistro := FN_OBT_DATOS_DET_VACUNACION(pDetVacunacionId, pControlVacunaId, vTipoPaginacion,
                                                     pPgnAct, pPgnTmn);
      ELSE 
          CASE 
          WHEN (NVL(pDetVacunacionId,0) > 0 AND
                NVL(pControlVacunaId,0) > 0) THEN
                pResultado := 'No se encontraron registros de control vacuna con los parámetros [Id: '||pDetVacunacionId||'] y [Control vacuna: '||pControlVacunaId||']';
                RAISE eRegistroNoExiste;
          WHEN NVL(pDetVacunacionId,0) > 0 THEN
               pResultado := 'No se encontraron registros de control vacuna relacionadas al  [Id: '||pDetVacunacionId||']';
               RAISE eRegistroNoExiste;
          WHEN NVL(pControlVacunaId,0) > 0 THEN
               pResultado := 'No se encontraron registros de control vacuna relacionadas al  [ExpedienteId: '||pControlVacunaId||']';
               RAISE eRegistroNoExiste; 
          WHEN (NVL(pDetVacunacionId,0) = 0 AND
               NVL(pControlVacunaId,0) = 0) THEN
               pResultado := 'No hay registros de vacunas';
               RAISE eRegistroNoExiste;                 
          ELSE
              pResultado := 'No se encontraron control de vacunas registradas';
              RAISE eRegistroNoExiste;             
          END CASE;
      END CASE;
      CASE
      WHEN (NVL(pDetVacunacionId,0) > 0 AND
            NVL(pControlVacunaId,0) > 0) THEN
            pResultado := 'Busqueda de registros realizada con exito para el [Id: '||pDetVacunacionId||'] y [Control vacuna: '||pControlVacunaId||']';
      WHEN NVL(pDetVacunacionId,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con exito para el Expediente Id: '||pDetVacunacionId;
      WHEN NVL(pControlVacunaId,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con exito para el Expediente Id: '||pControlVacunaId;
      ELSE
         pResultado := 'Busqueda de registros realizada con éxito';
      END CASE;    
  EXCEPTION
  WHEN eparametrosinvalidos THEN
      pResultado := pResultado;
      pMsgError  := vFirma ||'Parametros invalidos: ' || pResultado;
  WHEN eRegistroNoExiste THEN
       pResultado := pResultado;
       pMsgError  := vFirma||pResultado;
  WHEN OTHERS THEN
       pResultado := ' Hubo un error inesperado en la Base de Datos. Id de consultas: [DetVacunaId: '||pDetVacunacionId||'] o [Control Vacuna: '||pControlVacunaId||']';
       pMsgError  := vFirma ||pResultado||' - '||SQLERRM; 
  END PR_C_DET_VACUNA;

  PROCEDURE PR_U_DET_VACUNACION (pDetVacunacionId  IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE,
                                 pControlVacunaId  IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                                 pFecVacuna        IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                 pPerVacunaId      IN SIPAI.SIPAI_DET_VACUNACION.PERSONAL_VACUNA_ID%TYPE,
                                 pViaAdmin         IN SIPAI.SIPAI_DET_VACUNACION.VIA_ADMINISTRACION_ID%TYPE,
                                 pHrVacunacion     IN SIPAI.SIPAI_DET_VACUNACION.HORA_VACUNACION%TYPE,
								 pDetVacLoteFecvenId IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE,

                                 ------NUEVOS CAMPOS-------------------------------------------------------------
								 pObservacion		 IN SIPAI.SIPAI_DET_VACUNACION.OBSERVACION%TYPE,
								 pFechaProximaVacuna IN SIPAI.SIPAI_DET_VACUNACION.FECHA_PROXIMA_VACUNA%TYPE, 
								 pNoAplicada		 IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
								 pMotivoNoAplicada   IN SIPAI.SIPAI_DET_VACUNACION.MOTIVO_NO_APLICADA%TYPE,  
								 pTipoEstrategia	 IN SIPAI.SIPAI_DET_VACUNACION.TIPO_ESTRATEGIA_ID%TYPE,

								 pEsRefuerzo                IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,
                                 pCasoEmbarazo              IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,	
								 pIdRelTipoVacunaEdad       IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
								 pUniSaludActualizacionId   IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,	
                                 pEsAplicadaNacional        IN      NUMBER,
								------------------------------------------------------------------------------------ 
								 pUsuario          IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE, 
                                 pEstadoRegistroId IN VARCHAR2,
                                 pResultado        OUT VARCHAR2,
                                 pMsgError         OUT VARCHAR2) IS
  vFirma   VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.PR_U_DET_VACUNACION => ';    
  --Validar programa Esquema
   v_Estado_VacunacionId NUMBER;

    --Edad de Vaunacion
      vExpedienteId NUMBER(10);
      vTextoEdad VARCHAR(250);
      vAnio NUMBER;
      vMes  NUMBER;
      vDia  NUMBER;
      vContarEsavi  NUMBER;

  BEGIN

     SELECT EXPEDIENTE_ID  
     INTO   vExpedienteId
     FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA
     WHERE CONTROL_VACUNA_ID = pControlVacunaId;


      CASE
      WHEN pEstadoRegistroId = vGLOBAL_ESTADO_PASIVO THEN 

		  IF  FN_EXISTE_DOSIS_ANTERIOR  (pControlVacunaId,pDetVacunacionId) THEN
	                pResultado := 'No se puede eliminar la dosis por que existe una o mas dosis posteriores al ' ||pFecVacuna;
                    pMsgError  := pResultado;
                    RAISE ePasivarInvalido;
	    END IF;


          <<PasivaRegistro>>
          BEGIN

          SELECT COUNT(*)  
          INTO vContarEsavi 
          FROM SIPAI_ESAVI_DET_VACUNAS
          WHERE   DET_VACUNACION_ID=pDetVacunacionId
          AND     ESTADO_REGISTRO_ID=6869;

          IF vContarEsavi = 0 THEN 
        
        /*Eliminar Borrado Fisico e implementar borrado Logico para el BI
          --  BORRADO FISICO   --eliminar hijos
           DELETE  SIPAI.SIPAI_DET_VACUNACION_SECTOR
           WHERE DET_VACUNACION_ID =  pDetVacunacionId ;
            --eliminar registros padre uno a uno
            DELETE  SIPAI.SIPAI_DET_VACUNACION
            WHERE DET_VACUNACION_ID     =  pDetVacunacionId ;
            --Restarle 1 aplicada al master  y  actualizar la cantidad de dosis aplicada
            UPDATE  SIPAI.SIPAI_MST_CONTROL_VACUNA
            SET     CANTIDAD_VACUNA_APLICADA =  CANTIDAD_VACUNA_APLICADA-1
            WHERE   CONTROL_VACUNA_ID=pControlVacunaId;
             --eliminar el master se la cantidad aplicada quedo en cero
             DELETE  SIPAI.SIPAI_MST_CONTROL_VACUNA
             WHERE   CONTROL_VACUNA_ID=pControlVacunaId
             AND     CANTIDAD_VACUNA_APLICADA=0;
        */  
        --IMPLEMENTAR BORRADO LOGICO 
         --vGLOBAL_ESTADO_ELIMINADO  CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Eliminado'); 
            UPDATE  SIPAI.SIPAI_DET_VACUNACION
            SET     ESTADO_REGISTRO_ID   =vGLOBAL_ESTADO_ELIMINADO,
                    USUARIO_PASIVA       = pUsuario,
                    FECHA_PASIVO         =SYSDATE,     
                    USUARIO_MODIFICACION =pUsuario,
                    FECHA_MODIFICACION   =SYSDATE 
            WHERE   DET_VACUNACION_ID     =  pDetVacunacionId ;
            
          --Restarle 1 aplicada al master  y  actualizar la cantidad de dosis aplicada
            UPDATE  SIPAI.SIPAI_MST_CONTROL_VACUNA
            SET     CANTIDAD_VACUNA_APLICADA =  CANTIDAD_VACUNA_APLICADA-1,
                    USUARIO_MODIFICACION = pUsuario,
                    FECHA_MODIFICACION   =SYSDATE 
            WHERE   CONTROL_VACUNA_ID=pControlVacunaId;
             --eliminar el master se la cantidad aplicada quedo en cero
             UPDATE  SIPAI.SIPAI_MST_CONTROL_VACUNA
             SET     ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ELIMINADO,
                     USUARIO_PASIVA       = pUsuario,
                     FECHA_PASIVO         =SYSDATE,     
                     USUARIO_MODIFICACION =pUsuario,
                     FECHA_MODIFICACION   =SYSDATE  
             WHERE   CONTROL_VACUNA_ID=pControlVacunaId
             AND     CANTIDAD_VACUNA_APLICADA=0;    
            
              --Eliminar las proximas citas generadas en el expediente de este detalle 
             DELETE  SIPAI.SIPAI_DET_PROXIMA_CITA WHERE EXPEDIENTE_ID=vExpedienteId;   
             --Generar de nuevo las citas del registro al ultimo registro.
            PKG_SIPAI_UTILITARIOS.PR_REGISTRO_DET_ROXIMA_CITA(vExpedienteId,pResultado,pMsgError);

            pResultado := 'El registro se elimino correctamente';          
            PR_ACT_FECHA_INICIO_VAC_MASTER(pControlVacunaId,pResultado,pMsgError);

           ELSE
              pResultado := 'No se puede eliminar el registros de detalle de vacuna por que tiene relacion con la ficha ESAVI';   
              RAISE  eParametrosInvalidos;
            END IF;

    END PasivaRegistro;

       WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN
          <<ActivarRegistro>>
          BEGIN

             UPDATE SIPAI.SIPAI_DET_VACUNACION
                SET ESTADO_REGISTRO_ID   = pEstadoRegistroId, 
                    USUARIO_MODIFICACION = pUsuario,    
                    USUARIO_PASIVA       = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN USUARIO_PASIVA IS NULL THEN pUsuario
                                           ELSE USUARIO_PASIVA
                                           END,    
                    FECHA_PASIVO         = CASE
                                           WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN NULL
                                           WHEN FECHA_PASIVO IS NULL THEN CURRENT_TIMESTAMP
                                           ELSE FECHA_PASIVO
                                           END
              WHERE DET_VACUNACION_ID = pDetVacunacionId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 

					 PR_ACT_FECHA_INICIO_VAC_MASTER(pControlVacunaId,pResultado,pMsgError);

          END ActivarRegistro;
        ELSE 
          <<ActualizarRegistros>>
          BEGIN
          
          -- Validar fecha de dosis solo si ES actualización
            IF pUniSaludActualizacionId IS NOT NULL THEN
                pResultado := FN_VALIDAR_FECHA_DOSIS(
                    pControlVacunaId,
                    pIdRelTipoVacunaEdad,
                    pFecVacuna
                );
                
                IF pResultado != 'OK' THEN
                    pMsgError := pResultado;
                    RAISE eParametrosInvalidos;
                END IF;
            END IF;


              --Validar programa Esquema
			  --DBMS_OUTPUT.PUT_LINE(pControlVacunaId);
			 -- DBMS_OUTPUT.PUT_LINE(pFecVacuna);
             -- v_Estado_VacunacionId := FN_CALCULAR_ESTADO_ACTUALIZACION ( pControlVacunaId, pFecVacuna ,pNoAplicada,pUniSaludActualizacionId,pIdRelTipoVacunaEdad,pResultado,pMsgError );
			 --la funcion v_Estado_VacunacionId no aplica en el update

             --Validar Fechas  Programada en ves INDEX uniq_idx_det_x_fecha control_vacuna_id FECHA_VACUNACION
	          --que es infuncional por registro pasivo
			  IF FN_EXISTE_FECHA_VACUNA_CRTID (pControlVacunaId,pFecVacuna,pDetVacunacionId)  THEN
			   pResultado := 'Existe una dosis aplicada en fecha de vacunacion '||pFecVacuna ;
			   pMsgError  := pResultado;
			   RAISE eRegistroExiste;
			  END IF;

              --Edad de Vacunacion
             vTextoEdad :=PKG_SIPAI_UTILITARIOS.FN_OBT_EDAD(vExpedienteId,pFecVacuna);
             vAnio:=JSON_VALUE(vTextoEdad, '$.anio');
             vMes:=JSON_VALUE(vTextoEdad, '$.mes');
             vDia:=JSON_VALUE(vTextoEdad, '$.dia');

             UPDATE SIPAI.SIPAI_DET_VACUNACION
                SET CONTROL_VACUNA_ID          = NVL(pControlVacunaId,CONTROL_VACUNA_ID),
                    FECHA_VACUNACION           = NVL(pFecVacuna,FECHA_VACUNACION),
                    PERSONAL_VACUNA_ID         = NVL(pPerVacunaId,PERSONAL_VACUNA_ID),
                    VIA_ADMINISTRACION_ID      = NVL(pViaAdmin,VIA_ADMINISTRACION_ID),
                    HORA_VACUNACION            = NVL(pHrVacunacion,HORA_VACUNACION),							
				   ------NUEVOS CAMPOS---
					OBSERVACION					= NVL(pObservacion,OBSERVACION),
		       		FECHA_PROXIMA_VACUNA		= NVL(pFechaProximaVacuna,FECHA_PROXIMA_VACUNA),
					NO_APLICADA					= NVL(pNoAplicada,NO_APLICADA),
		    	    MOTIVO_NO_APLICADA			= NVL(pMotivoNoAplicada,MOTIVO_NO_APLICADA),
		          	TIPO_ESTRATEGIA_ID			= NVL(pTipoEstrategia,TIPO_ESTRATEGIA_ID),
					ES_REFUERZO					= NVL(pEsRefuerzo,ES_REFUERZO),	
                    CASO_EMBARAZO               = NVL(pCasoEmbarazo,CASO_EMBARAZO),
					--REL_TIPO_VACUNA_EDAD_ID     = NVL(pIdRelTipoVacunaEdad,REL_TIPO_VACUNA_EDAD_ID),
					UNIDAD_SALUD_ACTUALIZACION_ID = NVL(pUniSaludActualizacionId,UNIDAD_SALUD_ACTUALIZACION_ID),
              --      ESTADO_VACUNACION_ID          = NVL(v_Estado_VacunacionId,ESTADO_VACUNACION_ID), 	
		            -----Edad Vacunacion----------------------------------------------------------------------------------------
                    EDAD_ANIO   = NVL(vAnio,EDAD_ANIO), 
                    EDAD_MES_EXTRA= NVL(vMes,EDAD_MES_EXTRA),
                    EDAD_DIA_EXTRA= NVL(vDia,EDAD_DIA_EXTRA),
                 --------------------------------------------------------------------  
                    ES_APLICADA_NACIONAL =NVL(pEsAplicadaNacional,ES_APLICADA_NACIONAL),
                    USUARIO_MODIFICACION       = pUsuario

              WHERE DET_VACUNACION_ID = pDetVacunacionId AND

                    ESTADO_REGISTRO_ID != SIPAI.PKG_SIPAI_CONTROL_VACUNAS.vGLOBAL_ESTADO_ELIMINADO; 

				    PR_ACT_FECHA_INICIO_VAC_MASTER(pControlVacunaId,pResultado,pMsgError);	

          END ActualizarRegistros;
        END CASE;

  EXCEPTION
  WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;
  WHEN ePasivarInvalido THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;
WHEN eRegistroExiste THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;
           
WHEN NO_DATA_FOUND THEN
           pResultado := 'Registro no encontrado';
           pMsgError  := vFirma||pResultado||' - '||SQLERRM;    

WHEN OTHERS THEN
       pResultado := 'Error no controlado';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM; 
END PR_U_DET_VACUNACION; 


  PROCEDURE SIPAI_CRUD_DET_VACUNACION (pDetVacunacionId    IN OUT SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE,
                                       pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
                                       pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                       pPerVacunaId        IN SIPAI.SIPAI_DET_VACUNACION.PERSONAL_VACUNA_ID%TYPE,
                                       pViaAdmin           IN SIPAI.SIPAI_DET_VACUNACION.VIA_ADMINISTRACION_ID%TYPE,
                                       pHrVacunacion       IN SIPAI.SIPAI_DET_VACUNACION.HORA_VACUNACION%TYPE,
                                       pDetVacLoteFecvenId IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE,                         
									------NUEVOS CAMPOS-------------------------------------------------------------
									   pObservacion		   IN SIPAI.SIPAI_DET_VACUNACION.OBSERVACION%TYPE,
									   pFechaProximaVacuna IN SIPAI.SIPAI_DET_VACUNACION.FECHA_PROXIMA_VACUNA%TYPE, 
									   pNoAplicada		   IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
									   pMotivoNoAplicada   IN SIPAI.SIPAI_DET_VACUNACION.MOTIVO_NO_APLICADA%TYPE,  
									   pTipoEstrategia	   IN SIPAI.SIPAI_DET_VACUNACION.TIPO_ESTRATEGIA_ID%TYPE,
									   pEsRefuerzo          IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,		
                                       pCasoEmbarazo       IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,
									   pIdRelTipoVacunaEdad IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,															  
									   pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,	
                                       -----------------------------------------------------------------------------------
                                       pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                       pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                       pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                       pAccionEstado    IN VARCHAR2,
                                       --------------Datos de Sectorizacion Residencia-----------------
                                       pSectorResidenciaNombre	                IN   	VARCHAR2,
                                       pSectorResidenciaId	                    IN   	NUMBER, 
                                       pUnidadSaludResidenciaId	                IN   	NUMBER, 
                                       pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaResidenciaId       IN   	NUMBER, 
                                       pEntidadAdministrativaResidenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudResidencia	                IN   	VARCHAR2,
                                       pSectorLongitudResidencia	            IN   	VARCHAR2,
                                       --------------Datos de Sectorizacion Ocurrencia-----------------	
                                       pSectorOcurrenciaId	                    IN   	NUMBER, 
                                       pSectorOcurrenciaNombre	                IN   	VARCHAR2,
                                       pUnidadSaludOcurrenciaId	                IN   	NUMBER, 
                                       pUnidadSaludOcurrenciaNombre	            IN   	VARCHAR2,
                                       pEntidadAdministrativaOcurrenciaId	    IN   	NUMBER, 
                                       pEntidadAdministrativaOcurrenciaNombre	IN   	VARCHAR2,
                                       pSectorLatitudOcurrencia	                IN   	VARCHAR2,
                                       pSectorLongitudOcurrencia	            IN   	VARCHAR2,
                                       --2024 Agregar Comunidad-----------------------------------------
                                       pComunidadResidenciaId                   IN   	NUMBER,  
                                       pComunidadResidenciaNombre               IN   	VARCHAR2,
                                       pComunidadoOcurrenciaId                  IN   	NUMBER,  
                                       pComunidadOcurrrenciaNombre              IN   	VARCHAR2,
                                       pEsAplicadaNacional                      IN      NUMBER, 
                                       pGrpPrioridad                           IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                       -----------------------------------------------------------------
                                       pTipoAccion         IN VARCHAR2,
                                       ----------------Parametros de Salidas ---------------------------					   
                                       pRegistro        OUT var_refcursor,
                                       pResultado       OUT VARCHAR2,
                                       pMsgError        OUT VARCHAR2) IS

  vFirma            VARCHAR2(100) := 'PKG_SIPAI_REGISTRO_NOMINAL.SIPAI_CRUD_DET_VACUNACION => '||pFecVacuna||' - ';  
  vEstadoRegistroId SIPAI.SIPAI_DET_VACUNACION.ESTADO_REGISTRO_ID%TYPE;   



  vPgnAct NUMBER;
  vPgnTmn NUMBER;  
  vTipoPaginacion NUMBER; --Agregar a V2


  BEGIN
     -- Lote obligatorio solo si NO es actualización
    IF pUniSaludActualizacionId IS NULL AND pDetVacLoteFecvenId IS NULL THEN
        pResultado := 'El lote es obligatorio';
        pMsgError  := pResultado;
        RAISE eParametrosInvalidos;
    END IF;

    
      CASE
      WHEN pTipoAccion IS NULL THEN 
           pResultado := 'El párametro pTipoOperacion no puede venir NULL';
           pMsgError  := pResultado;
           RAISE eParametroNull;
      ELSE NULL;
      END CASE;	 


      CASE
      WHEN pTipoAccion = kINSERT THEN

           --POST PROD VALIDAR EL SILAIS OCURRENCIA
           /*CASE
             WHEN NVL(pEntidadAdministrativaOcurrenciaId,0) = 0  THEN
                pResultado := 'El Silais Id de Ocurrencia no puede ser nulo ';
                pMsgError  := pResultado;
                RAISE eParametroNull;  
            ELSE NULL;
            END CASE; */
            
        -- Validar fecha solo si ES actualización
    IF pUniSaludActualizacionId IS NOT NULL THEN
        pResultado := FN_VALIDAR_FECHA_DOSIS(
            pControlVacunaId,
            pIdRelTipoVacunaEdad,
            pFecVacuna
        );
        
        IF pResultado != 'OK' THEN
            pMsgError := pResultado;
            RAISE eParametrosInvalidos;
        END IF;
    END IF;

           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;

           CASE
           WHEN NVL(pSistemaId,0) = 0  THEN
              pResultado := 'El Id sistema no puede venir nulo';
              pMsgError  := pResultado;
              RAISE eParametroNull;                  
           ELSE NULL;
           END CASE;

           PR_I_DET_VACUNACION (pDetVacunacionId => pDetVacunacionId, 
                                pControlVacunaId => pControlVacunaId, 
                                pFecVacuna       => pFecVacuna,       
                                pPerVacunaId     => pPerVacunaId,     
                                pViaAdmin        => pViaAdmin,        
                                pHrVacunacion    => pHrVacunacion,  
								pDetVacLoteFecvenId => pDetVacLoteFecvenId,		
								------NUEVOS CAMPOS-------------------------------------------------------------
								 pObservacion		 => pObservacion,
								 pFechaProximaVacuna => pFechaProximaVacuna, 
								 pNoAplicada		 => pNoAplicada, 
								 pMotivoNoAplicada   => pMotivoNoAplicada,  
								 pTipoEstrategia	 => pTipoEstrategia,
								 pEsRefuerzo          => pEsRefuerzo,
                                 pCasoEmbarazo       => pCasoEmbarazo,
								 pIdRelTipoVacunaEdad => pIdRelTipoVacunaEdad,	
								 pUniSaludActualizacionId=> pUniSaludActualizacionId,
                                 ---Sectorizacion Residencia--------------------------------------------------
                                 pSectorResidenciaNombre	=>	pSectorResidenciaNombre	,
                                pSectorResidenciaId	=>	pSectorResidenciaId	,
                                pUnidadSaludResidenciaId	=>	pUnidadSaludResidenciaId	,
                                pUnidadSaludResidenciaNombre	=>	pUnidadSaludResidenciaNombre	,
                                pEntidadAdministrativaResidenciaId	=>	pEntidadAdministrativaResidenciaId	,
                                pEntidadAdministrativaResidenciaNombre	=>	pEntidadAdministrativaResidenciaNombre	,
                                pSectorLatitudResidencia	=>	pSectorLatitudResidencia	,
                                pSectorLongitudResidencia	=>	pSectorLongitudResidencia	,
                                 ---Sectorizacion Ocurrencia--------------------------------------------------            
                                pSectorOcurrenciaId	=>	pSectorOcurrenciaId	,
                                pSectorOcurrenciaNombre	=>	pSectorOcurrenciaNombre	,
                                pUnidadSaludOcurrenciaId	=>	pUnidadSaludOcurrenciaId	,
                                pUnidadSaludOcurrenciaNombre	=>	pUnidadSaludOcurrenciaNombre	,
                                pEntidadAdministrativaOcurrenciaId	=>	pEntidadAdministrativaOcurrenciaId	,
                                pEntidadAdministrativaOcurrenciaNombre	=>	pEntidadAdministrativaOcurrenciaNombre	,
                                pSectorLatitudOcurrencia	=>	pSectorLatitudOcurrencia	,
                                pSectorLongitudOcurrencia	=>	pSectorLongitudOcurrencia	,
                                --2024 Agregar Comunidad-----------------------------------------
                                pComunidadResidenciaId                   => pComunidadResidenciaId,  
                                pComunidadResidenciaNombre               => pComunidadResidenciaNombre,
                                pComunidadoOcurrenciaId                  => pComunidadoOcurrenciaId,  
                                pComunidadOcurrrenciaNombre              => pComunidadOcurrrenciaNombre,
                                pEsAplicadaNacional                      => pEsAplicadaNacional,
                                pGrpPrioridad                           =>  pGrpPrioridad,
								------------------------------------------------------------------------------------            
                                pUniSaludId         => pUniSaludId,
                                pSistemaId          => pSistemaId,       
                                pUsuario            => pUsuario,                               
                                pResultado          => pResultado,       
                                pMsgError           => pMsgError);        
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF; 

           CASE
           WHEN NVL(pDetVacunacionId,0) > 0 THEN
                PR_C_DET_VACUNA (pDetVacunacionId => pDetVacunacionId,
                                 pControlVacunaId => pControlVacunaId,  
                                 pPgnAct          => vPgnAct,
                                 pPgnTmn          => vPgnTmn,
                                 pRegistro        => pRegistro,   
                                 pResultado       => pResultado,       
                                 pMsgError        => pMsgError);
                IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                   RAISE eSalidaConError;
                END IF;
           ELSE NULL;
           END CASE;
           pResultado := 'Registro creado con Exito';
           
      WHEN pTipoAccion = kUPDATE THEN
           CASE
           WHEN pUsuario IS NULL THEN
                pResultado := 'El usuario no puede venir nulo.';
                pMsgError  := pResultado;
                RAISE eParametroNull;
           ELSE 
                dbms_output.put_line ('antes de validar usuario');
                CASE -- validamos que el usuario se valido, con mst_usuarios
                WHEN (SIPAI.PKG_SIPAI_UTILITARIOS.FN_VALIDAR_USUARIO (pUsuario)) = FALSE THEN
                      pResultado := 'Usuario no valido';
                      pMsgError  := pResultado;
                      RAISE eRegistroNoExiste;
                ELSE NULL;
                END CASE;
           END CASE;
           CASE
           WHEN NVL(pDetVacunacionId,0) = 0 THEN  --NVL(pExpedienteId,0) = 0 THEN
                    pResultado := 'Id no puede venir NULL';
                    pMsgError  := pResultado;
                    RAISE eParametroNull;
           ELSE NULL; 
           END CASE;            
           CASE
           WHEN pAccionEstado = 0 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_ACTIVO;
           WHEN pAccionEstado = 1 THEN
                vEstadoRegistroId := vGLOBAL_ESTADO_PASIVO;
           ELSE NULL;
           END CASE; 
           
           
           
           PR_U_DET_VACUNACION (pDetVacunacionId  => pDetVacunacionId, 
                                pControlVacunaId  => pControlVacunaId,
                                pFecVacuna        => pFecVacuna,      
                                pPerVacunaId      => pPerVacunaId,    
                                pViaAdmin         => pViaAdmin,       
                                pHrVacunacion     => pHrVacunacion, 
								pDetVacLoteFecvenId=> pDetVacLoteFecvenId,                       
								------NUEVOS CAMPOS-------------------------------------------------------------
								 pObservacion		 => pObservacion,
								 pFechaProximaVacuna => pFechaProximaVacuna, 
								 pNoAplicada		 => pNoAplicada, 
								 pMotivoNoAplicada   => pMotivoNoAplicada,  
								 pTipoEstrategia	 => pTipoEstrategia,
								 pEsRefuerzo              => pEsRefuerzo,
                                 pCasoEmbarazo            => pCasoEmbarazo,
								 pIdRelTipoVacunaEdad     => pIdRelTipoVacunaEdad,	
								 pUniSaludActualizacionId => pUniSaludActualizacionId,
                                 pEsAplicadaNacional      => pEsAplicadaNacional,
								-----------------------------------------------------------------------------------						   
                                pUsuario          => pUsuario,        
                                pEstadoRegistroId => vEstadoRegistroId,   
                                pResultado        => pResultado,      
                                pMsgError         => pMsgError);   
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF; 

           CASE
           WHEN NVL(pDetVacunacionId,0) > 0 THEN

		   --Verificar que control vacuna esta activo con uno o mas detalle
		   --IF FN_VALIDAR_MASTER_DETELLE_PASIVADO(pDetVacunacionId,pControlVacunaId)THEN
		   IF FN_VALIDA_DET_VACUNA (pDetVacunacionId, pControlVacunaId, vTipoPaginacion) THEN 

			   PR_C_DET_VACUNA (pDetVacunacionId => pDetVacunacionId,
                                 pControlVacunaId => pControlVacunaId,  
                                 pPgnAct          => vPgnAct,
                                 pPgnTmn          => vPgnTmn,
                                 pRegistro        => pRegistro,   
                                 pResultado       => pResultado,       
                                 pMsgError        => pMsgError);
		   END IF;


                IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
                   RAISE eSalidaConError;
                END IF;
           ELSE NULL;
           END CASE;                                    
           pResultado := 'Registro actualizado con éxito';

      WHEN pTipoAccion = kCONSULTAR THEN
           PR_C_DET_VACUNA (pDetVacunacionId => pDetVacunacionId,
                            pControlVacunaId => pControlVacunaId,  
                            pPgnAct          => vPgnAct,
                            pPgnTmn          => vPgnTmn,
                            pRegistro        => pRegistro,   
                            pResultado       => pResultado,       
                            pMsgError        => pMsgError);
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;
      ELSE NULL;
      END CASE;
  EXCEPTION
      WHEN eUpdateInvalido THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;      
      WHEN eParametroNull THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroNoExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;
      WHEN eRegistroExiste THEN
           pResultado := pResultado;  
           pMsgError  := vFirma||pMsgError;                       
      WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;
      WHEN eSalidaConError THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pMsgError;  --vMsgError;
           
      WHEN NO_DATA_FOUND THEN
           pResultado := 'Registro no encontrado';
           pMsgError  := vFirma||pResultado||' - '||SQLERRM;    
           
      WHEN OTHERS THEN
           pResultado := 'Error no controlado';
           pMsgError  := vFirma||pResultado||' - '||SQLERRM;       
  END SIPAI_CRUD_DET_VACUNACION; 

END PKG_SIPAI_REGISTRO_NOMINAL;
/