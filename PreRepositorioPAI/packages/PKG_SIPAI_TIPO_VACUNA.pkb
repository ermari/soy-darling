CREATE OR REPLACE PACKAGE BODY SIPAI."PKG_SIPAI_TIPO_VACUNA" 
AS  

 vAMBITO_VACUNA             NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('CLA-REG-ESQ-AMB||02');
 vAMBITO_VITAMINA           NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('CLA-REG-ESQ-AMB||03');
 vAMBITO_DESPARCITANTE      NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id('CLA-REG-ESQ-AMB||04');  
 vTipoVacunadT              NUMBER:=FN_SIPAI_CATALOGO_ESTADO_ID('SIPAI026');--dt

FUNCTION FN_LISTA_REL_EDAD_FRECUECUENCIA_ANUAL (pExpedienteId IN NUMBER, pFechaVacunacion DATE)
   RETURN VARCHAR2
IS

   fechaUltimaDosis DATE;
   anioFechaVacunacion NUMBER:= EXTRACT(YEAR FROM pFechaVacunacion);
   anioFechaUltimaDosis     NUMBER;
   anioEntreFechas          NUMBER;
   mesesEntreFechas         NUMBER;

   vLista     VARCHAR2(4000);  -- Ampliado en caso de lista grande
   vContador  NUMBER := 0;

   --en caso de vacunas por actualziacion
   vExisteEnAnio NUMBER;
   vFechaPosterior DATE;
   vFechaAnterior DATE;



BEGIN
   vLista := '[';

   FOR r IN (SELECT REL_TIPO_VACUNA_EDAD_ID,FRECUENCIA_ANUAL,EDAD_ENTRE_DOSIS
               FROM SIPAI_REL_TIPO_VACUNA_EDAD
              WHERE FRECUENCIA_ANUAL >= 1
                AND ESTADO_REGISTRO_ID = 6869)
   LOOP

       SELECT MAX(FECHA_VACUNACION)
              --TRUNC(MONTHS_BETWEEN( MAX(FECHA_VACUNACION),pFechaVacunacion)/12)  
       INTO fechaUltimaDosis--,anioEntreFechas
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA M
        JOIN SIPAI.SIPAI_DET_VACUNACION     D
          ON D.CONTROL_VACUNA_ID = M.CONTROL_VACUNA_ID
        JOIN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
          ON M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
        JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVAC
          ON CATVAC.CATALOGO_ID = REL.TIPO_VACUNA_ID
        JOIN SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD E
          ON REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
         AND E.REL_TIPO_VACUNA_EDAD_ID = D.REL_TIPO_VACUNA_EDAD_ID
         WHERE M.EXPEDIENTE_ID = pExpedienteId
         AND M.ESTADO_REGISTRO_ID = 6869
        --Agregar filtro estado activo por el cambio a borrado logico
         AND D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
         AND D.REL_TIPO_VACUNA_EDAD_ID = r.REL_TIPO_VACUNA_EDAD_ID
        
         ;

     anioFechaUltimaDosis := EXTRACT(YEAR FROM fechaUltimaDosis);
     anioEntreFechas      := anioFechaVacunacion -anioFechaUltimaDosis;
     mesesEntreFechas     := TRUNC(MONTHS_BETWEEN(pFechaVacunacion, fechaUltimaDosis));  

       /*DBMS_OUTPUT.PUT_LINE('fechaUltimaDosis '||fechaUltimaDosis);
       DBMS_OUTPUT.PUT_LINE('anioFechaUltimaDosis '||anioFechaUltimaDosis);
       DBMS_OUTPUT.PUT_LINE('anioEntreFechas '||anioEntreFechas);
       DBMS_OUTPUT.PUT_LINE('mesesEntreFechas '||mesesEntreFechas);
       DBMS_OUTPUT.PUT_LINE('R.EDAD_ENTRE_DOSIS '|| R.EDAD_ENTRE_DOSIS);
         */


       -- 1. Verificar que no tenga vacunas aplicadas en el anio  de la Fecha de vacunacion del parametro pFechaVacunacion 
         SELECT COUNT(1)
         INTO vExisteEnAnio
         FROM SIPAI.SIPAI_MST_CONTROL_VACUNA M
         JOIN SIPAI.SIPAI_DET_VACUNACION D ON D.CONTROL_VACUNA_ID = M.CONTROL_VACUNA_ID
         WHERE M.EXPEDIENTE_ID = pExpedienteId
         AND M.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
         --Agregar filtro estado activo por el cambio a borrado logico
         AND D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO   
         AND D.REL_TIPO_VACUNA_EDAD_ID = r.REL_TIPO_VACUNA_EDAD_ID
         AND EXTRACT(YEAR FROM FECHA_VACUNACION) = EXTRACT(YEAR FROM pFechaVacunacion);
      --2. Si no hay vacunas aplicadas ese anio,
         IF vExisteEnAnio = 0 THEN
             -- obtener la min(fecha aplicacion) que sea mayor a mi pfechaVacuna
          SELECT MIN(FECHA_VACUNACION)
            INTO vFechaPosterior
            FROM SIPAI.SIPAI_MST_CONTROL_VACUNA M
            JOIN SIPAI.SIPAI_DET_VACUNACION D ON D.CONTROL_VACUNA_ID = M.CONTROL_VACUNA_ID
           WHERE M.EXPEDIENTE_ID = pExpedienteId
             AND M.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
             AND D.REL_TIPO_VACUNA_EDAD_ID = r.REL_TIPO_VACUNA_EDAD_ID
             AND FECHA_VACUNACION > pFechaVacunacion;

          -- obtener la max(fecha aplicacion) que sea menor  mi pfechaVacuna  fecha anterior
          SELECT MAX(FECHA_VACUNACION)
           INTO vFechaAnterior
           FROM SIPAI.SIPAI_MST_CONTROL_VACUNA M
           JOIN SIPAI.SIPAI_DET_VACUNACION D ON D.CONTROL_VACUNA_ID = M.CONTROL_VACUNA_ID
           WHERE M.EXPEDIENTE_ID = pExpedienteId
           AND M.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
           --Agregar filtro estado activo por el cambio a borrado logico
           AND D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO  
           AND D.REL_TIPO_VACUNA_EDAD_ID = r.REL_TIPO_VACUNA_EDAD_ID
           AND FECHA_VACUNACION < pFechaVacunacion;

             -- Validar rango entre fechas
             --4. luego verificar que mi pfechaVacuna sea menor a la fecha sacada en el punto 2 menos los meses entre dosis 
             -- 5. luego verificar que mi pfechaVacunan sea mayor a la fecha sacada en el punto 3 mas  los meses entre dosis
             IF (vFechaPosterior IS NULL OR pFechaVacunacion < ADD_MONTHS(vFechaPosterior, -r.EDAD_ENTRE_DOSIS))
             AND (vFechaAnterior IS NULL OR pFechaVacunacion > ADD_MONTHS(vFechaAnterior, r.EDAD_ENTRE_DOSIS)) THEN

          vContador := vContador + 1;
          vLista := vLista || r.REL_TIPO_VACUNA_EDAD_ID || ',';

         END IF; 
        END IF;     
    END LOOP;

    IF vContador > 0 THEN
      -- Remover última coma
      vLista := SUBSTR(vLista, 1, LENGTH(vLista) - 1);
      vLista := vLista || ']';
   ELSE
      vLista := '[]';
   END IF;

   RETURN vLista;

END; 

 FUNCTION FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE(pExpedienteId NUMBER,pcodigoVacuna VARCHAR2,
 pcodigoDosis VARCHAR2) RETURN NUMBER
 AS 
    vContador PLS_INTEGER;
 BEGIN 

     SELECT COUNT(*)
     into   vContador
     FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
     JOIN   SIPAI.SIPAI_DET_VACUNACION     D
     ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
     JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
     ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
     JOIN   CATALOGOS.SBC_CAT_CATALOGOS CATVAC ON CATVAC.CATALOGO_ID=REL.TIPO_VACUNA_ID
     JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
     ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
     AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
     ------------------------------------------------------------
     WHERE M.EXPEDIENTE_ID=pExpedienteId
     AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO 
     --Agregar filtro estado activo por el cambio a borrado logico
     AND D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO  
     AND   CATVAC.CODIGO=pcodigoVacuna
     AND   E.CODIGO_NUM_DOSIS=pcodigoDosis;

     RETURN vContador;

 END;
 
 FUNCTION FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE_ANUAL(pExpedienteId NUMBER,pcodigoVacuna VARCHAR2,
 pcodigoDosis VARCHAR2, pAnio NUMBER) RETURN NUMBER
 AS 
    vContador PLS_INTEGER;
 BEGIN 

     SELECT COUNT(*)
     into   vContador
     FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
     JOIN   SIPAI.SIPAI_DET_VACUNACION     D
     ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
     JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
     ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
     JOIN   CATALOGOS.SBC_CAT_CATALOGOS CATVAC ON CATVAC.CATALOGO_ID=REL.TIPO_VACUNA_ID
     JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
     ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
     AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
     ------------------------------------------------------------
     WHERE M.EXPEDIENTE_ID=pExpedienteId
     AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO 
     --Agregar filtro estado activo por el cambio a borrado logico
     AND   D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO  
     AND   CATVAC.CODIGO=pcodigoVacuna
     AND   E.CODIGO_NUM_DOSIS=pcodigoDosis
     AND   EXTRACT(YEAR FROM D.FECHA_VACUNACION) = pAnio;

     RETURN vContador;

 END;


