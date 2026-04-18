CREATE OR REPLACE PACKAGE SIPAI."PKG_SIPAI_TIPO_VACUNA" 
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

-- fsequeira
   TYPE var_refcursor IS REF CURSOR;

   kINSERT              CONSTANT CHAR (1) := 'I';
   kUPDATE              CONSTANT CHAR (1) := 'U';
   kDELETE              CONSTANT CHAR (1) := 'D';
   kCONSULTAR           CONSTANT CHAR (1) := 'C';  

  eRegistroExiste      EXCEPTION;
  eRegistroNoExiste    EXCEPTION;
  eParametrosInvalidos EXCEPTION;
  eParametroNull       EXCEPTION;
  eSalidaConError      EXCEPTION;
  ePasivarInvalido     EXCEPTION;
  eUpdateInvalido      EXCEPTION;    

  kACCIONESTADO_PASIVO_TRUE CONSTANT NUMBER := 1;
  vGLOBAL_ESTADO_ACTIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Activo');  -- fs
  vGLOBAL_ESTADO_ELIMINADO  CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Eliminado'); 
  vGLOBAL_ESTADO_PASIVO     CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Pasivo'); 
  vGLOBAL_ESTADO_PRECARGADO CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Precargado');
  vGLOBAL_ESTADO_UNIFICADO  CATALOGOS.SBC_CAT_CATALOGOS.CATALOGO_ID%TYPE := SIPAI.PKG_SIPAI_UTILITARIOS.FN_OBT_ESTADO_REGISTRO ('Unificado');  


PROCEDURE  PRC_PROXIMA_CITA_DOSIS ( pRelTipoVacunaId IN OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                    pEdad            IN NUMBER,
									pTipoEdad        IN VARCHAR2,
									pTipoAccion      IN VARCHAR2,
                                    ---------Agregar Fecha Vacunacion para calcular la edad de vacunacion--------
                                    pFechaVacunacion  IN DATE,
						            pRegistro       		OUT var_refcursor,
									pResultado       		OUT VARCHAR2,
									pMsgError       		OUT VARCHAR2
								   );

  PROCEDURE SIPAI_CRUD_REL_TIP_VACUNA (pRelTipoVacunaId       IN OUT SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.REL_TIPO_VACUNA_ID%TYPE,
                                       pTipVacuna             IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIPO_VACUNA_ID%TYPE,
                                       pFabVacuna             IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.FABRICANTE_VACUNA_ID%TYPE,  
                                       pCantDosis             IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS%TYPE,                  
									   pTieneRefuerzo         IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_REFUERZOS%TYPE,
									   pCantDosisRefuerzo     IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_REFUERZO%TYPE,            
									   pConfiguracionVacunaId IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CONFIGURACION_VACUNA_ID%TYPE,                                 
									   pCodigoExpediente      IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
									   pEdad                  IN NUMBER,
									   pTipoEdad              IN VARCHAR2,		
                                       pCodigoPrograma        IN VARCHAR2,
									   pTipoFiltro            IN NUMBER,  
                                       pTieneAdicional        IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.TIENE_ADICIONAL%TYPE,
									   pCantDosisAdicional	  IN SIPAI.SIPAI_REL_TIP_VACUNACION_DOSIS.CANTIDAD_DOSIS_ADICIONAL%TYPE,
									   ----Auditoria
									   pUniSaludId            IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                       pSistemaId             IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                       pUsuario               IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                                  
                                       pAccionEstado          IN VARCHAR2,
                                       --Periodos Vacuna-------
                                       pFechaInicio           IN VARCHAR2,       
                                       pFechaFin              IN VARCHAR2,
                                       pTipoAccion            IN VARCHAR2,
                                        ---------Agregar Fecha Vacunacion para calcular la edad de vacunacion--------
                                        pFechaVacunacion        IN DATE,
                                         ---Cambio Grupo Prioridad  y EdadMaxima
                                        pEdadMaxima             IN  NUMBER,
                                        pTieneGrupoPrioridad    IN  NUMBER,
                                        pTieneFrecuenciaAnuales IN  NUMBER,
                                        pGrupoPrioridades       IN  VARCHAR,
                                        pSexoAplicable          IN NUMBER,
                                       ------------------------------------------------------------------------------
                                       pRegistro        OUT var_refcursor,
                                       pResultado       OUT VARCHAR2,
                                       pMsgError        OUT VARCHAR2);


 PROCEDURE SIPAI_CRUD_VACUNAS_FABRICANTES ( 
                                        pJson     in   CLOB,
                                        pResultado  OUT VARCHAR2,
                                        pMsgError   OUT VARCHAR2,
                                        pRegistro   OUT var_refcursor
                                        ) ;




END PKG_SIPAI_TIPO_VACUNA;
/