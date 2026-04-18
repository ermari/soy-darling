CREATE OR REPLACE PACKAGE SIPAI.PKG_SIPAI_UTILITARIOS 
AUTHID CURRENT_USER
AS

SUBTYPE vMAX_VARCHAR2 IS VARCHAR2(32767);

TYPE var_refcursor IS REF CURSOR;
  eRegistroExiste      EXCEPTION;
  eRegistroNoExiste    EXCEPTION;
  eParametrosInvalidos EXCEPTION;
  eParametroNull       EXCEPTION;
  eSalidaConError      EXCEPTION;
  ePasivarInvalido     EXCEPTION;
  eUpdateInvalido      EXCEPTION;
  eCoincidencia        EXCEPTION;
  
  NULL_VALUE_NOT_NULL   EXCEPTION;
  PRAGMA EXCEPTION_INIT (NULL_VALUE_NOT_NULL, -01400);
   
  VALUE_ERROR_CONVERT    EXCEPTION;
  PRAGMA EXCEPTION_INIT (VALUE_ERROR_CONVERT, -06502);
   
  K_CODE_CUSTOM_EXCEPTION   NUMBER := -20990;
  MINSA_CUSTOM_EXCEPTION    EXCEPTION;
  PRAGMA EXCEPTION_INIT (MINSA_CUSTOM_EXCEPTION, -20990);
   
  K_STRG_COMODIN_EXCEPTION CHAR(3 char)     := '\-\';  
  
  kSoloTexto VARCHAR2 (26 char) := '[^A-Za-záéíóúÁÉÍÓÚñÑÜü'' ]';
  
  K_VAL_CAT_CHIELD_ID     CHAR(5)     := 'CHLID';
  K_VAL_CAT_CHIELD        CHAR(3)     := 'CHL';
  K_VAL_CAT_PARENT        CHAR(3)     := 'PRN';
  K_VAL_CAT               CHAR(4)     := 'UNKW';
  K_ID             VARCHAR2(10)        := 'ID';
  K_EXP_BASE       VARCHAR2(10)        := 'EXP_BASE';
  K_TYPE_EXP_BASE  VARCHAR2(10)        := 'T_EXP_BASE';
  K_CODE_EXP       VARCHAR2(10)        := 'CODE_EXP';
  K_TYPE_CODE_EXP  VARCHAR2(10)        := 'T_CODE_EXP';     
  K_LKUSR_USERNAME      VARCHAR2(10)   := 'USRNM';
  K_LKSYS_CODE          VARCHAR2(10)   := 'SYS_CODE';
  
  --Cat Values -> State
  K_CAT_REG_ACT                    VARCHAR2 (6) := 'ACTREG';
  K_CAT_REG_PAS                    VARCHAR2 (6) := 'PASREG';
  K_CAT_REG_DEL                    VARCHAR2 (6) := 'DELREG';
  K_STATE_REG                      VARCHAR2 (5) := 'STREG';
  
  --TypesEntity
  K_CFG_EXP_BASE       VARCHAR2(20) := 'CFG_EXP_BASE';
  K_MST_COD_EXP        VARCHAR2(20) := 'CPDE_EXP_ID';
  K_HST_COD_EXP        VARCHAR2(20) := 'CPDE_HST_EXP_ID';
  K_MST_PACIENTES      VARCHAR2(20) := 'MST_PX';
  
  K_MST_USUARIOS       VARCHAR2(20) := 'SCS_USRS';
  K_MST_SISTEMAS       VARCHAR2(20) := 'SCS_SYS';
  K_SYS_CD_PX          VARCHAR2(20) := 'PA';
 
  K_DET_EXP_LOC        VARCHAR2(20) := 'EXP_LOC';
  K_DET_PROGRAM        VARCHAR2(20) := 'PROGRAMA';
  K_DET_PX_CRCT        VARCHAR2(20) := 'PX_CRCTR';--Caracterísitcas
  K_DET_PX_CNCT        VARCHAR2(20) := 'PX_CNCT';--Contactos
  K_DET_PX_FNMC        VARCHAR2(20) := 'PX_FNCM';--Financiamientos
  K_DET_PX_IDNT        VARCHAR2(20) := 'PX_IDNT';--Identificaciones
  K_DET_XP_IDNT        VARCHAR2(20) := 'XP_IDNT';--Identificaciones  
  K_DET_PX_RSDN        VARCHAR2(20) := 'PX_RSDN';--Residencias
  
  K_FNMC_CODE          VARCHAR2(20) := 'FNMC_CODE';
  K_IDNTF_CODE         VARCHAR2(20) := 'IDNTF_CODE';
   
  K_VLD_ID             VARCHAR2(20) := 'ID';
  K_VLD_CODE           VARCHAR2(20) := 'CODE';
  K_VLD_CODE_CHILD     VARCHAR2(20) := 'CODE_C';
  K_VLD_CODE_PARENT    VARCHAR2(20) := 'CODE_P'; 
 
 
  K_CAT_C_EXP           VARCHAR2(10) := 'CODEXP';
  K_CAT_C_EXP_UNC       VARCHAR2(10) := 'UNC';
  K_CAT_C_EXP_RCN       VARCHAR2(10) := 'RNC';
  K_CAT_C_EXP_DSC       VARCHAR2(10) := 'DSC';
    
  K_CAT_C_GSANGUINEO    VARCHAR2(10) := 'GSANG';
  K_CAT_C_ETNIA         VARCHAR2(10) := 'ETNIA';
  --K_CAT_C_RELIGIONES    VARCHAR2(10) := 'RELIGIONES';
  K_CAT_C_RELIGIONES    VARCHAR2(10) := 'HSF_RELIG';  

  --K_CAT_C_ST_CIVIL      VARCHAR2(20) := 'ESTADO CIVIL';
  K_CAT_C_ST_CIVIL      VARCHAR2(20) := 'ESTCV';
  --K_CAT_C_OCUPACION     VARCHAR2(10) := 'HSF_OCUPA';
  K_CAT_C_OCUPACION     VARCHAR2(15) := 'OCUPACIONES';
  
  
  K_CAT_C_EST_PRCS   VARCHAR2(10) := 'ESTADOS';
  K_CAT_C_EST_PRCS_INICIADO VARCHAR2(5) := 'I';
  K_CAT_C_EST_PRCS_PROGRAMADO VARCHAR2(5) := 'P';
  K_CAT_C_EST_PRCS_FINALIZADO VARCHAR2(5) := 'F';
  
  K_LKPX_EXP_ELT        VARCHAR2(10) := 'EXPELCT';
  K_LKPX_CED_NIC        VARCHAR2(10) := 'CEDNCRG';
  K_LKPX_EXP_LOC        VARCHAR2(10) := 'EXPLCLS';
  
  K_LKPX_TP_IDNT        VARCHAR2(11) := 'PXSRCHDCTPS'; 
  
  K_CAT_UND_SLD         VARCHAR2(20) := 'UND_SALUD'; 
  
  K_CAT_PROGRAMS        VARCHAR2(20) := 'PRGRM';
  K_CAT_CRCT            VARCHAR2(10)  := 'CRCPX';
  K_CAT_FINANCIAMIENTO  VARCHAR2(20) := 'FINANCIAMNTOS';
  K_CAT_IDNTF_PX        VARCHAR2(10) := 'IDNPX';
  K_CAT_IDNTF_PRS        VARCHAR2(10) := 'TPIDNTF';
  K_CAT_TPO_RESIDENCIA  VARCHAR2(20) := 'TPRESIDENC';
  K_CAT_TPO_CONTACTOS   VARCHAR2(20) := 'TPRELACION';

  kIDENTIF_CEDULA_NIC   CHAR(3) := 'CED';
  kIDENTIF_PASPORTE     CHAR(3) := 'PAS';
  
 FUNCTION FN_VALIDAR_USUARIO (pUsuario IN VARCHAR2) RETURN BOOLEAN;  
 FUNCTION FN_OBT_ESTADO_REGISTRO (pValor IN CATALOGOS.SBC_CAT_CATALOGOS.VALOR%TYPE) RETURN NUMBER;
 PROCEDURE PR_FORMATEO_NOMBRES (pPrimerNombre    IN OUT CATALOGOS.SBC_MST_PERSONAS.PRIMER_NOMBRE%TYPE,
                                pSegundoNombre   IN OUT CATALOGOS.SBC_MST_PERSONAS.SEGUNDO_NOMBRE%TYPE,
                                pPrimerApellido  IN OUT CATALOGOS.SBC_MST_PERSONAS.PRIMER_APELLIDO%TYPE,
                                pSegundoApellido IN OUT CATALOGOS.SBC_MST_PERSONAS.SEGUNDO_APELLIDO%TYPE);
                                
 PROCEDURE PR_FORMATEAR_PARAMETROS (pIdentificacion  IN OUT VARCHAR2,
                                    pNombreCompleto  IN OUT VARCHAR2,
                                    pPrimerNombre    IN OUT VARCHAR2,
                                    pSegundoNombre   IN OUT VARCHAR2,
                                    pPrimerApellido  IN OUT VARCHAR2,
                                    pSegundoApellido IN OUT VARCHAR2,
                                    pResultado       OUT VARCHAR2,
                                    pMsgError        OUT VARCHAR2);
 PROCEDURE PR_VALIDA_RANGO_FECHA (pFechaInicio IN DATE,
                                  pFechaFin    IN DATE,
                                  pResultado   OUT VARCHAR2,
                                  pMsgError    OUT VARCHAR2);
                                  
                                  
 FUNCTION FN_OBT_EDAD ( pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,					  
                            pFecVacuna       IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE
				          ) RETURN VARCHAR ; 

