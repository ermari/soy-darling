CREATE OR REPLACE PACKAGE SIPAI."PKG_SIPAI_REGISTRO_NOMINAL" 
   AUTHID CURRENT_USER
AS
   SUBTYPE MAXVARCHAR2 IS VARCHAR2(32000);
   vQuery  MAXVARCHAR2;
   vQuery1 MAXVARCHAR2;
   --Declaración Constantes
   kBusquedaIdenticacionId   CHAR (3) := 'BII';
   kBusquedaIdenticacionNm   CHAR (3) := 'BIN';
   kPrsIdntf                 CHAR (4) := 'IDNT';
   kPrsNIdnt                 CHAR (4) := 'NIDN';
   kPrsRNac                  CHAR (4) := 'RNAC';
   kPrsDscn                  CHAR (4) := 'DSCN';
   -- --------------------
   -- --------------------
   vDncQry                   VARCHAR2 (32000);
   kDELETE              CONSTANT CHAR (1) := 'D';
   kCONSULTAR           CONSTANT CHAR (1) := 'C';  

   TYPE array_str_data_persona IS TABLE OF VARCHAR2 (1250)
      INDEX BY PLS_INTEGER;

   TYPE tipo_edad IS RECORD (ANIO NUMBER(10), MES NUMBER(10), DIA NUMBER);  

   -- Cursores