FUNCTION FN_OBTNER_PROXIMA_CITA(    pRelTipoVacunaId IN OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                    pEdad NUMBER,
									pTipoEdad VARCHAR2
									) RETURN var_refcursor
	AS

    vRegistro var_refcursor;
	v_edad_actual number;
    v_edad_proxima number;
	v_tipo_edad_proxima varchar2(1);
	v_cantidad_edad_cita  number;
	v_fecha_proxima_dosi date:=sysdate;
	v_proxima_vacuna varchar2(200);
    v_contador number;
	v_fecha_texto VARCHAR2(30);

     BEGIN 
              SELECT   count(1) 
			  INTO    v_contador
              FROM SIPAI_VACUNA_EDADES_VIEW 
              WHERE  pEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
              AND  TIPO_EDAD= pTipoEdad and REL_TIPO_VACUNA_ID=pRelTipoVacunaId
              ORDER BY   ORDEN_VACUNA  ,ORDEN_EDAD;	

          IF v_contador = 1 THEN
	          SELECT   ORDEN_EDAD 
			  INTO    v_edad_actual
              FROM SIPAI_VACUNA_EDADES_VIEW 
              WHERE  pEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
              AND  TIPO_EDAD= pTipoEdad and REL_TIPO_VACUNA_ID=pRelTipoVacunaId
              ORDER BY   ORDEN_VACUNA  ,ORDEN_EDAD;	

			  SELECT  DISTINCT EDAD_DESDE, TIPO_EDAD
			    INTO   v_edad_proxima, v_tipo_edad_proxima
               FROM    SIPAI_VACUNA_EDADES_VIEW 
               WHERE  ORDEN_EDAD=v_edad_actual+1
               AND V_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
               AND E_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
			   ;

			   SELECT RTRIM(LISTAGG( '''' ||NOMBRE_VACUNA|| ''',' )  WITHIN GROUP ( ORDER BY ORDEN_VACUNA ), ',')
               INTO  v_proxima_vacuna
			   FROM    SIPAI_VACUNA_EDADES_VIEW 
               WHERE  ORDEN_EDAD=v_edad_actual+1        
               AND V_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
               AND E_ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
			   ;

            	--Calcular Dias	y --CALCULAR FECHA PROXIMA CITA		
			   IF v_tipo_edad_proxima='D'	THEN
			       v_cantidad_edad_cita:=0; --No existe proxima cita en dias hasta 2M
			   END IF;

			   IF v_tipo_edad_proxima='M'	THEN
			   --Restamos los Meses Ejem Proxima Cita es 4mes y edad Act.es 2Mes la cita sera entre Dos mes a la fecha Actual
				  v_cantidad_edad_cita:=v_edad_proxima-v_edad_actual; 
			      v_fecha_proxima_dosi:=ADD_MONTHS(SYSDATE,v_cantidad_edad_cita);
               END IF;  

			    IF  v_tipo_edad_proxima='A'	THEN 
				--Obtenemos la diferencia de años y la pasamos a meses
				  v_cantidad_edad_cita:=(v_edad_proxima-v_edad_actual) *12; 
				   v_fecha_proxima_dosi:=ADD_MONTHS(SYSDATE,v_cantidad_edad_cita) ;
				END IF; 

				v_fecha_texto:=  EXTRACT(YEAR FROM  v_fecha_proxima_dosi)
				               ||'-' || LPAD(EXTRACT(MONTH FROM  v_fecha_proxima_dosi),2,0)
							    ||'-' ||LPAD(EXTRACT(DAY FROM  v_fecha_proxima_dosi),2,0);


				 OPEN vRegistro FOR

                  SELECT  v_fecha_texto FECHA_PROXIMA_DOSIS, 
				          v_proxima_vacuna NOMBRE_VACUNA from dual;
              ELSE
               OPEN vRegistro FOR
               SELECT '' from dual;

              END IF;

        	      RETURN  vRegistro;		

 END;

 FUNCTION FN_OBTENER_MESES_ENTRE_DOSIS(pVacunaId number, pCodigoEdad varchar) return NUMBER AS

  vMesesEntreDosis NUMBER;

   BEGIN

    SELECT rtve.EDAD_ENTRE_DOSIS
    into   vMesesEntreDosis
    FROM   sipai_rel_tip_vacunacion_dosis rtvac 
    JOIN   SIPAI_REL_TIPO_VACUNA_EDAD rtve ON rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
    AND   rtvac.estado_registro_id = 6869
    AND   rtve.ESTADO_REGISTRO_ID = 6869
    JOIN  SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID 
    AND   PRME.ESTADO_REGISTRO_ID = 6869
    WHERE rtvac.tipo_vacuna_id=pVacunaId   --7752
    AND   PRME.CODIGO_EDAD= pCodigoEdad;--       'COD_INT_EDAD_7918'

   RETURN vMesesEntreDosis;
 END;

--FiltroDt  --ajuste dt 2024
 FUNCTION FN_OBTNER_FILTRO_DT( pEdad NUMBER,pCodigoExpediente NUMBER,pFechaVacunacion IN DATE ) RETURN NUMBER AS
  filtroDt NUMBER:=0;   
  vCount NUMBER; 
  vEsquema1 NUMBER:=0;
  --------------------------------
  vCodigoEdad VARCHAR2(50);
  vUltimaFechaVacunacion DATE;
  vEdadEntreDosis   NUMBER; --CALCULADO EN MES 
  vEdadUltimaDosis  NUMBER;
  vPrimeraDosisEsquema1 NUMBER;
  vSegundaDosisEsquema1 NUMBER;

  BEGIN 

      SELECT COUNT(*)---pRME.CODIGO_EDAD  ,detVAC.FECHA_VACUNACION
      INTO   vPrimeraDosisEsquema1
      FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA mst
      JOIN   SIPAI.SIPAI_DET_VACUNACION     detVAC on  mst.control_vacuna_id=detVAC.control_vacuna_id 
      JOIN   sipai_rel_tip_vacunacion_dosis rtvac on  mst.tipo_vacuna_id = rtvac.rel_tipo_vacuna_id
      JOIN   SIPAI_REL_TIPO_VACUNA_EDAD   	rtve ON   rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
      AND    detVAC.REL_TIPO_VACUNA_EDAD_ID = rtve.REL_TIPO_VACUNA_EDAD_ID AND rtve.ESTADO_REGISTRO_ID = 6869
      JOIN   SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID AND PRME.ESTADO_REGISTRO_ID = 6869 --ESQUEMA_EDAD=1
      WHERE  mst.EXPEDIENTE_ID=pCodigoExpediente
      --Agregar filtro estado activo por el cambio a borrado logico
      AND    mst.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
      AND    detVAC.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
      and    rtvac.estado_registro_id=vGLOBAL_ESTADO_ACTIVO
      AND    rtvac.tipo_vacuna_id=vTipoVacunadT   --en desa es 7752
      AND    PRME.CODIGO_EDAD IN('COD_INT_EDAD_7786');

      SELECT COUNT(*)---pRME.CODIGO_EDAD  ,detVAC.FECHA_VACUNACION
      INTO   vSegundaDosisEsquema1
      FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA mst
      JOIN   SIPAI.SIPAI_DET_VACUNACION     detVAC on  mst.control_vacuna_id=detVAC.control_vacuna_id 
      JOIN   sipai_rel_tip_vacunacion_dosis rtvac on  mst.tipo_vacuna_id = rtvac.rel_tipo_vacuna_id
      JOIN   SIPAI_REL_TIPO_VACUNA_EDAD   	rtve ON   rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
      AND    detVAC.REL_TIPO_VACUNA_EDAD_ID = rtve.REL_TIPO_VACUNA_EDAD_ID AND rtve.ESTADO_REGISTRO_ID = 6869
      JOIN   SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID AND PRME.ESTADO_REGISTRO_ID = 6869 --ESQUEMA_EDAD=1
      WHERE  mst.EXPEDIENTE_ID=pCodigoExpediente
      --Agregar filtro estado activo por el cambio a borrado logico
      AND    mst.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
      AND    detVAC.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
      and    rtvac.estado_registro_id=vGLOBAL_ESTADO_ACTIVO
      AND    rtvac.tipo_vacuna_id=vTipoVacunadT   --en desa es 7752
      AND    PRME.CODIGO_EDAD IN('COD_INT_EDAD_7787');

  IF  pEdad >= 120 AND pEdad <= 239 THEN
     DBMS_OUTPUT.PUT_LINE ('CASO EDAD ENTRE 10 Y 19') ;

      IF  vPrimeraDosisEsquema1=0 THEN
           filtroDt:=1;
           vEsquema1:=1;
      END IF;
  END IF;

  IF  pEdad >= 240 AND pEdad <= 251 THEN
    DBMS_OUTPUT.PUT_LINE ('CASO EDAD 20 MAS ') ;
      IF  vPrimeraDosisEsquema1=0 THEN
           filtroDt:=1;
           vEsquema1:=1;
      ELSIF vSegundaDosisEsquema1=0 THEN
         filtroDt:=2;
         vEsquema1:=1;
      END IF;
  END IF;

    DBMS_OUTPUT.PUT_LINE ('pEdad='||pEdad ||' vPrimeroDosisEsquema1='||vPrimeraDosisEsquema1 || ' vSegundaDosisEsquema1='||vSegundaDosisEsquema1) ;

  IF  pEdad >= 252 AND vPrimeraDosisEsquema1 =1  AND vSegundaDosisEsquema1=0 THEN 
     DBMS_OUTPUT.PUT_LINE ('CASO EDAD 21 A MAS PERO TIENE 1 DOSI DE ESQUEMA 1 ') ;
         filtroDt:=2;
         vEsquema1:=1;

  END IF;

--CASO DE 21 A MAS sin  esquema 1
  IF  pEdad >= 252 AND vEsquema1=0 THEN
     --contar si  tiene dt en su historial de vacunacion.
        SELECT count(*)
        into  vCount
        FROM SIPAI.SIPAI_MST_CONTROL_VACUNA mst
        JOIN sipai_rel_tip_vacunacion_dosis rtvac ON mst.tipo_vacuna_id = rtvac.rel_tipo_vacuna_id
        AND rtvac.estado_registro_id = 6869  and mst.estado_registro_id=6869
        WHERE mst.EXPEDIENTE_ID = pCodigoExpediente
        --Agregar filtro estado activo por el cambio a borrado logico
       AND    mst.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
       AND    rtvac.tipo_vacuna_id = vTipoVacunadT;

     -- si no tiene entoces se asigna la primera dosis despues de 21 anios.
     IF vCount=0 THEN 
            filtroDt:=3;
     ELSE   --Si se encontro registro entoces obtener los datos del ultimo registros 
            SELECT  PRME.CODIGO_EDAD, detVAC.FECHA_VACUNACION  --, NVL(rtve.EDAD_ENTRE_DOSIS,0)EDAD_ENTRE_DOSIS
            INTO    vCodigoEdad,vUltimaFechaVacunacion
            FROM SIPAI.SIPAI_MST_CONTROL_VACUNA mst
            JOIN SIPAI.SIPAI_DET_VACUNACION detVAC ON mst.control_vacuna_id = detVAC.control_vacuna_id
            JOIN sipai_rel_tip_vacunacion_dosis rtvac ON mst.tipo_vacuna_id = rtvac.rel_tipo_vacuna_id
             AND rtvac.estado_registro_id = 6869
            JOIN SIPAI_REL_TIPO_VACUNA_EDAD rtve ON rtvac.REL_TIPO_VACUNA_ID = rtve.REL_TIPO_VACUNA_ID
                AND detVAC.REL_TIPO_VACUNA_EDAD_ID = rtve.REL_TIPO_VACUNA_EDAD_ID
                AND rtve.ESTADO_REGISTRO_ID = 6869
            JOIN SIPAI.SIPAI_PRM_RANGO_EDAD PRME ON rtve.EDAD_ID = PRME.EDAD_ID
                AND PRME.ESTADO_REGISTRO_ID = 6869
            WHERE mst.EXPEDIENTE_ID = pCodigoExpediente
            --Agregar filtro estado activo por el cambio a borrado logico
            AND    mst.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
            AND rtvac.tipo_vacuna_id = vTipoVacunadT
            AND detVAC.FECHA_VACUNACION = ( SELECT MAX(detVAC2.FECHA_VACUNACION)  
                                            FROM SIPAI.SIPAI_MST_CONTROL_VACUNA mst2
                                            JOIN sipai_rel_tip_vacunacion_dosis rtvac2 ON mst2.tipo_vacuna_id = rtvac2.rel_tipo_vacuna_id
                                            JOIN SIPAI.SIPAI_DET_VACUNACION detVAC2 ON mst2.control_vacuna_id = detVAC2.control_vacuna_id     
                                            WHERE mst2.EXPEDIENTE_ID = pCodigoExpediente
                                            --Agregar filtro estado activo por el cambio a borrado logico
                                            AND mst2.ESTADO_REGISTRO_ID    = vGLOBAL_ESTADO_ACTIVO 
                                            AND detVAC2.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
                                            AND rtvac2.tipo_vacuna_id      = vTipoVacunadT

                                );

            vEdadUltimaDosis := TRUNC(months_between(pFechaVacunacion,vUltimaFechaVacunacion));
            -- DBMS_OUTPUT.PUT_LINE ('vEdadUltimaDosis' || vEdadUltimaDosis) ;
            --Si es primera dosis y han pasados los meses entre dosis de la config. de 2dadosi   asignar 2da. Dosis 

          --DBMS_OUTPUT.PUT_LINE ('vCodigoEdad' || vCodigoEdad) ;
            IF vCodigoEdad='COD_INT_EDAD_7917'  AND (vEdadUltimaDosis>=FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7918'))  THEN
                   DBMS_OUTPUT.PUT_LINE ('Edad entre dosis' || FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7918')) ;
                   filtroDt:=4;
            ELSIF vCodigoEdad='COD_INT_EDAD_7918'  AND (vEdadUltimaDosis>=FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7919'))  THEN
                dBMS_OUTPUT.PUT_LINE ('Edad entre dosis' || FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7919')) ;
                filtroDt:=5;
            ELSIF vCodigoEdad='COD_INT_EDAD_7919'  AND (vEdadUltimaDosis>=FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7920'))  THEN
                DBMS_OUTPUT.PUT_LINE ('Edad entre dosis' || FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7920')) ;
                filtroDt:=6;
            ELSIF vCodigoEdad='COD_INT_EDAD_7920'  AND (vEdadUltimaDosis>=FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7921'))  THEN
               dBMS_OUTPUT.PUT_LINE ('Edad entre dosis' || FN_OBTENER_MESES_ENTRE_DOSIS(vTipoVacunadT, 'COD_INT_EDAD_7921')) ;
                filtroDt:=7;
            ELSIF vCodigoEdad='COD_INT_EDAD_7921'  THEN --Es la 5ta.dosis
                filtroDt:=0;--osea no hay dosis que mostrar
            END IF;
      END IF;
   END IF;

  RETURN filtroDt;

 END;
---CONSULTA PROXIMA CITA
 PROCEDURE  PRC_PROXIMA_CITA_DOSIS ( pRelTipoVacunaId IN OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                    pEdad               IN NUMBER,
									pTipoEdad           IN  VARCHAR2,
									pTipoAccion         IN VARCHAR2,
                                    ---------Agregar Fecha Vacunacion para calcular la edad de vacunacion--------
                                    pFechaVacunacion        IN DATE,
                                    ------------------------------------
						            pRegistro       		OUT var_refcursor,
									pResultado       		OUT VARCHAR2,
									pMsgError       		OUT VARCHAR2
								   )IS
   vFechaProximaCita  DATE;							   

 BEGIN   
   pRegistro:= FN_OBTNER_PROXIMA_CITA(pRelTipoVacunaId,pEdad,pTipoEdad);
 END  PRC_PROXIMA_CITA_DOSIS;

--F1 NOV-2024  FILTRO VACUNAS GEO
 FUNCTION FN_OBTENER_VACUNAS_GEO RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN

    OPEN vRegistro FOR
     SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.VALOR                    CATTIPVAC_DESCRIPCION,   --usamos el valor en ves  de descripcion para filtro de pantalla nominal
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL,

            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
			 FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
           LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
           LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
    ------------WHERE -------------------------------
    WHERE E.ES_GEO=1
    AND   A.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO  
    AND    E.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO 
    ; 
    DBMS_OUTPUT.PUT_LINE ('FN_OBTENER_VACUNAS_GEO');

     RETURN vRegistro;

  END FN_OBTENER_VACUNAS_GEO;  

--F8  ACTUALIZACION
 FUNCTION FN_ACTUALIZACION_ESQUEMA  (  pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                            pEdad IN NUMBER,
                                            pTipoEdad IN VARCHAR2,
                                            pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                            pFechaVacunacion  IN DATE
                                        )RETURN var_refcursor AS

  vRegistro var_refcursor;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');

    --Transformar los meses edad a dias desde la fecha de nacimiento
  vFechaNacimiento DATE;
  vEdad       NUMBER;
  vFiltroDt   NUMBER:=0;
  vAnioVacunacion NUMBER:=EXTRACT(YEAR FROM pFechaVacunacion);

  vExisteNumeroDosisAnteriorExpediente NUMBER;
  --2026
    vExistePrimeraDosisCOVID NUMBER:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE_ANUAL(
                                   pCodigoExpediente,'SIPAIVAC041','CODINTVAL-9',vAnioVacunacion );  
    vExisteSegundaDosisCOVID NUMBER:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE_ANUAL(
                                   pCodigoExpediente,'SIPAIVAC041','CODINTVAL-10',vAnioVacunacion ); 

   vFiltroListaVacunaAnual varchar2(4000):=FN_LISTA_REL_EDAD_FRECUECUENCIA_ANUAL(pCodigoExpediente,pFechaVacunacion);


BEGIN

    DBMS_OUTPUT.PUT_LINE ('F8- FN_ACTUALIZACION_ESQUEMA');

     --VALIDAR SI EL EXPEDIENTE TIENE 1 DOSIS VPH APLICADA.
   vExisteNumeroDosisAnteriorExpediente:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE(pCodigoExpediente,'SIPAI012023','CODINTVAL-9' );
   DBMS_OUTPUT.PUT_LINE ('vExisteNumeroDosisAnteriorExpediente' ||vExisteNumeroDosisAnteriorExpediente);

  --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);
     DBMS_OUTPUT.PUT_LINE ('vAMBITO_VACUNA= '||vAMBITO_VACUNA);

      vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

      --obtener el valor del filtro de la dt
      vFiltroDt:=FN_OBTNER_FILTRO_DT(vEdad,pCodigoExpediente,pFechaVacunacion);

        DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);
        DBMS_OUTPUT.PUT_LINE ('vFiltroDt= '||vFiltroDt);

  OPEN vRegistro FOR   
        SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
         LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
         LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
            ------------WHERE -------------------------------
           -- WHERE  vEdad >= REDAD.EDAD_DESDE AND vEdad <=  ((REDAD.EDAD_HASTA + 0.99)+0.25)      
            --WHERE  pEdad >= REDAD.EDAD_DESDE AND pEdad <=  (REDAD.EDAD_HASTA + 0.25)
			---WHERE   vEdad BETWEEN REDAD.EDAD_DESDE AND  A.EDAD_MAX 
             WHERE   (vEdad BETWEEN REDAD.EDAD_DESDE AND  A.EDAD_MAX OR vEdad BETWEEN REDAD.EDAD_DESDE AND  REDAD.EDAD_HASTA)  
             AND  TIPO_EDAD='M' --pTipoEdad
             AND   C.ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
            -- AND   E.ES_ADICIONAL=0 
           --  AND   E.ES_REFUERZO=0
             AND   A.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
             AND    E.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
             AND ((E.REL_TIPO_VACUNA_EDAD_ID NOT IN 
                                              ( 
                                                 SELECT E.REL_TIPO_VACUNA_EDAD_ID 
                                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                                 ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                                 ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                                 AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                                                 ------------------------------------------------------------
                                                 WHERE M.EXPEDIENTE_ID=pCodigoExpediente
                                                 AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                                 --Agregar por que sera borrado logico
                                                 AND   D.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                   )                             )
             -- or A.rel_tipo_vacuna_id = 61  influenza de adulto
            OR A.REL_TIPO_VACUNA_ID IN (
                                          SELECT REL_TIPO_VACUNA_ID 
                                          FROM SIPAI_REL_TIP_VACUNACION_DOSIS 
                                          ---------------------------------------------
                                          WHERE TIPO_VACUNA_ID =( 
                                                                  SELECT CATALOGO_ID 
                                                                  FROM  CATALOGOS.SBC_CAT_CATALOGOS 
                                                                  WHERE CODIGO = 'SIPAI0037' 
                                                                  AND PASIVO=0
                                                                  )
                                           AND  ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                           AND  ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                         )) 

            --Ajuste para Dt VPH y COVID
              AND  CATTIPVAC.CODIGO !='SIPAI026' 
              AND  CATTIPVAC.CODIGO !='SIPAI012023'
              AND  CATTIPVAC.CODIGO !='SIPAIVAC041'  --Exclir COVID 
             --EXCLUIR DOSIS ANUALES 
              AND   E.FRECUENCIA_ANUAL=0
        --Filtro Vacunas Covid segun dosis aplicadas en el expediente
          UNION 
          SELECT *
          FROM SIPAI_TIPO_VACUNA_VIEW
          WHERE CATTIPVAC_CODIGO = 'SIPAIVAC041'
          AND 
          (   -- Mostrar 1ra Dosis COVID
            (CODIGO_NUM_DOSIS = 'CODINTVAL-9' AND vExistePrimeraDosisCOVID = 0) 
          OR  -- Mostrar 2da Dosis COVID
            (CODIGO_NUM_DOSIS = 'CODINTVAL-10' AND vExistePrimeraDosisCOVID = 1 
                                               AND vExisteSegundaDosisCOVID = 0 )
          )
          AND  vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
          --vFiltro Vacunas Anuales
             UNION
             SELECT * 
             FROM SIPAI_TIPO_VACUNA_VIEW
             WHERE vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA AND  TIPO_EDAD='M' AND REL_TIPO_VACUNA_EDAD_ID IN (select jt.ID  from dual,  json_table(vFiltroListaVacunaAnual, '$[*]' 
                                                COLUMNS (ID NUMBER PATH '$'))jT)
            ---- EXCLUIR COVID PARA QUE NO SE DUPLIQUE
            --SE ESTA  manejando su lógica de 1ra y 2da dosis de forma manual en el BLOQUE ANTERRIOR
            AND CATTIPVAC_CODIGO != 'SIPAIVAC041'
           ----vFiltroDt
           
           UNION        
             SELECT * 
             FROM SIPAI_TIPO_VACUNA_VIEW
             WHERE  CATTIPVAC_CODIGO='SIPAI026'
             AND (  vFiltroDt  = 1  AND EDAD_ID=7786 OR
                    vFiltroDt  = 2  AND EDAD_ID=7787 OR 
                  ----2do Esquema-------------------------------
                   vFiltroDt  = 3  AND EDAD_ID=7917  OR
                   vFiltroDt  = 4  AND EDAD_ID=7918  OR
                   vFiltroDt  = 5  AND EDAD_ID=7919 OR
                   vFiltroDt  = 6  AND EDAD_ID=7920 OR   
                   vFiltroDt  = 7  AND EDAD_ID=7921
                )              
        --  vFiltro VPH
            UNION        
             SELECT * 
             FROM SIPAI_TIPO_VACUNA_VIEW
             WHERE  CATTIPVAC_CODIGO='SIPAI012023'
             AND    REL_TIPO_VACUNA_EDAD_ID NOT  IN (
                                                 SELECT E.REL_TIPO_VACUNA_EDAD_ID 
                                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                                 ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                                 ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                                 AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                                                 ------------------------------------------------------------
                                                 WHERE M.EXPEDIENTE_ID     =pCodigoExpediente
                                                 AND  M.ESTADO_REGISTRO_ID =vGLOBAL_ESTADO_ACTIVO
                                                 --Agregar filtro estado activo por el cambio a borrado logico
                                                AND D.ESTADO_REGISTRO_ID    = vGLOBAL_ESTADO_ACTIVO 
                                                )
             AND    vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
             AND (  vExisteNumeroDosisAnteriorExpediente  = 0  AND CODIGO_NUM_DOSIS='CODINTVAL-9' OR
                    vExisteNumeroDosisAnteriorExpediente  = 1  AND  CODIGO_NUM_DOSIS='CODINTVAL-10' 
             AND EDAD_ENTRE_DOSIS <= (SELECT 
                                           MAX(TRUNC(MONTHS_BETWEEN(pFechaVacunacion, D.FECHA_VACUNACION))) 
                                           FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                           JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                          ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                          JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                          ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                          JOIN   CATALOGOS.SBC_CAT_CATALOGOS CATVAC ON CATVAC.CATALOGO_ID=REL.TIPO_VACUNA_ID
                                          JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                          ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                          AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                             ------------------------------------------------------------
                             WHERE M.EXPEDIENTE_ID=pCodigoExpediente
                             AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                             --Agregar filtro estado activo por el cambio a borrado logico
                             AND   D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
                             AND   CATVAC.CODIGO='SIPAI012023'
                             AND   E.CODIGO_NUM_DOSIS='CODINTVAL-9'
                             )
                );            
     --ORDER BY  EDAD_DESDE;

     RETURN vRegistro;

 END FN_ACTUALIZACION_ESQUEMA;

--F12
 FUNCTION FN_OBT_ESQUEMA_ATRASADO  (    pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                        pEdad IN NUMBER,
                                        pTipoEdad IN VARCHAR2,
                                        pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                        pFechaVacunacion  IN DATE
)RETURN var_refcursor AS
  vRegistro var_refcursor;
  vQuery VARCHAR2(4000);

   vEdad NUMBER;
   vFechaNacimiento DATE;

BEGIN

 DBMS_OUTPUT.PUT_LINE ('F12 FN_OBT_ESQUEMA_ATRASADO');

    --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);

     vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

     DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);


      OPEN vRegistro FOR 
        SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
            E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
         LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
         LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
    ----------------------------------------------------------------------------------------------
    WHERE A.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
    AND   E.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
    AND   E.ES_ADICIONAL=0 
    AND   E.ES_REFUERZO=0
    AND   C.ESQUEMA_AMBITO_ID = vAMBITO_VACUNA

    AND NOT EXISTS (
                    SELECT *
                    FROM  SIPAI_ESQUEMA_VIEW  M
                    WHERE M.EXPEDIENTE_ID = pCodigoExpediente 
                    AND   M.REL_TIPO_VACUNA_ID = A.REL_TIPO_VACUNA_ID 
                    AND   M.REL_TIPO_VACUNA_EDAD_ID = E.REL_TIPO_VACUNA_EDAD_ID
                   )
    AND vEdad >= REDAD.EDAD_DESDE
    --AND pEdad <= REDAD.EDAD_HASTA    
    AND vEdad < A.EDAD_MAX  
    --Ajuste para Dt-2024
     AND  CATTIPVAC.CODIGO !='SIPAI026'    
    ORDER BY REDAD.EDAD_DESDE; 

  RETURN vRegistro;

 END FN_OBT_ESQUEMA_ATRASADO;

--F10
 FUNCTION FN_DOSIS_REFUERZO  (        pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad IN NUMBER,
									   pTipoEdad IN VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                       pFechaVacunacion  IN DATE
									   )RETURN var_refcursor AS
  vRegistro var_refcursor;
  vQuery VARCHAR2(4000);

  vEdad NUMBER;
  vFechaNacimiento DATE;

BEGIN

   DBMS_OUTPUT.PUT_LINE ('F10 FN_DOSIS_REFUERZO');

    --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);

     vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

     DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);


  OPEN vRegistro FOR 
       SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
           LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
    ----------------------------------------------------------------------------
     WHERE
          NOT EXISTS (
                      select  *
                       from  SIPAI_ESQUEMA_VIEW  m
                       where m.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
                       and   m.REL_TIPO_VACUNA_EDAD_ID=E.REL_TIPO_VACUNA_EDAD_ID
                       and   m.dtv_estado_registro_id=vGLOBAL_ESTADO_ACTIVO
                       and  m.expediente_id=pCodigoExpediente --4819240
             )

            AND    A.ESTADO_REGISTRO_ID= vGLOBAL_ESTADO_ACTIVO
             AND   E.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
            AND  REDAD.EDAD_DESDE <= vEdad
            AND  vEdad <= REDAD.EDAD_HASTA
           AND  (TIPO_EDAD='M' )
           AND   ES_REFUERZO=1
		   AND    ESQUEMA_AMBITO_ID=vAMBITO_VACUNA
           ORDER BY REDAD.EDAD_DESDE;

  DBMS_OUTPUT.PUT_LINE ('FN_DOSIS_REFUERZO');

  RETURN vRegistro;

 END FN_DOSIS_REFUERZO;

--F11
 FUNCTION FN_DOSIS_ADICIONAL  (        pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad IN NUMBER,
									   pTipoEdad IN VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                       pFechaVacunacion  IN DATE
									   )RETURN var_refcursor AS
  vRegistro var_refcursor;
  vQuery VARCHAR2(4000);

   vEdad NUMBER;
   vFechaNacimiento  DATE;


BEGIN

    DBMS_OUTPUT.PUT_LINE ('F11 FN_DOSIS_ADICIONAL');

    --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);

     vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

     DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);



  OPEN vRegistro FOR 

    SELECT A.*
       FROM SIPAI_TIPO_VACUNA_VIEW A
       WHERE
          NOT EXISTS (
               select  *
                       from  SIPAI_ESQUEMA_VIEW  m
                       where m.REL_TIPO_VACUNA_ID=a.rel_id
                       and   m.REL_TIPO_VACUNA_EDAD_ID=a.REL_TIPO_VACUNA_EDAD_ID
                       and   m.dtv_estado_registro_id=vGLOBAL_ESTADO_ACTIVO
                       and  m.expediente_id=pCodigoExpediente --4819240
             )

           -- AND  EDAD_DESDE <= vEdad
           AND   vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
           AND  (TIPO_EDAD='M' )
           AND   ES_ADICIONAL=1
		   AND    ESQUEMA_AMBITO_ID=vAMBITO_VACUNA
        
           ORDER BY A.EDAD_DESDE;

DBMS_OUTPUT.PUT_LINE ('FN_DOSIS_ADICIONAL');

  RETURN vRegistro;

END FN_DOSIS_ADICIONAL;

--F9
 FUNCTION CONSULTAR_VITAMINAS_EDAD    (pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad IN NUMBER,
									   pTipoEdad IN VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                       pFechaVacunacion  IN DATE
									   )RETURN var_refcursor AS


  vRegistro var_refcursor;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');

  vEdad NUMBER;
  vFechaNacimiento DATE;

BEGIN

    DBMS_OUTPUT.PUT_LINE ('F9- CONSULTAR_VITAMINAS_EDAD ');
    --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);
     vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

     DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);

  OPEN vRegistro FOR
            SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           REDAD.VALOR_EDAD || ' - ' ||CATTIPVAC.VALOR                   CATTIPVAC_VALOR,          
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            CATDET.CODIGO                                 CODIGO_NUM_DOSIS,  
            CATDET.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
             ---------------------------------------------------------------------------------------------
            LEFT JOIN SIPAI_DET_VALOR   catDet  ON E.CODIGO_NUM_DOSIS=catDet.CODIGO AND  catDet.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
            ------------WHERE -------------------------------
			WHERE  vEdad  BETWEEN EDAD_DESDE AND EDAD_HASTA
			AND  TIPO_EDAD= 'M'
			AND   C.ESQUEMA_AMBITO_ID 
            IN  ( vAMBITO_VITAMINA ,vAMBITO_DESPARCITANTE)
            AND A.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
			AND E.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO;

     RETURN vRegistro;

	DBMS_OUTPUT.PUT_LINE ('CONSULTAR_VITAMINAS_EDAD');