FUNCTION FN_OBT_VACUNA_PROXIMA_CITA ( pExpedienteId    IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE					  
				          ) RETURN VARCHAR ; 

FUNCTION FN_CALCULAR_ESTADO_ACTUALIZACION_VACUNA (  pControlVacunaId    IN SIPAI.SIPAI_DET_VACUNACION.CONTROL_VACUNA_ID%TYPE,					  
                                                    pFecVacuna          IN SIPAI.SIPAI_DET_VACUNACION.FECHA_VACUNACION%TYPE,
                                                    pNoAplicada		   IN SIPAI.SIPAI_DET_VACUNACION.NO_APLICADA%TYPE, 
                                                    pUniSaludActualizacionId  IN SIPAI.SIPAI_DET_VACUNACION.UNIDAD_SALUD_ACTUALIZACION_ID%TYPE,	
                                                    pIdRelTipoVacunaEdad  IN SIPAI.SIPAI_DET_VACUNACION.REL_TIPO_VACUNA_EDAD_ID%TYPE
                                           )  RETURN NUMBER ;
                                           
FUNCTION  FN_OBTENER_CURSOR_VACUNAS_PROXIMA_CITA (pExpedienteId IN PLS_INTEGER 
                                        ) RETURN var_refcursor ;
                                        
PROCEDURE PR_REGISTRO_DET_ROXIMA_CITA (pExpedienteId  NUMBER, pResultado   OUT VARCHAR2,  pMsgError    OUT VARCHAR2);
                                  
                          
                          
                                  
 
END PKG_SIPAI_UTILITARIOS;
/