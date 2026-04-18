CREATE OR REPLACE PACKAGE SIPAI."PKG_SIPAI_RPT_VACUNACION" 
AS

/*
  Proyecto    : SIPAI
  Módulo      : Reportes de Vacunación
  Fecha Cambio: 13/04/2026
  Autor       : ematamoros
  Descripción : Modificacion en REPORTE_TARJETA_VACUNACION Que solo presente la ultima Dosis de vacunas COVID
*/
   
   TYPE var_refcursor IS REF CURSOR;
   TYPE reg_madre IS RECORD (expedienteId NUMBER(10),nombre VARCHAR2(100));
   
   eParametrosInvalidos EXCEPTION;

PROCEDURE REPORTE_FECHA_PROXIMA_CITA (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                     pRegistro     OUT var_refcursor
									);
                                    
PROCEDURE MENSAJE_FECHA_PROXIMA_CITA (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                     pRegistro     OUT var_refcursor
									);                                    
                                    

PROCEDURE ESQUEMA_VACUNACION (pRegistro OUT var_refcursor);

PROCEDURE REPORTE_ESQUEMA_VACUNACION (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                      pRegistro       OUT CLOB
									);

PROCEDURE REPORTE_TARJETA_VACUNACION (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                      pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                      pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
								      pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
									  pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                      pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,  
                                      pMsgError        OUT VARCHAR2, 
                                      pResultado       OUT VARCHAR2,                           
                                      pRegistro        OUT CLOB
                                      );
  /*Procedimiento para devolve el objeto json en un cursor para crear el reporte en jaspe report*/                                    
PROCEDURE PR_CONSULTA_TARJETA_VACUNACION(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                         pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                         pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
								         pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
									     pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                         pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                         
                                         pMsgError        OUT VARCHAR2, 
                                         pResultado       OUT VARCHAR2, 
                                         pRegistro        OUT sys_refcursor
                                      );
  --Se genero este procedure para separar vacunas de suplemento para verlo en sub reporte jasper                                   
PROCEDURE PR_CONSULTA_TARJETA_VACUNACION_SUPLEMENTO(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                         pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                         pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
								         pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
									     pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                         pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,                         
                                         pMsgError        OUT VARCHAR2, 
                                         pResultado       OUT VARCHAR2, 
                                         pRegistro        OUT sys_refcursor
                                      );
                                      
                                      
                                      
                                      
                                      
                                      
                                      
                                                                                          
PROCEDURE PR_INSERT_SIPAI_CTRL_DOCUMENTOS_VACUNA (pControlDocumentoId IN  OUT NUMBER,
                                                  pExpedienteId       IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                                  pTipoDocumento      IN VARCHAR2,
                                                  pPrefijoCodigoDoc   IN VARCHAR2,
                                                  pUniSaludId      IN CATALOGOS.SBC_CAT_UNIDADES_SALUD.UNIDAD_SALUD_ID%TYPE,
                                                  pDepartamentoId  IN CATALOGOS.SBC_CAT_DEPARTAMENTOS.DEPARTAMENTO_ID%TYPE,
                                                  pMunicipioId     IN CATALOGOS.SBC_CAT_MUNICIPIOS.MUNICIPIO_ID%TYPE,  
                                                  pSistemaId       IN SEGURIDAD.SCS_CAT_SISTEMAS.SISTEMA_ID%TYPE,
                                                  pUsuario         IN SEGURIDAD.SCS_MST_USUARIOS.USERNAME%TYPE,  
                                                  pMsgError        OUT VARCHAR2, 
                                                  pResultado       OUT VARCHAR2);
                                                  
PROCEDURE PR_CONSULTAR_SIPAI_CTRL_DOCUMENTOS_VACUNA (pCodigoRandom     IN VARCHAR2,
                                                     pMsgError        OUT VARCHAR2, 
                                                     pResultado       OUT VARCHAR2,                           
                                                     pRegistro        OUT CLOB
                                      );        
 

PROCEDURE REPORTE_PERSONA_MADRE (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                      pRegistro OUT CLOB);

PROCEDURE REPORTE_PERSONA_HERMANO (pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE,
                                      pRegistro OUT CLOB);
                                      
FUNCTION FN_FECHA_PROXIMA_CITA(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE ) RETURN  VARCHAR2;  
FUNCTION FN_FECHA_PROXIMA_CITA_dT(pExpedienteId IN SIPAI.SIPAI_MST_CONTROL_VACUNA.EXPEDIENTE_ID%TYPE ) RETURN  VARCHAR2;

PROCEDURE LISTA_REPORTE_SIPAI (pRegistro OUT var_refcursor);

END PKG_SIPAI_RPT_VACUNACION;
/