END CONSULTAR_VITAMINAS_EDAD;

--F6
 FUNCTION CONSULTAR_VACUNAS_EDAD    (  pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad IN NUMBER,
									   pTipoEdad IN VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                                       pFechaVacunacion  IN DATE
                                       )RETURN var_refcursor AS

  vRegistro var_refcursor;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');

    --Transformar los meses edad a dias desde la fecha de nacimiento
  vFechaNacimiento DATE;
  vEdad       NUMBER;
  vFiltroDt   NUMBER:=0;
  vAnioVacunacion NUMBER:=EXTRACT(YEAR FROM pFechaVacunacion);

  vRelEdadId  NUMBER;
  vExisteNumeroDosisAnteriorExpediente NUMBER;
  
  vExistePrimeraDosisCOVID NUMBER:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE_ANUAL(
                                   pCodigoExpediente,'SIPAIVAC041','CODINTVAL-9',vAnioVacunacion ); 
  vExisteSegundaDosisCOVID NUMBER:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE_ANUAL(
                                   pCodigoExpediente,'SIPAIVAC041','CODINTVAL-10',vAnioVacunacion ); 
  

  vFiltroListaVacunaAnual varchar2(4000):=FN_LISTA_REL_EDAD_FRECUECUENCIA_ANUAL(pCodigoExpediente,pFechaVacunacion);

