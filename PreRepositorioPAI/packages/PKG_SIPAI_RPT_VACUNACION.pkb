CREATE OR REPLACE PACKAGE BODY SIPAI."PKG_SIPAI_RPT_VACUNACION" AS

vPROGRAMA_VACUNA_PAI         NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('PRO_VAC || 02');
vPROGRAMA_VACUNA_COVID       NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('PRO_VAC || 01');

FUNCTION FN_FECHA_TEXTO(pFecha  IN DATE) RETURN  VARCHAR2 AS 
 v_fecha_texto VARCHAR2(30);
  BEGIN
   v_fecha_texto:=  EXTRACT(YEAR FROM  pFecha)
				               ||'-' || LPAD(EXTRACT(MONTH FROM pFecha),2,0)
							    ||'-' ||LPAD(EXTRACT(DAY FROM  pFecha),2,0);
   RETURN   v_fecha_texto;   
END FN_FECHA_TEXTO; 

FUNCTION FECHA_DDMMYYYY(pFecha  IN DATE) RETURN  VARCHAR2 AS 
 v_fecha_texto VARCHAR2(30);
  BEGIN
   v_fecha_texto:=  LPAD(EXTRACT(DAY FROM  pFecha),2,0) ||'-'|| LPAD(EXTRACT(MONTH FROM pFecha),2,0) ||'-'||  EXTRACT(YEAR FROM  pFecha);

   RETURN   v_fecha_texto;   
END FECHA_DDMMYYYY; 

FUNCTION FN_FECHA_PROXIMA_CITA(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE ) RETURN  VARCHAR2 AS 
 v_fecha_proxima_cita DATE;
  BEGIN
      SELECT  MAX( DTV.FECHA_PROXIMA_VACUNA)	
        INTO v_fecha_proxima_cita
         FROM  SIPAI.SIPAI_MST_CONTROL_VACUNA MCV 
          JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV
           ON   DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS ESTADO
          ON  ESTADO.CATALOGO_ID = DTV.ESTADO_VACUNACION_ID
         WHERE MCV.EXPEDIENTE_ID=pExpedienteId 
         AND dtv.estado_registro_id = 6869
         AND MCV.estado_registro_id = 6869
         AND ESTADO.CODIGO NOT IN ('EST_APL_VAC||08','EST_APL_VAC||09', 'EST_APL_VAC||03')
         AND UNIDAD_SALUD_ACTUALIZACION_ID IS NULL;
         --AND ESTADO.CODIGO != 'EST_APL_VAC||03';--Aplicada por Actualización de esquema  son tres estados de actaulizacion   EMR

         IF v_fecha_proxima_cita IS NULL THEN
            RETURN NULL;
        ELSE
            RETURN  FN_FECHA_TEXTO( v_fecha_proxima_cita);  
        END IF;

END FN_FECHA_PROXIMA_CITA; 

FUNCTION FN_FECHA_PROXIMA_CITA_dT(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE ) RETURN  VARCHAR2 AS 

  v_fecha_proxima_cita      DATE;
  vTipoVacunadT             NUMBER:=FN_SIPAI_CATALOGO_ESTADO_ID('SIPAI026');
  vReltipoVacunaEdad        NUMBER;

  BEGIN

    SELECT REL_TIPO_VACUNA_EDAD_ID --, VALOR_EDAD,TIPO_VACUNA_ID
    INTO  vReltipoVacunaEdad
    FROM  SIPAI_REL_TIPO_VACUNA_EDAD A  JOIN SIPAI_REL_TIP_VACUNACION_DOSIS B 	ON B.REL_TIPO_VACUNA_ID = A.REL_TIPO_VACUNA_ID
    JOIN SIPAI_prm_RANGO_EDAD CTEDAD ON CTEDAD.EDAD_ID = A.EDAD_ID 
    WHERE  B.TIPO_VACUNA_ID=vTipoVacunadT
    AND   A.ESTADO_REGISTRO_ID = 6869  
    AND   CTEDAD.CODIGO_EDAD ='COD_INT_EDAD_7786';


      SELECT  MAX( DTV.FECHA_PROXIMA_VACUNA)	
        INTO    v_fecha_proxima_cita
         FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA MCV 
          JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV
           ON   DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
          JOIN  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS R 
           ON   r.rel_tipo_vacuna_id=MCV.tipo_vacuna_id 
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS ESTADO
          ON  ESTADO.CATALOGO_ID = DTV.ESTADO_VACUNACION_ID
         WHERE MCV.EXPEDIENTE_ID=pExpedienteId AND ESTADO.CODIGO != 'EST_APL_VAC||03'
         AND  dtv.caso_embarazo=1
         AND dtv.estado_registro_id = 6869
         AND MCV.estado_registro_id = 6869
         AND  r.tipo_vacuna_id=vTipoVacunadT
         AND  dtv.REL_TIPO_VACUNA_EDAD_ID=vReltipoVacunaEdad;


         IF v_fecha_proxima_cita IS NULL THEN
            RETURN NULL;
        ELSE
            RETURN  FN_FECHA_TEXTO( v_fecha_proxima_cita);  
        END IF;

END FN_FECHA_PROXIMA_CITA_dT; 

FUNCTION FN_TRANSFORMAR_CADENA_VACUNAS_PROXIMA_CITAS(p_cadena  IN VARCHAR) RETURN  VARCHAR2 AS 

    v_cadena_original VARCHAR2(250) :=p_cadena;
    v_cadena_dosi VARCHAR2(250) :=    SUBSTR(v_cadena_original, 1, INSTR(v_cadena_original, '-') - 1);

    v_cadena_transformada VARCHAR2(4000);
    v_tokens_arr SYS.ODCIVARCHAR2LIST;

  BEGIN
     -- Dividir la cadena original en tokens basados en ","
    v_tokens_arr := SYS.ODCIVARCHAR2LIST();
    FOR i IN 1..REGEXP_COUNT(v_cadena_original, ',') + 1 LOOP
        v_tokens_arr.EXTEND;
        v_tokens_arr(i) := TRIM(REGEXP_SUBSTR(v_cadena_original, '[^,]+', 1, i));
    END LOOP;
    -- Buscar y reemplazar las repeticiones de "(Primera Dosis)" para consolidarlas
    FOR i IN 1..v_tokens_arr.COUNT LOOP
        IF INSTR(v_tokens_arr(i), v_cadena_dosi) > 0 THEN
            v_tokens_arr(i) := REPLACE(v_tokens_arr(i), v_cadena_dosi, '');
            --quitar caracteres -
            v_tokens_arr(i) := REPLACE(v_tokens_arr(i), '-', '');
             -- DBMS_OUTPUT.PUT_LINE( v_tokens_arr(i));

        END IF;
    END LOOP;
    -- Construir la cadena transformada

    FOR i IN 1..v_tokens_arr.COUNT LOOP
        v_cadena_transformada := v_cadena_transformada || v_tokens_arr(i);
        IF i < v_tokens_arr.COUNT THEN
            v_cadena_transformada := v_cadena_transformada || ',';
        END IF;
    END LOOP;

     v_cadena_transformada := REPLACE(v_cadena_transformada, ' ', '');
     v_cadena_transformada := v_cadena_dosi ||   '('|| v_cadena_transformada || ')';


    -- Imprimir el resultado
    DBMS_OUTPUT.PUT_LINE(v_cadena_transformada);

   RETURN   v_cadena_transformada;   
END FN_TRANSFORMAR_CADENA_VACUNAS_PROXIMA_CITAS; 


PROCEDURE REPORTE_FECHA_PROXIMA_CITA (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pRegistro     OUT var_refcursor
                                       )
