CREATE OR REPLACE PACKAGE SIPAI."PKG_SIPAI_CONSULTA_REGISTRO_NOMINAL" AS
  
  TYPE var_refcursor IS REF CURSOR;

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

  PROCEDURE SIPAI_CONSULTA_MASTER (        pFiltro          IN NUMBER,
                                           pFechaInicio     IN VARCHAR2,
                                           pFechaFin        IN VARCHAR2,
                                           pIdentificacion  IN VARCHAR2,
                                           pPrimerNombre    IN VARCHAR2,
                                           pSegundoNombre   IN VARCHAR2,
                                           pPrimerApellido  IN VARCHAR2,
                                           pSegundoApellido IN VARCHAR2,
                                           pProgramaId      IN NUMBER,
                                           pTipoAmbito      IN NUMBER,
                                           pPgnAct          IN NUMBER DEFAULT 1, 
                                           pPgnTmn          IN NUMBER DEFAULT 100, 
                                           listaUnidadesSalud IN VARCHAR2,
                                           pRelTipoVacuna      IN NUMBER,
                                           ---------------------------------
                                           pRegistro        OUT var_refcursor,
                                           pResultado       OUT VARCHAR2,
                                           pMsgError        OUT VARCHAR2,
                                           pCantRegistros   OUT NUMBER
                                             );

  PROCEDURE SIPAI_CONSULTA_DETALLE        (pControlVacunaId  IN NUMBER,
                                           pExpedienteId  IN NUMBER,
                                           pProgramaId      IN NUMBER,
										   pFiltro          IN NUMBER,
                                          --------------------------------- 
                                           pRegistro        OUT var_refcursor,                       
                                           pResultado       OUT VARCHAR2,                       
                                           pMsgError        OUT VARCHAR2);


END PKG_SIPAI_CONSULTA_REGISTRO_NOMINAL;

/*
  Notas Numero Filtros Para el Maste
        1. Rangos de Fecha
        2. Identificacion
        3. Primer Nombre y Primer Apellido
        4. Primer Nombre y Dos Apellido
        5. Dos Nombre y Dos Apellido
        6. Dos Nombre y Primer Apellido.

           Parametro Adicional pTipoAmbito
             Valor Null  Todos los ambito
             Valor    1  Ambito Vacuna
             Valor    2  Ambito Vitaminas
             Valor    3  Ambito Desparacitantes
*/
/