BEGIN
  DBMS_OUTPUT.PUT_LINE ('F6- CONSULTAR_VACUNAS_EDAD');
 -- DBMS_OUTPUT.PUT_LINE ('vAnioVacunacion' ||vAnioVacunacion);
  --DBMS_OUTPUT.PUT_LINE ('vExistePrimeraDosisCOVID' ||vExistePrimeraDosisCOVID);
 -- DBMS_OUTPUT.PUT_LINE ('vExisteSegundaDosisCOVID' ||vExisteSegundaDosisCOVID); 
   --VALIDAR SI EL EXPEDIENTE TIENE 1 DOSIS VPH APLICADA.
   vExisteNumeroDosisAnteriorExpediente:=FN_VALIDAR_NUMERO_DOSIS_EXPEDIENTE(pCodigoExpediente,'SIPAI012023','CODINTVAL-9' );

  --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);
     DBMS_OUTPUT.PUT_LINE ('vAMBITO_VACUNA= '||vAMBITO_VACUNA);

      vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));
      --obtener el valor del filtro de la dt
      vFiltroDt:=FN_OBTNER_FILTRO_DT(vEdad,pCodigoExpediente,pFechaVacunacion);

      DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);
      DBMS_OUTPUT.PUT_LINE ('vFiltroDt= '||vFiltroDt);

  OPEN vRegistro FOR   
        SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
            LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
            ------------WHERE -------------------------------
           -- WHERE  vEdad >= REDAD.EDAD_DESDE AND vEdad <=  ((REDAD.EDAD_HASTA + 0.99)+0.25)      
            --WHERE  pEdad >= REDAD.EDAD_DESDE AND pEdad <=  (REDAD.EDAD_HASTA + 0.25)
			WHERE  vEdad BETWEEN REDAD.EDAD_DESDE AND REDAD.EDAD_HASTA
             AND  TIPO_EDAD='M' --pTipoEdad
             AND   C.ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
             AND   E.ES_ADICIONAL=0 
             AND   E.ES_REFUERZO=0
             AND   A.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
             AND    E.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
             AND ((E.REL_TIPO_VACUNA_EDAD_ID NOT IN 
                                              ( 
                                                 SELECT E.REL_TIPO_VACUNA_EDAD_ID 
                                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                                 ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                                 ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                                 AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                                                 ------------------------------------------------------------
                                                 WHERE M.EXPEDIENTE_ID=pCodigoExpediente
                                                 AND  M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                                 --Agregar por que sera borrado logico
                                                 AND  D.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                   )                             )
             -- or A.rel_tipo_vacuna_id = 61  influenza de adulto
             OR A.REL_TIPO_VACUNA_ID IN (
                                          SELECT REL_TIPO_VACUNA_ID 
                                          FROM SIPAI_REL_TIP_VACUNACION_DOSIS 
                                          ---------------------------------------------
                                          WHERE TIPO_VACUNA_ID =( 
                                                                  SELECT CATALOGO_ID 
                                                                  FROM  CATALOGOS.SBC_CAT_CATALOGOS 
                                                                  WHERE CODIGO = 'SIPAI0037' 
                                                                  AND PASIVO=0
                                                                  )
                                           AND  ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                           AND  ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                         ))

            --Ajuste para Dt VPH y COVID
              AND  CATTIPVAC.CODIGO !='SIPAI026' 
              AND   CATTIPVAC.CODIGO !='SIPAI012023'  --Exclir VPH
              AND  CATTIPVAC.CODIGO !='SIPAIVAC041'  --Exclir COVID 
            --EXCLUIR DOSIS ANUALES 
              AND   E.FRECUENCIA_ANUAL=0
        
          --Filtro Vacunas Covid segun dosis aplicadas en el expediente
          UNION 
          SELECT *
          FROM SIPAI_TIPO_VACUNA_VIEW
          WHERE CATTIPVAC_CODIGO = 'SIPAIVAC041'
          AND 
          (   -- Mostrar 1ra Dosis COVID
            (CODIGO_NUM_DOSIS = 'CODINTVAL-9' AND vExistePrimeraDosisCOVID = 0) 
          OR  -- Mostrar 2da Dosis COVID
            (CODIGO_NUM_DOSIS = 'CODINTVAL-10' AND vExistePrimeraDosisCOVID = 1 
                                               AND vExisteSegundaDosisCOVID = 0 )
          )
          AND  vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
          
           --vFiltro Vacunas Anuales
             UNION
             SELECT * 
             FROM SIPAI_TIPO_VACUNA_VIEW
             WHERE  ES_ADICIONAL=0 
             AND   ES_REFUERZO=0
             AND  vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA AND  TIPO_EDAD='M'
             AND REL_TIPO_VACUNA_EDAD_ID IN (select jt.ID  from dual,  json_table(vFiltroListaVacunaAnual, '$[*]' 
                                                COLUMNS (ID NUMBER PATH '$'))jT)
            ---- EXCLUIR COVID PARA QUE NO SE DUPLIQUE
            --SE ESTA  manejando su lógica de 1ra y 2da dosis de forma manual en el BLOQUE ANTERRIOR
            AND CATTIPVAC_CODIGO != 'SIPAIVAC041'
            
              ----vFiltroDt
           UNION
             SELECT * 
             FROM SIPAI_TIPO_VACUNA_VIEW
             WHERE  CATTIPVAC_CODIGO='SIPAI026'
             AND (  vFiltroDt  = 1  AND EDAD_ID=7786 OR
                    vFiltroDt  = 2  AND EDAD_ID=7787 OR 
                  ----2do Esquema-------------------------------
                   vFiltroDt  = 3  AND EDAD_ID=7917  OR
                   vFiltroDt  = 4  AND EDAD_ID=7918  OR
                   vFiltroDt  = 5  AND EDAD_ID=7919 OR
                   vFiltroDt  = 6  AND EDAD_ID=7920 OR   
                   vFiltroDt  = 7  AND EDAD_ID=7921
                )  

            --  vFiltro VPH
            UNION        
             SELECT * 
             FROM   SIPAI_TIPO_VACUNA_VIEW
             WHERE  CATTIPVAC_CODIGO='SIPAI012023'
             AND    REL_TIPO_VACUNA_EDAD_ID NOT  IN (
                                                 SELECT E.REL_TIPO_VACUNA_EDAD_ID 
                                                 FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                                 JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                                 ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                                 ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                                 JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                                 ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                                 AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                                                 ------------------------------------------------------------
                                                 WHERE M.EXPEDIENTE_ID=pCodigoExpediente
                                                 AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                                                 --Agregar filtro estado activo por el cambio a borrado logico
                                                 AND   D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
                                          )

             AND    vEdad BETWEEN EDAD_DESDE AND EDAD_HASTA
             AND (  vExisteNumeroDosisAnteriorExpediente  = 0  AND CODIGO_NUM_DOSIS='CODINTVAL-9' OR
                    vExisteNumeroDosisAnteriorExpediente  = 1  AND  CODIGO_NUM_DOSIS='CODINTVAL-10'
                    AND EDAD_ENTRE_DOSIS <= (SELECT 
                                           MAX(TRUNC(MONTHS_BETWEEN(pFechaVacunacion, D.FECHA_VACUNACION))) 
                                           FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA M
                                           JOIN   SIPAI.SIPAI_DET_VACUNACION     D
                                          ON     D.CONTROL_VACUNA_ID =M.CONTROL_VACUNA_ID
                                          JOIN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS REL
                                          ON     M.TIPO_VACUNA_ID = REL.REL_TIPO_VACUNA_ID
                                          JOIN   CATALOGOS.SBC_CAT_CATALOGOS CATVAC ON CATVAC.CATALOGO_ID=REL.TIPO_VACUNA_ID
                                          JOIN   SIPAI.SIPAI_REL_TIPO_VACUNA_EDAD e
                                          ON     REL.REL_TIPO_VACUNA_ID = E.REL_TIPO_VACUNA_ID
                                          AND    E.REL_TIPO_VACUNA_EDAD_ID=D.REL_TIPO_VACUNA_EDAD_ID
                             ------------------------------------------------------------
                             WHERE M.EXPEDIENTE_ID=pCodigoExpediente
                             AND   M.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                             --Agregar filtro estado activo por el cambio a borrado logico
                             AND   D.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO 
                             AND   CATVAC.CODIGO='SIPAI012023'
                             AND   E.CODIGO_NUM_DOSIS='CODINTVAL-9'
                             )
                )
         

                ;            
     --ORDER BY  EDAD_DESDE;

     RETURN vRegistro;


END CONSULTAR_VACUNAS_EDAD;