-- fsequeira
   TYPE var_refcursor IS REF CURSOR;

   kINSERT              CONSTANT CHAR (1) := 'I';
   kUPDATE              CONSTANT CHAR (1) := 'U';

  eRegistroExiste      EXCEPTION;
  eRegistroNoExiste    EXCEPTION;
  eParametrosInvalidos EXCEPTION;
  eParametroNull       EXCEPTION;
  eSalidaConError      EXCEPTION;
  ePasivarInvalido     EXCEPTION;
  eUpdateInvalido      EXCEPTION;    

  kACCIONESTADO_PASIVO_TRUE CONSTANT NUMBER := 2;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');  -- fs
  vGLOBAL_ESTADO_ELIMINADO  CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Eliminado'); 
  vGLOBAL_ESTADO_PASIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Pasivo'); 
  vGLOBAL_ESTADO_PRECARGADO CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Precargado');
  vGLOBAL_ESTADO_UNIFICADO  CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Unificado');  


  PROCEDURE SIPAI_CRUD_CONTROL_VACUNA (pControlVacunaId      IN OUT SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                       pExpedienteId         IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                       pProgVacuna           IN SIPAI.SIPAI_MST_CONTROL_VACUNA.PROGRAMA_VACUNA_ID%TYPE,
                                       pGrpPrioridad         IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                       pEnfCronicaId         IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,
                                       pTipVacuna            IN SIPAI.SIPAI_MST_CONTROL_VACUNA.TIPO_VACUNA_ID%TYPE,
                                       pCantVacunaApli       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_APLICADA%TYPE,
                                       pCantVacunaProg       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CANTIDAD_VACUNA_PROGRAMADA%TYPE,
                                       pFechaPrimVacuna      IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_INICIO_VACUNA%TYPE,
                                       pFechaUltVacuna       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.FECHA_FIN_VACUNA%TYPE,
                                       pFecVacuna            IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                       pHrVacunacion         IN SIPAI.SIPAI_DET_VACUNACION.HORA_VACUNACION%TYPE,
                                       pDetVacLoteFecvenId   IN SIPAI.SIPAI_DET_VACUNACION.DETALLE_VACUNA_X_LOTE_ID%TYPE,
									   pPerVacunaId          IN SIPAI.SIPAI_DET_VACUNACION.PERSONAL_VACUNA_ID%TYPE,
                                       pViaAdmin             IN SIPAI.SIPAI_DET_VACUNACION.VIA_ADMINISTRACION_ID%TYPE,
                                      ------NUEVOS CAMPOS-------------------------------------------------------------
									   pObservacion		     IN SIPAI.SIPAI_DET_VACUNACION.OBSERVACION%TYPE,
									   pFechaProximaVacuna   IN SIPAI.SIPAI_DET_VACUNACION.FECHA_PROXIMA_VACUNA%TYPE, 
									   pNoAplicada		     IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
									   pMotivoNoAplicada     IN SIPAI.SIPAI_DET_VACUNACION.MOTIVO_NO_APLICADA%TYPE,  
									   pTipoEstrategia	     IN SIPAI.SIPAI_DET_VACUNACION.TIPO_ESTRATEGIA_ID%TYPE,
									   pEsRefuerzo           IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,
                                       pCasoEmbarazo         IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,
									   pIdRelTipoVacunaEdad  IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,                                     
									   pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,
									  ------------------------------------------------------------------------------------ 
									   pUniSaludId           IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                       pSistemaId            IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                       pUsuario              IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                       pAccionEstado         IN VARCHAR2,
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
                                       pTipoAccion                               IN VARCHAR2,
                                       ----------------Parametros de Salidas ---------------------------
                                       pRegistro             OUT var_refcursor,
                                       pResultado            OUT VARCHAR2,
                                       pMsgError             OUT VARCHAR2);

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
									   pEsRefuerzo           IN SIPAI.SIPAI_DET_VACUNACION.ES_REFUERZO%TYPE,
                                       pCasoEmbarazo       IN SIPAI.SIPAI_DET_VACUNACION.CASO_EMBARAZO%TYPE,
									   pIdRelTipoVacunaEdad  IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
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
                                       pGrpPrioridad                            IN SIPAI.SIPAI_MST_CONTROL_VACUNA.GRUPO_PRIORIDAD_ID%TYPE,
                                      ------------------------------------------------------------------
                                       pTipoAccion         IN VARCHAR2,
                                       ----------------Parametros de Salidas ---------------------------
                                       pRegistro           OUT var_refcursor,
                                       pResultado          OUT VARCHAR2,
                                       pMsgError           OUT VARCHAR2);

  PROCEDURE SIPAI_CRUD_PER_X_ENF_CRONICAS (pDetPerXEnfCronId  IN OUT SIPAI_PER_VACUNADA_ENF_CRON.DET_PER_X_ENFCRON_ID%TYPE,
                                           pControlVacunaId   IN SIPAI.SIPAI_MST_CONTROL_VACUNA.CONTROL_VACUNA_ID%TYPE,
                                           pExpedienteId      IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.EXPEDIENTE_ID%TYPE,       
                                           pEnfCronicaId      IN SIPAI.SIPAI_PER_VACUNADA_ENF_CRON.ENF_CRONICA_ID%TYPE,            
                                           pUsuario           IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                            
                                           pAccionEstado      IN VARCHAR2,
                                           pTipoAccion        IN VARCHAR2,
                                           pRegistro          OUT var_refcursor,
                                           pResultado         OUT VARCHAR2,
                                           pMsgError          OUT VARCHAR2);
                                           
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
                                 pMsgError           OUT VARCHAR2);
                                 
                                 
 FUNCTION FN_EXISTE_DOSIS_ANTERIOR (pControlVacunaId  IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,
								     pDetVacunacionId  IN SIPAI.SIPAI_DET_VACUNACION.DET_VACUNACION_ID%TYPE

) RETURN BOOLEAN;





    /*                                       
PROCEDURE PR_I_DET_PROXIMA_CITA   ( pExpedienteId     IN  NUMBER,
                                      pFechaProximaVacuna   IN DATE,
                                      pTipVacunaId       IN  NUMBER,
                                      pIdRelTipoVacunaEdad    IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE,
                                       --------------Datos de Sectorizacion Residencia-----------------
                                       pSectorResidenciaId	                    IN   	NUMBER, 
									   pSectorResidenciaNombre	                IN   	VARCHAR2,
									   pUnidadSaludResidenciaId	                IN   	NUMBER, 
									   pUnidadSaludResidenciaNombre	            IN   	VARCHAR2,
									   pEntidadAdminResidenciaId       IN   	NUMBER, 
									   pEntidadAdminResidenciaNombre	IN   	VARCHAR2,
									   --------------------------------------------------------------
									   pResultado          OUT VARCHAR2,
                                       pMsgError           OUT VARCHAR2) ;
*/
END PKG_SIPAI_REGISTRO_NOMINAL;
/