IS 
--Variables
    vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
    v_fecha_proxima_cita varchar2(30);
    v_orden_vacuna_edad  number;
    v_proxima_edad  varchar2(30);
    v_vacunas varchar2(4000);
    -------------------------------
    v_codigo_VPH_SEXO  varchar2(30);
    v_fecha_proxima_citadT_embarazada varchar2(30);
    ------------------------------------
    vEdad NUMBER;
    v_fecha_proxima_cita_detalle date; 
    v_fecha_nacimiento_persona date;
    --------------------------------------
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
                                 AND    D.ESTADO_REGISTRO_ID=6869
                                 AND    M.ESTADO_REGISTRO_ID=6869
                                 AND    D.UNIDAD_SALUD_ACTUALIZACION_ID IS NULL
                                 AND    M.TIPO_VACUNA_ID NOT IN (SELECT A2.REL_TIPO_VACUNA_ID
                                                             FROM  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS A2
                                                             JOIN  CATALOGOS.SBC_CAT_CATALOGOS CAT  ON CAT.CATALOGO_ID=A2.TIPO_VACUNA_ID
                                                             WHERE  CAT.CODIGO  IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039','SIPAIVAC041')
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
                AND    DETVAC.ESTADO_REGISTRO_ID=6869 ;

                IF vcontador = 0  THEN  -- Ya tiene 1ra Dosis
                   --Genera segunda cita
                  v_codigo_VPH_SEXO:='NO APLICA'  ;      
               END IF;
     END IF;     

   --Validar que el orden de edad llegue hasta la vph
    IF v_orden_vacuna_edad IS NULL or v_fecha_proxima_cita_detalle IS NULL OR v_orden_vacuna_edad >11  THEN
        pRegistro := NULL;
    ELSE

     v_fecha_proxima_cita:=FN_FECHA_PROXIMA_CITA(pExpedienteId);
     v_fecha_proxima_citadT_embarazada :=FN_FECHA_PROXIMA_CITA_dT(pExpedienteId);

      DBMS_OUTPUT.PUT_LINE('v_fecha_proxima_cita= ' || v_fecha_proxima_cita);
      DBMS_OUTPUT.PUT_LINE('v_fecha_proxima_citadT_embarazada= ' || v_fecha_proxima_citadT_embarazada);

        WITH numero_dosis as 
            (
            SELECT  
                Q.VACUNA  ||' ('||Q.NUMERO_DOSIS || ')' NUMERO_DOSIS ,  
                Q.EDAD_DESDE  

            FROM 
            (
            SELECT CAT.VALOR VACUNA,
            --ROW_NUMBER()OVER (PARTITION BY CAT.VALOR ORDER BY  PRE.EDAD_DESDE )NDOSIS,
               --  ROW_NUMBER()OVER (PARTITION BY CAT.VALOR ORDER BY  PRE.EDAD_DESDE ) || ' dosis' DOSIS,  
                   PRE.EDAD_DESDE,REL.REL_TIPO_VACUNA_ID, CAT.CODIGO,NS.VALOR NUMERO_DOSIS  
            FROM SIPAI.SIPAI_PRM_RANGO_EDAD PRE
            JOIN  SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD TVE ON TVE.EDAD_ID=PRE.EDAD_ID AND  TVE.ESTADO_REGISTRO_ID=6869
            JOIN SIPAI_DET_VALOR NS ON NS.CODIGO=TVE.CODIGO_NUM_DOSIS
            JOIN  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL ON REL.REL_TIPO_VACUNA_ID=TVE.REL_TIPO_VACUNA_ID AND REL.ESTADO_REGISTRO_ID=6869
            JOIN  CATALOGOS.SBC_CAT_CATALOGOS CAT  ON CAT.CATALOGO_ID=REL.TIPO_VACUNA_ID
            WHERE    PRE.ESQUEMA_EDAD=1 AND  CAT.CODIGO  NOT IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039','SIPAIVAC041')
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

            SELECT    
              SUBSTR(   RTRIM(LISTAGG( '' || NUM_DOSIS.NUMERO_DOSIS || ', ' ) WITHIN GROUP ( ORDER BY EDAD_DESDE ), ',') 
              ,1,Length(RTRIM(LISTAGG( '' || NUM_DOSIS.NUMERO_DOSIS || ', ' ) WITHIN GROUP ( ORDER BY EDAD_DESDE ), ',') )-2 ) LISTA_DOSIS
              INTO v_vacunas
             FROM   numero_dosis NUM_DOSIS  
             WHERE  NUM_DOSIS.EDAD_DESDE =(SELECT DISTINCT PRME2.EDAD_DESDE 
                                           FROM SIPAI.SIPAI_PRM_RANGO_EDAD PRME2
                                           WHERE PRME2.ESQUEMA_EDAD=1
                                           AND   PRME2.PASIVO=0
                                           AND   PRME2.ORDEN=v_orden_vacuna_edad

                                           );

     DBMS_OUTPUT.PUT_LINE('v_vacunas= ' || v_vacunas);
     IF v_fecha_proxima_cita IS NULL OR v_vacunas IS NULL THEN
        pRegistro := NULL;
     ELSE

           IF v_fecha_proxima_citadT_embarazada = v_fecha_proxima_cita THEN

            OPEN pRegistro FOR  
              SELECT  v_fecha_proxima_cita  FECHA_PROXIMA_CITA, 
                      v_vacunas || '(caso dt)'  PROXIMAS_VACUNAS FROM DUAL;  
           ELSE
            OPEN pRegistro FOR  

           SELECT  v_fecha_proxima_cita  FECHA_PROXIMA_CITA, 
                    v_vacunas  PROXIMAS_VACUNAS  FROM DUAL;  
           END IF;

     END IF;
     END IF;

    EXCEPTION
       WHEN NO_DATA_FOUND THEN
        OPEN pRegistro FOR   
           SELECT  ''  FECHA_PROXIMA_CITA, 
                   ''  PROXIMAS_VACUNAS  FROM DUAL; 
END;

PROCEDURE MENSAJE_FECHA_PROXIMA_CITA (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pRegistro     OUT var_refcursor
                                       )
IS 
--Variables
    vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
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
---------------------------------------------------------
    SELECT  FECHA_PROXIMA_VACUNA
    INTO   v_fecha_proxima_cita_detalle
    FROM   SIPAI_DET_VACUNACION
    WHERE  DET_VACUNACION_ID =(  SELECT  MAX(DET_VACUNACION_ID)
                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID    
                                 WHERE  M.EXPEDIENTE_ID=pExpedienteId
                                 AND    D.ESTADO_REGISTRO_ID=6869
                                 AND    M.ESTADO_REGISTRO_ID=6869
                                 AND    D.UNIDAD_SALUD_ACTUALIZACION_ID IS NULL
                                 AND    M.TIPO_VACUNA_ID NOT IN (SELECT A2.REL_TIPO_VACUNA_ID
                                                             FROM  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS A2
                                                             JOIN  CATALOGOS.SBC_CAT_CATALOGOS CAT  ON CAT.CATALOGO_ID=A2.TIPO_VACUNA_ID
                                                             WHERE  CAT.CODIGO  IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039','SIPAIVAC041')
                                                             )

                                );

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

     DBMS_OUTPUT.PUT_LINE('v_orden_vacuna_edad= ' || v_orden_vacuna_edad);

     IF v_orden_vacuna_edad =5 THEN --9 meses
         v_orden_vacuna_edad:=6;    --12 meses
         vEdad:=12;
          DBMS_OUTPUT.PUT_LINE('vEdadCambiada=' ||vEdad);
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
                AND    DETVAC.ESTADO_REGISTRO_ID=6869 ;

                IF vcontador = 0  THEN  -- Ya tiene 1ra Dosis
                   --Genera segunda cita
                  v_codigo_VPH_SEXO:='NO APLICA'  ;      
               END IF;
     END IF;     

   --Validar que el orden de edad llegue hasta la vph
    IF v_orden_vacuna_edad IS NULL or v_fecha_proxima_cita_detalle IS NULL OR v_orden_vacuna_edad >11  THEN
        pRegistro := NULL;
    ELSE

     v_fecha_proxima_cita:=FN_FECHA_PROXIMA_CITA(pExpedienteId);
     v_fecha_proxima_citadT_embarazada :=FN_FECHA_PROXIMA_CITA_dT(pExpedienteId);

        WITH numero_dosis as 
            (
            SELECT   
                   Q.NUMERO_DOSIS  ||'-'||Q.VACUNA || '' NUMERO_DOSIS ,  
                   Q.EDAD_DESDE           

            FROM 
            (
            SELECT CAT.VALOR VACUNA,
            PRE.EDAD_DESDE,REL.REL_TIPO_VACUNA_ID, CAT.CODIGO,NS.VALOR NUMERO_DOSIS  
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
            )  SELECT  SUBSTR(   RTRIM(LISTAGG( '' || NUM_DOSIS.NUMERO_DOSIS || ', ' ) WITHIN GROUP ( ORDER BY EDAD_DESDE ), ',') 
              ,1,Length(RTRIM(LISTAGG( '' || NUM_DOSIS.NUMERO_DOSIS || ', ' ) WITHIN GROUP ( ORDER BY EDAD_DESDE ), ',') )-2 ) LISTA_DOSIS
              INTO v_vacunas
             FROM   numero_dosis NUM_DOSIS  
             WHERE  NUM_DOSIS.EDAD_DESDE =(SELECT DISTINCT PRME2.EDAD_DESDE 
                                           FROM SIPAI.SIPAI_PRM_RANGO_EDAD PRME2
                                           WHERE PRME2.ESQUEMA_EDAD=1
                                           AND   PRME2.PASIVO=0
                                           AND   PRME2.ORDEN=v_orden_vacuna_edad

                                           );

     DBMS_OUTPUT.PUT_LINE('v_vacunas= ' || v_vacunas);
     --caso orden 7 1ra.Dosis-DPT, 2da.Dosis-MMR (SPR)   no aplicar la transformacion
     IF v_orden_vacuna_edad !=7 THEN
      v_vacunas:=FN_TRANSFORMAR_CADENA_VACUNAS_PROXIMA_CITAS(v_vacunas);
     END IF;

     IF v_fecha_proxima_cita IS NULL OR v_vacunas IS NULL THEN
        pRegistro := NULL;
     ELSE

           IF v_fecha_proxima_citadT_embarazada = v_fecha_proxima_cita THEN

            OPEN pRegistro FOR  
              SELECT  v_fecha_proxima_cita  FECHA_PROXIMA_CITA, 
                      v_vacunas || '(caso dt)'  PROXIMAS_VACUNAS FROM DUAL;  
           ELSE
            OPEN pRegistro FOR  

           SELECT  v_fecha_proxima_cita  FECHA_PROXIMA_CITA, 
                    v_vacunas  PROXIMAS_VACUNAS  FROM DUAL;  
           END IF;

     END IF;
     END IF;

    EXCEPTION
       WHEN NO_DATA_FOUND THEN
        OPEN pRegistro FOR   
           SELECT  ''  FECHA_PROXIMA_CITA, 
                   ''  PROXIMAS_VACUNAS  FROM DUAL; 

END;



FUNCTION FN_OBT_REGISTRO_MADRE (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE 
							   )RETURN reg_madre AS
 r_madre reg_madre;
 v_contador number;    

BEGIN
 SELECT  count(1) 
 INTO v_contador
 FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER
	 JOIN  CATALOGOS.SBC_REL_PERSONAS_COD_EXP REP
		ON    REP.EXPEDIENTE_1_ID=PER.EXPEDIENTE_ID 
	 JOIN  CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER2
		ON    REP.EXPEDIENTE_2_ID=PER2.EXPEDIENTE_ID
		INNER JOIN  CATALOGOS.SBC_CAT_CATALOGOS CREP --CAMBIO
		ON    CREP.CATALOGO_ID = REP.MOTIVO_ID 
		AND   CREP.CODIGO='PMDR'  --6852 MADRE  6853  PPDR PADRE
    where  per.expediente_id=pExpedienteId;


	  IF v_contador =1 THEN 
	   SELECT PER2.EXPEDIENTE_ID,
			( PER2.PRIMER_NOMBRE  ||' '|| PER2.SEGUNDO_NOMBRE ||' '||
			  PER2.PRIMER_APELLIDO||' '|| PER2.SEGUNDO_APELLIDO
			 ) NOMBRE_MADRE INTO r_madre.expedienteId, r_madre.nombre
       FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER
	  JOIN  CATALOGOS.SBC_REL_PERSONAS_COD_EXP REP
		ON    REP.EXPEDIENTE_1_ID=PER.EXPEDIENTE_ID 
	   JOIN  CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER2
		ON    REP.EXPEDIENTE_2_ID=PER2.EXPEDIENTE_ID
		INNER JOIN  CATALOGOS.SBC_CAT_CATALOGOS CREP
		ON    CREP.CATALOGO_ID = REP.MOTIVO_ID 
		AND   CREP.CODIGO='PMDR'  --6852 MADRE  6853  PPDR PADRE
       where  per.expediente_id=pExpedienteId;

	  END IF;

RETURN r_madre;	

END FN_OBT_REGISTRO_MADRE;

PROCEDURE ESQUEMA_VACUNACION ( pRegistro  OUT var_refcursor)IS

BEGIN
      OPEN pRegistro FOR  


WITH ESQUEMA1 AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY R.ORDEN) as EDADES,
          C.ORDEN ORDEN_VACUNA, R.ORDEN ORDEN_EDAD,
          A.TIPO_VACUNA_ID ,CATTIPVAC.VALOR NOMBRE_VACUNA,
          ----Ajuste Dt 2024
          CASE
           WHEN   --codigo de la primera dosis 21 anio dt representa en una sola leyende las 5 dosis Dt
             R.CODIGO_EDAD ='COD_INT_EDAD_7917' 
           THEN '21 Años a mas, (1er,2da,3ra,4ta,5ta dosis dT)'
           ELSE  R.VALOR_EDAD 
          END AS  VALOR_EDAD,

          A.CANTIDAD_DOSIS REL_CANT_DOSIS
         FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS A
           JOIN SIPAI.SIPAI_CONFIGURACION_VACUNA C ON C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID
           JOIN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD E ON E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
           JOIN SIPAI.SIPAI_PRM_RANGO_EDAD R ON R.EDAD_ID = E.EDAD_ID
           JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID
           LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID
           WHERE R.ESQUEMA_EDAD=1 AND E.ESTADO_REGISTRO_ID=6869 AND A.ESTADO_REGISTRO_ID=6869
           AND   CATTIPVAC.CODIGO NOT IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039','SIPAI0038','SIPAIVAC041')
           --Ajuste dt 2024 dejar solo la primer dosis 
           AND   R.CODIGO_EDAD  NOT IN ('COD_INT_EDAD_7918','COD_INT_EDAD_7919','COD_INT_EDAD_7920','COD_INT_EDAD_7921'
          )
           --'SIPAI0038'  Neumococo 23 
         )
         SELECT ORDEN_EDAD ORDEN_VACUNA, VALOR_EDAD NOMBRE_VACUNA, RTRIM(LISTAGG( '' ||NOMBRE_VACUNA|| ',' )
         WITHIN GROUP ( ORDER BY NOMBRE_VACUNA ), ',') VACUNAS,0 REL_CANT_DOSIS, 0 tipo_vacuna_id
         FROM ESQUEMA1
           group by ORDEN_EDAD,VALOR_EDAD --,NOMBRE_VACUNA,REL_CANT_DOSIS,TIPO_VACUNA_ID
           ORDER BY ORDEN_EDAD;

     /*

      WITH ESQUEMA1 AS (
        SELECT
          ROW_NUMBER() OVER (ORDER BY R.ORDEN) as EDADES,
          C.ORDEN ORDEN_VACUNA, R.ORDEN ORDEN_EDAD,
          A.TIPO_VACUNA_ID ,CATTIPVAC.VALOR NOMBRE_VACUNA,
          R.VALOR_EDAD VALOR_EDAD, A.CANTIDAD_DOSIS REL_CANT_DOSIS
         FROM SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS A
           JOIN SIPAI.SIPAI_CONFIGURACION_VACUNA C ON C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID
           JOIN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD E ON E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
           JOIN SIPAI.SIPAI_PRM_RANGO_EDAD R ON R.EDAD_ID = E.EDAD_ID
           JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID
           LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID
           WHERE R.ESQUEMA_EDAD=1 AND E.ESTADO_REGISTRO_ID=6869 AND A.ESTADO_REGISTRO_ID=6869
           AND   CATTIPVAC.CODIGO NOT IN ('SIPAI0037','SIPAI027','SIPAI028','SIPAI039','SIPAI0038')
           --'SIPAI0038'  Neumococo 23 
         )
 SELECT ORDEN_EDAD ORDEN_VACUNA, VALOR_EDAD NOMBRE_VACUNA, RTRIM(LISTAGG( '' ||NOMBRE_VACUNA|| ',' )
 WITHIN GROUP ( ORDER BY NOMBRE_VACUNA ), ',') VACUNAS,0 REL_CANT_DOSIS, 0 tipo_vacuna_id
 FROM ESQUEMA1
   group by ORDEN_EDAD,VALOR_EDAD --,NOMBRE_VACUNA,REL_CANT_DOSIS,TIPO_VACUNA_ID
   ORDER BY ORDEN_EDAD;
*/

END ESQUEMA_VACUNACION;

PROCEDURE REPORTE_ESQUEMA_VACUNACION (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pRegistro    OUT CLOB
									   )
IS 

 v_expedienteId number    :=pExpedienteId ; 
 vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
 v_fecha_proxima_cita DATE;
 v_fecha_texto   VARCHAR2(30);
 v_cod_catalogo_vacuna NUMBER;
 v_cod_catalogo_edad NUMBER;
 v_edad_id number;
 v_cat_vacuna_id number;
 v_det_vacuna_id number;
--v_dato varchar2(1000);
n_edad varchar2(4000);
n_vacuna varchar2(4000);
n_detalle varchar2(4000);
v_totalEdad  number;
v_totalVacuna number;
v_totalDosis number;
v_cero varchar2(2);
 --pExpedienteId;      --4819137 ; --   4819082
v_edad number ;
v_vacuna number ;
 vAMBITO_VACUNA             NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('CLA-REG-ESQ-AMB||02');

vData CLOB;
--parametro de entrada
 CURSOR c_tipoVacuna(padreId number, programaId number) IS					
	SELECT  
            C.catalogo_id id, 
            C.valor     
	FROM    CATALOGOS.SBC_CAT_CATALOGOS C
	JOIN    SIPAI_CONFIGURACION_VACUNA V	ON   V.TIPO_VACUNA_ID = C.CATALOGO_ID
	WHERE   C.CATALOGO_SUP = padreId AND V.PROGRAMA_VACUNA_ID = programaId
            AND   V.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
            AND   V.ESQUEMA_AMBITO_ID = vAMBITO_VACUNA
            ORDER BY V.ORDEN;

   CURSOR c_tipoEdad IS
   SELECT  Edad_ID id,valor_edad valor  FROM SIPAI_PRM_RANGO_EDAD WHERE  ESQUEMA_EDAD=1 and pasivo = 0 order by orden;


 CURSOR c_edad_vacunacion(idEdad number, tipoVacunaId number ) IS
     --grupo prioridad mayo  2024 la vista SIPAI_ESQUEMA_VIEW no tiene grupo prioridad se comenta y se agrega el select con el grupo de prioridad
        SELECT 
         MCV.CONTROL_VACUNA_ID, ESMCV.CODIGO, MCV.EXPEDIENTE_ID,MCV.ESTADO_REGISTRO_ID,
         DTV.DET_VACUNACION_ID, TVD.REL_TIPO_VACUNA_ID,TVD.TIPO_VACUNA_ID,CTV.VALOR  NOMBRE_VACUNA,
         TVE.REL_TIPO_VACUNA_EDAD_ID,TVE.EDAD_ID,CVE.CODIGO CODIGO_VACUNA, CVE.VALOR NOMBRE_EDAD_VACUNA , 
         DTV.NO_APLICADA,DTV.CASO_EMBARAZO,DECODE(MNA.VALOR , NULL ,'0',MNA.VALOR) NOMBRE_MOTIVO_NO_APLICA,
         DTV.ESTADO_VACUNACION_ID, CEV.VALOR ESTADO_VACUNACION,(PER.PRIMER_NOMBRE  ||' '|| PER.SEGUNDO_NOMBRE ||' '||
         PER.PRIMER_APELLIDO||' '||PER.SEGUNDO_APELLIDO) NOMBRE_COMPLETO, USA.UNIDAD_SALUD_ID,USA.ENTIDAD_ADTVA_ID,
         --08 2024 Agregar aplicada en otro Pais.
         DECODE (DTV.ES_APLICADA_NACIONAL,1,USA.NOMBRE, 'Otro Pais')  NOMBRE_UNIDAD_SALUD,
         DECODE (DTV.ES_APLICADA_NACIONAL,1,UAD.NOMBRE, 'Otro Pais')  NOMBRE_SILAIS,

         usa.municipio_id,MUN.NOMBRE NOMBRE_MUNICIPIO,mun.departamento_id,DEP.NOMBRE NOMBRE_DEPARTAMENTO,
         dtv.FECHA_VACUNACION,dtv.HORA_VACUNACION,dtv.FECHA_PROXIMA_VACUNA,DPV.PERSONAL_VACUNA_ID,
        (DPV.PRIMER_NOMBRE  ||' '||  DPV.SEGUNDO_NOMBRE ||' '||	 DPV.PRIMER_APELLIDO||' '||
         DPV.SEGUNDO_APELLIDO )NOMBRE_vacunador, DTV.TIPO_ESTRATEGIA_ID, DTV.ESTADO_REGISTRO_ID  DTV_ESTADO_REGISTRO_ID,
        tve.estado_registro_id  tve_estado_registro_id, USAA.UNIDAD_SALUD_ID UNIDAD_SALUD_ACTUALIZACION_ID,
        USAA.NOMBRE   NOMBRE_UNIDAD_SALUD_ACTUALIZACION,UADA.ENTIDAD_ADTVA_ID ENTIDAD_ADTVA_ID_ACTUALIZACION,
        UADA.NOMBRE  NOMBRE_SILAIS_ACTUALIZACION , /* Agregar grupo prioridad  2024*/
        MCV.GRUPO_PRIORIDAD_ID, CGP.VALOR GRUPO_PRIORIDAD_VALOR
        --08 2024 Agregar aplicada en otro Pais.
        ,DTV.ES_APLICADA_NACIONAL

        FROM  CATALOGOS.SBC_MST_PERSONAS PER
        JOIN  SIPAI.SIPAI_MST_CONTROL_VACUNA MCV ON    MCV.EXPEDIENTE_ID= PER.EXPEDIENTE_ID 
        JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV    ON    DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
        LEFT JOIN  SIPAI.SIPAI_DET_PERSONAL_VACUNA DPV 	ON    DPV.PERSONAL_VACUNA_ID=DTV.PERSONAL_VACUNA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CEV       ON   CEV.CATALOGO_ID=DTV.ESTADO_VACUNACION_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS  MNA      ON   MNA.CATALOGO_ID=DTV.MOTIVO_NO_APLICADA
				--tipo vacuna y catalago tipo vacuna
        JOIN  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS TVD 	ON    TVD.REL_TIPO_VACUNA_ID=MCV.TIPO_VACUNA_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CTV           ON    CTV.CATALOGO_ID = TVD.TIPO_VACUNA_ID
        --Agregar Grupo Prioridad
         LEFT JOIN   CATALOGOS.SBC_CAT_CATALOGOS CGP    ON    CGP.CATALOGO_ID =  MCV.GRUPO_PRIORIDAD_ID
				--Unidad de salud SILAI
        JOIN  catalogos.sbc_cat_unidades_salud USA   	ON    DTV.UNIDAD_SALUD_ID=USA.UNIDAD_SALUD_ID
        JOIN  catalogos.sbc_cat_entidades_adtvas UAD	ON    UAD.ENTIDAD_ADTVA_ID=USA.ENTIDAD_ADTVA_ID
				 -- Unidad de salud municipio y departamento
        LEFT JOIN  catalogos.sbc_cat_municipios mun     ON   mun.municipio_id=USA.municipio_id
        LEFT JOIN  catalogos.sbc_cat_departamentos DEP	ON   DEP.departamento_id=MUN.departamento_id
				--tipo vacuna edad  y catalo de edad
        JOIN  SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD  TVE  	ON    DTV.REL_TIPO_VACUNA_EDAD_ID=TVE.REL_TIPO_VACUNA_EDAD_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CVE			ON    CVE.CATALOGO_ID = TVE.EDAD_ID  
                --LUGAR VACUNA ACTUALIZACION
        LEFT JOIN  catalogos.sbc_cat_unidades_salud USAA ON    DTV.UNIDAD_SALUD_ACTUALIZACION_ID=USAA.UNIDAD_SALUD_ID
        LEFT JOIN  catalogos.sbc_cat_entidades_adtvas UADA	ON    USAA.ENTIDAD_ADTVA_ID=UADA.ENTIDAD_ADTVA_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS ESMCV				ON    ESMCV.CATALOGO_ID = MCV.ESTADO_REGISTRO_ID
        WHERE ESMCV.CODIGO != 'PASREG' 
        -------------------------------ESTADOS DE REGISTROS-------------------------------------------------
        AND  DTV.ESTADO_REGISTRO_ID=6869  AND TVD.ESTADO_REGISTRO_ID=6869  AND  TVE.ESTADO_REGISTRO_ID=6869
        -----------------------PARAMETROS ------------------------------------------------------------------
        AND  MCV.EXPEDIENTE_ID= v_expedienteId
        AND  TVE.EDAD_ID=idEdad
        AND  TVD.TIPO_VACUNA_ID=tipoVacunaId;  

BEGIN
--Busca el codigo padre de las Vacuna
     SELECT CATALOGO_ID INTO v_cod_catalogo_vacuna
        FROM   CATALOGOS.SBC_CAT_CATALOGOS
        --WHERE  CODIGO = 'TIP_VAC_SIPAI' AND  PASIVO = 0;
        WHERE  CODIGO = 'TIPOVACUV2' AND  PASIVO = 0;

 SELECT  count(*) into v_totalEdad  FROM SIPAI_PRM_RANGO_EDAD WHERE  ESQUEMA_EDAD=1 and pasivo = 0 order by orden;

   --Contar vacunas por programa
    select  count(*) into v_totalVacuna
	FROM    CATALOGOS.SBC_CAT_CATALOGOS
	JOIN    SIPAI_CONFIGURACION_VACUNA
	ON      TIPO_VACUNA_ID =CATALOGO_ID
	WHERE   CATALOGO_SUP=v_cod_catalogo_vacuna 
    AND     PROGRAMA_VACUNA_ID=vPROGRAMA_VACUNA_PAI
    AND     ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
     AND    ESQUEMA_AMBITO_ID = vAMBITO_VACUNA;			

    select  count(*) into v_totalDosis
     from  SIPAI_ESQUEMA_VIEW m
	 where m.expediente_id=v_expedienteId
     and m.DTV_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
     and m.TVE_ESTADO_REGISTRO_ID =vGLOBAL_ESTADO_ACTIVO ;---- 4819093


    --Obteneter la ultima proxima cita
        SELECT  MAX( DTV.FECHA_PROXIMA_VACUNA)	
         INTO v_fecha_proxima_cita
         FROM  SIPAI.SIPAI_MST_CONTROL_VACUNA MCV 
          JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV
           ON   DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
         WHERE MCV.EXPEDIENTE_ID=v_expedienteId;     ---4819219 

         v_fecha_texto  := FN_FECHA_TEXTO(v_fecha_proxima_cita);     
    --Armar el inicio y el nodo de vacuna   
       vData:='{"vacunas" : ["EDAD",';
   --lista catalogo de vacuna
   -- DBMS_OUTPUT.PUT_LINE (v_cod_catalogo_vacuna);
     FOR reg0 IN c_tipoVacuna(v_cod_catalogo_vacuna,vPROGRAMA_VACUNA_PAI) LOOP
           IF c_tipoVacuna%ROWCOUNT = v_totalVacuna THEN
            n_vacuna:='"'|| reg0.valor|| '"';
             vData :=vData||n_vacuna ;
            ELSE
             n_vacuna:='"'|| reg0.valor|| '"'|| ',';
              vData :=vData||n_vacuna ;
            END IF;
       END LOOP;

		  vData :=vData  || ' ], "datos":[';

          DBMS_OUTPUT.PUT_LINE (vData);

---fin del catlogo vacuna

     n_detalle:= '0';
     --RECORRER EL CATALOGO DE EDADES
      FOR a IN  c_tipoEdad  LOOP
         n_edad:='{' || '"'|| 'EDAD' || '"' || ':'|| '"'
                  ||a.valor || '"' || ',';

	     vData:=vData ||' ' || n_edad;

         v_edad:=a.id;
         --RECORRO LA CATALOGO DE VACUNA PARA TENER LA EDAD Y VACUNAS ENLAZADA
       n_detalle:='0';
       FOR  b in c_tipoVacuna(v_cod_catalogo_vacuna,vPROGRAMA_VACUNA_PAI) LOOP
           v_vacuna:=b.id;
          --RECORRO LA VACUNAS APLICADAS
          FOR c  IN  c_edad_vacunacion(v_edad,v_vacuna) Loop
        --  if c.TIPO_VACUNA_ID= v_vacuna  and c.edad_id=v_edad then
                n_vacuna:='"'|| b.valor|| '"'|| ':';                    --A

		      vData:=vData ||' '||  n_vacuna;

              n_detalle:='[{'
                                        ||  '"id":'    || c.DET_VACUNACION_ID ||', '
                                        || '"estado":' ||  '"'|| c.ESTADO_VACUNACION ||  '"'||', '
                                        || '"grupoPrioridad":' ||  '"'|| c.GRUPO_PRIORIDAD_VALOR ||  '"'||', '
                                        || '"motivo":' ||  '"'||  c.NOMBRE_MOTIVO_NO_APLICA ||  '"'||', '     
                                        || '"nVacuna":' ||  '"'|| c.NOMBRE_VACUNA ||  '"'||', '
                                        || '"cVacuna":' ||  '"'|| c.CODIGO_VACUNA ||  '"'||', '
                                        || '"persona":' ||  '"'|| c.NOMBRE_COMPLETO ||  '"' ||', ' 
                                        || '"unidad":' ||  '"'|| c.NOMBRE_UNIDAD_SALUD ||  '"'||', '
                                        || '"silais":' ||  '"'|| c.NOMBRE_SILAIS ||  '"'||', '
                                        || '"unidadActualizacion":' ||  '"'|| c.NOMBRE_UNIDAD_SALUD_ACTUALIZACION ||  '"'||', '
                                        || '"silaisActualizacion":' ||  '"'|| c.NOMBRE_SILAIS_ACTUALIZACION ||  '"'||', '
                                        || '"fecha":' ||  '"'  ||  

                                        to_char(trunc(c.FECHA_VACUNACION), 'DD') || '/' ||to_char(trunc(c.FECHA_VACUNACION), 'mm') || '/' || to_char(trunc(c.FECHA_VACUNACION), 'YYYY')
                                        ||  '"'||' , '
                                        || '"fechaCita":' ||'"'|| v_fecha_texto ||  '"'||', '
                                        || '"vacunador":' ||  '"'|| (c.NOMBRE_VACUNADOR) ||  '"'||' '
                                        || '}]';


			        vData:=vData ||' '||  n_detalle;
            --end if;
            END LOOP; --detalle
                if n_detalle = '0' then
                   IF c_tipoVacuna%ROWCOUNT <> v_totalVacuna THEN
                       n_vacuna:='"'|| b.valor|| '"'|| ':0,';

                    ELSE
                     n_vacuna:='"'|| b.valor|| '"'|| ':0';
                    END IF;

		           vData:=vData ||' '||  n_vacuna; 
             else
				IF c_tipoVacuna%ROWCOUNT <> v_totalVacuna THEN

                   vData:=vData ||' '||  ',';      
                 END IF;
             end if;
                n_detalle:='0';
              END LOOP; --Vacuna
          IF c_tipoEdad%ROWCOUNT <> v_totalEdad THEN

			  vData:=vData ||' '|| '},'; 
          ELSE
			   vData:=vData ||' '|| '}'; 
          END IF;
       END LOOP;--Edad

	        vData:=vData ||' '||']}'; 
             pRegistro:=vData ; 

	 DBMS_OUTPUT.PUT_LINE (pRegistro);
END;

FUNCTION FN_EDAD_TEXTO ( pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,					  
                            pFecVacuna    VARCHAR2
				          ) RETURN VARCHAR2 AS

  v_edad VARCHAR2(250);
  anios NUMBER;
  meses NUMBER;

 BEGIN
 
     v_edad :=PKG_SIPAI_UTILITARIOS.FN_OBT_EDAD(pExpedienteId,pFecVacuna);
     anios:=JSON_VALUE(v_edad, '$.anio');
     meses:=JSON_VALUE(v_edad, '$.mes');
   --  vDia:=JSON_VALUE(vTextoEdad, '$.dia')
     v_edad:=anios || ' anios y ' || meses || ' meses';
  -- Imprime el resultado
  --DBMS_OUTPUT.PUT_LINE(v_edad);
   RETURN v_edad ;

 END FN_EDAD_TEXTO;

PROCEDURE REPORTE_TARJETA_VACUNACION (pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                      pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                      pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
								      pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
									  pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                      pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,    
                                      pMsgError        OUT VARCHAR2 , 
                                      pResultado       OUT VARCHAR2,     
                                      pRegistro        OUT CLOB
									  )
IS 

--tipo de Reporte pedirlo en el parametro in
vTipoReporteTarjeta NUMBER:=1; --0 Detallada, 1 Simplificada
v_sistemaId NUMBER:=NVL(pSistemaId,0); --Validar cuando el llamdo no es del sipai
--v_cantida_dosis number;
v_cod_padre_vac NUMBER;
v_expediente_id number:=pExpedienteId ;  --; -- 4819137;  --4819137
r_madre reg_madre :=FN_OBT_REGISTRO_MADRE (pExpedienteId);
vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
vFirma VARCHAR2(100) := 'PKG_SIPAI_RPT_VACUNACION.REPORTE_TARJETA_VACUNACION => ';
vRecordCount number;

v_cat_vacuna_id number;
v_det_vacuna_id number;

--nodos
n_persona varchar2(4000);
n_redServicio varchar2(4000);
n_datosPerinetales  varchar2(4000);
n_vacuna varchar2(4000);
n_dosis varchar2(4000);
---
v_totalVacuna number;
v_totalDosis number;
v_cero varchar2(2);
v_municipio_ocr varchar2(100);
v_contador number;

v_cantidad_vacunas_covid_esquema_PAI number;

vData CLOB;

 CURSOR c_tipoVacuna(padreId number, programaId number) IS
  SELECT  catalogo_id id, (valor) valor  
    from CATALOGOS.SBC_CAT_CATALOGOS A
    JOIN SIPAI_CONFIGURACION_VACUNA B
    ON  A.CATALOGO_ID=B.TIPO_VACUNA_ID
    WHERE CATALOGO_SUP =padreId
    AND  B.PROGRAMA_VACUNA_ID=vPROGRAMA_VACUNA_PAI
    AND  B.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO;

 CURSOR c_dato_persona(pExpedienteId number) IS
        SELECT  DISTINCT   PER.EXPEDIENTE_ID,
            PER.PERSONA_ID,
            per.EADMN_OCR_NOMBRE,	
            PER.CODIGO_EXPEDIENTE_ELECTRONICO,
            PER.IDENTIFICACION_NUMERO,
            PER.PRIMER_NOMBRE,
            PER.SEGUNDO_NOMBRE,
            PER.PRIMER_APELLIDO,
            PER.SEGUNDO_APELLIDO,
            PER.SEXO_ID,
            PER.FALLECIDO,
            PER.SEXO_CODIGO, 
            DECODE (SUBSTR(PER.SEXO_CODIGO,-1), 'M','MASCULINO','FEMENINO' )SEXO,  
            TRUNC(PER.FECHA_NACIMIENTO) FECHA_NACIMIENTO,
			LPAD(EXTRACT(DAY FROM  PER.FECHA_NACIMIENTO),2,0) DIA,
			LPAD(EXTRACT(MONTH FROM  PER.FECHA_NACIMIENTO),2,0) MES,
			EXTRACT(YEAR FROM  PER.FECHA_NACIMIENTO) ANIO ,
			--LUGAR DE NACIMIENTO
			PER.pais_nacimiento_id,
            PER.pais_origen_nombre,
            PER.departamento_nacimiento_id ,
			PER.departamento_nacimiento_nombre,	
            PER.municipio_nacimiento_id,
            PER.municipio_nacimiento_nombre,
		  --UNIDAD DE SALUD OCURRENCIA
		    PER.unidad_salud_ocr_id ,  
            PER.unidad_salud_ocr_nombre ,   
            PER.ud_admn_ocr_id,
		    PER.ud_admn_ocr_nombre,
			--LUGAR DE RESIDENCIA
			PER.DIRECCION_RESIDENCIA,
            DEPART.DEPARTAMENTO_ID departamento_residencia_id,
            DEPART.NOMBRE departamento_residencia_nombre,

			MUNICIP.MUNICIPIO_ID municipio_residencia_id,
            MUNICIP.NOMBRE municipio_residencia_nombre,

			CTRLUSALUD.UNIDAD_SALUD_ID unidad_salud_rsd_id,
            CTRLUSALUD.NOMBRE unidad_salud_rsd_nombre,
            SEC.NOMBRE SECTOR,
            DIST.NOMBRE DISTRITO,
            COMRES.NOMBRE AS BARRIO,

            ENTADMIN.ENTIDAD_ADTVA_ID ud_admn_rsd_id,
			ENTADMIN.NOMBRE ud_admn_rsd_nombre,
            PER.TELEFONO

		FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER
        LEFT  JOIN  CATALOGOS.SBC_CAT_COMUNIDADES COMRES                            ON COMRES.COMUNIDAD_ID = PER.COMUNIDAD_RESIDENCIA_ID
        LEFT  JOIN  CATALOGOS.SBC_CAT_DISTRITOS DIST                ON DIST.DISTRITO_ID = COMRES.DISTRITO_ID
        LEFT  JOIN  CATALOGOS.SBC_REL_SECTOR_COMUNIDADES RELSECCOM  ON RELSECCOM.COMUNIDAD_ID = PER.COMUNIDAD_RESIDENCIA_ID AND RELSECCOM.PASIVO = 0
        LEFT  JOIN  CATALOGOS.SBC_CAT_SECTORES SEC                  ON SEC.SECTOR_ID = RELSECCOM.SECTOR_ID
        LEFT  JOIN  CATALOGOS.SBC_CAT_UNIDADES_SALUD CTRLUSALUD     ON SEC.UNIDAD_SALUD_ID = CTRLUSALUD.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_CAT_MUNICIPIOS MUNICIP              ON MUNICIP.MUNICIPIO_ID = CTRLUSALUD.MUNICIPIO_ID
        LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS ENTADMIN            ON ENTADMIN.ENTIDAD_ADTVA_ID = CTRLUSALUD.ENTIDAD_ADTVA_ID
        LEFT JOIN CATALOGOS.SBC_CAT_MUNICIPIOS MUNICIP              ON MUNICIP.MUNICIPIO_ID = CTRLUSALUD.MUNICIPIO_ID
        LEFT JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS DEPART            ON DEPART.DEPARTAMENTO_ID = MUNICIP.DEPARTAMENTO_ID
        where  per.expediente_id=pExpedienteId;

  CURSOR c_dato_perinetales (pExpedienteId number)IS
   SELECT LN.VALOR lugarNacimiento, TN.VALOR   tipoNacimiento,
            AP.VALOR  atendido, P.VALOR  pesoNacimiento          
        FROM  SIPAI_ANTECEDENTE_PERINATAL A
		LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS LN
		ON LN.CATALOGO_ID = A.LUGAR_NACIMIENTO_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS TN
        ON TN.CATALOGO_ID = A.TIPO_NACIMIENTO
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AP
        ON AP.CATALOGO_ID = A.ATENDIDO_POR
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS P
		ON P.CATALOGO_ID = A.PESO
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATESTADO
        ON CATESTADO.CATALOGO_ID = A.ESTADO_REGISTRO_ID
         WHERE  A.EXPEDIENTE_ID= pExpedienteId;
		--AND  A.ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_PASIVO;

CURSOR c_dato_dosis (pExpedienteId number)IS
  WITH DETALLE_VACUNAS_PAI AS (
    SELECT
        MCV.CONTROL_VACUNA_ID,
        MCV.EXPEDIENTE_ID,
        DTV.DET_VACUNACION_ID,
        TO_CHAR(DTV.FECHA_VACUNACION, 'YYYY/MM/DD') TXT_FECHA_VACUNACION,
        DTV.FECHA_VACUNACION,
        TVD.TIPO_VACUNA_ID,
        CTV.CODIGO CODIGO_VACUNA,
        DECODE(CTV.CODIGO, 'SIPAI026', CTV.VALOR, CTV.VALOR) NOMBRE_VACUNA,
        DTV.UNIDAD_SALUD_ID,
        USA.NOMBRE US_NOMBRE,
        DTV.TIPO_ESTRATEGIA_ID,
        CTE.VALOR NOMBRE_ESTRATEGIA,
        TVE.EDAD_ID,
        CVE.VALOR_EDAD NOMBRE_EDAD_VACUNA,
        TVD.CANTIDAD_DOSIS,
        SCV.ESQUEMA_AMBITO_ID,
        CATCV.CODIGO CODIGO_AMBITO,
        CATCV.VALOR NOMBRE_AMBITO,
        CEV.CODIGO CODIGO_ESTADO_VACUNACION,
        CEV.VALOR ESTADO_VACUNACION,
        USAA.UNIDAD_SALUD_ID UNIDAD_SALUD_ACTUALIZACION_ID,
        USAA.NOMBRE NOMBRE_UNIDAD_SALUD_ACTUALIZACION,
        UADA.ENTIDAD_ADTVA_ID ENTIDAD_ADTVA_ID_ACTUALIZACION,
        UADA.NOMBRE NOMBRE_SILAIS_ACTUALIZACION,
        DTV.ES_APLICADA_NACIONAL,
        NVL(SCV.ORDEN, 0) AS ORDEN_VACUNA,
        NVL(CVE.ORDEN, 0) AS ORDEN_EDAD,
        ROW_NUMBER() OVER (
            PARTITION BY CTV.CODIGO 
            ORDER BY DTV.FECHA_VACUNACION DESC, DTV.DET_VACUNACION_ID DESC
        ) AS RN
    FROM SIPAI.SIPAI_MST_CONTROL_VACUNA MCV
    JOIN SIPAI.SIPAI_DET_VACUNACION DTV ON DTV.CONTROL_VACUNA_ID = MCV.CONTROL_VACUNA_ID
    LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CTE ON CTE.CATALOGO_ID = DTV.TIPO_ESTRATEGIA_ID
    JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS TVD ON TVD.REL_TIPO_VACUNA_ID = MCV.TIPO_VACUNA_ID
    JOIN SIPAI_CONFIGURACION_VACUNA SCV ON SCV.CONFIGURACION_VACUNA_ID = TVD.CONFIGURACION_VACUNA_ID
    JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCV ON CATCV.CATALOGO_ID = SCV.ESQUEMA_AMBITO_ID
    JOIN CATALOGOS.SBC_CAT_CATALOGOS CTV ON CTV.CATALOGO_ID = TVD.TIPO_VACUNA_ID
    JOIN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD TVE ON TVE.REL_TIPO_VACUNA_EDAD_ID = DTV.REL_TIPO_VACUNA_EDAD_ID
    JOIN SIPAI_PRM_RANGO_EDAD CVE ON CVE.EDAD_ID = TVE.EDAD_ID
    LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CEV ON CEV.CATALOGO_ID = DTV.ESTADO_VACUNACION_ID
    JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USA ON USA.UNIDAD_SALUD_ID =
        CASE 
            WHEN CEV.CODIGO = 'EST_APL_VAC||03' THEN DTV.UNIDAD_SALUD_ACTUALIZACION_ID
            ELSE DTV.UNIDAD_SALUD_ID 
        END
    LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USAA ON DTV.UNIDAD_SALUD_ACTUALIZACION_ID = USAA.UNIDAD_SALUD_ID
    LEFT JOIN CATALOGOS.SBC_CAT_ENTIDADES_ADTVAS UADA ON USAA.ENTIDAD_ADTVA_ID = UADA.ENTIDAD_ADTVA_ID
    WHERE MCV.EXPEDIENTE_ID = pExpedienteId
      AND MCV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
      AND DTV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
),
ULTIMA_VACUNA_PROG_VAC_COVID AS (
    SELECT 
        MCV.CONTROL_VACUNA_ID, MCV.EXPEDIENTE_ID, DTV.DET_VACUNACION_ID,
        TO_CHAR(DTV.FECHA_VACUNACION, 'YYYY/MM/DD') AS TXT_FECHA_VACUNACION,
        DTV.FECHA_VACUNACION, MCV.TIPO_VACUNA_ID, 
        CTV.CODIGO CODIGO_VACUNA, CTV.VALOR NOMBRE_VACUNA, 
        DTV.UNIDAD_SALUD_ID, USA.NOMBRE US_NOMBRE,
        NULL AS TIPO_ESTRATEGIA_ID, NULL AS NOMBRE_ESTRATEGIA, 
        NULL AS EDAD_ID, NULL AS NOMBRE_EDAD_VACUNA, 
        TVD.CANTIDAD_DOSIS, NULL AS ESQUEMA_AMBITO_ID, 
        NULL AS CODIGO_AMBITO, NULL AS NOMBRE_AMBITO, 
        NULL AS CODIGO_ESTADO_VACUNACION, NULL AS ESTADO_VACUNACION, 
        NULL AS UNIDAD_SALUD_ACTUALIZACION_ID, 
        NULL AS NOMBRE_UNIDAD_SALUD_ACTUALIZACION, 
        NULL AS ENTIDAD_ADTVA_ID_ACTUALIZACION,
        NULL AS NOMBRE_SILAIS_ACTUALIZACION, 
        1 AS ES_APLICADA_NACIONAL, 
        99999 AS ORDEN_VACUNA, 
        99999 AS ORDEN_EDAD, 
        1 AS RN
    FROM SIPAI.SIPAI_MST_CONTROL_VACUNA MCV
    JOIN SIPAI.SIPAI_DET_VACUNACION DTV ON DTV.CONTROL_VACUNA_ID = MCV.CONTROL_VACUNA_ID
    JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS TVD ON TVD.REL_TIPO_VACUNA_ID = MCV.TIPO_VACUNA_ID
    JOIN CATALOGOS.SBC_CAT_CATALOGOS CTV ON CTV.CATALOGO_ID = TVD.TIPO_VACUNA_ID
    JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD USA ON USA.UNIDAD_SALUD_ID = DTV.UNIDAD_SALUD_ID
    WHERE MCV.EXPEDIENTE_ID = pExpedienteId
      AND MCV.PROGRAMA_VACUNA_ID = vPROGRAMA_VACUNA_COVID
      AND v_cantidad_vacunas_covid_esquema_PAI = 0
      --AND vTipoReporteTarjeta=0
      
    ORDER BY DTV.FECHA_VACUNACION DESC
    FETCH FIRST 1 ROW ONLY
)
-- ENVOLVEMOS TODO PARA QUE EL ORDER BY FUNCIONE CORRECTAMENTE
SELECT * FROM (
    SELECT * FROM DETALLE_VACUNAS_PAI
    WHERE (CODIGO_VACUNA = 'SIPAIVAC041' AND RN = 1) ---- Si es la vacuna COVID, solo la más reciente
       OR (CODIGO_VACUNA <> 'SIPAIVAC041')  -- Si es cualquier otra, traer todas
    UNION ALL
    SELECT * FROM ULTIMA_VACUNA_PROG_VAC_COVID
) RESULTADO_FINAL
ORDER BY ORDEN_VACUNA, ORDEN_EDAD;
      
    v_nombre_vacuna varchar2(100);
    v_nombre_edad varchar2(100);
    v_i  number;	
    v_dosis_aplicada number;	
    edad_texto VARCHAR2(40);
    lugar VARCHAR2(250);
    
    --Codigo Random QR
    vCodigoRandom            VARCHAR(30):='';
    vCodigoTarjeta           VARCHAR(30):= '';
    vControlDocumentoId      NUMBER ;
    vTipoDocumento           VARCHAR(30):='TIPDOCS03';
    vPrefijoCodigoDoc        VARCHAR(15):='TVAC';

BEGIN 

--Contar Vacunas Covid Registradas en el Esquema PAI
    SELECT COUNT(1)
    INTO v_cantidad_vacunas_covid_esquema_PAI
    FROM SIPAI.SIPAI_MST_CONTROL_VACUNA MCV
    JOIN SIPAI.SIPAI_DET_VACUNACION DTV ON DTV.CONTROL_VACUNA_ID = MCV.CONTROL_VACUNA_ID
    JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS TVD ON TVD.REL_TIPO_VACUNA_ID = MCV.TIPO_VACUNA_ID
    JOIN CATALOGOS.SBC_CAT_CATALOGOS CTV ON CTV.CATALOGO_ID = TVD.TIPO_VACUNA_ID
    WHERE MCV.EXPEDIENTE_ID = pExpedienteId
    AND   MCV.PROGRAMA_VACUNA_ID = vPROGRAMA_VACUNA_PAI
    AND   CTV.CODIGO ='SIPAIVAC041'
    AND   MCV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
    AND   DTV.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO;

--Registrar Codigo Random QR
IF v_sistemaId > 0 THEN 
      PR_INSERT_SIPAI_CTRL_DOCUMENTOS_VACUNA      (pControlDocumentoId => vControlDocumentoId,
                                                   pExpedienteId  => pExpedienteId, 
                                                   pTipoDocumento  => vTipoDocumento,
                                                   pPrefijoCodigoDoc  => vPrefijoCodigoDoc,
                                                   pUniSaludId    => pUniSaludId,
                                                   pDepartamentoId => pDepartamentoId,
                                                   pMunicipioId   => pMunicipioId,
                                                   pSistemaId     => pSistemaId,
                                                   pUsuario       => pUsuario,
                                                   pMsgError        => pMsgError ,
                                                   pResultado       => pResultado                           
                                                   );
    IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
        pResultado:='Error al Generar el Codigo QR del Documento';
        RAISE eParametrosInvalidos;
    END IF; 

        --Recuperar el codigo QR y de Tarjeta con el id Generado en la tabla de control para 
        --ponerla en el json 
        SELECT CODIGO, CODIGO_BOLETA 
        INTO   vCodigoRandom, vCodigoTarjeta
        FROM  SIPAI.SIPAI_CTRL_DOCUMENTOS_VACUNA
        WHERE CTRL_DOCUMENTO_VACUNA_ID=vControlDocumentoId;
 END IF;

--obtner el codigo padre para el catalogo de vacuna 
     SELECT CATALOGO_ID INTO v_cod_padre_vac
        FROM   CATALOGOS.SBC_CAT_CATALOGOS
        --WHERE  CODIGO = 'TIP_VAC_SIPAI' AND  PASIVO = 0;
        WHERE  CODIGO = 'TIPOVACUV2' AND  PASIVO = 0;

 --Contar  vacunas
    select  count(*) into v_totalVacuna
    from CATALOGOS.SBC_CAT_CATALOGOS
    WHERE CATALOGO_SUP =v_cod_padre_vac ; --7189

    --Armar el inicio y el nodo de vacuna

     vData:='{"tarjeta" :{ ';

     FOR cper IN c_dato_persona(v_expediente_id) LOOP

       SELECT count(*)
        into   v_contador
        FROM   CATALOGOS.SBC_CAT_UNIDADES_SALUD U
        JOIN   CATALOGOS.SBC_CAT_MUNICIPIOS M
        ON     U.MUNICIPIO_ID=M.MUNICIPIO_ID
        JOIN   CATALOGOS.SBC_CAT_DEPARTAMENTOS D
        ON     M.DEPARTAMENTO_ID=D.DEPARTAMENTO_ID
        WHERE U.UNIDAD_SALUD_ID=cper.UNIDAD_SALUD_OCR_ID; 
       ---Este contador es para asegurarse que existe registro

       IF v_contador !=0  THEN 
            SELECT D.NOMBRE
            INTO   v_municipio_ocr
            FROM   CATALOGOS.SBC_CAT_UNIDADES_SALUD U
            JOIN   CATALOGOS.SBC_CAT_MUNICIPIOS M
            ON     U.MUNICIPIO_ID=M.MUNICIPIO_ID
            JOIN   CATALOGOS.SBC_CAT_DEPARTAMENTOS D
            ON     M.DEPARTAMENTO_ID=D.DEPARTAMENTO_ID
            WHERE U.UNIDAD_SALUD_ID=cper.UNIDAD_SALUD_OCR_ID; 
       END IF;

        n_persona:=  '"personaId":' ||'"'|| cper.PERSONA_ID ||  '"'||', '
              || '"expedienteId":' ||'"'|| cper.EXPEDIENTE_ID ||  '"'||', '
              || '"expediente":' ||'"'|| cper.CODIGO_EXPEDIENTE_ELECTRONICO ||  '"'||', '
              || '"codigoQR":' ||  '"'|| vCodigoRandom  ||  '"'||', '
              || '"codigotarjeta":' ||  '"'|| vCodigoTarjeta ||  '"'||', '
              || '"identificacion":' ||'"'|| cper.IDENTIFICACION_NUMERO ||  '"'||', '
              || '"primernombre":' ||  '"'|| cper.PRIMER_NOMBRE ||  '"'||', '
              || '"segundonombre":' ||  '"'|| cper.SEGUNDO_NOMBRE ||  '"'||', '
              || '"primerapellido":' ||  '"'|| cper.PRIMER_APELLIDO ||  '"'||', '
              || '"segundoapellido":' ||  '"'|| cper.SEGUNDO_APELLIDO ||  '"'||', '
              || '"nombreMadre":' ||  '"'|| r_madre.nombre ||  '"'||', '
              || '"fechaNacimiento":' ||  '"'||  'DIA: '||cper.DIA||' '|| 'MES: '||cper.MES||' '|| 'ANIOS: '||cper.ANIO ||  '"'||', '
              || '"fallecido":' ||'"'|| cper.FALLECIDO ||  '"'||', '
              || '"telefono":' ||'"'|| cper.TELEFONO ||  '"'||', '
              || '"usuarioConsulta":' ||'"'|| pUsuario ||  '"'||', '
              || '"fechaHoy":' ||'"'|| TO_CHAR(SYSDATE, 'DD-MM-YYYY')   ||  '"'||', ' 
              || '"sexo":' ||  '"'|| cper.SEXO ||  '"'||', ' ;

        
        vData:=vData||' '||n_persona;

        n_redServicio:= '"redServico":' ||  '{'
               || '"direccion":' ||  '"'|| cper.DIRECCION_RESIDENCIA ||  '"'||', ' 
               || '"unidad":' ||  '"'|| cper.unidad_salud_rsd_nombre ||  '"'||', ' 
               || '"municipio":' ||  '"'|| cper.municipio_residencia_nombre ||  '"'||', '  
               || '"sector":' ||  '"'|| cper.sector ||  '"'||', ' 
               || '"distrito":' ||  '"'|| cper.distrito ||  '"'||', ' 
               || '"barrio":' ||  '"'|| cper.BARRIO||  '"'||', '
               || '"silais":' ||  '"'|| cper.ud_admn_rsd_nombre ||  '"'
               || '},'; 

        vData:=vData||' '||n_redServicio;

            FOR cDper IN c_dato_perinetales(cper.EXPEDIENTE_ID) LOOP
				  n_datosPerinetales:=  '"nacimiento":{'
				  || '"lugarNacimiento":' ||  '"'|| cDper.lugarNacimiento ||  '"'||', '
				  || '"tipoNacimiento":' ||  '"'|| cDper.tipoNacimiento   ||  '"'||', '
				  || '"atendido":' ||  '"'|| cDper.atendido  ||  '"'||', '
				  || '"pesoNacimiento":' ||  '"'|| cDper.pesoNacimiento   ||  '"'||'},' ;	    
            END LOOP;--datos perinetales

        vData:=vData||' '||n_datosPerinetales;              	

	END LOOP; --fin nodo de persona

     --Contar la cantidad de dosis que tiene el expediente en el programa PAI
    SELECT COUNT (*) 
    INTO vRecordCount 
    FROM  SIPAI.SIPAI_MST_CONTROL_VACUNA MCV
    JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV ON DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
    WHERE  MCV.EXPEDIENTE_ID=pExpedienteId
    AND    MCV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
    AND    DTV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
    AND    MCV.PROGRAMA_VACUNA_ID=vPROGRAMA_VACUNA_PAI;


   --032024 EMR 
   --inicio arreglo de vacuna 
      IF vRecordCount=0 THEN 
        vData:=vData||' '||'"vacunas":[';   --No tiene registros y no se incia con llave por que sera un array vacio
      ELSE
       vData:=vData||' '||'"vacunas":[{';   --tiene llave por que se crearaon los arreglos de dosis
      END IF;


      FOR cper IN c_dato_dosis(v_expediente_id) LOOP
        v_i:=c_dato_dosis%ROWCOUNT;
      END LOOP; 

	 FOR cDo IN c_dato_dosis(v_expediente_id) LOOP
      -- DBMS_OUTPUT.PUT_LINE ('c_dato_dosis%ROWCOUNT'|| c_dato_dosis%ROWCOUNT); 

       n_dosis := '"titulo":' ||  '"'|| cDo.NOMBRE_VACUNA || '"'||',' 
	               || '"dosis"'  || ' :[';
       vData:=vData||' '||n_dosis;   

       /*
       SELECT count(1)
       INTO v_dosis_aplicada
       FROM  SIPAI.SIPAI_MST_CONTROL_VACUNA MCV
       JOIN  SIPAI.SIPAI_DET_VACUNACION  DTV          ON  DTV.CONTROL_VACUNA_ID= MCV.CONTROL_VACUNA_ID
       JOIN  SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS TVD ON  TVD.REL_TIPO_VACUNA_ID=MCV.TIPO_VACUNA_ID
       JOIN  SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD  TVE 	  ON  TVE.REL_TIPO_VACUNA_EDAD_ID=DTV.REL_TIPO_VACUNA_EDAD_ID
       WHERE MCV.EXPEDIENTE_ID = v_expediente_id
       AND   MCV.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
       AND   TVD.TIPO_VACUNA_ID=cDo.TIPO_VACUNA_ID
       AND   TVE.EDAD_ID=cDo.EDAD_ID;
       */

         --Edad texto
         edad_texto:=FN_EDAD_TEXTO(v_expediente_id,cDo.FECHA_VACUNACION);
         --08 2024  DOSIS APLICADAS EN OTRO PAIS
         IF cDo.ES_APLICADA_NACIONAL =1 THEN
             --lugar:=cDo.US_NOMBRE;
           --Actualizaciion 10/2025 
           IF cDo.UNIDAD_SALUD_ACTUALIZACION_ID IS NULL THEN
             
             SELECT  INITCAP( DE.NOMBRE || '/'|| MU.NOMBRE || '-'||US.NOMBRE)
             INTO    lugar
             FROM    CATALOGOS.SBC_CAT_UNIDADES_SALUD   US
             LEFT  JOIN CATALOGOS.SBC_CAT_MUNICIPIOS    MU ON US.MUNICIPIO_ID= MU.MUNICIPIO_ID      AND US.PASIVO=0
             LEFT  JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS  DE ON DE.DEPARTAMENTO_ID= MU.DEPARTAMENTO_ID AND DE.PASIVO=0
             WHERE  US.UNIDAD_SALUD_ID=cDo.UNIDAD_SALUD_ID 
             AND    US.PASIVO=0;
        
          ELSE 
             SELECT  INITCAP( DE.NOMBRE || '/'|| MU.NOMBRE || '-'||US.NOMBRE)
             INTO    lugar
             FROM    CATALOGOS.SBC_CAT_UNIDADES_SALUD   US
             LEFT  JOIN CATALOGOS.SBC_CAT_MUNICIPIOS    MU ON US.MUNICIPIO_ID= MU.MUNICIPIO_ID      AND US.PASIVO=0
             LEFT  JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS  DE ON DE.DEPARTAMENTO_ID= MU.DEPARTAMENTO_ID AND DE.PASIVO=0
             WHERE  US.UNIDAD_SALUD_ID=cDo.UNIDAD_SALUD_ACTUALIZACION_ID 
             AND    US.PASIVO=0;
          END IF;
       
       
       
       
        ELSE
            lugar:='Otro Pais';
        END IF;
        
          v_dosis_aplicada:=1;--ITERANDO SOLO UNA VEZ POR CADA DOSIS
          

          FOR j IN 1..v_dosis_aplicada LOOP
            if j=v_dosis_aplicada then

		     n_dosis:='{'
                      ||  '"masterVacunacionId":'    || cDO.CONTROL_VACUNA_ID ||', '
                      ||  '"detalleVacunacionId":'   || cDO.DET_VACUNACION_ID ||', '
			          || '"dosi"' || ' :' ||  '"' ||cDo.NOMBRE_EDAD_VACUNA|| '"'||',' 
		              || '"fecha"' || ' :'||  '"' ||cDo.TXT_FECHA_VACUNACION|| '"'|| ','
		              || '"lugar"' || ' :'||  '"' ||lugar|| '"'||','
                      || '"estrategia"' || ' :'||  '"' ||cDo.NOMBRE_ESTRATEGIA|| '"'||','

                      ||  '"ordenVacuna":'    || cDO.ORDEN_VACUNA ||', '
                      ||  '"ordenEdad":'      || cDO.ORDEN_EDAD ||', '

                      || '"unidadActualizacion"' || ' :'||  '"' ||cDo.NOMBRE_UNIDAD_SALUD_ACTUALIZACION|| '"'||','
                      || '"silaisActualizacion"' || ' :'||  '"' ||cDo.NOMBRE_SILAIS_ACTUALIZACION|| '"'||','
                      || '"estadoVacuna"' || ' :'||  '"' ||cDo.ESTADO_VACUNACION|| '"'||','
                      || '"codigoEstadoVacuna"' || ' :'||  '"' ||cDo.CODIGO_ESTADO_VACUNACION|| '"'||','
                      || '"Edad"' || ' :'||  '"' ||edad_texto|| '"'||',' 
                      || '"ambito"' || ' :'||  '"' ||cDo.CODIGO_AMBITO|| '"'||',' 
                      || '"nombreAmbito"' || ' :' ||  '"' ||cDo.NOMBRE_AMBITO|| '"'||',' 
                      || '"codigoVacuna"' || ' :' ||  '"' ||cDo.CODIGO_VACUNA|| '"'

                      || '}';
             else          
              n_dosis:='{'
                      ||  '"masterVacunacionId":'    || cDO.CONTROL_VACUNA_ID ||', '
                      ||  '"detalleVacunacionId":'   || cDO.DET_VACUNACION_ID ||', '
			          || '"dosi"' || ' :' ||  '"' ||cDo.NOMBRE_EDAD_VACUNA|| '"'||',' 
		              || '"fecha"' || ' :'||  '"' ||cDo.FECHA_VACUNACION|| '"'|| ','
		              || '"lugar"' || ' :'||  '"' ||lugar|| '"'||','
                      || '"estrategia"' || ' :'||  '"' ||cDo.NOMBRE_ESTRATEGIA|| '"'||','

                      || '"unidadActualizacion"' || ' :'||  '"' ||cDo.NOMBRE_UNIDAD_SALUD_ACTUALIZACION|| '"'||','
                      || '"silaisActualizacion"' || ' :'||  '"' ||cDo.NOMBRE_SILAIS_ACTUALIZACION|| '"'||','
                      || '"estadoVacuna"' || ' :'||  '"' ||cDo.ESTADO_VACUNACION|| '"'||','
                      || '"codigoEstadoVacuna"' || ' :'||  '"' ||cDo.CODIGO_ESTADO_VACUNACION|| '"'||','
                      || '"Edad"' || ' :'||  '"' ||edad_texto|| '"'||',' 
                      || '"ambito"' || ' :' ||  '"' ||cDo.CODIGO_AMBITO|| '"'||','
                      || '"nombreAmbito"' || ' :' ||  '"' ||cDo.NOMBRE_AMBITO || '"'||',' 
                      || '"codigoVacuna"' || ' :' ||  '"' ||cDo.CODIGO_VACUNA|| '"'

                      || '},';
             end if;   
                   vData:=vData||' '||n_dosis;  

             END LOOP;         
         
          --si es la ultima vacuna 
          if  v_i<>c_dato_dosis%ROWCOUNT THEN
             n_dosis:=']},{'; 
             vData:=vData||' '||n_dosis;      

          ELSE
               n_dosis:=']}';  
               vData:=vData||' '||n_dosis;  

          END IF;

	 END  LOOP;
     
    
 
     vData:=vData||' '||']}}';  
     pRegistro:=vData;

     pResultado:='El documento tarjeta de vacuna ha si generado';

	DBMS_OUTPUT.PUT_LINE (pRegistro); 

EXCEPTION

  WHEN eParametrosInvalidos THEN
      pMsgError  := vFirma || ' ' || pResultado;

  WHEN OTHERS THEN
       pResultado := ' Error al generar reporte de Tarjeta de Vacunacion';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;



END;

PROCEDURE REPORTE_PERSONA_MADRE (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pRegistro    OUT CLOB
									   )
IS 

v_expediente_id number:= pExpedienteId ;   --4819137;4264098;4819137
vGLOBAL_ESTADO_ACTIVO   CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
 r_madre reg_madre  :=  FN_OBT_REGISTRO_MADRE(pExpedienteId);
v_departamento_id NUMBER;
v_nombre_departamento VARCHAR2(100);


--nodos
n_persona1 varchar2(4000);
n_persona2 varchar2(4000);

---
vAnio        varchar2 (10);
vMes         varchar2 (10);
vDias        varchar2 (10);
v_fecha_texto varchar2(15);
v_contador  number;

vData CLOB;

 CURSOR c_expediente_hijo (pExpedienteId number) IS
  SELECT  P1.PER_NOMINAL_ID , P1.PERSONA_ID  ,  P1.PACIENTE_ID,       
     --codigo de expediente
     P1.EXPEDIENTE_ID,P1.TIPO_EXPEDIENTE_CODIGO,P1.CODIGO_EXPEDIENTE_ELECTRONICO,
     P1.TIPO_EXPEDIENTE_NOMBRE,P1.TIPO_IDENTIFICACION_ID,P1.IDENTIFICACION_CODIGO,
     P1.IDENTIFICACION_NUMERO, P1.IDENTIFICACION_NOMBRE, 
     P1.PRIMER_NOMBRE, P1.SEGUNDO_NOMBRE, P1.PRIMER_APELLIDO,P1.SEGUNDO_APELLIDO,TELEFONO,
     P1.ETNIA_ID,P1.ETNIA_CODIGO,P1.ETNIA_VALOR, --Etnia
     P1.DIRECCION_RESIDENCIA, -- direcciondomicilio
      --divisionpolitica
    P1.COMUNIDAD_RESIDENCIA_ID,P1.COMUNIDAD_RESIDENCIA_NOMBRE, 
    P1.LOCALIDAD_ID, P1.LOCALIDAD_CODIGO, P1.LOCALIDAD_NOMBRE ,      
    P1.DISTRITO_RESIDENCIA_ID, P1.DISTRITO_RESIDENCIA_NOMBRE ,         
    P1.MUNICIPIO_RESIDENCIA_ID ,P1.MUNICIPIO_RESIDENCIA_NOMBRE ,        
    DEPA.DEPARTAMENTO_ID DEPARTAMENTO_RESIDENCIA_ID,
    DEPA.NOMBRE DEPARTAMENTO_RESIDENCIA_NOMBRE,
    P1.REGION_RESIDENCIA_ID, P1.REGION_RESIDENCIA_NOMBRE,                  
    P1.PAIS_NACIMIENTO_ID,P1.PAIS_ORIGEN_NOMBRE,
    P1.SEXO_ID, P1.SEXO_CODIGO, P1.SEXO_VALOR, --sexo
    --Fecha Nacimiento   
    P1.FECHA_NACIMIENTO,   -- 22-09-2021          
    P1.FALLECIDO,  -- "difunto": 0     
      --entidad   
      P1.EADMN_OCR_ID,P1.EADMN_OCR_NOMBRE,
   --unidad
      P1.UNIDAD_SALUD_OCR_ID, P1.UNIDAD_SALUD_OCR_NOMBRE
     FROM  CATALOGOS.SBC_MST_PERSONAS_NOMINAL P1
     JOIN CATALOGOS.SBC_CAT_COMUNIDADES      comu   ON P1.COMUNIDAD_RESIDENCIA_ID=comu.COMUNIDAD_ID AND comu.PASIVO=0
     JOIN CATALOGOS.SBC_CAT_MUNICIPIOS       munI   ON comu.MUNICIPIO_ID=munI.MUNICIPIO_ID AND munI.PASIVO=0
     JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS    DEPA   ON MUNI.DEPARTAMENTO_ID=DEPA.DEPARTAMENTO_ID AND depA.PASIVO=0

     WHERE P1.EXPEDIENTE_ID = v_expediente_id;

CURSOR C_EXPEDIENTE_MADRE (pExpedienteId number) IS	 
	SELECT PER2.PERSONA_ID,PER2.PRIMER_NOMBRE,PER2.SEGUNDO_NOMBRE,
          PER2.PRIMER_APELLIDO,PER2.SEGUNDO_APELLIDO,PER2.TELEFONO,
          --Paciente
          PER2.PACIENTE_ID,PER2.EXPEDIENTE_ID,PER2.TIPO_EXPEDIENTE_CODIGO,
          PER2.CODIGO_EXPEDIENTE_ELECTRONICO,PER2.TIPO_EXPEDIENTE_NOMBRE,
           --Identificacion
          PER2.TIPO_IDENTIFICACION_ID,PER2.IDENTIFICACION_CODIGO,
          PER2.IDENTIFICACION_NUMERO,PER2.IDENTIFICACION_NOMBRE  
    FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER
	 JOIN  CATALOGOS.SBC_REL_PERSONAS_COD_EXP REP
		ON    REP.EXPEDIENTE_1_ID=PER.EXPEDIENTE_ID 
	 JOIN  CATALOGOS.SBC_MST_PERSONAS_NOMINAL PER2
		ON    REP.EXPEDIENTE_2_ID=PER2.EXPEDIENTE_ID
     JOIN  CATALOGOS.SBC_CAT_CATALOGOS CREP
		ON CREP.CATALOGO_ID = REP.MOTIVO_ID 
        AND CREP.CODIGO='PMDR'
    where  per.expediente_id=v_expediente_id; 

BEGIN
    --Armar el inicio y el nodo de vacuna
     /*SELECT count(1) into v_contador 
	 FROM CATALOGOS.SBC_REL_PERSONAS_COD_EXP 
     WHERE EXPEDIENTE_1_ID=v_expediente_id;*/

	 IF r_madre.nombre IS NULL THEN
         v_contador:=0;
     END IF;


     vData:='{ ';

     FOR cper1 IN c_expediente_hijo(v_expediente_id) LOOP

      SELECT LPAD (TRUNC (MONTHS_BETWEEN (SYSDATE, fnf) / 12), 3, '0') YEARS,
                        LPAD (TRUNC (MOD (MONTHS_BETWEEN (SYSDATE, fnf), 12)), 2, '0') MONTHS,
                        LPAD (TRUNC (SYSDATE- ADD_MONTHS (fnf,TRUNC (MONTHS_BETWEEN (SYSDATE, fnf) / 12) * 12
                        + TRUNC (MOD (MONTHS_BETWEEN (SYSDATE, fnf), 12)))),2,'0') DAYS
                   INTO vAnio, vMes, vDias
                  FROM (SELECT cper1.FECHA_NACIMIENTO fnf 
                          FROM DUAL); 

        IF  cper1.MUNICIPIO_RESIDENCIA_ID != NULL THEN                  
            SELECT M.DEPARTAMENTO_ID, D.NOMBRE 
            INTO v_departamento_id, v_nombre_departamento
            FROM CATALOGOS.SBC_CAT_DEPARTAMENTOS D
            JOIN  CATALOGOS.SBC_CAT_MUNICIPIOS M
            ON    D.DEPARTAMENTO_ID=M.DEPARTAMENTO_ID
            AND   M.MUNICIPIO_ID=cper1.MUNICIPIO_RESIDENCIA_ID
            AND   M.PASIVO=0 
            WHERE D.PASIVO=0;
        END IF;


        v_fecha_texto:= FN_FECHA_TEXTO( cper1.FECHA_NACIMIENTO);     

        n_persona1:=  '"id":' ||'"'|| cper1.PER_NOMINAL_ID ||  '"'||', '
              || '"persona":{' 
              || '"id":' ||'"'|| cper1.PERSONA_ID ||  '"'||', '

              || '"paciente":{' 
              || '"id":' ||'"'|| cper1.PACIENTE_ID ||  '"'||', '

              || '"codigoExpediente":{'  
              || '"id":' ||'"'|| cper1.EXPEDIENTE_ID ||  '"'||', '
              || '"codigo":' ||'"'|| cper1.TIPO_EXPEDIENTE_CODIGO ||  '"'||', '
              || '"nombre":' ||'"'|| cper1.CODIGO_EXPEDIENTE_ELECTRONICO ||  '"'||', '
              || '"valor":' ||'"'|| cper1.TIPO_EXPEDIENTE_NOMBRE ||  '"'||'}}, '
              || '"identificacion":{' 
              || '"id":' ||'"'|| cper1.TIPO_IDENTIFICACION_ID ||  '"'||', '
              || '"codigo":' ||'"'|| cper1.IDENTIFICACION_CODIGO ||  '"'||', '
              || '"valor":' ||'"'|| cper1.IDENTIFICACION_NUMERO ||  '"'||'}, '
              || '"primernombre":' ||  '"'|| cper1.PRIMER_NOMBRE ||  '"'||', '
              || '"segundonombre":' ||  '"'|| cper1.SEGUNDO_NOMBRE ||  '"'||', '
              || '"primerapellido":' ||  '"'|| cper1.PRIMER_APELLIDO ||  '"'||', '
              || '"segundoapellido":' ||  '"'|| cper1.SEGUNDO_APELLIDO ||  '"'||', '
              || '"telefono":' ||  '"'|| cper1.TELEFONO ||  '"'||', '
              || '"etnia":{'  
              || '"id":' ||'"'|| cper1.ETNIA_ID ||  '"'||', '
              || '"codigo":' ||'"'|| cper1.ETNIA_CODIGO ||  '"'||', '
              || '"valor":' ||'"'|| cper1.ETNIA_VALOR ||  '"'||'}, '
              || '"direcciondomicilio":' ||'"'|| cper1.DIRECCION_RESIDENCIA || '"'||', '

              || '"divisionpolitica":{'   
                 || '"comunidad":{'  
                   || '"id":' ||'"'|| cper1.COMUNIDAD_RESIDENCIA_ID ||  '"'||', '
                   || '"nombre":' ||'"'|| cper1.COMUNIDAD_RESIDENCIA_NOMBRE ||  '"'||'}, '
                || '"localidad":{'  
                   || '"id":' ||'"'|| cper1.LOCALIDAD_ID ||  '"'||', '
                   || '"nombre":' ||'"'|| cper1.LOCALIDAD_NOMBRE ||  '"'||'}, '  
               || '"distrito":{'  
                   || '"id":' ||'"'|| cper1.DISTRITO_RESIDENCIA_ID ||  '"'||', '
                   || '"nombre":' ||'"'|| cper1.DISTRITO_RESIDENCIA_NOMBRE ||  '"'||'}, '  
               || '"municipio":{'  
                   || '"id":' ||'"'|| cper1.MUNICIPIO_RESIDENCIA_ID ||  '"'||', '
                   || '"nombre":' ||'"'|| cper1.MUNICIPIO_RESIDENCIA_NOMBRE ||  '"'||'}, '                  
               || '"departamento":{'  
                   || '"id":' ||'"'|| v_departamento_id ||  '"'||', '
                   || '"nombre":' ||'"'|| v_nombre_departamento ||  '"'||'}, '         
               || '"paisnacimiento":{'  
                   || '"id":' ||'"'|| cper1.PAIS_NACIMIENTO_ID ||  '"'||', '
                   || '"nombre":' ||'"'|| cper1.PAIS_ORIGEN_NOMBRE ||  '"'||'}}, '           
               || '"sexo":{' 
                 || '"id":' ||'"'|| cper1.SEXO_ID ||  '"'||', '
                 || '"codigo":' ||'"'|| cper1.SEXO_CODIGO ||  '"'||', '
                 || '"valor":' ||'"'|| cper1.SEXO_VALOR ||  '"'||'}, '

              || '"fechanacimiento":' ||'"'|| v_fecha_texto || '"'||', '
               || '"edad":{'
                || '"anios":' ||'"'|| vAnio ||  '"'||', '
                || '"meses":' ||'"'|| vMes ||  '"'||', '
                || '"dias":' ||'"'|| vDias ||  '"'||' }, '
             || '"difunto":' ||'"'|| cper1.FALLECIDO || '"'||' }, '
             || '"entidad":{' 
                || '"id":' ||'"'|| cper1.EADMN_OCR_ID ||  '"'||', '
                || '"nombre":' ||'"'|| cper1.EADMN_OCR_NOMBRE ||  '"'||', '  
             || '"unidad":{' 
                || '"id":' ||'"'|| cper1.UNIDAD_SALUD_OCR_ID ||  '"'||', '
                || '"nombre":' ||'"'|| cper1.UNIDAD_SALUD_OCR_NOMBRE ||  '"'||'}} ';

           vData:=vData||' '||n_persona1;

	END LOOP; --fin nodo de persona

    IF v_contador =0 THEN
       vData:=vData  ||'}';
    ELSE 
        vData:=vData  ||',';
    FOR cper2 IN c_expediente_madre(v_expediente_id) LOOP

     n_persona2:= '"madre":{' 
              || '"id":' ||'"'|| cper2.PERSONA_ID ||  '"'||', '
              || '"primernombre":' ||  '"'|| cper2.PRIMER_NOMBRE ||  '"'||', '
              || '"segundonombre":' ||  '"'|| cper2.SEGUNDO_NOMBRE ||  '"'||', '
              || '"primerapellido":' ||  '"'|| cper2.PRIMER_APELLIDO ||  '"'||', '
              || '"segundoapellido":' ||  '"'|| cper2.SEGUNDO_APELLIDO ||  '"'||', '
              || '"telefono":' ||  '"'|| cper2.TELEFONO ||  '"'||', '
              || '"paciente":{' 
              || '"id":' ||'"'|| cper2.PACIENTE_ID ||  '"'||', '
              || '"codigoExpediente":{'  
              || '"id":' ||'"'|| cper2.EXPEDIENTE_ID ||  '"'||', '
              || '"codigo":' ||'"'|| cper2.TIPO_EXPEDIENTE_CODIGO ||  '"'||', '
              || '"nombre":' ||'"'|| cper2.CODIGO_EXPEDIENTE_ELECTRONICO ||  '"'||', '
              || '"valor":' ||'"'|| cper2.TIPO_EXPEDIENTE_NOMBRE ||  '"'||'}}, '
              || '"identificacion":{' 
              || '"id":' ||'"'|| cper2.TIPO_IDENTIFICACION_ID ||  '"'||', '
              || '"codigo":' ||'"'|| cper2.IDENTIFICACION_CODIGO ||  '"'||', '
              || '"valor":' ||'"'|| cper2.IDENTIFICACION_NUMERO ||  '"'||'}}} ';


 END  LOOP;
 END IF;

     vData:=vData||' '||n_persona2;

	 pRegistro:=vData;  

	DBMS_OUTPUT.PUT_LINE (vData); 

END;

PROCEDURE REPORTE_PERSONA_HERMANO (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pRegistro    OUT CLOB
									   )
IS 


--nodos
n_hijos CLOB;
---
vAnio        varchar2 (10);
vMes         varchar2 (10);
vDias        varchar2 (10);
v_fecha_texto varchar2(15);
v_contador  number;
r_madre reg_madre  :=  FN_OBT_REGISTRO_MADRE(pExpedienteId);
vData CLOB;


CURSOR c_expediente_hijo  IS

      SELECT  PPHJ.EXPEDIENTE_ID PPHJ_EXPEDIENTE_ID,
                PMDR.EXPEDIENTE_ID PMDR_EXPEDIENTE_ID,
                PPHJ.CODIGO_EXPEDIENTE_ELECTRONICO CODIGO_EXPEDIENTE,
                (PPHJ.PRIMER_NOMBRE  ||' '|| PPHJ.SEGUNDO_NOMBRE ||' '|| PPHJ.PRIMER_APELLIDO||' '|| PPHJ.SEGUNDO_APELLIDO ) NOMBRE_HIJO,
                PPHJ.FECHA_NACIMIENTO,
			    DECODE (SUBSTR(PPHJ.SEXO_CODIGO,-1), 'M','MASCULINO','FEMENINO' )SEXO 
       FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PMDR
	  JOIN  CATALOGOS.SBC_REL_PERSONAS_COD_EXP REP
		ON    REP.EXPEDIENTE_2_ID=PMDR.EXPEDIENTE_ID 
	   JOIN  CATALOGOS.SBC_MST_PERSONAS_NOMINAL PPHJ
		ON    REP.EXPEDIENTE_1_ID=PPHJ.EXPEDIENTE_ID
	    JOIN  CATALOGOS.SBC_CAT_CATALOGOS CREP
		ON    CREP.CATALOGO_ID = REP.MOTIVO_ID 
		AND   CREP.CODIGO='PMDR'  --6852 MADRE  6853  PPDR PADRE 6854 PPHJ
       where  REP.EXPEDIENTE_2_ID=r_madre.expedienteId--de la Madre
       AND   PPHJ.EXPEDIENTE_ID NOT IN (pExpedienteId);

BEGIN

     SELECT COUNT(1)
	   INTO  v_contador
       FROM CATALOGOS.SBC_MST_PERSONAS_NOMINAL PMDR
	  JOIN  CATALOGOS.SBC_REL_PERSONAS_COD_EXP REP
		ON    REP.EXPEDIENTE_2_ID=PMDR.EXPEDIENTE_ID 
	   JOIN  CATALOGOS.SBC_MST_PERSONAS_NOMINAL PPHJ
		ON    REP.EXPEDIENTE_1_ID=PPHJ.EXPEDIENTE_ID
	    JOIN  CATALOGOS.SBC_CAT_CATALOGOS CREP
		ON    CREP.CATALOGO_ID = REP.MOTIVO_ID 
		AND   CREP.CODIGO='PMDR'  --6852 MADRE  6853  PPDR PADRE 6854 PPHJ
       where  REP.EXPEDIENTE_2_ID=r_madre.expedienteId
       AND   PPHJ.EXPEDIENTE_ID NOT IN (pExpedienteId);--de la Madre 


vData:='{ "Lista": [ ';
 FOR cper1 IN c_expediente_hijo  LOOP

        v_fecha_texto:= FECHA_DDMMYYYY(cper1.FECHA_NACIMIENTO);

  		n_hijos:= '{'			 			
                  || '"expedienteId":' ||'"'|| cper1.PPHJ_EXPEDIENTE_ID ||  '"'||', '
                  || '"expediente":'   ||'"'|| cper1.CODIGO_EXPEDIENTE  ||  '"'||', '
				  || '"nombre":'       ||'"'|| cper1.NOMBRE_HIJO        ||  '"'||', '
				  || '"sexo":'         ||'"'|| cper1.SEXO ||  '"'||', '
				  || '"fecha Nacimiento":' ||'"'|| v_fecha_texto ||  '"'||' ';

	 --si es la ultimo hijo
          IF  v_contador<> c_expediente_hijo%ROWCOUNT THEN
             n_hijos:=n_hijos ||'},';             
          ELSE
             n_hijos:=n_hijos ||'}';   
          END IF;
          vData:=  vData || ' ' ||   n_hijos;

         -- DBMS_OUTPUT.PUT_LINE  (n_hijos); 

END LOOP; 
vData:= vData ||  ' ]}';		   
pRegistro:=vData;

DBMS_OUTPUT.PUT_LINE (r_madre.expedienteId); 
DBMS_OUTPUT.PUT_LINE (vData); 

END;

PROCEDURE LISTA_REPORTE_SIPAI ( pRegistro  OUT var_refcursor)IS

BEGIN
      OPEN pRegistro FOR    
        SELECT REPORTE_ID, CODIGO, NOMBRE_REPORTE, TIPO_NIVEL,DESCRIPCION_REPORTE
        FROM SIPAI_TABLA_REPORTES; 

END LISTA_REPORTE_SIPAI;

PROCEDURE PR_INSERT_SIPAI_CTRL_DOCUMENTOS_VACUNA(  pControlDocumentoId IN OUT NUMBER,
                                                   pExpedienteId       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE, 
                                                   pTipoDocumento      IN VARCHAR2,
                                                   pPrefijoCodigoDoc   IN VARCHAR2,
                                                   pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                                   pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
                                                   pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
                                                   pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                                   pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,  
                                                   pMsgError        OUT VARCHAR2, 
                                                   pResultado       OUT VARCHAR2                           

                                      ) AS

     vCodValidacionId NUMBER;  
     vRegistroId      NUMBER(10) ;
     vCodigoRandom  VARCHAR(30);
     vTipoDocumentoId NUMBER:=FN_SIPAI_CATALOGO_ESTADO_Id(pTipoDocumento);
     vTipoOperacion   VARCHAR2(1) := 'I';
     vRegistro        HOSPITALARIO.PKG_SNH_COD_QR_DOCS.var_cursor; 
     vResultado      VARCHAR2(100);
     vMsgError       VARCHAR2(250);
     --Variable para el codigo Random
     vCodigoTarjeta VARCHAR(30);


  BEGIN
    -- TODO: Implementation required for PROCEDURE PKG_SIPAI_RPT_VACUNACION.PR_INSTER_SIPAI_CTRL_DOCUMENTOS_VACUNA
    SELECT NVL(MAX(CTRL_DOCUMENTO_VACUNA_ID),0 )+1
    INTO   vRegistroId 
    FROM SIPAI_CTRL_DOCUMENTOS_VACUNA;

    --Generar Codigo Random

     HOSPITALARIO.PKG_SNH_COD_QR_DOCS.PR_CRUD_CFG_CODIGOS_QR_DOCS(pCodValidacionId => vCodValidacionId,
                                                                 pRegistroId      => vRegistroId,
                                                                 pTipoDocumentoId => vTipoDocumentoId,
                                                                 pCodigo          => NULL,
                                                                 pUsuario         => pUsuario,
                                                                 pTipoOperacion   => vTipoOperacion,
                                                                 pRegistro        => vRegistro,
                                                                 pResultado       => vResultado,
                                                                 pMsgError        => vMsgError);
      CASE WHEN TRIM(vMsgError) IS NOT NULL THEN
           DBMS_OUTPUT.PUT_LINE('Resultado Error: '||vResultado);
           DBMS_OUTPUT.PUT_LINE('Mensaje Error: '||vMsgError);
     ELSE

        SELECT codigo  
        INTO   vCodigoRandom
        FROM HOSPITALARIO.SNH_CFG_CODIGOS_VALIDACION_DOC_QR
        WHERE COD_VALIDACION_ID=vCodValidacionId;
          DBMS_OUTPUT.PUT_LINE('Mensaje codigo: '||vCodigoRandom);

        --Calcular Codigo de Tarjeta
        IF vRegistroId <999999 THEN 
             SELECT pPrefijoCodigoDoc || '-'  || 
                    TO_CHAR(SYSDATE, 'YYYY') ||'-'||
                    LPAD(vRegistroId, 6, '0')
             INTO vCodigoTarjeta
             FROM dual;
        ELSE
            SELECT pPrefijoCodigoDoc || '-'  || 
                  TO_CHAR(SYSDATE, 'YYYY') ||'-'|| vRegistroId
             INTO vCodigoTarjeta
             FROM dual;
        END IF;

        INSERT INTO SIPAI.SIPAI_CTRL_DOCUMENTOS_VACUNA(EXPEDIENTE_ID,
                                                    TIPO_DOCUMENTO_ID,
                                                    CODIGO,
                                                    CODIGO_BOLETA,
                                                    USUARIO_REGISTRO,
                                                    UNIDAD_SALUD_ID,
                                                    MUNICIPIO_ID,
                                                    DEPARTAMENTO_ID,
                                                    SISTEMA_ID,
                                                    FECHA_REGISTRO)

                        VALUES(pExpedienteId,
                               vTipoDocumentoId,
                               vCodigoRandom,
                               vCodigoTarjeta,
                               pUsuario,
                               pUniSaludId,
                               pMunicipioId,
                               pDepartamentoId,
                               pSistemaId,
                               SYSDATE
                               )
        RETURNING CTRL_DOCUMENTO_VACUNA_ID INTO pControlDocumentoId;
          pResultado := 'Registro creado con exito';
         DBMS_OUTPUT.PUT_LINE (pResultado);
        END CASE;

 END PR_INSERT_SIPAI_CTRL_DOCUMENTOS_VACUNA;

PROCEDURE PR_CONSULTAR_SIPAI_CTRL_DOCUMENTOS_VACUNA (pCodigoRandom     IN VARCHAR2,
                                                     pMsgError        OUT VARCHAR2, 
                                                     pResultado       OUT VARCHAR2,                           
                                                     pRegistro        OUT CLOB
                                      ) AS

  vFirma     VARCHAR2(100):='PKG_SIPAI_RPT_VACUNACION.PR_CONSULTAR_SIPAI_CTRL_DOCUMENTOS_VACUNA ';
  vContador  NUMBER;

  BEGIN
  --Validar el codigo qr 

     SELECT COUNT(1) 
     INTO   vContador
     FROM   SIPAI.SIPAI_CTRL_DOCUMENTOS_VACUNA D
     WHERE  D.CODIGO = pCodigoRandom;

     IF vContador=0 THEN  
        pResultado:='el Codigo QR no es valido';
        RAISE eParametrosInvalidos;

     END IF;

      SELECT JSON_ARRAYAGG(
           JSON_OBJECT(
               'registroId' VALUE D.CTRL_DOCUMENTO_VACUNA_ID,
               'codigoQr' VALUE D.CODIGO,
               'codigoTarjeta' VALUE D.CODIGO_BOLETA,
               'fechaRegistro' VALUE TO_CHAR(D.FECHA_REGISTRO, 'YYYY-MM-DD HH24:MI:SS'),
               'usuario' VALUE D.USUARIO_REGISTRO,
               'tipoDocumentoId' VALUE D.TIPO_DOCUMENTO_ID,
               'nombreDocumento' VALUE C.VALOR,
               'expedienteId' VALUE D.EXPEDIENTE_ID,
               'nombrePersona' VALUE P.PRIMER_NOMBRE || ' ' || P.SEGUNDO_NOMBRE || ' ' || P.PRIMER_APELLIDO || ' ' || P.SEGUNDO_APELLIDO,
               'departamentoId' VALUE D.DEPARTAMENTO_ID,
               'nombreDepartamento' VALUE DEPA.NOMBRE,
               'municipioId' VALUE D.MUNICIPIO_ID,
               'nombreMunicipio' VALUE MUNI.NOMBRE,
               'unidadSaludId' VALUE USALUD.UNIDAD_SALUD_ID,
               'nombreUnidadSalud' VALUE USALUD.NOMBRE
           )  RETURNING CLOB
         ) AS JSON_RESULT
        INTO pRegistro
        FROM SIPAI.SIPAI_CTRL_DOCUMENTOS_VACUNA D
        --USAR LEFT JOIN POR QUE PARA EL CEFTIFICADO LOS VALORES SON NULO
        LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD   USALUD ON  D.UNIDAD_SALUD_ID=USALUD.UNIDAD_SALUD_ID
        LEFT JOIN CATALOGOS.SBC_MST_PERSONAS_NOMINAL P ON D.EXPEDIENTE_ID = P.EXPEDIENTE_ID
        LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS C ON D.TIPO_DOCUMENTO_ID = C.CATALOGO_ID
        LEFT JOIN CATALOGOS.SBC_CAT_MUNICIPIOS MUNI ON D.MUNICIPIO_ID = MUNI.MUNICIPIO_ID AND MUNI.PASIVO = 0
        LEFT JOIN CATALOGOS.SBC_CAT_DEPARTAMENTOS DEPA ON D.DEPARTAMENTO_ID = DEPA.DEPARTAMENTO_ID
        WHERE D.CODIGO = pCodigoRandom;

         pResultado:='Codigo Valido';
         DBMS_OUTPUT.PUT_LINE (pRegistro);

      --AGREGAR EXEPCIONES PARA CUANDO NO EXISTE DATO QR 

  EXCEPTION

  WHEN eParametrosInvalidos THEN
      pMsgError  := vFirma || ' ' || pResultado;

  END PR_CONSULTAR_SIPAI_CTRL_DOCUMENTOS_VACUNA;


  --Obtener datos de tarjeta de vacunacion en un cursor para reporte en jasper report
  PROCEDURE PR_CONSULTA_TARJETA_VACUNACION(  pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                             pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                             pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
                                             pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
                                             pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                             pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                         
                                             pMsgError        OUT VARCHAR2, 
                                             pResultado       OUT VARCHAR2, 
                                             pRegistro        OUT sys_refcursor
                                      ) AS

     vReporteTajeta CLOB;                                  
  BEGIN
    -- TODO: Implementation required for PROCEDURE PKG_SIPAI_RPT_VACUNACION.PR_CONSULTA_TARJETA_VACUNACION

   REPORTE_TARJETA_VACUNACION ( pExpedienteId,
                                pUniSaludId,
                                pDepartamentoId,
                                pMunicipioId,
                                pSistemaId,
                                pUsuario,
                                pMsgError, pResultado, vReporteTajeta );  
                                
                                DBMS_OUTPUT.PUT_LINE('vReporteTajeta +' ||vReporteTajeta);


     OPEN pRegistro FOR 
        SELECT 
              jt.*,
              vac.NOMBRE_VACUNA,
              vac.CONTROL_VACUNA_ID,
              vac.DET_VACUNACION_ID,
              vac.NOMBRE_DOSIS,
              vac.FECHA_VACUNACION,
              vac.LUGAR_OCURRENCIA,
              vac.ESTRATEGIA,
              vac.UNIDAD_SALUD_ACTUALIZACION,
              vac.SILAIS_ACTUALIZACION,
              vac.ESTADO_APLICACION,
              vac.CODIGO_ESTADO_VACUNA,
              vac.EDAD,
              vac.CODIGO_AMBITO,
              vac.VALOR_AMBITO,
              vac.CODIGO_VACUNA,
              vac.ORDEN_VACUNA,
              vac.ORDEN_EDAD
            FROM
              JSON_TABLE(
                 vReporteTajeta,
                '$.tarjeta'
                COLUMNS (
                  CODIGO_QR VARCHAR2(30) PATH '$.codigoQR',
                  CODIGO_DOCUMENTO VARCHAR2(30) PATH '$.codigotarjeta',
                  PERSONA_ID NUMBER PATH '$.personaId',
                  EXPEDIENTE_ID NUMBER PATH '$.expedienteId',
                  EXPEDIENTE_ELECTRONICO VARCHAR2(30) PATH '$.expediente',
                  IDENTIFICACION VARCHAR2(50) PATH '$.identificacion',
                  PRIMER_NOMBRE VARCHAR2(50) PATH '$.primernombre',
                  SEGUNDO_NOMBRE VARCHAR2(50) PATH '$.segundonombre',
                  PRIMER_APELLIDO VARCHAR2(50) PATH '$.primerapellido',
                  SEGUNDO_APELLIDO VARCHAR2(50) PATH '$.segundoapellido',
                  NOMBRE_MADRE VARCHAR2(150) PATH '$.nombreMadre',
                  FECHA_NACIMIENTO VARCHAR2(50) PATH '$.fechaNacimiento',
                  FALLECIDO NUMBER PATH '$.fallecido',
                  SEXO VARCHAR2(10) PATH '$.sexo',
                  TELEFONO VARCHAR2(10) PATH '$.telefono',
                  DIRECCION VARCHAR2(200) PATH '$.redServico.direccion',
                  NOMBRE_UNIDAD_SALUD VARCHAR2(100) PATH '$.redServico.unidad',
                  NOMBRE_MUNICIPIO VARCHAR2(100) PATH '$.redServico.municipio',
                  NOMBRE_SECTOR VARCHAR2(100) PATH '$.redServico.sector',
                  NOMBRE_COMUNIDAD VARCHAR2(100) PATH '$.redServico.barrio',
                  NOMBRE_SILAIS VARCHAR2(100) PATH '$.redServico.silais',
                  USUARIO_CONSULTA VARCHAR2(100) PATH '$.usuarioConsulta',
                  FECHA_CONSULTA   VARCHAR2(100) PATH '$.fechaHoy'
                )
              ) jt
            LEFT OUTER JOIN
              JSON_TABLE(
                vReporteTajeta,
                '$.tarjeta.vacunas[*]'
                COLUMNS (
                  NOMBRE_VACUNA VARCHAR2(100) PATH '$.titulo',
                  NESTED PATH '$.dosis[*]'
                  COLUMNS (
                    CONTROL_VACUNA_ID NUMBER PATH '$.masterVacunacionId',
                    DET_VACUNACION_ID NUMBER PATH '$.detalleVacunacionId',
                    NOMBRE_DOSIS VARCHAR2(100) PATH '$.dosi',
                    FECHA_VACUNACION VARCHAR2(20) PATH '$.fecha',
                    LUGAR_OCURRENCIA VARCHAR2(200) PATH '$.lugar',
                    ESTRATEGIA VARCHAR2(50) PATH '$.estrategia',
                    UNIDAD_SALUD_ACTUALIZACION VARCHAR2(200) PATH '$.unidadActualizacion',
                    SILAIS_ACTUALIZACION VARCHAR2(100) PATH '$.silaisActualizacion',
                    ESTADO_APLICACION VARCHAR2(100) PATH '$.estadoVacuna',
                    CODIGO_ESTADO_VACUNA VARCHAR2(100) PATH '$.codigoEstadoVacuna',
                    EDAD VARCHAR2(100) PATH '$.Edad',
                    CODIGO_AMBITO VARCHAR2(50) PATH '$.ambito',
                    VALOR_AMBITO VARCHAR2(100) PATH '$.nombreAmbito',
                    CODIGO_VACUNA VARCHAR2(50) PATH '$.codigoVacuna',
                    ORDEN_VACUNA VARCHAR2(50) PATH '$.ordenVacuna',
                    ORDEN_EDAD VARCHAR2(50) PATH '$.ordenEdad'
                  )
                )
              ) vac ON 1=1
               WHERE vac.CODIGO_AMBITO IS NULL OR vac.CODIGO_AMBITO = 'CLA-REG-ESQ-AMB||02'
               ORDER BY  vac.FECHA_VACUNACION;

END PR_CONSULTA_TARJETA_VACUNACION;

  --Obtener datos de tarjeta de vacunacion en un cursor para reporte en jasper report
  PROCEDURE PR_CONSULTA_TARJETA_VACUNACION_SUPLEMENTO(  pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                                         pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                                         pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
                                                         pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
                                                         pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                                         pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                         
                                                         pMsgError        OUT VARCHAR2, 
                                                         pResultado       OUT VARCHAR2, 
                                                         pRegistro        OUT sys_refcursor
                                      ) AS

     vReporteTajeta CLOB;                                  
  BEGIN
    -- TODO: Implementation required for PROCEDURE PKG_SIPAI_RPT_VACUNACION.PR_CONSULTA_TARJETA_VACUNACION

   REPORTE_TARJETA_VACUNACION ( pExpedienteId,
                                pUniSaludId,
                                pDepartamentoId,
                                pMunicipioId,
                                pSistemaId,
                                pUsuario,
                                pMsgError, pResultado, vReporteTajeta );     


     OPEN pRegistro FOR 
        SELECT *
              FROM JSON_TABLE(
                vReporteTajeta ,
          '$.tarjeta'
          COLUMNS (
            --DATO TARJETA 
            CODIGO_QR          VARCHAR2(30)  PATH '$.codigoQR',
            CODIGO_DOCUMENTO    VARCHAR2(30)  PATH '$.codigotarjeta',
            --DATOS PERSONA
            PERSONA_ID          NUMBER  PATH '$.personaId',
            EXPEDIENTE_ID       NUMBER  PATH '$.expedienteId',
            EXPEDIENTE_ELECTRONICO          VARCHAR2(30)  PATH '$.expediente',
            IDENTIFICACION                  VARCHAR2(50)  PATH '$.identificacion',
            PRIMER_NOMBRE                   VARCHAR2(50)  PATH '$.primernombre',
            SEGUNDO_NOMBRE                  VARCHAR2(50)  PATH '$.segundonombre',
            PRIMER_APELLIDO                 VARCHAR2(50)  PATH '$.primerapellido',
            SEGUNDO_APELLIDO                VARCHAR2(50)  PATH '$.segundoapellido',
            NOMBRE_MADRE                    VARCHAR2(150) PATH '$.nombreMadre',
            FECHA_NACIMIENTO                VARCHAR2(50)  PATH '$.fechaNacimiento',
            FALLECIDO                       NUMBER       PATH '$.fallecido',
            SEXO                            VARCHAR2(10)  PATH '$.sexo',
            DIRECCION                       VARCHAR2(200) PATH '$.redServico.direccion',
            NOMBRE_UNIDAD_SALUD             VARCHAR2(100) PATH '$.redServico.unidad',
            NOMBRE_MUNICIPIO                VARCHAR2(100) PATH '$.redServico.municipio',
            NOMBRE_SECTOR                   VARCHAR2(100) PATH '$.redServico.sector',
            NOMBRE_COMUNIDAD                VARCHAR2(100) PATH '$.redServico.barrio',
            NOMBRE_SILAIS                   VARCHAR2(100) PATH '$.redServico.silais',

            NESTED PATH '$.vacunas[*]'
            COLUMNS (
              NOMBRE_VACUNA               VARCHAR2(100) PATH '$.titulo',
              NESTED PATH '$.dosis[*]'
              COLUMNS (
                CONTROL_VACUNA_ID    NUMBER        PATH '$.masterVacunacionId',
                DET_VACUNACION_ID    NUMBER        PATH '$.detalleVacunacionId',
                NOMBRE_DOSIS         VARCHAR2(100) PATH '$.dosi',
                FECHA_VACUNACION     VARCHAR2(20)  PATH '$.fecha',
                LUGAR_OCURRENCIA                VARCHAR2(200) PATH '$.lugar',
                ESTRATEGIA           VARCHAR2(50)  PATH '$.estrategia',
                UNIDAD_SALUD_ACTUALIZACION  VARCHAR2(200) PATH '$.unidadActualizacion',
                SILAIS_ACTUALIZACION  VARCHAR2(100) PATH '$.silaisActualizacion',
                ESTADO_APLICACION       VARCHAR2(100) PATH '$.estadoVacuna',
                CODIGO_ESTADO_VACUNA   VARCHAR2(100) PATH '$.codigoEstadoVacuna',
                EDAD                 VARCHAR2(100)  PATH '$.Edad',
                CODIGO_AMBITO               VARCHAR2(50) PATH '$.ambito',
                VALOR_AMBITO                 VARCHAR2(100) PATH '$.nombreAmbito',
                CODIGO_VACUNA            VARCHAR2(50) PATH '$.codigoVacuna',
                ORDEN_VACUNA            VARCHAR2(50) PATH '$.ordenVacuna',
                ORDEN_EDAD            VARCHAR2(50) PATH '$.ordenEdad'
              )
            )
          )
          ) jt
          WHERE CODIGO_AMBITO !='CLA-REG-ESQ-AMB||02';



  END PR_CONSULTA_TARJETA_VACUNACION_SUPLEMENTO;

END;
/