--F13 Obetener vacuna dT para casos de embarazo
 FUNCTION CONSULTAR_dT    (  pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                             pEdad IN NUMBER,
                             pTipoEdad IN VARCHAR2,
                             pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
                             pFechaVacunacion  IN DATE
                           )RETURN var_refcursor AS

  vRegistro var_refcursor;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');
  vReltipoVacunaEdad        NUMBER;
  vContador                 NUMBER;

  vFechaNacimiento          DATE;
  vEdad                      NUMBER; 
  -- 120   240  ---

 BEGIN

  DBMS_OUTPUT.PUT_LINE ('F13- CONSULTAR_dT');

    --Transformar los meses edad a dias desde la fecha de nacimiento
     SELECT FECHA_NACIMIENTO  
     INTO   vFechaNacimiento
     FROM   CATALOGOS.SBC_MST_PERSONAS_NOMINAL 
     WHERE  expediente_id=pCodigoExpediente;

     -- vEdadMesesDia:= months_between(SYSDATE,vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('vFechaNacimiento= '||vFechaNacimiento);
     DBMS_OUTPUT.PUT_LINE ('pFechaVacunacion= '||pFechaVacunacion);

     vEdad:= TRUNC(months_between(pFechaVacunacion,vFechaNacimiento));

     DBMS_OUTPUT.PUT_LINE ('vEdad= '||vEdad);


      SELECT COUNT(*) 
      into vContador
      FROM   SIPAI.SIPAI_MST_CONTROL_VACUNA mst
      JOIN   sipai_rel_tip_vacunacion_dosis rel on  mst.tipo_vacuna_id = rel.rel_tipo_vacuna_id
      WHERE  mst.EXPEDIENTE_ID=pCodigoExpediente
      and    mst.estado_registro_id=vGLOBAL_ESTADO_ACTIVO
      and    rel.estado_registro_id=vGLOBAL_ESTADO_ACTIVO
      AND    rel.tipo_vacuna_id=vTipoVacunadT;
     

      IF vContador= 0 THEN 

        SELECT REL_TIPO_VACUNA_EDAD_ID --, VALOR_EDAD,TIPO_VACUNA_ID
        INTO  vReltipoVacunaEdad
        FROM  SIPAI_REL_TIPO_VACUNA_EDAD A  JOIN SIPAI_REL_TIP_VACUNACION_DOSIS B 	ON B.REL_TIPO_VACUNA_ID = A.REL_TIPO_VACUNA_ID
        JOIN SIPAI_prm_RANGO_EDAD CTEDAD ON CTEDAD.EDAD_ID = A.EDAD_ID 
        WHERE  B.TIPO_VACUNA_ID=vTipoVacunadT
        AND   A.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO   
        --AND   CTEDAD.VALOR_EDAD ='10 años';
        AND CTEDAD.CODIGO_EDAD='COD_INT_EDAD_7786';

     ELSE 

        SELECT REL_TIPO_VACUNA_EDAD_ID --, VALOR_EDAD,TIPO_VACUNA_ID
        INTO  vReltipoVacunaEdad
        FROM  SIPAI_REL_TIPO_VACUNA_EDAD A  
        JOIN SIPAI_REL_TIP_VACUNACION_DOSIS B 	ON B.REL_TIPO_VACUNA_ID = A.REL_TIPO_VACUNA_ID
        JOIN SIPAI_prm_RANGO_EDAD CTEDAD ON CTEDAD.EDAD_ID = A.EDAD_ID 
        WHERE  B.TIPO_VACUNA_ID=vTipoVacunadT
        AND   A.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO   
        AND CTEDAD.CODIGO_EDAD ='COD_INT_EDAD_7787';  --'20 años'

      END IF;

  OPEN vRegistro FOR   
		     SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
           FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
         LEFT   JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
			 ------------WHERE -------------------------------
             WHERE  A.TIPO_VACUNA_ID  =vTipoVacunadT
             AND    E.REL_TIPO_VACUNA_EDAD_ID=vReltipoVacunaEdad
              AND   A.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO
               AND   E.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO;

            DBMS_OUTPUT.PUT_LINE ('CONSULTAR_dT');

     RETURN vRegistro;


END CONSULTAR_dT;

--F7  por programa FILTRO 7 
 FUNCTION FN_OBT_VACUNA_PROGRAMA (pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE 
								  ) RETURN var_refcursor AS 
  vRegistro var_refcursor;

  BEGIN
    OPEN vRegistro FOR
          SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
			 FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
           LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
          LEFT  JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
            ------------WHERE -------------------------------
				WHERE C.PROGRAMA_VACUNA_ID =pProgramaId
			    AND   C.ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
			   AND    A.ESTADO_REGISTRO_ID=vGLOBAL_ESTADO_ACTIVO
                AND   E.ESTADO_REGISTRO_ID = vGLOBAL_ESTADO_ACTIVO

             ORDER BY C.ORDEN,REDAD.ORDEN ASC
			   ;          
  RETURN vRegistro;  

 END FN_OBT_VACUNA_PROGRAMA;

 FUNCTION FN_VALIDA_REL_TIPO_DOSIS (  pRelTipoVacunaId IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                     pTipVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                     pFabVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,
                                     pCantDosis       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,        
                                     pEdad IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									 pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE ,
									 pTipoFiltro IN  NUMBER,
									pTipoPaginacion  OUT NUMBER) RETURN BOOLEAN AS
  vConteo SIMPLE_INTEGER := 0;
  vExiste BOOLEAN := FALSE;

  BEGIN 
       CASE
       WHEN NVL(pCantDosis,0) > 0 THEN
            BEGIN

			SELECT COUNT (1)
              INTO vConteo
              from dual;

            /*SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE CANTIDAD_DOSIS = pCantDosis AND
                   REL_TIPO_VACUNA_ID > 0;*/
            END;
            pTipoPaginacion := 1;
       WHEN NVL(pFabVacuna,0) > 0 THEN   
            BEGIN
			SELECT COUNT (1)
              INTO vConteo
              from dual;

          /*  SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE FABRICANTE_VACUNA_ID = pFabVacuna AND
                   REL_TIPO_VACUNA_ID > 0;*/
            END;
            pTipoPaginacion := 2;
       WHEN NVL(pTipVacuna,0) > 0 THEN   
            BEGIN
			SELECT COUNT (1)
              INTO vConteo
              from dual;

            /*SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE TIPO_VACUNA_ID = pTipVacuna AND
                   REL_TIPO_VACUNA_ID > 0;*/
            END;  
            pTipoPaginacion := 3;  
       WHEN NVL(pRelTipoVacunaId, 0 ) > 0 THEN
            BEGIN

			SELECT COUNT (1)
              INTO vConteo
              from dual;

           /* SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE REL_TIPO_VACUNA_ID = pRelTipoVacunaId AND
                   REL_TIPO_VACUNA_ID > 0;
			 pTipoPaginacion := 4;	*/   
            END;  

		---Vacunas x Edad---------	
		WHEN NVL(pEdad, 0 ) > 0 THEN

		  BEGIN
            SELECT COUNT (1)
              INTO vConteo
              from dual;
              --FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             --WHERE REL_TIPO_VACUNA_ID = pRelTipoVacunaId AND
               --    REL_TIPO_VACUNA_ID > 0;
            END;  
            pTipoPaginacion := 6;	

		---Esquema Atrasado---------	
		WHEN NVL(pTipoFiltro, 0 ) > 0 THEN

		  BEGIN

            SELECT COUNT (1)
              INTO vConteo
              from dual;
              --FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             --WHERE REL_TIPO_VACUNA_ID = pRelTipoVacunaId AND
               --    REL_TIPO_VACUNA_ID > 0;
            END;  
            pTipoPaginacion := 8;		


	   ---Vacunas x Programa---------	
		WHEN NVL(pProgramaId, 0 ) > 0 THEN
		  BEGIN
            SELECT COUNT (1)
              INTO vConteo
              from dual;

            END;  
            pTipoPaginacion := 7;	

       ELSE 
            BEGIN

			SELECT COUNT (1)
              INTO vConteo
              from dual;

			/*
            SELECT COUNT (1)
              INTO vConteo
              FROM SIPAI_REL_TIP_VACUNACION_DOSIS
             WHERE REL_TIPO_VACUNA_ID > 0;*/
            END;  
            pTipoPaginacion := 5;       
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
  END FN_VALIDA_REL_TIPO_DOSIS;

--F15
FUNCTION FN_OBT_RELVAC_DOSIS_X_CANT (pCantDosis IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE

									   ) RETURN var_refcursor AS 
  vRegistro var_refcursor;

  BEGIN
    OPEN vRegistro FOR
          SELECT *
          -----------FROM---------------------------------
          FROM  SIPAI_TIPO_VACUNA_VIEW 
          ------------WHERE -------------------------------
          WHERE REL_ID > 0 
          AND   ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
          AND	REL_CANT_DOSIS = pCantDosis;

   DBMS_OUTPUT.PUT_LINE ('FN_OBT_RELVAC_DOSIS_X_CANT');

  RETURN vRegistro;  

 END FN_OBT_RELVAC_DOSIS_X_CANT;

--F16
FUNCTION FN_OBT_RELVAC_DOSIS_X_FABVAC (pFabVacuna IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE
                                        ) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
    OPEN vRegistro FOR
	    SELECT *
          -----------FROM---------------------------------
          FROM  SIPAI_TIPO_VACUNA_VIEW 
          ------------WHERE -------------------------------
          WHERE REL_ID > 0 
          AND   ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
          AND   CATREL_FABRICANTE_VAC_ID = pFabVacuna;
            
DBMS_OUTPUT.PUT_LINE ('FN_OBT_RELVAC_DOSIS_X_FABVAC');

    RETURN vRegistro;
  END FN_OBT_RELVAC_DOSIS_X_FABVAC;

--F17
FUNCTION FN_OBT_RELVAC_DOSIS_X_TIPVAC (pTipVacuna IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE

										) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
    OPEN vRegistro FOR
          SELECT *
          -----------FROM---------------------------------
          FROM  SIPAI_TIPO_VACUNA_VIEW 
          ------------WHERE -------------------------------
          WHERE REL_ID > 0 
          AND   ESQUEMA_AMBITO_ID =vAMBITO_VACUNA
          AND  CATREL_TIPO_VACUNA_ID = pTipVacuna;
      DBMS_OUTPUT.PUT_LINE ('FN_OBT_RELVAC_DOSIS_X_TIPVAC');  
     RETURN vRegistro;
 END FN_OBT_RELVAC_DOSIS_X_TIPVAC;

--F5    TODOS
FUNCTION FN_OBT_RELVAC_DOSIS_TODOS RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
    OPEN vRegistro FOR
          SELECT *
          -----------FROM---------------------------------
          FROM  SIPAI_TIPO_VACUNA_VIEW 
          ------------WHERE -------------------------------
           WHERE REL_ID > 0;
          
    DBMS_OUTPUT.PUT_LINE ('FN_OBT_RELVAC_DOSIS_TODOS');
    RETURN vRegistro;

  END FN_OBT_RELVAC_DOSIS_TODOS;  

--F14
 FUNCTION FN_OBT_RELVAC_DOSIS_X_ID (pRelTipoVacunaId IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                      pFabVacuna IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE

									  )
									  RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
    OPEN vRegistro FOR
           SELECT 
	       A.REL_TIPO_VACUNA_ID              REL_ID,
           A.TIPO_VACUNA_ID                  CATREL_TIPO_VACUNA_ID,                 -- catalogo de tipo vacuna
           A.EDAD_MAX EDAD_MAX,
           TO_CHAR(A.EDAD_MAX / 12)|| ' ' || 'AÑOS ' || '(' || A.EDAD_MAX ||' MESES)' EDAD_MAXN,
           CATTIPVAC.CODIGO                  CATTIPVAC_CODIGO,
           ND.VALOR_SECUNDARIO     || ' - ' ||CATTIPVAC.VALOR  CATTIPVAC_VALOR,                      
           CATTIPVAC.DESCRIPCION             CATTIPVAC_DESCRIPCION,    
           CATTIPVAC.PASIVO                  CATTIPVAC_PASIVO,        
           A.FABRICANTE_VACUNA_ID            CATREL_FABRICANTE_VAC_ID,              -- catalogo de fabricante vacuna
           CATFABVAC.CODIGO                  RELTIP_CATFABVAC_CODIGO,
           CATFABVAC.VALOR                   RELTIP_CATFABVAC_VALOR,         
           CATFABVAC.DESCRIPCION             RELTIP_CATFABVAC_DESCRIPCION,   
           CATFABVAC.PASIVO                  RELTIP_CATFABVAC_PASIVO, 
           A.ESTADO_REGISTRO_ID              REL_ESTADO_REGISTRO_ID,                -- catalogo de estado registro
           CATCTRLESTREG.CODIGO              CATRELESTADO_CODIGO,
           CATCTRLESTREG.VALOR               CATRELESTADO_VALOR,              
           CATCTRLESTREG.DESCRIPCION         CATRELESTADO_DESCRIPCION,    
           CATCTRLESTREG.PASIVO              CATRELESTADO_PASIVO, 
           A.SISTEMA_ID                      REL_SISTEM_ID,                         -- sistema 
           CTRLSIST.NOMBRE                   RELSIST_NOMBRE, 
           CTRLSIST.DESCRIPCION              RELSIST_DESCRIPCION, 
           CTRLSIST.CODIGO                   RELSIST_CODIGO,     
           CTRLSIST.PASIVO                   RELSIST_PASIVO, 
           A.UNIDAD_SALUD_ID                 REL_UNIDAD_SALUD_ID,                   -- unidad de salud
           RELUSALUD.NOMBRE                  RELUSALUD_US_NOMBRE,    
           RELUSALUD.CODIGO                  RELUSALUD_US_CODIGO,    
           RELUSALUD.RAZON_SOCIAL            RELUSALUD_US_RSOCIAL, 
           RELUSALUD.DIRECCION               RELUSALUD_US_DIREC,   
           RELUSALUD.EMAIL                   RELUSALUD_US_EMAIL,   
           RELUSALUD.ABREVIATURA             RELUSALUD_US_ABREV,   
           RELUSALUD.ENTIDAD_ADTVA_ID        RELUSALUD_US_ENTADMIN,
           RELUSALUD.PASIVO                  RELUSALUD_US_PASIVO,   
           A.CANTIDAD_DOSIS                  REL_CANT_DOSIS,
           A.USUARIO_REGISTRO                REL_USR_REGISTRO,
           A.FECHA_REGISTRO                  REL_FEC_REGISTRO,
           A.USUARIO_MODIFICACION            REL_USR_MODIFICACION,
           A.FECHA_MODIFICACION              REL_FEC_MODIFICACION,
           A.USUARIO_PASIVA                  REL_USR_PASIVA,
           A.FECHA_PASIVO                    REL_FEC_PASIVA,
		     --   NUEVO CAMPOS
		   C.CONFIGURACION_VACUNA_ID,
           C.REGION_ID                       REL_REGION_ID,
           CATREGION.VALOR                   REL_NOMBRE_REGION,
           C.VIA_ADMINISTRACION_ID           REL_VIA_ADMINISTRACION_ID,
           CATVADM.VALOR                     REL_NOMBRE_VIA_ADMINISTRACION,
           A.TIENE_REFUERZOS                 TIENE_REFUERZOS ,
           A.CANTIDAD_DOSIS_REFUERZO		  CANTIDAD_DOSIS_REFUERZO, 
           C.PROGRAMA_VACUNA_ID		          PROGRAMA_VACUNA_ID,
           PROGVAC.VALOR                      NOMBRE_PROGRAMA_VAC,
           ---VACUNA X EDAD
            E.REL_TIPO_VACUNA_EDAD_ID,
            E.EDAD_ID                      EDAD_ID,
			REDAD.VALOR_EDAD                   VALOR_EDAD,
			E.ES_SIMULTANEA                ES_SIMULTANEA,
             E.ES_REFUERZO                  ES_REFUERZO,
            E.ES_ADICIONAL                 ES_ADICIONAL, 
            REDAD.EDAD_DESDE              EDAD_DESDE,
            REDAD.EDAD_HASTA              EDAD_HASTA,
            REDAD.TIPO_EDAD               TIPO_EDAD,
            REDAD.CODIGO_EDAD,
			A.TIENE_ADICIONAL,
			A.CANTIDAD_DOSIS_ADICIONAL,
            C.ESQUEMA_AMBITO_ID,
            AMB.VALOR             NOMBRE_AMBITO  ,
            ND.CODIGO                                 CODIGO_NUM_DOSIS,       
            ND.VALOR                                  NOMBRE_NUM_DOSIS,
            E.ES_REQUERIDO_DOSIS_ANTERIOR,
            E.EDAD_MAX_DOSIS,
            E.EDAD_ENTRE_DOSIS,
            A.FECHA_INICIO,
            A.FECHA_FIN,
            A.TIENE_GRUPO_PRIORIDAD,
            A.TIENE_FRECUENCIA_ANUALES,
            A.GRUPO_PRIODIDADES,
            A.SEXO_APLICABLE 
		    -----------FROM---------------------------------
            FROM  SIPAI_REL_TIP_VACUNACION_DOSIS A
            JOIN  SIPAI_CONFIGURACION_VACUNA C 
             ON   C.CONFIGURACION_VACUNA_ID=A.CONFIGURACION_VACUNA_ID  
            LEFT JOIN  SIPAI_REL_TIPO_VACUNA_EDAD E
              ON   E.REL_TIPO_VACUNA_ID=A.REL_TIPO_VACUNA_ID
            LEFT JOIN  SIPAI_PRM_RANGO_EDAD REDAD               
               ON  E.EDAD_ID=REDAD.EDAD_ID
            ---------------------------------------------------------------------------------------------
            LEFT JOIN SIPAI.SIPAI_DET_VALOR ND ON E.CODIGO_NUM_DOSIS=ND.CODIGO  AND ND.PASIVO=0
            ---------------------------------------------------------------------------------------------
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATTIPVAC
              ON CATTIPVAC.CATALOGO_ID = A.TIPO_VACUNA_ID 
               --NUEVOS JOINS NUEVOS CAMPOS
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATREGION
              ON CATREGION.CATALOGO_ID = C.REGION_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATVADM
              ON CATVADM.CATALOGO_ID = C.VIA_ADMINISTRACION_ID  
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS PROGVAC
              ON PROGVAC.CATALOGO_ID = C.PROGRAMA_VACUNA_ID    
             ------- AMBITO -------
             LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS AMB
              ON AMB.CATALOGO_ID = C.ESQUEMA_AMBITO_ID    
             ---------------
            LEFT JOIN CATALOGOS.SBC_CAT_CATALOGOS CATFABVAC
              ON CATFABVAC.CATALOGO_ID = A.FABRICANTE_VACUNA_ID 
            JOIN CATALOGOS.SBC_CAT_CATALOGOS CATCTRLESTREG
              ON CATCTRLESTREG.CATALOGO_ID = A.ESTADO_REGISTRO_ID   
            JOIN SEGURIDAD.SCS_CAT_SISTEMAS CTRLSIST
              ON CTRLSIST.SISTEMA_ID = A.SISTEMA_ID 
            LEFT JOIN CATALOGOS.SBC_CAT_UNIDADES_SALUD RELUSALUD
              ON RELUSALUD.UNIDAD_SALUD_ID = A.UNIDAD_SALUD_ID
             
          ------------WHERE -------------------------------
          WHERE A.REL_TIPO_VACUNA_ID    = pRelTipoVacunaId;

     DBMS_OUTPUT.PUT_LINE ('FN_OBT_RELVAC_DOSIS_X_ID');
     RETURN vRegistro;
  END FN_OBT_RELVAC_DOSIS_X_ID;


FUNCTION FN_OBT_DATOS_REL_TIPO_DOSIS (pRelTipoVacunaId IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                        pTipVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                        pFabVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,
                                        pCantDosis       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,
										 -----Vacunas x Edad---------
									   pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad IN NUMBER,
									   pTipoEdad IN VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
									   pTipoFiltro NUMBER,	
                                       ---------Agregar Fecha Vacunacion para calcular la edad
                                       pFechaVacunacion DATE,
									   ----------------------
                                        vTipoPaginacion  IN NUMBER, 
                                        pPgnAct          IN NUMBER,
                                        pPgnTmn          IN NUMBER) RETURN var_refcursor AS
  vRegistro var_refcursor;
  BEGIN
        DBMS_OUTPUT.put_line (pTipoFiltro);
       CASE
       WHEN NVL(pRelTipoVacunaId, 0 ) > 0 THEN
          vRegistro := FN_OBT_RELVAC_DOSIS_X_ID (pRelTipoVacunaId,pFabVacuna);        
       WHEN NVL(pFabVacuna,0) > 0 THEN 
            vRegistro := FN_OBT_RELVAC_DOSIS_X_FABVAC (pFabVacuna);   
       WHEN NVL(pTipVacuna,0) > 0 THEN   
            vRegistro := FN_OBT_RELVAC_DOSIS_X_TIPVAC (pTipVacuna);       
       WHEN NVL(pCantDosis,0) > 0 THEN
            vRegistro := FN_OBT_RELVAC_DOSIS_X_CANT (pCantDosis); 
       --WHEN NVL(pTipoFiltro,0) > 0 AND NVL(pEdad,0) > 0 THEN  

	     /*WHEN pTipoFiltro= 9 THEN  
            vRegistro := FN_OBT_ESQUEMA_ATRASADO (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId);*/					
		--WHEN pEdad IS NOT NULL THEN 

        WHEN pTipoFiltro=1 THEN  
             vRegistro := FN_OBTENER_VACUNAS_GEO ();

		WHEN pTipoFiltro=9 THEN  
            vRegistro := CONSULTAR_VITAMINAS_EDAD (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);	

        WHEN pTipoFiltro=10 THEN  
            vRegistro := FN_DOSIS_REFUERZO (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);	

        WHEN pTipoFiltro=11 THEN  
            vRegistro := FN_DOSIS_ADICIONAL (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);

        WHEN pTipoFiltro= 12 THEN  -- ESQUEMA ATRASADO
            vRegistro := FN_OBT_ESQUEMA_ATRASADO(pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);	

         WHEN pTipoFiltro= 13 THEN  -- RETORNAR VACUNA DT
             vRegistro := CONSULTAR_dT (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);

        WHEN pTipoFiltro= 8 THEN  -- ACTUALIZACION
            vRegistro := FN_ACTUALIZACION_ESQUEMA (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);

	WHEN pTipoFiltro=6   THEN  
            vRegistro := CONSULTAR_VACUNAS_EDAD (pCodigoExpediente,pEdad,pTipoEdad,pProgramaId,pFechaVacunacion);
       WHEN NVL(pProgramaId,0) > 0 THEN   
            vRegistro := FN_OBT_VACUNA_PROGRAMA (pProgramaId);	
       ELSE   
            DBMS_OUTPUT.put_line ('pTipoFiltro' ||  pTipoFiltro) ;
           vRegistro := FN_OBT_RELVAC_DOSIS_TODOS;
       END CASE;  
    RETURN vRegistro;
  END FN_OBT_DATOS_REL_TIPO_DOSIS;


PROCEDURE PR_I_REL_TIP_VACUNA (  pRelTipoVacunaId         OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                 pTipVacuna               IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                 pFabVacuna               IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,
                                 pCantDosis               IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,
	                             --Esquema
								 pTieneRefuerzo           IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_REFUERZOS%TYPE,  
								 pCantDosisRefuerzo 	  IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_REFUERZO%TYPE,            
								 pConfiguracionVacunaId   IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,  
                                 pTieneAdicional          IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_ADICIONAL%TYPE,
								 pCantDosisAdicional	  IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_ADICIONAL%TYPE,								 
                                 --Periodos Vacuna-------
                                 pFechaInicio             IN VARCHAR2,       
                                 pFechaFin                IN VARCHAR2,
                                 --Grupo Prioridad y edad maxima
                                 pEdadMaxima              IN NUMBER,
                                 pTieneGrupoPrioridad     IN NUMBER,
                                 pTieneFrecuenciaAnuales  IN  NUMBER,
                                 pGrupoPrioridades        IN VARCHAR2,
                                 pSexoAplicable           IN NUMBER,
                                --Auditoria--------------
								 pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                 pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                 pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                 pResultado       OUT VARCHAR2,
                                 pMsgError        OUT VARCHAR2) IS
  vFirma VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_I_REL_TIP_VACUNA => ';  
  vContadorTipoVacunaId NUMBER;
  vNombreVacuna  VARCHAR2(100);

  BEGIN

      SELECT COUNT(*) 
      INTO   vContadorTipoVacunaId
      FROM   SIPAI_REL_TIP_VACUNACION_DOSIS
      WHERE  TIPO_VACUNA_ID=pTipVacuna
      AND    ESTADO_REGISTRO_ID=6869;

      IF  vContadorTipoVacunaId >0 THEN 
          SELECT VALOR 
          INTO   vNombreVacuna
          FROM   CATALOGOS.SBC_CAT_CATALOGOS
          WHERE  CATALOGO_ID=pTipVacuna; 

          pResultado := 'el tipo vacuna (|' || vNombreVacuna || ') ya existe';
          RAISE eRegistroExiste;  
      END IF;

     INSERT INTO SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS (TIPO_VACUNA_ID, 
                                                     FABRICANTE_VACUNA_ID, 
                                                     CANTIDAD_DOSIS,                                                   
													 TIENE_REFUERZOS,
													 CANTIDAD_DOSIS_REFUERZO,
													 CONFIGURACION_VACUNA_ID,
													 TIENE_ADICIONAL,
													 CANTIDAD_DOSIS_ADICIONAL,
                                                     --Periodo--
                                                     FECHA_INICIO,
                                                     FECHA_FIN,
                                                     --Grupo prioridad y edad  max
                                                     EDAD_MAX,
                                                     TIENE_GRUPO_PRIORIDAD,
                                                     TIENE_FRECUENCIA_ANUALES,
                                                     GRUPO_PRIODIDADES,
                                                     SEXO_APLICABLE, 
													  --Auditoria						
                                                     ESTADO_REGISTRO_ID,
                                                     SISTEMA_ID,
                                                     UNIDAD_SALUD_ID,
                                                     USUARIO_REGISTRO)
								 VALUES(pTipVacuna,
										pFabVacuna,
										pCantDosis,
										pTieneRefuerzo,
										pCantDosisRefuerzo,             
										pConfiguracionVacunaId,  
										pTieneAdicional,
										pCantDosisAdicional,
                                        --PERIODO
                                        to_date(pFechaInicio,'DD/MM/YYYY'),
                                        to_date(pFechaFin,'DD/MM/YYYY'),
                                         --Grupo prioridad y edad  max
                                        pEdadMaxima,                 
                                        pTieneGrupoPrioridad,
                                        pTieneFrecuenciaAnuales,
                                        pGrupoPrioridades,
                                        pSexoAplicable,
										---Auditoria
										vGLOBAL_ESTADO_ACTIVO,
										pSistemaId,
										pUniSaludId,
										pUsuario)
      RETURNING REL_TIPO_VACUNA_ID INTO pRelTipoVacunaId;

  EXCEPTION

  WHEN eRegistroExiste THEN
      pResultado := pResultado;
      pMsgError  := vFirma ||'Error al Eliminar Registro de Vacunas: ' || pResultado;

  WHEN OTHERS THEN
       pResultado := 'Error al insertar tipo de vacuna';   
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;
   END PR_I_REL_TIP_VACUNA; 

PROCEDURE PR_U_REL_TIP_VACUNA ( pRelTipoVacunaId        IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                pTipVacuna              IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                pFabVacuna              IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,  
                                pCantDosis              IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,                            
	                            --Esquema
                                pTieneRefuerzo          IN    SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_REFUERZOS%TYPE,  
								pCantDosisRefuerzo 	    IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_REFUERZO%TYPE,            
							    pConfiguracionVacunaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,            
								pTieneAdicional         IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_ADICIONAL%TYPE,
								pCantDosisAdicional	    IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_ADICIONAL%TYPE,
								 --Periodos Vacuna-------
                                pFechaInicio            IN VARCHAR2,       
                                pFechaFin               IN VARCHAR2,
                                -- Grupo Prioridad y edad maxima
                                pEdadMaxima             IN  NUMBER,
                                pTieneGrupoPrioridad    IN  NUMBER,
                                pTieneFrecuenciaAnuales IN  NUMBER,
                                pGrupoPrioridades       IN  VARCHAR2,
                                pSexoAplicable          IN  NUMBER,
                                ---Auditoria---------
                                pUsuario                IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                pEstadoRegistroId       IN VARCHAR2,
                                pResultado              OUT VARCHAR2,
                                pMsgError               OUT VARCHAR2) IS
   vFirma   VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_U_REL_TIP_VACUNA => ';   
   vCantidadVacunaEdades NUMBER;



  BEGIN
      CASE
        WHEN pEstadoRegistroId = vGLOBAL_ESTADO_PASIVO THEN       
          <<PasivaRegistro>>
          BEGIN
          --VALIDAR ANTES DE PASIVAR
           SELECT COUNT(*)  
           INTO   vCantidadVacunaEdades
           FROM   SIPAI_REL_TIPO_VACUNA_EDAD
           WHERE  REL_TIPO_VACUNA_ID=pRelTipoVacunaId
           AND    ESTADO_REGISTRO_ID=6869;

           IF   vCantidadVacunaEdades  > 0 THEN 
              pResultado := 'existen registros de edades asociadas';
              RAISE eUpdateInvalido;  
           END IF;
              --PASIVAR
             UPDATE SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
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
             WHERE REL_TIPO_VACUNA_ID     =  pRelTipoVacunaId AND
                   ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 
          END PasivaRegistro;
       WHEN pEstadoRegistroId = vGLOBAL_ESTADO_ACTIVO THEN
          <<ActivarRegistro>>
          BEGIN
             UPDATE SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
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
              WHERE REL_TIPO_VACUNA_ID = pRelTipoVacunaId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 
          END ActivarRegistro;
        ELSE 
          <<ActualizarRegistros>>
          BEGIN

           DBMS_OUTPUT.put_line('TIENE_FRECUENCIA_ANUALES'||pTieneFrecuenciaAnuales);
             UPDATE SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS
                SET TIPO_VACUNA_ID       = NVL(pTipVacuna,TIPO_VACUNA_ID),
                    FABRICANTE_VACUNA_ID = NVL(pFabVacuna,FABRICANTE_VACUNA_ID),
					CANTIDAD_DOSIS       = NVL(pCantDosis, CANTIDAD_DOSIS),
					--Esquema
					TIENE_REFUERZOS            = NVL(pTieneRefuerzo,TIENE_REFUERZOS),
					CANTIDAD_DOSIS_REFUERZO    = NVL(pCantDosisRefuerzo,CANTIDAD_DOSIS_REFUERZO),
					CONFIGURACION_VACUNA_ID	   = NVL(pConfiguracionVacunaId,CONFIGURACION_VACUNA_ID),
					TIENE_ADICIONAL			   = NVL(pTieneAdicional,TIENE_ADICIONAL),
					CANTIDAD_DOSIS_ADICIONAL   = NVL(pCantDosisAdicional,CANTIDAD_DOSIS_ADICIONAL),
                    ---Periodo
                    FECHA_INICIO   = NVL(to_date(pFechaInicio,'DD/MM/YYYY'),FECHA_INICIO),
                    FECHA_FIN   =    NVL(to_date(pFechaFin,'DD/MM/YYYY'),FECHA_FIN),
                   --- Grupo Prioridad y edad maxima
                    EDAD_MAX                = NVL(pEdadMaxima,EDAD_MAX),
                    TIENE_GRUPO_PRIORIDAD   = NVL(pTieneGrupoPrioridad,TIENE_GRUPO_PRIORIDAD),
                    TIENE_FRECUENCIA_ANUALES = NVL(pTieneFrecuenciaAnuales,TIENE_FRECUENCIA_ANUALES),
                    GRUPO_PRIODIDADES        = NVL(pGrupoPrioridades,GRUPO_PRIODIDADES),
                    SEXO_APLICABLE           = NVL(pSexoAplicable,SEXO_APLICABLE ),
                    --Auditoria
                    USUARIO_MODIFICACION = pUsuario   
              WHERE REL_TIPO_VACUNA_ID   = pRelTipoVacunaId AND
                    ESTADO_REGISTRO_ID != vGLOBAL_ESTADO_ELIMINADO; 
          END ActualizarRegistros;
        END CASE;

  EXCEPTION

   WHEN eUpdateInvalido THEN
      pResultado := pResultado;
       pMsgError  := vFirma ||'Error al Eliminar Registro de Vacunas: ' || pResultado;

  WHEN OTHERS THEN
       pResultado := 'Error no controlado';
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;  
  END PR_U_REL_TIP_VACUNA;  

PROCEDURE PR_C_REL_TIPO_VACUNA_DOSIS (pRelTipoVacunaId IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                        pTipVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                        pFabVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,  
                                        pCantDosis       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,
										 -----Vacunas x Edad---------
									   pCodigoExpediente IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad NUMBER,
									   pTipoEdad VARCHAR2,
									   pProgramaId  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,
									   pTipoFiltro IN NUMBER,	
                                       ---------Agregar Fecha Vacunacion para calcular la edad de vacunacion--------
                                       pFechaVacunacion  IN DATE,
                                       pPgnAct          IN NUMBER,
                                       pPgnTmn          IN NUMBER,
                                       pRegistro        OUT var_refcursor,
                                       pResultado       OUT VARCHAR2,
                                       pMsgError        OUT VARCHAR2) IS
  vFirma          VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_C_REL_TIPO_VACUNA_DOSIS => ';
  vTipoPaginacion NUMBER; 
  BEGIN
  DBMS_OUTPUT.put_line (pTipoFiltro || ' aqui') ;
      CASE
      WHEN (
        FN_VALIDA_REL_TIPO_DOSIS (
                                      pRelTipoVacunaId, 
                                      pTipVacuna, 
                                      pFabVacuna, 
                                      pCantDosis,
									  pEdad,
									  pProgramaId,
									  pTipoFiltro,
                                      vTipoPaginacion
                                )) = TRUE 
        THEN 
        pRegistro := FN_OBT_DATOS_REL_TIPO_DOSIS(  pRelTipoVacunaId, 
                                                   pTipVacuna, 
                                                   pFabVacuna, 
                                                   pCantDosis, 
                                                   pCodigoExpediente,
                                                   pEdad ,
                                                   pTipoEdad , 
                                                   pProgramaId,
                                                   pTipoFiltro,
                                                   --Agregar Fecha Vacunacion para calcular la edad
                                                   pFechaVacunacion,
                                                   vTipoPaginacion , 
                                                   pPgnAct, 
                                                   pPgnTmn);
      ELSE 
          CASE 
          WHEN NVL(pCantDosis, 0) > 0 THEN
               pResultado := 'No se encontraron registros de relación vacunas dosis [Cantidad dosis: '||pCantDosis||']';
               RAISE eRegistroNoExiste;  
          WHEN NVL(pFabVacuna,0) > 0 THEN
               pResultado := 'No se encontraron registros de relación vacunas dosis parámetros con el [fabricante Id: '||pFabVacuna||']';
               RAISE eRegistroNoExiste;
          WHEN NVL(pTipVacuna,0) > 0 THEN
               pResultado := 'No se encontraron registros de relación vacuna, relacionadas al  [pTipVacuna: '||pTipVacuna||']';
               RAISE eRegistroNoExiste; 
          WHEN NVL(pRelTipoVacunaId,0) > 0 THEN
               pResultado := 'No se encontraron registros de relación vacuna, relacionadas al  [pRelTipoVacunaId: '||pRelTipoVacunaId||']';
               RAISE eRegistroNoExiste;               
          ELSE
              pResultado := 'No se encontraron registros de relación vacuna registradas';
              RAISE eRegistroNoExiste;             
          END CASE;
      END CASE;
      CASE 
      WHEN NVL(pCantDosis, 0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con éxito, [Cantidad dosis: '||pCantDosis||']';
      WHEN NVL(pFabVacuna,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con éxito, parámetros con el [fabricante Id: '||pFabVacuna||']';
      WHEN NVL(pTipVacuna,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con éxito, relacionadas al  [pTipVacuna: '||pTipVacuna||']';
      WHEN NVL(pRelTipoVacunaId,0) > 0 THEN
           pResultado := 'Busqueda de registros realizada con éxito, relacionadas al  [pRelTipoVacunaId: '||pRelTipoVacunaId||']';
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
       pResultado := ' Hubo un error inesperado en la Base de Datos. Id de consultas: [Id: '||pRelTipoVacunaId||'], [pTipVacuna: '||pTipVacuna||'], [pFabVacuna: '||pFabVacuna||'], [pCantDosis: '||pCantDosis||']';
       pMsgError  := vFirma ||pResultado||' - '||SQLERRM;   
  END PR_C_REL_TIPO_VACUNA_DOSIS;


PROCEDURE SIPAI_CRUD_REL_TIP_VACUNA (  pRelTipoVacunaId IN OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                       pTipVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                       pFabVacuna       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,  
                                       pCantDosis       IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,                                    
                                       ----Esquema--------
									   pTieneRefuerzo         IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_REFUERZOS%TYPE,
									   pCantDosisRefuerzo 	  IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_REFUERZO%TYPE,            
									   pConfiguracionVacunaId IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE, 
									   -----Vacunas x Edad---------
									   pCodigoExpediente   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad               IN NUMBER,
									   pTipoEdad           IN VARCHAR2,
									   pCodigoPrograma     IN  VARCHAR2, 
									   pTipoFiltro         IN NUMBER,  
									   pTieneAdicional     IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_ADICIONAL%TYPE,
									   pCantDosisAdicional IN   SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_ADICIONAL%TYPE,
									  ----Auditoria-------
									   pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                       pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                       pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                       pAccionEstado    IN VARCHAR2,
                                       --Periodos Vacuna-------
                                       pFechaInicio     IN VARCHAR2,       
                                       pFechaFin        IN VARCHAR2,
                                       pTipoAccion      IN VARCHAR2,
                                        ---------Agregar Fecha Vacunacion para calcular la edad de vacunacion--------
                                       pFechaVacunacion IN DATE,
                                        ---Cambio Grupo Prioridad  y EdadMaxima
                                       pEdadMaxima             IN NUMBER,
                                       pTieneGrupoPrioridad    IN NUMBER,
                                       pTieneFrecuenciaAnuales IN NUMBER,
                                       pGrupoPrioridades       IN  VARCHAR,
                                       pSexoAplicable          IN NUMBER,
                                       ------------------------------------------------------------------------------
                                       pRegistro        OUT var_refcursor,
                                       pResultado       OUT VARCHAR2,
                                       pMsgError        OUT VARCHAR2) IS

  vFirma            VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.SIPAI_CRUD_REL_TIP_VACUNA => ';  
  vEstadoRegistroId SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.ESTADO_REGISTRO_ID%TYPE; 
  vPgnAct           NUMBER;
  vPgnTmn           NUMBER;   

  pProgramaId    NUMBER :=FN_SIPAI_CATALOGO_ESTADO_Id(pCodigoPrograma);

  BEGIN
  DBMS_OUTPUT.put_line ('aqui');
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
          PR_I_REL_TIP_VACUNA (pRelTipoVacunaId      	=> pRelTipoVacunaId, 
                               pTipVacuna            	=> pTipVacuna,      
                               pFabVacuna       		=> pFabVacuna,
                               pCantDosis       		=> pCantDosis,
							   pTieneRefuerzo 	 		=> pTieneRefuerzo,
							   pCantDosisRefuerzo 		=> pCantDosisRefuerzo,            
							   pConfiguracionVacunaId 	=> pConfiguracionVacunaId, 
							   pTieneAdicional        	=>pTieneAdicional,
							   pCantDosisAdicional     	=>pCantDosisAdicional,
                               --Periodos Vacuna-------
                               pFechaInicio         	=>pFechaInicio,  
                               pFechaFin       	        =>pFechaFin,
                                --Grupo Prioridad y edad maxima
                               pEdadMaxima              =>pEdadMaxima,
                               pTieneGrupoPrioridad     =>pTieneGrupoPrioridad,
                               pTieneFrecuenciaAnuales  =>pTieneFrecuenciaAnuales, 
                               pGrupoPrioridades        =>pGrupoPrioridades, 
                               pSexoAplicable           =>pSexoAplicable, 
								--Auditoria----------
                               pUniSaludId              => pUniSaludId,
                               pSistemaId               => pSistemaId,      
                               pUsuario                 => pUsuario,        
                               pResultado               => pResultado,      
                               pMsgError                => pMsgError
                               );       
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF;
           CASE
           WHEN NVL(pRelTipoVacunaId,0) > 0 THEN
                PR_C_REL_TIPO_VACUNA_DOSIS (pRelTipoVacunaId => pRelTipoVacunaId,           
                                            pTipVacuna       => pTipVacuna,                 
                                            pFabVacuna       => pFabVacuna,                
                                            pCantDosis       => pCantDosis,
											----Parametros Vacunas x edad--
											pCodigoExpediente =>pCodigoExpediente,
										    pEdad =>pEdad,
											pTipoEdad=>pTipoEdad,
											pProgramaId =>pProgramaId,
											pTipoFiltro=>pTipoFiltro,	
                                            pFechaVacunacion=>pFechaVacunacion,
											-------------------------------								
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
           pResultado := 'registro creado exitosamente';

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
           WHEN NVL(pRelTipoVacunaId,0) = 0 THEN
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
           PR_U_REL_TIP_VACUNA (pRelTipoVacunaId        => pRelTipoVacunaId,           
                                pTipVacuna              => pTipVacuna,                 
                                pFabVacuna              => pFabVacuna,                
                                pCantDosis              => pCantDosis,
								--Esquema
								pTieneRefuerzo 	        => pTieneRefuerzo,
								pCantDosisRefuerzo      => pCantDosisRefuerzo,            
								pConfiguracionVacunaId  => pConfiguracionVacunaId,
								pTieneAdicional        	=>pTieneAdicional,
							    pCantDosisAdicional     =>pCantDosisAdicional,
                                ----Periodo----------------------------
                                pFechaInicio         	=>pFechaInicio,  
                                pFechaFin       	    =>pFechaFin,
                                --Grupo Prioridad y edad maxima
                                pEdadMaxima             =>pEdadMaxima,
                                pTieneGrupoPrioridad    =>pTieneGrupoPrioridad,
                                pTieneFrecuenciaAnuales =>pTieneFrecuenciaAnuales, 
                                pGrupoPrioridades       =>pGrupoPrioridades, 
                                pSexoAplicable          =>pSexoAplicable, 
								--Auditoria-----------------------------
                                pUsuario                => pUsuario,                  
                                pEstadoRegistroId       => vEstadoRegistroId,         
                                pResultado              => pResultado,                
                                pMsgError               => pMsgError
                                );                 
           IF pMsgError IS NOT NULL AND LENGTH (TRIM (pMsgError)) > 0 THEN
              RAISE eSalidaConError;
           END IF; 

           CASE
           WHEN NVL(pRelTipoVacunaId,0) > 0 THEN
                PR_C_REL_TIPO_VACUNA_DOSIS (pRelTipoVacunaId => pRelTipoVacunaId,           
                                            pTipVacuna       => pTipVacuna,                 
                                            pFabVacuna       => pFabVacuna,                
                                            pCantDosis       => pCantDosis,
											----Parametros Vacunas x edad--
											pCodigoExpediente =>pCodigoExpediente, 
										    pEdad			   => pEdad,
										    pTipoEdad 			   =>pTipoEdad ,
											pProgramaId  =>   pProgramaId ,
											pTipoFiltro=>pTipoFiltro,	
                                            pFechaVacunacion=>pFechaVacunacion,
											-------------------------------
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
           pResultado := 'registro actualizado exitosamente';

      WHEN pTipoAccion = kCONSULTAR THEN

           PR_C_REL_TIPO_VACUNA_DOSIS (pRelTipoVacunaId => pRelTipoVacunaId,           
                                       pTipVacuna       => pTipVacuna,                 
                                       pFabVacuna       => pFabVacuna,                
                                       pCantDosis       => pCantDosis,
									   ----Parametros Vacunas x edad--
										pCodigoExpediente =>pCodigoExpediente,
										pEdad =>pEdad,
										pTipoEdad=>pTipoEdad,
										pProgramaId  =>   pProgramaId ,
										pTipoFiltro=>pTipoFiltro,	
                                        pFechaVacunacion=> pFechaVacunacion,
										-------------------------------
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
      WHEN OTHERS THEN
           pResultado := 'Error no controlado';
           pMsgError  := vFirma||pResultado||' - '||SQLERRM;   

  END SIPAI_CRUD_REL_TIP_VACUNA; 

  --CONSULTAR REL VACUNAS FABRICANTES 
  --F01
  FUNCTION   FN_OBT_VACUNAS_FABRICANTES_ID(pRelTipoVacunaFabricanteId PLS_INTEGER) RETURN   var_refcursor as 
   vRegistro var_refcursor;
  BEGIN  
    OPEN  vRegistro  FOR 
            SELECT 
                A.REL_TIPO_VACUNAS_FABRICANTE_ID ,    
                A.REL_TIPO_VACUNA_ID    ,       
                A.FABRICANTE_VACUNA_ID  ,  
                A.CODIGO_FABRICANTE ,  
                CFAB.VALOR NOMBRE_FABRICANTE,
                A.TIPO_VACUNA_ID ,                 
                A.CODIGO_TIPO_VACUNA  ,
                CVAC.VALOR NOMBRE_VACUNA,
                A.ESTADO_REGISTRO_ID ,
                A.USUARIO_REGISTRO,
                A.FECHA_REGISTRO ,
                A.USUARIO_MODIFICACION ,
                A.FECHA_MODIFICACION 
        FROM SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE A
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CFAB ON A.FABRICANTE_VACUNA_ID=CFAB.CATALOGO_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CVAC ON A.TIPO_VACUNA_ID=CVAC.CATALOGO_ID
        ------------------------------------------------------------------------------
        WHERE  A.REL_TIPO_VACUNAS_FABRICANTE_ID=pRelTipoVacunaFabricanteId
        AND    A.ESTADO_REGISTRO_ID=6869;

        RETURN vRegistro; 

 END;

 --F02
 FUNCTION   FN_OBT_VACUNAS_FABRICANTES_REL(pRelTipoVacunaId PLS_INTEGER) RETURN   var_refcursor as 
   vRegistro var_refcursor;
  BEGIN  
    OPEN  vRegistro  FOR 
            SELECT 
                A.REL_TIPO_VACUNAS_FABRICANTE_ID ,    
                A.REL_TIPO_VACUNA_ID    ,       
                A.FABRICANTE_VACUNA_ID  ,  
                A.CODIGO_FABRICANTE ,  
                CFAB.VALOR NOMBRE_FABRICANTE,
                A.TIPO_VACUNA_ID ,                 
                A.CODIGO_TIPO_VACUNA  ,
                CVAC.VALOR NOMBRE_VACUNA,
                A.ESTADO_REGISTRO_ID ,
                A.USUARIO_REGISTRO,
                A.FECHA_REGISTRO ,
                A.USUARIO_MODIFICACION ,
                A.FECHA_MODIFICACION 
        FROM SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE A
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CFAB ON A.FABRICANTE_VACUNA_ID=CFAB.CATALOGO_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CVAC ON A.TIPO_VACUNA_ID=CVAC.CATALOGO_ID
        ------------------------------------------------------------------------------
        WHERE  A.REL_TIPO_VACUNA_ID=pRelTipoVacunaId
        AND    A.ESTADO_REGISTRO_ID=6869;

        RETURN vRegistro; 

 END;

 --F03
 FUNCTION   FN_OBT_VACUNAS_FABRICANTES_TODO RETURN   var_refcursor as 
   vRegistro var_refcursor;
  BEGIN  
    OPEN  vRegistro  FOR 
            SELECT 
                A.REL_TIPO_VACUNAS_FABRICANTE_ID ,    
                A.REL_TIPO_VACUNA_ID    ,       
                A.FABRICANTE_VACUNA_ID  ,  
                A.CODIGO_FABRICANTE ,  
                CFAB.VALOR NOMBRE_FABRICANTE,
                A.TIPO_VACUNA_ID ,                 
                A.CODIGO_TIPO_VACUNA  ,
                CVAC.VALOR NOMBRE_VACUNA,
                A.ESTADO_REGISTRO_ID ,
                A.USUARIO_REGISTRO,
                A.FECHA_REGISTRO ,
                A.USUARIO_MODIFICACION ,
                A.FECHA_MODIFICACION 
        FROM SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE A
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CFAB ON A.FABRICANTE_VACUNA_ID=CFAB.CATALOGO_ID
        JOIN  CATALOGOS.SBC_CAT_CATALOGOS CVAC ON A.TIPO_VACUNA_ID=CVAC.CATALOGO_ID
        ------------------------------------------------------------------------------
        WHERE A.ESTADO_REGISTRO_ID=6869;

        RETURN vRegistro; 

 END;

  --CREAR REL VACUNAS FABRICANTES 
 PROCEDURE PR_CREAR_VACUNAS_FABRICANTE( 	---Parametros
                                        pRelTipoVacunaId          IN NUMBER,
                                        pTipoVacunaId             IN NUMBER,
                                        pCodigoVacuna             IN VARCHAR2,
                                        pFabricanteId             IN NUMBER,
                                        pCodigoFabricante         IN VARCHAR2, 
                                        -----------------------------
                                        pUsuario          IN VARCHAR2,
                                        pResultado  OUT VARCHAR2,
                                        pMsgError   OUT VARCHAR2,
                                        pRegistro   OUT var_refcursor
                                        ) IS                                       
  vFirma   VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_CREAR_VACUNAS_FABRICANTE => '; 
  registro  SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE%ROWTYPE;

  BEGIN

      registro.REL_TIPO_VACUNA_ID:=pRelTipoVacunaId;
      registro.TIPO_VACUNA_ID:= pTipoVacunaId;
      registro.CODIGO_TIPO_VACUNA:= pCodigoVacuna;
      registro.FABRICANTE_VACUNA_ID:=pFabricanteId;
      registro.CODIGO_FABRICANTE:= pCodigoFabricante;
      ----------------------------------------
      registro.USUARIO_REGISTRO:=pUsuario;
      registro.FECHA_REGISTRO:=sysdate;
      registro.ESTADO_REGISTRO_ID:=6869;

      INSERT INTO SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE VALUES registro;
      COMMIT;

      pResultado:='Registro insertado con exito';
      pRegistro:=FN_OBT_VACUNAS_FABRICANTES_REL(pRelTipoVacunaId);      

  EXCEPTION

  WHEN OTHERS THEN
       pResultado := 'Error al insertar Datos ';    
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;

  END PR_CREAR_VACUNAS_FABRICANTE;

   --CREAR REL VACUNAS FABRICANTES 
 PROCEDURE PR_MODIFICAR_VACUNAS_FABRICANTE( 	---Parametros
                                            pRelTipoVacunaFabricanteId IN NUMBER,
                                            pRelTipoVacunaId           IN NUMBER,
                                            pTipoVacunaId              IN NUMBER,
                                            pCodigoVacuna              IN VARCHAR2,
                                            pFabricanteId              IN NUMBER,
                                            pCodigoFabricante          IN VARCHAR2, 
                                            -----------------------------
                                            pUsuario          IN VARCHAR2,
                                            pResultado  OUT VARCHAR2,
                                            pMsgError   OUT VARCHAR2,
                                            pRegistro   OUT var_refcursor
                                        ) IS                                       
  vFirma   VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_MODIFICAR_VACUNAS_FABRICANTE => '; 
  registro  SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE%ROWTYPE;

  BEGIN

      UPDATE  SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE
           SET     REL_TIPO_VACUNA_ID   = NVL(pRelTipoVacunaId,REL_TIPO_VACUNA_ID),
                   TIPO_VACUNA_ID       = NVL(pTipoVacunaId,TIPO_VACUNA_ID),
                   CODIGO_TIPO_VACUNA   = NVL(pCodigoVacuna,CODIGO_TIPO_VACUNA),
                   FABRICANTE_VACUNA_ID = NVL(pFabricanteId,FABRICANTE_VACUNA_ID),
                   CODIGO_FABRICANTE    = NVL(pCodigoFabricante,CODIGO_FABRICANTE),

                   FECHA_MODIFICACION=SYSDATE, 
                   USUARIO_MODIFICACION=pUsuario
           WHERE   REL_TIPO_VACUNAS_FABRICANTE_ID = pRelTipoVacunaFabricanteId;


           pResultado:=' Registro Modificado con Exito... '|| pRelTipoVacunaFabricanteId;
           --pRegistro:=FN_OBT_CATALOGO_DETALLE_ID( reg.CATALOGO_VALOR_ID );  

      COMMIT;

      pResultado:='Registro insertado con exito';
      pRegistro:=FN_OBT_VACUNAS_FABRICANTES_REL(pRelTipoVacunaId);      

  EXCEPTION

  WHEN OTHERS THEN
       pResultado := 'Error al insertar Datos ';    
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;

  END PR_MODIFICAR_VACUNAS_FABRICANTE;

    --CREAR REL VACUNAS FABRICANTES 
 PROCEDURE PR_ELIMINAR_VACUNAS_FABRICANTE( 	---Parametros
                                            pRelTipoVacunaFabricanteId IN NUMBER,
                                            -----------------------------
                                            pUsuario          IN VARCHAR2,
                                            pResultado  OUT VARCHAR2,
                                            pMsgError   OUT VARCHAR2,
                                            pRegistro   OUT var_refcursor
                                        ) IS                                       
  vFirma   VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.PR_ELIMINAR_VACUNAS_FABRICANTE => '; 

  vTieneLoteAsociado pls_integer;

  BEGIN
          SELECT COUNT(*)
          INTO  vTieneLoteAsociado
          FROM  SIPAI_DET_TIPVAC_X_LOTE
          WHERE REL_TIPO_VACUNAS_FABRICANTE_ID = pRelTipoVacunaFabricanteId
          AND   ESTADO_REGISTRO_ID=6869;

          IF  NVL(vTieneLoteAsociado,0) > 0 THEN
               pResultado := 'El Registro Fabricante Vacuna Tiene Lotes Asociados';
               pMsgError  := pResultado;
               RAISE eParametrosInvalidos;   
          END IF;

           DELETE   SIPAI.SIPAI_REL_TIPO_VACUNAS_FABRICANTE
           WHERE    REL_TIPO_VACUNAS_FABRICANTE_ID = pRelTipoVacunaFabricanteId;

           pResultado:=' Registro Eliminado con Exito... ';

      COMMIT;

  EXCEPTION

  WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado; 

  WHEN OTHERS THEN
       pResultado := 'Error al insertar Datos ';    
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;

  END PR_ELIMINAR_VACUNAS_FABRICANTE;

  PROCEDURE SIPAI_CRUD_VACUNAS_FABRICANTES ( 	---Parametros de Entrada
                                        pJson     in   CLOB,
                                        pResultado  OUT VARCHAR2,
                                        pMsgError   OUT VARCHAR2,
                                        pRegistro   OUT var_refcursor
							                ) IS


  vFirma   VARCHAR2(100) := 'PKG_SIPAI_TIPO_VACUNA.SIPAI_CRUD_VACUNAS_FABRICANTES => ';  
  v_crud VARCHAR2(10);
  vFiltro  NUMBER:=JSON_VALUE(pJson,'$.filtro');

   vRelTipoVacunaId NUMBER;   --:=JSON_VALUE(pJson,'$.relTipoVacunaId');
  vTIpoVacunaId NUMBER:=JSON_VALUE(pJson,'$.tipoVacunaId');
  vCodigoVacuna VARCHAR2(30)  :=JSON_VALUE(pJson,'$.codigoVacuna');

  vRelTipoVacunaFabricanteId  NUMBER(10);
  vFabricanteId NUMBER(10);
  vCodigoFabricante  VARCHAR2(30);
  vUsuario VARCHAR2(50);

  BEGIN


  --Recorrer el arreglo de los datos detalle
   FOR reg IN (
       SELECT jt.*
         FROM JSON_TABLE( 
         pJson, '$'
          COLUMNS (
            NESTED PATH '$.fabricantes[*]'
             COLUMNS (

                REL_TIPO_VACUNAS_FABRICANTE_ID  NUMBER PATH '$.relTipoVacunaFabricanteId',
                FABRICANTE_ID NUMBER PATH '$.fabricanteId',
                CODIGO_FABRICANTE VARCHAR PATH '$.codigoFabricante',
                ACCION             varchar2(10) PATH '$.accion'
                                )))jt
                 )
    LOOP

    v_crud :=reg.ACCION; ---JSON_VALUE(pJson,'$.fabricantes.accion');
    vFabricanteId      := reg.FABRICANTE_ID;
    vCodigoFabricante  := reg.CODIGO_FABRICANTE;

     DBMS_OUTPUT.PUT_LINE('v_crud'||v_crud);
    IF  v_crud ='crear' THEN

       DBMS_OUTPUT.PUT_LINE('RUN CREAR');  

     IF  NVL(vTIpoVacunaId,0) = 0 THEN
          pResultado := 'El Id Tipo vacuna no puede venir nulo';
          pMsgError  := pResultado;
          RAISE eParametrosInvalidos;   
    ELSE                     
              SELECT REL_TIPO_VACUNA_ID 
              INTO   vRelTipoVacunaId
              FROM   SIPAI_REL_TIP_VACUNACION_DOSIS
              WHERE  TIPO_VACUNA_ID=vTIpoVacunaId
              AND    ESTADO_REGISTRO_ID=6869;

    END IF;


       vUsuario:=JSON_VALUE(pJson,'$.usuarioCreacion' RETURNING VARCHAR2(50)  NULL ON EMPTY );
       PR_CREAR_VACUNAS_FABRICANTE( ---Parametros----
                                    vRelTipoVacunaId,
                                    vTIpoVacunaId,
                                    vCodigoVacuna,
                                    vFabricanteId,
                                    vCodigoFabricante,
                                    -------------------
                                    vUsuario, 
                                    pResultado,
                                    pMsgError,
                                    pRegistro);

    ELSIF  v_crud ='modificar' THEN
      DBMS_OUTPUT.PUT_LINE('RUN MODIFICAR');

      IF  NVL(vTIpoVacunaId,0) = 0 THEN
          pResultado := 'El Id Tipo vacuna no puede venir nulo';
          pMsgError  := pResultado;
          RAISE eParametrosInvalidos;   
      ELSE                     
              SELECT REL_TIPO_VACUNA_ID 
              INTO   vRelTipoVacunaId
              FROM   SIPAI_REL_TIP_VACUNACION_DOSIS
              WHERE  TIPO_VACUNA_ID=vTIpoVacunaId
              AND    ESTADO_REGISTRO_ID=6869;

    END IF;

      vRelTipoVacunaFabricanteId:= reg.REL_TIPO_VACUNAS_FABRICANTE_ID; --JSON_VALUE(pJson,'$.fabricantes.relTipoVacunaFabricanteId');
      vUsuario:=JSON_VALUE(pJson,'$.usuarioModifica' RETURNING VARCHAR2(50)  NULL ON EMPTY );

       PR_MODIFICAR_VACUNAS_FABRICANTE( 	---Parametros
                                            vRelTipoVacunaFabricanteId,
                                            vRelTipoVacunaId,
                                            vTipoVacunaId,
                                            vCodigoVacuna,
                                            vFabricanteId,
                                            vCodigoFabricante, 
                                            -----------------------------
                                            vUsuario ,
                                            pResultado ,
                                            pMsgError,
                                            pRegistro);

          pResultado := 'El registro ha sido modificado';    

          --pRegistro:=FN_SELECT_VACUNAS_EXP(vExpedienteId );
     ELSIF  v_crud ='eliminar' THEN

       vRelTipoVacunaFabricanteId:= reg.REL_TIPO_VACUNAS_FABRICANTE_ID; 
       vUsuario:=JSON_VALUE(pJson,'$.usuarioModifica' RETURNING VARCHAR2(50)  NULL ON EMPTY ); 

       DBMS_OUTPUT.PUT_LINE('RUN ELIMINAR / PASIVAR ');
       PR_ELIMINAR_VACUNAS_FABRICANTE( 	---Parametros
                                            vRelTipoVacunaFabricanteId ,
                                            -----------------------------
                                            vUsuario,
                                            pResultado,
                                            pMsgError,
                                            pRegistro
                                            );

     ELSIF  v_crud ='consultar' THEN
        DBMS_OUTPUT.PUT_LINE('Accion' || v_crud ||'Filtro' || vFiltro || 'RUN CONSULTAR POR TIPO DE FILTRO');

       IF vFiltro  = 1 THEN 
            pRegistro:=FN_OBT_VACUNAS_FABRICANTES_ID(vRelTipoVacunaFabricanteId ); 
       END IF;

       IF vFiltro  =2 THEN 
            pRegistro:=FN_OBT_VACUNAS_FABRICANTES_REL(vRelTipoVacunaId ); 
       END IF;

       IF vFiltro  =3 THEN 
            pRegistro:=FN_OBT_VACUNAS_FABRICANTES_TODO(); 
       END IF;

    END IF;
   END LOOP;

  EXCEPTION
  WHEN eParametrosInvalidos THEN
           pResultado := pResultado;
           pMsgError  := vFirma||pResultado;        

  WHEN OTHERS THEN
       pResultado := 'Error en el CRUD de Datos ';    
       pMsgError  := vFirma||pResultado||' - '||SQLERRM;

  END SIPAI_CRUD_VACUNAS_FABRICANTES;

END PKG_SIPAI_TIPO_VACUNA;
/