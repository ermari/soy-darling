CREATE OR REPLACE PACKAGE BODY SIPAI.PKG_SIPAI_UTILITARIOS
AS

 FUNCTION FN_VALIDAR_USUARIO (pUsuario IN VARCHAR2) RETURN BOOLEAN AS
 vContador SIMPLE_INTEGER := 0;
 vRetorna  BOOLEAN := FALSE;
 BEGIN

      IF pUsuario IS NOT NULL THEN
         SELECT COUNT (1)
           INTO vContador
           FROM SEGURIDAD.SCS_MST_USUARIOS
          WHERE UPPER (USERNAME) = UPPER (pUsuario) AND
                ROWNUM = 1;

         IF vContador > 0 THEN
            vRetorna := TRUE;
         END IF;
      END IF;
         RETURN vRetorna;
  EXCEPTION
    WHEN OTHERS THEN
         RETURN FALSE;     
 END FN_VALIDAR_USUARIO;

 FUNCTION FN_OBT_ESTADO_REGISTRO (pValor IN CATALOGOS.SBC_CAT_CATALOGOS.VALOR%TYPE) RETURN NUMBER AS
 vCatalogoId CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE;
 BEGIN
  -- 6869    ACTREG    Activo
  -- 6870    PASREG    Pasivo
  -- 6871    DELREG    Eliminado
     SELECT A.CATALOGO_ID
       INTO vCatalogoId  
       FROM CATALOGOS.SBC_CAT_CATALOGOS A
       JOIN CATALOGOS.SBC_CAT_CATALOGOS B 
         ON A.CATALOGO_SUP = B.CATALOGO_ID AND
            B.CODIGO = 'STREG' AND 
            B.PASIVO = 0
      WHERE A.VALOR  = pValor AND
            A.PASIVO = 0;

     RETURN vCatalogoId;
 EXCEPTION
  WHEN NO_DATA_FOUND THEN
       RETURN vCatalogoId;
  WHEN OTHERS THEN  
       RAISE_APPLICATION_ERROR (-20000, 'Problema al intentar obtener estado del registro. '||SQLERRM);     
       RETURN vCatalogoId;    
 END FN_OBT_ESTADO_REGISTRO;

 PROCEDURE PR_FORMATEO_NOMBRES (pPrimerNombre    IN OUT CATALOGOS.SBC_MST_PERSONAS.PRIMER_NOMBRE%TYPE,
                                pSegundoNombre   IN OUT CATALOGOS.SBC_MST_PERSONAS.SEGUNDO_NOMBRE%TYPE,
                                pPrimerApellido  IN OUT CATALOGOS.SBC_MST_PERSONAS.PRIMER_APELLIDO%TYPE,
                                pSegundoApellido IN OUT CATALOGOS.SBC_MST_PERSONAS.SEGUNDO_APELLIDO%TYPE) IS
  vFirma varchar2 (100) := 'PKG_SIPAI_CONTROL_VACUNAS.PR_FORMATEO_NOMBRES => ';                                
 BEGIN
       IF INSTR(pPrimerNombre,' ') > 0 THEN
                pSegundoNombre := TRIM(SUBSTR(pPrimerNombre,INSTR(pPrimerNombre,' ')+1) || ' ' || pSegundoNombre);
                pPrimerNombre  := TRIM(SUBSTR(pPrimerNombre,1,INSTR(pPrimerNombre,' ')-1));
       END IF;

       IF INSTR(pPrimerApellido,' ') > 0 THEN
                pSegundoApellido := SUBSTR(pPrimerApellido,INSTR(pPrimerApellido,' ')+1) || ' ' || pSegundoApellido;
                pPrimerApellido  := SUBSTR(pPrimerApellido,1,INSTR(pPrimerApellido,' ')-1);
       END IF; 
 END PR_FORMATEO_NOMBRES;
 PROCEDURE PR_FORMATEAR_PARAMETROS (pIdentificacion  IN OUT VARCHAR2,
                                    pNombreCompleto  IN OUT VARCHAR2,
                                    pPrimerNombre    IN OUT VARCHAR2,
                                    pSegundoNombre   IN OUT VARCHAR2,
                                    pPrimerApellido  IN OUT VARCHAR2,
                                    pSegundoApellido IN OUT VARCHAR2,
                                    pResultado       OUT VARCHAR2,
                                    pMsgError        OUT VARCHAR2) IS
 vFirma        varchar2 (100) := 'PKG_SIPAI_CONTROL_VACUNAS.PR_FORMATEAR_PARAMETROS => ';  
 BEGIN
     CASE
     WHEN (pPrimerNombre IS NOT NULL AND pPrimerApellido IS NOT NULL) THEN
           pPrimerNombre    := CATALOGOS.PKG_PR.FN_VALIDA_CADENA ('Primer Nombre',REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pPrimerNombre,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL),50,2,TRUE);         --TRIM(REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pPrimerNombre,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL));
           pSegundoNombre   := CATALOGOS.PKG_PR.FN_VALIDA_CADENA ('Segundo Nombre',REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pSegundoNombre,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL),50,0,FALSE);      --TRIM(REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pSegundoNombre,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL));
           pPrimerApellido  := CATALOGOS.PKG_PR.FN_VALIDA_CADENA ('Primer Apellido',REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pPrimerApellido,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL),50,2,TRUE);     --TRIM(REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pPrimerApellido,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL));
           pSegundoApellido := CATALOGOS.PKG_PR.FN_VALIDA_CADENA ('Segundo Apellido',REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pSegundoApellido,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL),50,0,FALSE);  --TRIM(REGEXP_REPLACE (TRANSLATE(UPPER (TRIM(REGEXP_REPLACE(pSegundoApellido,'[ ]+',' '))),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'), kSoloTexto, NULL));

           PR_FORMATEO_NOMBRES(pPrimerNombre    => pPrimerNombre,
                               pSegundoNombre   => pSegundoNombre, 
                               pPrimerApellido  => pPrimerApellido,
                               pSegundoApellido => pSegundoApellido);
           pNombreCompleto := pPrimerApellido||' '||pPrimerNombre;
     ELSE NULL;
     END CASE;
     CASE
     WHEN pIdentificacion IS NOT NULL THEN
          pIdentificacion  := REPLACE(REPLACE(REPLACE(TRANSLATE(UPPER(TRIM(pIdentificacion)),'ÁÉÍÓÚÄËÏÖÜ','AEIOUAEIOU'),'-'),'/'),' ');
     ELSE NULL;
     END CASE;
 EXCEPTION
 WHEN OTHERS THEN 
      pResultado := 'Error no controlado al intentar formatear los nombres';
      pMsgError  := vFirma||pResultado||' - '||SQLERRM; 
 END PR_FORMATEAR_PARAMETROS;

 PROCEDURE PR_VALIDA_RANGO_FECHA (pFechaInicio IN DATE,
                                  pFechaFin    IN DATE,
                                  pResultado   OUT VARCHAR2,
                                  pMsgError    OUT VARCHAR2) IS
 vFirma VARCHAR2(100) := 'PKG_SIPAI_UTILITARIOS.PR_VALIDA_RANGO_FECHA => ';                                 
 BEGIN
    CASE
    WHEN trunc(pFechaInicio) IS NULL OR trunc(pFechaFin) IS NULL THEN
        CASE
        WHEN pFechaInicio IS NULL AND pFechaFin IS NULL THEN
             pResultado := 'La fecha inicial y fecha final no pueden venir nulos';
             pMsgError  := pResultado;
             RAISE eParametroNull;
        WHEN pFechaInicio IS NULL THEN
             pResultado := 'La fecha inicial no puede venir nula';
             pMsgError  := pResultado;
             RAISE eParametroNull;
        ELSE
             pResultado := 'La fecha final no puede venir nula';
             pMsgError  := pResultado;
             RAISE eParametroNull;
        END CASE;
    ELSE 
        CASE
        WHEN trunc(pFechaFin) < trunc(pFechaInicio) THEN
             pResultado := 'La fecha final no puede ser menor a la fecha inicial';
             pMsgError  := pResultado;
             RAISE eParametrosInvalidos;
        WHEN TRUNC(pFechaInicio) > TRUNC(SYSDATE) THEN
             pResultado := 'La fecha inicial no puede ser mayor al día de hoy';
             pMsgError  := pResultado;
             RAISE eParametrosInvalidos;  
        ELSE NULL;          
        END CASE;
    END CASE; 
 EXCEPTION
 WHEN eParametroNull THEN
      pResultado := pResultado;
      pMsgError  := vFirma||pMsgError;
 WHEN eParametrosInvalidos THEN
      pResultado := pResultado;
      pMsgError  := vFirma||pMsgError;
 WHEN OTHERS THEN
      pResultado := 'Error no controlado al validar fechas de parámetros.';
      pMsgError  := vFirma||pResultado||' - '||sqlerrm;
 END PR_VALIDA_RANGO_FECHA; 
 
 FUNCTION FN_OBT_EDAD ( pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,					  
                            pFecVacuna       IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE
				          ) RETURN VARCHAR AS

 -- v_json CLOB;
  f_nacimiento date; --fecha de nacimiento de la persona
  f_calculo date:=pFecVacuna; --fecha a la cual deseamos saber la edad
  --
  textoEdad VARCHAR2(500) ;
  solo_meses number;
  anio number;
  mes number;
  dia number;

 BEGIN
   
       --datos iniciales
     SELECT FECHA_NACIMIENTO  
     INTO   f_nacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pExpedienteId;
     
    --todo a meses
    solo_meses := months_between(f_calculo, f_nacimiento);
    anio := trunc(solo_meses / 12);
    mes := trunc(mod(solo_meses, 12));
    dia := f_calculo - add_months(f_nacimiento, trunc(solo_meses));
    
   -- SELECT JSON_OBJECT('anio' VALUE anios,'mes' VALUE meses,'dia' VALUE dias) INTO v_json  FROM DUAL;
    
    textoEdad:= '{'
                   || '"anio":' ||'"'||anio|| '"'||', '
                   || '"mes":' ||'"'|| mes || '"'||', '
                   || '"dia":' ||'"'|| dia || '"'||'} ';
 
   RETURN textoEdad;

 END FN_OBT_EDAD; 
 
 FUNCTION FN_OBT_VACUNA_PROXIMA_CITA ( pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE				  
				          ) RETURN VARCHAR AS
 
   pregistro                  SYS_REFCURSOR;
   v_fecha_proxima_cita       varchar2(50);
   vListaVacunasProximaCita   VARCHAR2(500);
   vObjetoJson                VARCHAR2(550);

 BEGIN
 
  PKG_SIPAI_RPT_VACUNACION.REPORTE_FECHA_PROXIMA_CITA(
                                                        PEXPEDIENTEID => PEXPEDIENTEID,
                                                        PREGISTRO => PREGISTRO
                                                      );
   IF PREGISTRO IS not NULL THEN
        LOOP
          FETCH pregistro INTO v_fecha_proxima_cita, vListaVacunasProximaCita;
          EXIT WHEN pregistro%NOTFOUND;
          DBMS_OUTPUT.PUT_LINE('vListaVacunasProximaCita: ' || vListaVacunasProximaCita );
       END LOOP;
       CLOSE pregistro;
   END IF;
  
   -- SELECT JSON_OBJECT('anio' VALUE anios,'mes' VALUE meses,'dia' VALUE dias) INTO v_json  FROM DUAL;
    
    vObjetoJson:= '{'
                   || '"fechaUltimaCita":' ||'"'||v_fecha_proxima_cita|| '"'||', '
                   || '"VacunasUltimaCita":' ||'"'|| vListaVacunasProximaCita || '"'||'} ';
 
   RETURN vObjetoJson;

 END FN_OBT_VACUNA_PROXIMA_CITA; 
 
 FUNCTION FN_CALCULAR_ESTADO_ACTUALIZACION_VACUNA ( pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,					  
                                                    pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                                    pNoAplicada		   IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
                                                    pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,	
                                                    pIdRelTipoVacunaEdad  IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE
                                           ) 
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


     DBMS_OUTPUT.PUT_LINE('pUniSaludActualizacionId = '  || pUniSaludActualizacionId);
     DBMS_OUTPUT.PUT_LINE('v_edad_vacuna = ' || v_edad_vacuna);
     DBMS_OUTPUT.PUT_LINE('vEdadHasta = '    || vEdadHasta);
     DBMS_OUTPUT.PUT_LINE('vDosisRefuerzo = '|| vDosisRefuerzo);
     DBMS_OUTPUT.PUT_LINE('vDosisAdicional = '||vDosisAdicional);


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
       DBMS_OUTPUT.PUT_LINE('f_nacimiento = ' || f_nacimiento);
       DBMS_OUTPUT.PUT_LINE('pFecVacuna = ' || pFecVacuna);

        v_meses_paciente_edad := round(months_between(f_calculo, f_nacimiento));
      DBMS_OUTPUT.PUT_LINE('v_meses_paciente_edad = ' || v_meses_paciente_edad);

        -- ASIGNACION NUEVOS CAMPOS
        v_dias_vacuna := (v_edad_vacuna * 30); 
        --v_dias_vacuna_dias_aportuno:= (v_dias_vacuna + 29);
        v_dias_vacuna_dias_aportuno:= (vEdadHasta *30)+30 + 29;

        DBMS_OUTPUT.PUT_LINE('v_dias_vacuna = ' || v_dias_vacuna);
        DBMS_OUTPUT.PUT_LINE('v_dias_vacuna_dias_aportuno = ' || v_dias_vacuna_dias_aportuno);

        --SELECT (TO_DATE(pFecVacuna,'DD/MM/YY') - TO_DATE(f_nacimiento,'DD/MM/YY'))

        select ROUND(months_between(pFecVacuna, f_nacimiento)) * 30 
        INTO v_dias_actuales
        FROM DUAL;
        DBMS_OUTPUT.PUT_LINE('v_dias_actuales = ' || v_dias_actuales);
        SELECT TRUNC(months_between(TO_DATE(pFecVacuna,'DD/MM/YY'),dob)/12)
        INTO v_anio_actuales
        FROM (Select to_date(f_nacimiento,'DD/MM/YY') DOB FROM DUAL);
       DBMS_OUTPUT.PUT_LINE('v_anio_actuales = ' || v_anio_actuales);

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

          DBMS_OUTPUT.PUT_LINE('v_estado_edad = ' || v_estado_edad);
        CASE
            WHEN NVL(pUniSaludActualizacionId, 0 ) > 0 AND  v_estado_edad = 1 THEN
              vCatalogoId:= FN_SIPAI_CATALOGO_ESTADO_Id('EST_APL_VAC||08');

            WHEN NVL(pUniSaludActualizacionId, 0 ) > 0 AND  v_estado_edad = 2 THEN
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
 END FN_CALCULAR_ESTADO_ACTUALIZACION_VACUNA;
 
FUNCTION FN_OBTENER_CURSOR_VACUNAS_PROXIMA_CITA (pExpedienteId IN PLS_INTEGER ) RETURN var_refcursor AS
              


 vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
 pRegistro var_refcursor;


v_fecha_proxima_cita varchar2(30);
v_orden_vacuna_edad  number;
v_proxima_edad  varchar2(30);
v_vacunas varchar2(4000);

v_codigo_VPH_SEXO  varchar2(30);
v_fecha_proxima_citadT_embarazada varchar2(30);

vEdad NUMBER;
v_fecha_proxima_cita_detalle date; 
v_fecha_nacimiento_persona date;

vcontador NUMBER;

   BEGIN
   --SEXO PARA VPH
   SELECT SEXO_CODIGO , FECHA_NACIMIENTO
   INTO   v_codigo_VPH_SEXO, v_fecha_nacimiento_persona
   FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
   WHERE  EXPEDIENTE_ID=pExpedienteId;

   DBMS_OUTPUT.PUT_LINE('v_codigo_VPH_SEXO= ' || v_codigo_VPH_SEXO);
   DBMS_OUTPUT.PUT_LINE('v_fecha_nacimiento_persona= ' || v_fecha_nacimiento_persona);

   SELECT  FECHA_PROXIMA_VACUNA
    INTO   v_fecha_proxima_cita_detalle
    FROM   SIPAI_DET_VACUNACION
    WHERE  DET_VACUNACION_ID =(  SELECT  MAX(DET_VACUNACION_ID)
                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID    
                                 WHERE  M.EXPEDIENTE_ID=pExpedienteId
                                 AND    D.ESTADO_REGISTRO_ID=6869  --Solos los Activos. ya que se implemento borrado logico
                                 AND    M.ESTADO_REGISTRO_ID=6869
                                 AND    D.UNIDAD_SALUD_ACTUALIZACION_ID IS NULL
                                 AND    M.TIPO_VACUNA_ID NOT IN (SELECT A2.REL_TIPO_VACUNA_ID
                                                             FROM  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS A2
                                                             JOIN  CATALOGOS.SBC_CAT_CATALOGOS CAT  ON CAT.CATALOGO_ID=A2.TIPO_VACUNA_ID
                                                             WHERE  CAT.CODIGO  IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039')
                                                             )

                                );
    DBMS_OUTPUT.PUT_LINE('v_fecha_proxima_cita_detalle= ' || v_fecha_proxima_cita_detalle);

    SELECT ROUND( MONTHS_BETWEEN(v_fecha_proxima_cita_detalle, v_fecha_nacimiento_persona )) AS num_meses
    INTO    vEdad
    FROM    DUAL;

    DBMS_OUTPUT.PUT_LINE('vEdad=' ||vEdad);

    IF  v_codigo_VPH_SEXO='SEXO|M' THEN 
          v_codigo_VPH_SEXO:='SIPAI012023';--CODIGO VALIDO PARA VHP SEXO FEMENINO 
    ELSE 
        v_codigo_VPH_SEXO:='NO APLICA'  ;     
    END IF;

    DBMS_OUTPUT.PUT_LINE('v_codigo_VPH_SEXO= ' || v_codigo_VPH_SEXO);
   
     select
      nvl(max(r.orden)+1,0)
     into   v_orden_vacuna_edad 
     from  SIPAI_ESQUEMA_VIEW m
     join  SIPAI_PRM_RANGO_EDAD   r
     on    r.edad_id=m.edad_id
	 where m.expediente_id=pExpedienteId
     and m.DTV_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
     and m.TVE_ESTADO_REGISTRO_ID =vGLOBAL_ESTADO_ACTIVO
     AND M.CODIGO_VACUNA NOT IN(
                                 'SIPAI028'  --Fiebre Amarilla
                                );
          
    
   /*
     SELECT DISTINCT PRME2.EDAD_DESDE 
     INTO   v_orden_vacuna_edad
     FROM   SIPAI.SIPAI_PRM_RANGO_EDAD PRME2
     WHERE  PRME2.ESQUEMA_EDAD=1
     AND    PRME2.PASIVO=0
     AND    vEdad BETWEEN PRME2.EDAD_DESDE AND PRME2.EDAD_HASTA;
     /*/
     DBMS_OUTPUT.PUT_LINE('v_orden_vacuna_edad= ' || v_orden_vacuna_edad);

     IF v_orden_vacuna_edad =5 THEN --9 meses
         v_orden_vacuna_edad:=6;    --12 meses
         vEdad:=12;
          DBMS_OUTPUT.PUT_LINE('vEdadCambiada=' ||vEdad);
     /* vacunas del orden 5 ninguna genera vacunas en los 9 mees
        SIPAI024	MMR (SPR)	9 Meses a más (Adicional)
        SIPAI028	Fiebre Amarilla	9 Meses
        SIPAI039	MR (SR)	9 Meses a más (Adicional)
     */

     END IF;


     IF v_orden_vacuna_edad =8 THEN  
        v_orden_vacuna_edad:=9; --por que en el orden 8 solo esta (SIPAI0037)Influenza Adulto y no genera cita  
        vEdad:=72;
     END IF;     


     IF v_orden_vacuna_edad =11   AND  v_codigo_VPH_SEXO='SIPAI012023' THEN     

       --verificar si ya tiene la primera dosis de VPH
                SELECT  COUNT(*)
                INTO    vcontador 
                FROM   SIPAI_DET_VACUNACION DETVAC           
                JOIN   SIPAI_MST_CONTROL_VACUNA MST  ON DETVAC.CONTROL_VACUNA_ID=MST.CONTROL_VACUNA_ID
                JOIN   SIPAI_REL_TIP_VACUNACION_DOSIS RTVD   ON MST.TIPO_VACUNA_ID=RTVD.REL_TIPO_VACUNA_ID
                JOIN   SIPAI_REL_TIPO_VACUNA_EDAD RTVE ON DETVAC.REL_TIPO_VACUNA_EDAD_ID=RTVE.REL_TIPO_VACUNA_EDAD_ID AND RTVE.ESTADO_REGISTRO_ID=6869
                JOIN   SIPAI.SIPAI_DET_VALOR      catNDOSI ON CATNDOSI.CODIGO = RTVE.CODIGO_NUM_DOSIS
                JOIN   CATALOGOS.SBC_CAT_CATALOGOS CATV  ON CATV.CATALOGO_ID=RTVD.TIPO_VACUNA_ID
                WHERE  MST.EXPEDIENTE_ID=pExpedienteId
                AND    CATV.CODIGO='SIPAI012023' 
                AND    RTVE.CODIGO_NUM_DOSIS='CODINTVAL-9'
                AND    DETVAC.ESTADO_REGISTRO_ID=6869 ;  --Solos los Activos. ya que se implemento borrado logico

                IF vcontador = 0  THEN  -- Ya tiene 1ra Dosis
                   --Genera segunda cita
                  v_codigo_VPH_SEXO:='NO APLICA'  ;      
               END IF;
     END IF;     


    IF v_orden_vacuna_edad IS NULL OR v_orden_vacuna_edad >11  THEN
          pRegistro :=null;
    ELSE

     v_fecha_proxima_cita:=PKG_SIPAI_RPT_VACUNACION.FN_FECHA_PROXIMA_CITA(pExpedienteId);
     v_fecha_proxima_citadT_embarazada :=PKG_SIPAI_RPT_VACUNACION.FN_FECHA_PROXIMA_CITA_dT(pExpedienteId);

      DBMS_OUTPUT.PUT_LINE('v_fecha_proxima_cita= ' || v_fecha_proxima_cita);
      DBMS_OUTPUT.PUT_LINE('v_fecha_proxima_citadT_embarazada= ' || v_fecha_proxima_citadT_embarazada);
       
        OPEN pRegistro FOR 
         ------------------------------------------------ 
            WITH numero_dosis as 
            (
            SELECT   
                         Q.REL_TIPO_VACUNA_ID,
                         Q.REL_TIPO_VACUNA_EDAD_ID,
                         Q.CODIGO_VACUNA,
                         Q.NOMBRE_VACUNA, 
                         Q.CODIGO_DOSIS,
                         Q.NOMBRE_DOSIS,
                         Q.ORDEN,
                         Q.EDAD_DESDE    
            FROM 
            (          
             SELECT 
                        REL.REL_TIPO_VACUNA_ID,
                        TVE.REL_TIPO_VACUNA_EDAD_ID,
                        CAT.CODIGO   CODIGO_VACUNA,
                        CAT.VALOR    NOMBRE_VACUNA,
                        NS.CODIGO    CODIGO_DOSIS,
                        NS.VALOR     NOMBRE_DOSIS,
                        PRE.ORDEN,
                        PRE.EDAD_DESDE
            ---------------------------------------
            FROM SIPAI.SIPAI_PRM_RANGO_EDAD PRE
            JOIN  SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD TVE ON TVE.EDAD_ID=PRE.EDAD_ID AND  TVE.ESTADO_REGISTRO_ID=6869
            JOIN SIPAI_DET_VALOR NS ON NS.CODIGO=TVE.CODIGO_NUM_DOSIS
            JOIN  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL ON REL.REL_TIPO_VACUNA_ID=TVE.REL_TIPO_VACUNA_ID AND REL.ESTADO_REGISTRO_ID=6869
            JOIN  CATALOGOS.SBC_CAT_CATALOGOS CAT  ON CAT.CATALOGO_ID=REL.TIPO_VACUNA_ID
            WHERE    PRE.ESQUEMA_EDAD=1 AND  CAT.CODIGO  NOT IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039')
            AND      CAT.CODIGO !=v_codigo_VPH_SEXO
            AND      PRE.PASIVO=0
            --NO HAY PROXIMAS CITAS PARA DOSIS DE REFUERZO Y DOSIS ADICIONALES
            AND      TVE.ES_ADICIONAL=0
            AND      TVE.ES_REFUERZO=0
            --Filtrar por Edad
           -- AND      vEdad BETWEEN PRE.EDAD_DESDE AND PRE.EDAD_HASTA
            AND      (NVL(TVE.ES_REQUERIDO_DOSIS_ANTERIOR,0)=0 OR (SELECT COUNT(*)
                                                                   FROM sipai_mst_control_vacuna
                                                                   WHERE EXPEDIENTE_ID=pExpedienteId
                                                                   AND   TIPO_VACUNA_ID=REL.REL_TIPO_VACUNA_ID)>0)

            ORDER BY   PRE.EDAD_DESDE
            ) Q
            )         
            SELECT  *  
             FROM   numero_dosis NUM_DOSIS  
             WHERE  NUM_DOSIS.EDAD_DESDE =(SELECT DISTINCT PRME2.EDAD_DESDE 
                                           FROM SIPAI.SIPAI_PRM_RANGO_EDAD PRME2
                                           WHERE PRME2.ESQUEMA_EDAD=1
                                           AND   PRME2.PASIVO=0
                                           AND   PRME2.ORDEN=v_orden_vacuna_edad
                                           -- AND   vEdad BETWEEN PRME2.EDAD_DESDE AND PRME2.EDAD_HASTA
                                           );

     DBMS_OUTPUT.PUT_LINE('v_vacunas= ' || v_vacunas);
     
     END IF;
      RETURN pRegistro;

    EXCEPTION
       WHEN NO_DATA_FOUND THEN
        OPEN pRegistro FOR   
           SELECT  ''  FECHA_PROXIMA_CITA, 
                   ''  PROXIMAS_VACUNAS  FROM DUAL; 
END FN_OBTENER_CURSOR_VACUNAS_PROXIMA_CITA;

PROCEDURE PR_INSERTAR_DET_PROXIMA_CITA(pExpedienteId     IN  NUMBER,
                                       pFechaVacunacionCitaAnterior IN DATE,
                                       pFechaProximaVacuna   IN DATE,
                                       pTipVacunaId         IN   NUMBER,
                                       pIdRelTipoVacunaEdad    IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
                                       --------------Datos de Sectorizacion Residencia-----------------
                                       pSectorResidenciaId	                    IN   	NUMBER, 
									   pSectorResidenciaNombre	                IN   	VARCHAR2,
									   pUnidadSaludResidenciaId	                IN   	NUMBER, 
									   pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
									   pEntidadAdminResidenciaId                IN   	NUMBER, 
									   pEntidadAdminResidenciaNombre	        IN   	VARCHAR2,
									   --2024 08------------------------------------------------------------
                                       pComunidadResidenciaId                   IN   	NUMBER, 
                                       pComunidadResidenciaNombre               IN   	VARCHAR2,
                                       --------------------------------------------------------------
									   pResultado          OUT VARCHAR2,
                                       pMsgError           OUT VARCHAR2) IS


  vFirma       VARCHAR2(100) := 'PKG_SIPAI_UTILITARIOS.PR_INSERTAR_DET_PROXIMA_CITA => '; 

  vContador    PLS_INTEGER;
  vContador1    PLS_INTEGER;

  pregistro                  SYS_REFCURSOR;
  vRelTipoVacunaId           PLS_INTEGER;  
  vRelTipoVacunaEdadId		 PLS_INTEGER;   	
  vCodigoVacuna				 VARCHAR2(50);  
  vNombreVacuna 			 VARCHAR2(150);
  vCodigoDosis 				 VARCHAR2(50);
  vNombreDosis 				 VARCHAR2(150);
  vOrden           			 PLS_INTEGER;  
  vDesde           			 PLS_INTEGER;  

  --Variables
    BEGIN    
       pregistro:=FN_OBTENER_CURSOR_VACUNAS_PROXIMA_CITA(pExpedienteId);
       IF PREGISTRO IS not NULL THEN
        LOOP
          FETCH pregistro 
              INTO  vRelTipoVacunaId,  
                    vRelTipoVacunaEdadId,  	
                    vCodigoVacuna,  
                    vNombreVacuna, 
                    vCodigoDosis, 
                    vNombreDosis, 
                    vDesde,
                    vOrden;

            EXIT WHEN pregistro%NOTFOUND;
            
            SELECT COUNT(*)
            INTO   vContador
            FROM   SIPAI_DET_PROXIMA_CITA
            WHERE  EXPEDIENTE_ID=pExpedienteId
            AND    REL_TIPO_VACUNA_ID=vRelTipoVacunaId 
            AND    REL_TIPO_VACUNA_EDAD_ID=vRelTipoVacunaEdadId
            AND    ORDEN =vOrden;
            
            IF vContador >0 THEN  --EDITO
                    UPDATE   SIPAI_DET_PROXIMA_CITA
                     SET      FECHA_PROXIMA_CITA=pFechaProximaVacuna
                     WHERE  EXPEDIENTE_ID=pExpedienteId
                     AND    REL_TIPO_VACUNA_ID=vRelTipoVacunaId 
                     AND    REL_TIPO_VACUNA_EDAD_ID=vRelTipoVacunaEdadId
                     AND    ORDEN =vOrden;
                    
            
            ELSE --INSERTO
            
            --LISTAR LAS VACUNAS DEL SIGUIENTE ORDEN
                      INSERT INTO SIPAI.SIPAI_DET_PROXIMA_CITA(
                                                   DET_PROXIMA_CITA_ID,
                                                   EXPEDIENTE_ID, 
                                                   REL_TIPO_VACUNA_ID, 
                                                   REL_TIPO_VACUNA_EDAD_ID, 
                                                   CODIGO_VACUNA, 
                                                   NOMBRE_VACUNA, 
                                                   CODIGO_DOSIS, 
                                                   NOMBRE_DOSIS, 
                                                   FECHA_PROXIMA_CITA,
                                                   FECHA_VACUNACION_DOSI_ANTERIOR,
                                                   UNIDAD_SALUD_RESIDENCIA_ID, 
                                                   UNIDAD_SALUD_RESIDENCIA_NOMBRE, 
                                                   ENTIDAD_ADMIN_RESIDENCIA_ID, 
                                                   ENTIDAD_ADMIN_RESIDENCIA_NOMBRE, 
                                                   SECTOR_RESIDENCIA_ID, 
                                                   SECTOR_RESIDENCIA_NOMBRE, 
                                                   COMUNIDAD_RESIDENCIA_ID,
                                                   COMUNIDAD_RESIDENCIA_NOMBRE,
                                                   ORDEN, 
                                                   PASIVO  
                                                )
                                       VALUES   (   S_SIPAI_DET_PROXIMA_CITA.NEXTVAL,
                                                    pExpedienteId,
                                                    vRelTipoVacunaId,  
                                                    vRelTipoVacunaEdadId,  	
                                                    vCodigoVacuna,  
                                                    vNombreVacuna, 
                                                    vCodigoDosis, 
                                                    vNombreDosis, 
                                                    pFechaProximaVacuna,
                                                    pFechaVacunacionCitaAnterior,
                                                    pUnidadSaludResidenciaId,
                                                    pUnidadSaludResidenciaNombre,
                                                    pEntidadAdminResidenciaId,
                                                    pEntidadAdminResidenciaNombre,
                                                    pSectorResidenciaId,
                                                    pSectorResidenciaNombre,
                                                    pComunidadResidenciaId,  
                                                    pComunidadResidenciaNombre,
                                                    vOrden,
                                                    0  
                                                ) ; 
                                                commit;
                                                
            END IF;
            END LOOP;
            CLOSE pregistro;
          END IF;  
          
          --PASIVAR LAS CITAS APLICADAS
           UPDATE SIPAI_DET_PROXIMA_CITA C1
           SET C1.PASIVO =1 
           WHERE C1.DET_PROXIMA_CITA_ID
            IN  (
                            SELECT C.DET_PROXIMA_CITA_ID
                            FROM   SIPAI_DET_PROXIMA_CITA C
                            JOIN   SIPAI_DET_VACUNACION   D ON C.EXPEDIENTE_ID=D.EXPEDIENTE_ID
                            AND    C.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                            AND    C.REL_TIPO_VACUNA_ID=D.REL_TIPO_VACUNA_ID
                            WHERE  D.EXPEDIENTE_ID=pExpedienteId
                            AND    D.ESTADO_REGISTRO_ID=6869 --Solos los Activos. ya que se implemento borrado logico
                            AND    C.PASIVO=0
                        )
        AND C1.EXPEDIENTE_ID=pExpedienteId
        AND C1.REL_TIPO_VACUNA_EDAD_ID=pIdRelTipoVacunaEdad
        AND C1.REL_TIPO_VACUNA_ID=vRelTipoVacunaId
        ;
   
          

 EXCEPTION
    WHEN OTHERS THEN
       pResultado := 'Error al insertar registro de detalle de citas de vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM; 
  END PR_INSERTAR_DET_PROXIMA_CITA;
  
 PROCEDURE PR_REGISTRO_DET_ROXIMA_CITA (pExpedienteId  NUMBER, 
                                         pResultado OUT VARCHAR2,  
                                         pMsgError    OUT VARCHAR2)
 IS
 
   vFirma       VARCHAR2(100) := 'PKG_SIPAI_UTILITARIOS.PR_REGISTRO_DET_ROXIMA_CITA => '; 
   vContador  NUMBER;
 
   pFechaProximaVacuna     DATE;
   pTipVacunaId             NUMBER;
   pIdRelTipoVacunaEdad     NUMBER;
   --------------Datos de Sectorizacion Residencia-----------------
   pSectorResidenciaId	         NUMBER; 
   pSectorResidenciaNombre	     VARCHAR2(150);
   pUnidadSaludResidenciaId	     NUMBER;
   pUnidadSaludResidenciaNombre	 VARCHAR2(150);
   pEntidadAdminResidenciaId     NUMBER;
   pEntidadAdminResidenciaNombre VARCHAR2(150);
   --2024 08
   pComunidadResidenciaId        NUMBER;  
   pComunidadResidenciaNombre    VARCHAR2(150);
   ---------------------------------------------
   pFechaVacunacionDosiAnterior  DATE;

 BEGIN
     
      SELECT COUNT(*) 
      INTO   vContador     
      FROM  SIPAI_DET_VACUNACION DETVAC 
      JOIN  SIPAI_DET_VACUNACION_SECTOR DETVACS ON DETVAC.DET_VACUNACION_ID=DETVACS.DET_VACUNACION_ID
      WHERE DETVAC.DET_VACUNACION_ID=(SELECT MAX(DET_VACUNACION_ID) 
                                        FROM  SIPAI_DET_VACUNACION 
                                        WHERE EXPEDIENTE_ID=pExpedienteId
                                        AND   ESTADO_REGISTRO_ID=6869); --Solos los Activos. ya que se implemento borrado logico
    IF vContador > 0 THEN
                          
       SELECT  
               DETVAC.FECHA_VACUNACION,
               DETVAC.FECHA_PROXIMA_VACUNA,
               DETVAC.REL_TIPO_VACUNA_ID,
               DETVAC.REL_TIPO_VACUNA_EDAD_ID,
               DETVACS.SECTOR_RESIDENCIA_ID, 
               DETVACS.SECTOR_RESIDENCIA_NOMBRE,
               DETVACS.UNIDAD_SALUD_RESIDENCIA_ID,
               DETVACS.UNIDAD_SALUD_RESIDENCIA_NOMBRE,
               DETVACS.ENTIDAD_ADMIN_RESIDENCIA_ID,
               DETVACS.ENTIDAD_ADMIN_RESIDENCIA_NOMBRE,
               DETVACS.COMUNIDAD_RESIDENCIA_ID,
               DETVACS.COMUNIDAD_RESIDENCIA_NOMBRE
               INTO 
               pFechaVacunacionDosiAnterior,
               pFechaProximaVacuna,
               pTipVacunaId,
               pIdRelTipoVacunaEdad,
               pSectorResidenciaId,
               pSectorResidenciaNombre,
               pUnidadSaludResidenciaId,
               pUnidadSaludResidenciaNombre,
               pEntidadAdminResidenciaId,
               pEntidadAdminResidenciaNombre,
               pComunidadResidenciaId, 
               pComunidadResidenciaNombre
      FROM  SIPAI_DET_VACUNACION DETVAC 
      JOIN  SIPAI_DET_VACUNACION_SECTOR DETVACS ON DETVAC.DET_VACUNACION_ID=DETVACS.DET_VACUNACION_ID
      WHERE DETVAC.DET_VACUNACION_ID=(SELECT MAX(DET_VACUNACION_ID) 
                                        FROM  SIPAI_DET_VACUNACION 
                                        WHERE EXPEDIENTE_ID=pExpedienteId
                                        AND   ESTADO_REGISTRO_ID=6869);--Solos los Activos. ya que se implemento borrado logico
   
            PR_INSERTAR_DET_PROXIMA_CITA (
                                   pExpedienteId,
                                   pFechaVacunacionDosiAnterior,
                                   pFechaProximaVacuna,
                                   pTipVacunaId,
                                   pIdRelTipoVacunaEdad,
                                   pSectorResidenciaId,
                                   pSectorResidenciaNombre,
                                   pUnidadSaludResidenciaId,
                                   pUnidadSaludResidenciaNombre,
                                   pEntidadAdminResidenciaId,
                                   pEntidadAdminResidenciaNombre,
                                   pComunidadResidenciaId, 
                                   pComunidadResidenciaNombre,
                                   pResultado, 
                                   pMsgError
                                         );   
   
     END IF;
 
 EXCEPTION
    WHEN OTHERS THEN
       pResultado := 'Error al insertar registro de detalle de citas de vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM; 
 
 END  PR_REGISTRO_DET_ROXIMA_CITA;
 
END PKG_SIPAI_UTILITARIOS;
/