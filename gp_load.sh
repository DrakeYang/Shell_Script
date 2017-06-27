#!/bin/ksh
################################################################################
#                                                                              #
#  Shell name  : load_gp.sh
#                                                                              #
#  Description : Greenplum gpload를 이용하여 Target Table 적재 및 추가 옵션을 실행한다.
#                                                                              #
#  example     : load_gp.sh [options] Target_Table
#                                                                              #
################################################################################
#                                                                              #
#  Change Description.                                                         #
#  --------------------------------------------------------------------------- #
#  Date       Author   Ver    Description                                      #
#  +--------- +------  +----- +----------------------------------------------- #
#  2016.06.29 DFIBiz   0.11   DataStage 11.3.1.2 for Linux Upgrade             #
#  2012.07.12 DFIBiz   0.10   Initial Release                                  #
#                                                                              #
################################################################################

#-------------------------------------------------------------------------------
#   Function : func_PrintUsage -> 사용방법 출력
#-------------------------------------------------------------------------------
func_PrintUsage()
{
    typeset Exit_Code=$1

    echo "
  Usage : load_gp.sh [options] Target_Table

  Greenplum gploader를 이용하여 datafile을 Target_Table에 적재한다.

  Options:
  -h                Show this help and exit.

  -e                Delete_SQL(= del_타겟테이블.sql )을 이용하여 타겟테이블의 데이터를 삭제
                    자동으로 -T 옵션 설정됨

  -b sql_script     gpload 실행 전 수행할 SQL Script를 지정 (예 : JOB_NAME_before.sql )

  -a sql_script     gpload 실행 후 수행할 SQL Script를 지정 (예 : JOB_NAME_after.sql )

  -T                타겟테이블을 Truncate 하지 않음 ( Default : 타겟테이블 Truncate & Load )

  -p parameters     -e, -b, -a 옵션의 SQL Script에서 사용된 Parameters의 값을 전달한다. 여러 개인 경우 ,로 구분한다.
                    -p 옵션 있는 경우, 전달된 옵션_Argument를 기준으로 :파라미터명 → 파라미터값 으로 치환하여 실행
                    -p 옵션 없는 경우, DSParams 참조하여 :파라미터명 → $PROJDEF값 으로 치환하여 실행

  -u table          타겟테이블에 적재한 데이터를 이용하여 Upsert(= PK Join Delete & Insert)할 테이블을 지정
                    단, 타겟테이블과 Upsert할 테이블의 layout은 동일해야 함

  -i table          -u 옵션에서 PK Join Delete를 하지 않으며, Not Matched 데이터(= Left Outer Join & Is Null )만 적재함
                    단, 타겟테이블과 Upsert할 테이블의 layout은 동일해야 함

  -n null_char      데이터값이 NULL임을 지정하는 문자를 지정 ( Default : '' )

  -x                Fixed Length 방식으로 load 실행함 ( Default : Delimiter 방식, 구분자 : \x03 → '' )

  -f files          적재할 data file을 지정한다. 여러개인 경우 ,로 구분하여 나열

  -l error_limit    gpload yml 옵션 중 ERROR_LIMIT 값을 설정 ( Default : 1000, 0 지정시 ERROR_TABLE 옵션도 삭제됨 )

  -D directory      data file이 위치한 디렉토리를 절대경로로 지정

  Examples:
    load_gp.sh dw_supp_plan
    load_gp.sh -u dw_supp_plan -f dw_supp_plan1,dw_supp_plan2 dw_supp_pland_load
"

    exit $Exit_Code
}

#-------------------------------------------------------------------------------
#   Function : func_PrintLog -> 로그파일에 기록
#-------------------------------------------------------------------------------
func_PrintLog()
{
    echo "$*" >> $Log_File
}

#-------------------------------------------------------------------------------
#   Function : func_RunSQL -> SQL_File 실행
#-------------------------------------------------------------------------------
func_RunSQL()
{
    typeset SQL_File=$1
    typeset Target_Schema=$2
    typeset Exit_Code

    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ Run SQL Script ] psql Start --> $SQL_File"
    func_PrintLog "*-----------------------------------------------------------------------------*/"

    if [[ $Option_Argument = "" ]]; then
        $Run_SQL_Shell $SQL_File $Target_Schema >> $Log_File 2>&1
    else
        $Run_SQL_Shell -p "$Option_Argument" $SQL_File $Target_Schema >> $Log_File 2>&1
    fi

    Exit_Code=$?

    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ Run SQL Script ] psql End --> $SQL_File"
    func_PrintLog "*-----------------------------------------------------------------------------*/"

    #---------------------------------------------------------------------------
    #   SQL 실행 중 오류인 경우, 해당 오류코드로 Exit
    #---------------------------------------------------------------------------
    if [[ $Exit_Code != 0 ]]; then
         exit $Exit_Code
    fi
}

#-------------------------------------------------------------------------------
#   Function : func_RunGpLoad -> gpload 실행
#-------------------------------------------------------------------------------
func_RunGpLoad()
{
    typeset YML_File=$1
    typeset -i Error_Count
    typeset Exit_Code

    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ gpload ] Start"
    func_PrintLog "*-----------------------------------------------------------------------------*/"
    func_PrintLog ""
    func_PrintLog "    Command Line ▶ $Run_GP_Load $YML_File"
    func_PrintLog ""

    $Run_GP_Load $YML_File >> $Log_File 2>&1

    Exit_Code=$?

    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ gpload ] End."
    func_PrintLog "*-----------------------------------------------------------------------------*/"


    #---------------------------------------------------------------------------
    #   gpload 실행 중 오류인 경우, 해당 오류코드로 Exit
    #---------------------------------------------------------------------------
    if [[ $Exit_Code != 0 ]]; then
        func_PrintLog "/*------------------------------------------------------------------------------"
        func_PrintLog "*  [ Error ] gpload RETURN Code != 0"
        func_PrintLog "*-----------------------------------------------------------------------------*/"

        exit $Exit_Code
    fi
}

#-------------------------------------------------------------------------------
#   Function : func_IsInvalidTableCatalog -> Table이 Catalog에서 정상인지 체크
#
#   return 0 -> Table의 Catalog 변경 있음
#   return 1 -> Table의 Catalog 변경 없으며, 이전 Catalog와 동일함
#-------------------------------------------------------------------------------
func_IsInvalidTableCatalog()
{
    typeset Target_Table_Lower=$1
    typeset Curr_Catalog="/tmp/$Target_Table_Lower.$$.curr"
    typeset Prev_Catalog="/tmp/$Target_Table_Lower.$$.prev"

    grep ^$Target_Table_Lower\| $GP_Catalog_Curr > $Curr_Catalog
    grep ^$Target_Table_Lower\| $GP_Catalog_Prev > $Prev_Catalog

    #---------------------------------------------------------------------------
    #   현재 Catalog 정보 중 Target_Table_Lower 없다면, Table의 Catalog 변경 있음
    #---------------------------------------------------------------------------
    Catalog_Row_Cnt=`wc -l $Curr_Catalog | cut -d'/' -f1 | sed -e"s/ //g"`

    if [[ $Catalog_Row_Cnt -eq 0 ]]; then
        rm -f $Curr_Catalog $Prev_Catalog
        return 0
    fi

    #---------------------------------------------------------------------------
    #   현재 Catalog와 이전 Catalog 정보가 다르면, Table의 Catalog 변경 있음
    #---------------------------------------------------------------------------
    diff $Curr_Catalog $Prev_Catalog > /dev/null 2>&1

    if [[ $? != 0 ]]; then
        rm -f $Curr_Catalog $Prev_Catalog
        return 0
    fi

    rm -f $Curr_Catalog $Prev_Catalog

    return 1
}

#-------------------------------------------------------------------------------
#   Function : func_IsNeedMakeLoadScript -> Load_Script를 다시 생성할 필요가 있는지 체크
#
#   전제조건: BATCH 작업 시작시 한번씩 GP_Catalog_Curr(= gp_col_info.curr )를 갱신한다.
#
#   return 0 -> ( Load_script 재생성     ) Table의 Catalog 변경 있음
#   return 1 -> ( Load_script 재생성 안함) Table의 Catalog 변경 없으며, 이전 Catalog와 동일함
#-------------------------------------------------------------------------------
func_IsNeedMakeLoadScript()
{
    typeset Load_Script=$1
    typeset Target_Table_Lower=$2
    typeset Load_Script_Fprint=$3
    typeset Load_Script_Prev_Fprint="/tmp/$Target_Table_Lower.$$.finger"
    typeset Need_to_Make=1

    #---------------------------------------------------------------------------
    #   Load_script 없으면, Load_script 생성
    #---------------------------------------------------------------------------
    if [[ ! -f $Load_Script ]]; then
        return 0
    fi

    #---------------------------------------------------------------------------
    #   Load_script 존재하고, Greenplum Catalog 정보가 없으면, Load_script 재생성
    #---------------------------------------------------------------------------
    if [[ ! -f $GP_Catalog_Curr ]]; then
        return 0
    fi

    #---------------------------------------------------------------------------
    #   Load_script 존재하고, 이전 Catalog 정보가 존재 --> Catalog 변경 여부 판단
    #---------------------------------------------------------------------------
    func_IsInvalidTableCatalog $Target_Table_Lower

    if [[ $? = 0 ]]; then
        return 0
    fi

    return $Need_to_Make
}

#-------------------------------------------------------------------------------
#   Function : func_MakeLoadScript_Delimiter -> 구분자 방식 기준. gpload YML 파일 생성
#-------------------------------------------------------------------------------
func_MakeLoadScript_Delimiter()
{
    typeset Load_Script=$1
    typeset Target_Table_Lower=$2
    typeset Load_Script_Fprint=$3
    typeset Curr_Catalog="/tmp/$Target_Table_Lower.$$.curr"
    typeset Temp_Script="$Load_Script.$$.tmp"


    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ Make YML Script ] $Load_Script"
    func_PrintLog "*-----------------------------------------------------------------------------*/"
    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Make load script Start."

    #---------------------------------------------------------------------------
    #   $Target_Table_Lower 테이블의 컬럼정보를 $Curr_Catalog 파일로 생성함
    #---------------------------------------------------------------------------
    func_GetColumnInfo $Target_Table_Lower $Curr_Catalog

    #---------------------------------------------------------------------------
    #   Catalog 정보 예
    #---------------------------------------------------------------------------
    #   table_name, column_id, column_name, data_type_full, data_type_org, data_type_alias, data_length_full, data_length, data_scale, data_display, pk_yn, null_yn, dk_yn
    #---------------------------------------------------------------------------
    #   dw_etl_test_01|1|char_1|character(10)|character|character|(10)|10|0|10|Y|N|Y
    #   dw_etl_test_01|2|varchar_1|character varying(10)|character varying|varchar|(10)|10|0|10|Y|N|N
    #   dw_etl_test_01|3|numeric_1|numeric(10,0)|numeric|numeric|(10,0)|10|0|12|Y|N|N
    #   dw_etl_test_01|4|varchar_2|character varying(20)|character varying|varchar|(20)|20|0|20|N|Y|N
    #---------------------------------------------------------------------------

    ############################################################################
    #   [ 헤더 영역 ]
    ############################################################################
    cat <<EOF >> $Temp_Script
VERSION: 1.0.0.1
DATABASE: ${GP_DB}
USER: ${GP_LOAD_USER}
HOST: ${GP_HOST}
PORT: ${GP_PORT}
GPLOAD:
EOF

    ############################################################################
    #   [ INPUT: 영역 ] load 대상파일 형식 지정
    ############################################################################
    #---------------------------------------------------------------------------
    #   [     - SOURCE: 영역 ]
    #---------------------------------------------------------------------------
    cat <<EOF >> $Temp_Script
    INPUT:
        - SOURCE:
            LOCAL_HOSTNAME:
                - ${GP_LOCAL_HOST}
            PORT_RANGE: [${GP_PORT_RANGE}]
EOF

    #---------------------------------------------------------------------------
    #   파일명 목록 나열
    #---------------------------------------------------------------------------
    echo -n "            FILE: [ " >> $Temp_Script

    typeset -i Data_File_List_Len=${#Data_File_List[*]}
    typeset -i j=0

    while [[ $j -lt $Data_File_List_Len ]]
    do
        FILE=${Data_File_List[$j]}

        echo -n "${FILE}" >> $Temp_Script

        j=$((j + 1))

        if [[ $j -lt $Data_File_List_Len ]]; then
            echo -n ", " >> $Temp_Script
        fi
    done
    echo " ]" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   [     - COLUMNS: 영역 ] 파일에 대한 컬럼 목록 생성
    #---------------------------------------------------------------------------
    echo "        - COLUMNS:" >> $Temp_Script

    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "GPLOAD_COLUMNS" >> $Temp_Script
    done

    #---------------------------------------------------------------------------
    #   [     - FORMAT: ~ - ERROR_TABLE: 영역 ] 구분자, 널문자, 에러테이블 등등
    #---------------------------------------------------------------------------
    cat <<EOF >> $Temp_Script
        - FORMAT: csv
        - DELIMITER: "\x03"
        - NULL_AS: '$Null_Character'
        - QUOTE: '"'
        - ENCODING: 'UTF8'
EOF

    #---------------------------------------------------------------------------
    #   ERROR_LIMIT = 0 이면 ERROR_TABLE 설정하지 않음
    #---------------------------------------------------------------------------
    if [[ $GP_ERROR_LIMIT -eq 0 ]]; then
    cat <<EOF >> $Temp_Script
        - ERROR_LIMIT: ${GP_ERROR_LIMIT}
EOF
    else
    cat <<EOF >> $Temp_Script
        - ERROR_LIMIT: ${GP_ERROR_LIMIT}
        - ERROR_TABLE: ${GP_ERROR_TABLE}
EOF
    fi

    ############################################################################
    #   [ OUTPUT: 영역 ] 타겟 테이블 및 컬럼 매핑 지정
    ############################################################################
    echo "    OUTPUT:" >> $Temp_Script
    echo "        - TABLE: ${Target_Schema}.${GP_LOAD_TABLE}" >> $Temp_Script
    echo "        - MODE: INSERT" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   [     - MAPPING: 영역 ] 파일 컬럼 목록에 대한 테이블 컬럼 매핑 생성
    #---------------------------------------------------------------------------
    echo "        - MAPPING:" >> $Temp_Script

    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "GPLOAD_MAPPING" >> $Temp_Script
    done

    ############################################################################
    #   [ PRELOAD: 영역 ] gpload 내부적으로 external table drop 시 waiting 발생하지 않도록 옵션 추가
    ############################################################################
    echo "    PRELOAD:" >> $Temp_Script
    echo "        - REUSE_TABLES: TRUE" >> $Temp_Script

    ############################################################################
    #   [ SQL: 영역 ] gpload BEFORE, AFTER 실행 ( 사용 필요 시 )
    ############################################################################
    # echo "    SQL:" >> $Temp_Script
    # echo "        - BEFORE: \"DELETE FROM ; \"" >> $Temp_Script
    #---------------------------------------------------------------------------

    #---------------------------------------------------------------------------
    #   12. Load Script 생성 마무리
    #---------------------------------------------------------------------------
    rm -f $Curr_Catalog

    mv $Temp_Script $Load_Script

    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Make load script End."
}

#-------------------------------------------------------------------------------
#   Function : func_gpfdistDaemonStart -> Greenplum gpfdist 데몬 Start for Fixed
#-------------------------------------------------------------------------------
func_gpfdistDaemonStart()
{
    typeset -i Daemon_Cnt Error_Cnt
    typeset Command_Output

    #---------------------------------------------------------------------------
    #   gpfdist 데몬이 존재하지 않는 경우, ETL 서버 디렉토리, 포트에 대하여 데몬 Start
    #---------------------------------------------------------------------------
    Daemon_Cnt=`ps -ef | grep gpfdist | grep $GPFDIST_PORT | grep $Data_Directory | wc -l`

    if [[ $Daemon_Cnt -eq 0 ]]; then
        Command_Output=`gpfdist -d $Data_Directory -p $GPFDIST_PORT &`

        Error_Cnt=`echo $Command_Output | grep ERROR | wc -l`

        if [[ $Error_Cnt -gt 0 ]]; then
            echo "[$0] gpfdist daemon start error. [ gpfdist -d $Data_Directory -p $GPFDIST_PORT & ]"
            exit 3
        fi
    fi
}

#-------------------------------------------------------------------------------
#   Function : func_MakeLoadScript_Fixed -> 고정길이 방식 기준. EXTERNAL TABLE 생성 및 타겟 테이블 INSERT ~ SELECT 스크립트 생성
#-------------------------------------------------------------------------------
func_MakeLoadScript_Fixed()
{
    typeset Load_Script=$1
    typeset Target_Table_Lower=$2
    typeset Load_Script_Fprint=$3
    typeset Curr_Catalog="/tmp/$Target_Table_Lower.$$.curr"
    typeset Temp_Script="$Load_Script.$$.tmp"

    typeset External_Table="${GP_TEMP_SCHEMA}.ext_${Target_Table_Lower}"


    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Make CREATE READABLE EXTERNAL TABLE script Start [$Load_Script] ..."

    #---------------------------------------------------------------------------
    #   $Target_Table_Lower 테이블의 컬럼정보를 $Curr_Catalog 파일로 생성함
    #---------------------------------------------------------------------------
    func_GetColumnInfo $Target_Table_Lower $Curr_Catalog

    #---------------------------------------------------------------------------
    #   Catalog 정보 예
    #---------------------------------------------------------------------------
    #   table_name, column_id, column_name, data_type_full, data_type_org, data_type_alias, data_length_full, data_length, data_scale, data_display, pk_yn, null_yn, dk_yn
    #---------------------------------------------------------------------------
    #   dw_etl_test_01|1|char_1|character(10)|character|character|(10)|10|0|10|Y|N|Y
    #   dw_etl_test_01|2|varchar_1|character varying(10)|character varying|varchar|(10)|10|0|10|Y|N|N
    #   dw_etl_test_01|3|numeric_1|numeric(10,0)|numeric|numeric|(10,0)|10|0|12|Y|N|N
    #   dw_etl_test_01|4|varchar_2|character varying(20)|character varying|varchar|(20)|20|0|20|N|Y|N
    #---------------------------------------------------------------------------

    #---------------------------------------------------------------------------
    #   1. echo generation info.
    #---------------------------------------------------------------------------
    Current_Timestamp=`date +"%Y-%m-%d %H:%M:%S"`

    echo "/*" >> $Temp_Script
    echo "* Generated by load_gp.sh at $Current_Timestamp " >> $Temp_Script
    echo "*/" >> $Temp_Script
    echo "" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   2. Transaction Start
    #---------------------------------------------------------------------------
    echo "begin;  " >> $Temp_Script
    echo "" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   3. DROP EXTERNAL TABLE
    #---------------------------------------------------------------------------
    echo "/*----------------------------------------------------------" >> $Temp_Script
    echo "* 1. DROP EXTERNAL TABLE " >> $Temp_Script
    echo "*---------------------------------------------------------*/" >> $Temp_Script
    echo "DROP EXTERNAL TABLE if exists ${External_Table} ;" >> $Temp_Script
    echo "" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   4. header -> CREATE READABLE EXTERNAL TABLE ~~~
    #---------------------------------------------------------------------------
    echo "/*----------------------------------------------------------" >> $Temp_Script
    echo "* 2. CREATE READABLE EXTERNAL TABLE " >> $Temp_Script
    echo "*---------------------------------------------------------*/" >> $Temp_Script
    echo "CREATE READABLE EXTERNAL TABLE ${External_Table}" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   5. COLUMN 목록 선언 -> EXTERNAL TABLE에 대한 컬럼 목록 생성
    #---------------------------------------------------------------------------
    echo "(" >> $Temp_Script

    #---------------------------------------------------------------------------
    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "EXTERNAL_COLUMN" >> $Temp_Script
    done
    #---------------------------------------------------------------------------

    echo ")" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   6. LOCATION ~ file 선언
    #---------------------------------------------------------------------------
    echo -n "LOCATION (" >> $Temp_Script

    typeset -i Data_File_List_Len=${#Data_File_List[*]}
    typeset -i j=0

    while [[ $j -lt $Data_File_List_Len ]]
    do
        FILE=${Data_File_List[$j]}
        FILE_REV=`echo $FILE | rev`

        First_Pos_Delimiter=`expr index $FILE_REV "\/"`
        Data_File=`expr substr $FILE_REV 1 $First_Pos_Delimiter | rev`

        echo -n "'gpfdist://${GP_LOCAL_HOST}:${GPFDIST_PORT}/${Data_File}'" >> $Temp_Script

        j=$((j + 1))

        if [[ $j -lt $Data_File_List_Len ]]; then
            echo -n ", " >> $Temp_Script
        fi
    done

    echo ")" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   7. FORMAT
    #---------------------------------------------------------------------------
    echo "FORMAT 'CUSTOM' " >> $Temp_Script
    echo "(     " >> $Temp_Script
    echo "        formatter=fixedwidth_in" >> $Temp_Script

    #---------------------------------------------------------------------------
    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "EXTERNAL_FORMAT" >> $Temp_Script
    done
    #---------------------------------------------------------------------------

    echo "      , preserve_blanks='off'" >> $Temp_Script
    echo "      , null='$Null_Character'" >> $Temp_Script
    echo ")" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   8. footer -> EXTERNAL TABLE 선언 종료
    #---------------------------------------------------------------------------
    echo "ENCODING='UTF8'" >> $Temp_Script
    echo "LOG ERRORS INTO ${GP_ERROR_TABLE} SEGMENT REJECT LIMIT 10 ROWS;" >> $Temp_Script
    echo "" >> $Temp_Script

    echo "/*----------------------------------------------------------" >> $Temp_Script
    echo "* 4. INSERT INTO Target_TABLE ~ SELECT External_TABLE " >> $Temp_Script
    echo "*---------------------------------------------------------*/" >> $Temp_Script
    echo "INSERT INTO ${Target_Schema}.${GP_LOAD_TABLE}" >> $Temp_Script
    echo "(" >> $Temp_Script

    #---------------------------------------------------------------------------
    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "INSERT_SELECT" >> $Temp_Script
    done
    #---------------------------------------------------------------------------

    echo ")" >> $Temp_Script
    echo "SELECT  " >> $Temp_Script

    #---------------------------------------------------------------------------
    grep ^$Target_Table_Lower\| $Curr_Catalog | while read LINE
    do
        func_MakeColumnsClause "$LINE" "NULLIF_RTRIM" >> $Temp_Script
    done
    #---------------------------------------------------------------------------

    echo "  FROM  " >> $Temp_Script
    echo "        ${External_Table} ;" >> $Temp_Script
    echo "" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   9. Transaction End
    #---------------------------------------------------------------------------
    echo "end;  " >> $Temp_Script

    #---------------------------------------------------------------------------
    #   10. Load Script 생성 마무리
    #---------------------------------------------------------------------------
    rm -f $Curr_Catalog

    echo "/* __end__ */" >> $Temp_Script

    mv $Temp_Script $Load_Script

    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Make load script End [$Load_Script]."
}


#-------------------------------------------------------------------------------
#   Function : func_MakeColumnsClause -> 컬럼 목록 유형별 출력
#-------------------------------------------------------------------------------
func_MakeColumnsClause()
{
    typeset Column_Spec="$1"
    typeset Print_Type="$2"
    typeset column_id column_name data_type_full data_width

    #---------------------------------------------------------------------------
    #   Catalog 정보 예
    #---------------------------------------------------------------------------
    #   table_name, column_id, column_name, data_type_full, data_type_org, data_type_alias, data_length_full, data_length, data_scale, data_display, pk_yn, null_yn, dk_yn
    #---------------------------------------------------------------------------
    #   dw_etl_test_01|1|char_1|character(10)|character|character|(10)|10|0|10|Y|N|Y
    #   dw_etl_test_01|2|varchar_1|character varying(10)|character varying|varchar|(10)|10|0|10|Y|N|N
    #   dw_etl_test_01|3|numeric_1|numeric(10,0)|numeric|numeric|(10,0)|10|0|12|Y|N|N
    #   dw_etl_test_01|4|varchar_2|character varying(20)|character varying|varchar|(20)|20|0|20|N|Y|N
    #---------------------------------------------------------------------------

    IFS_ORIG=$IFS
    IFS=\|

    typeset -i i=1

    for FIELD in $Column_Spec
    do
        case $i in
        2) column_id="$FIELD" ;;
        3) column_name="$FIELD" ;;
        4) data_type_full="$FIELD" ;;
        5) data_type_org="$FIELD" ;;
        10) data_display="$FIELD" ;;
        12) null_yn="$FIELD" ;;
        *) ;;
        esac

        i=$((i + 1))
    done

    IFS=$IFS_ORIG

    #---------------------------------------------------------------------------
    #   출력 유형별 echo
    #---------------------------------------------------------------------------
    if [[ $Print_Type = "EXTERNAL_COLUMN" ]]; then
        if [[ $column_id -eq 1 ]]; then
            echo "        ${column_name} ${data_type_full}"
        else
            echo "      , ${column_name} ${data_type_full}"
        fi

    elif [[ $Print_Type = "EXTERNAL_FORMAT" ]]; then
        echo "      , ${column_name}=${data_display}"

    elif [[ $Print_Type = "INSERT_SELECT" ]]; then
        if [[ $column_id -eq 1 ]]; then
            echo "        ${column_name}"
        else
            echo "      , ${column_name}"
        fi

    elif [[ $Print_Type = "NULLIF_RTRIM" ]]; then
        if [[ $column_id -eq 1 ]]; then
            if [[ $null_yn = "N" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
                echo "            coalesce(rtrim(${column_name}), '${Null_Character}')"
            elif [[ $null_yn = "Y" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
                echo "            rtrim(${column_name})"
            else
                echo "            ${column_name}"
            fi
        else
            if [[ $null_yn = "N" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
                echo "          , coalesce(rtrim(${column_name}), '${Null_Character}')"
            elif [[ $null_yn = "Y" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
                echo "          , rtrim(${column_name})"
            else
                echo "          , ${column_name}"
            fi
        fi

    elif [[ $Print_Type = "GPLOAD_COLUMNS" ]]; then
        echo "            - ${column_name}: ${data_type_full}"

    elif [[ $Print_Type = "GPLOAD_MAPPING" ]]; then
        #-----------------------------------------------------------------------
        #   EDW의 경우, 문자 데이터이면서 Not Null 컬럼이면, coalesce() 실행하여 NULL 대신할 문자가 들어가도록 처리함
        #   2012-10-25. 숫자 컬럼값이 ''인 경우, Sybase -> Null로 적재되므로, case when ascii(rtrim())=0 then NULL ~ 추가함
        #-----------------------------------------------------------------------
        if [[ $null_yn = "N" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
            echo "            ${column_name}: coalesce(rtrim(${column_name}), '${Null_Character}')"
        elif [[ $null_yn = "Y" && ( $data_type_org = "character" || $data_type_org = "character varying" ) ]]; then
            echo "            ${column_name}: rtrim(${column_name})"
        elif [[ $null_yn = "Y" && ( $data_type_org = "numeric" || $data_type_org = "integer" ) ]]; then
            echo "            ${column_name}: case when ascii(rtrim(${column_name}))=0 then NULL else ${column_name} end"
        else
            echo "            ${column_name}: ${column_name}"
        fi

    fi
}

#-------------------------------------------------------------------------------
#   Function : func_GetColumnInfo -> 테이블의 컬럼정보를 생성함
#-------------------------------------------------------------------------------
func_GetColumnInfo()
{
    typeset My_Table_Lower=$1
    typeset My_Catalog=$2

    if [[ -f $GP_Catalog_Curr ]]; then
        grep ^$My_Table_Lower\| $GP_Catalog_Curr > $My_Catalog

        if [[ $? != 0 ]]; then
            func_PrintLog "[$0] ${GP_Catalog_Curr}에 $My_Table_Lower 정보가 없음."
        else
            return
        fi
    else
        func_PrintLog "[$0] ${GP_Catalog_Curr} 파일이 없음."
    fi

    #---------------------------------------------------------------------------
    #   GP_Catalog_Curr 에서, My_Table_Lower 해당하는 내용을 찾지 못함
    #       --> Greenplum 접속하여 My_Table_Lower 의 컬럼정보를 생성함
    #---------------------------------------------------------------------------
    func_PrintLog "[$0] Greenplum에 접속하여 $My_Table_Lower 테이블 Catalog 정보를 가져오는 중 ..."

    $Get_GP_Column_Info_Shell -s -t $My_Table_Lower > $My_Catalog

    if [[ $? != 0 ]]; then
        func_PrintLog "[$0] Greenplum $My_Table_Lower 테이블 Catalog 정보 획득 실패하여 종료함."
        func_PrintLog "[$0] ERROR - func_GetColumnInfo()"
        rm -f $My_Catalog

        exit 1
    fi

    #---------------------------------------------------------------------------
    #   생성된 My_Catalog 파일에 My_Table_Lower 테이블 존재하는지 재확인
    #---------------------------------------------------------------------------
    if grep ^$My_Table_Lower\| $My_Catalog >/dev/null; then
        :
    else
        func_PrintLog "[$0] Greenplum에 $My_Table_Lower 테이블이 존재하지 않아 종료함."
        func_PrintLog "[$0] ERROR - func_GetColumnInfo()"
        rm -f $My_Catalog

        exit 1
    fi
}

#-------------------------------------------------------------------------------
#   Function : func_MakeUpsertScript -> Source_Table의 데이터를 이용하여 Target_Table의 데이터를 upsert하는 스크립트를 생성
#
#   Upsert_Method == di(delete and insert)
#                    io(= insert only for not matched key)
#
#   func_MakeUpsertScript $Upsert_Script $Target_Table_Lower $Upsert_Table_Lower $Upsert_Method
#-------------------------------------------------------------------------------
func_MakeUpsertScript()
{
    typeset Upsert_Script=$1
    typeset Source_Table_Lower=$2
    typeset Target_Table_Lower=$3
    typeset Upsert_Method=$4
    typeset Source_Catalog="/tmp/$Source_Table_Lower.$$.curr"
    typeset Target_Catalog="/tmp/$Target_Table_Lower.$$.curr"
    typeset Temp_Script="$Upsert_Script.$$.tmp"
    typeset Table_Prefix=""
    typeset Source_Table_Schema=""
    typeset Target_Table_Schema=""

    typeset column_name pk_yn
    typeset -i j k

    #---------------------------------------------------------------------------
    #   Source_Table_Schema 생성
    #---------------------------------------------------------------------------
    Table_Prefix=`expr substr $Source_Table_Lower 1 1`
    Table_Prefix_2=`expr substr $Source_Table_Lower 1 4`

    if [[ $Table_Prefix_2 = "etl_" ]]; then
            Source_Table_Schema="edw_meta"
    else
        case $Table_Prefix in
        d)
            Source_Table_Schema="edw_dda"
            ;;
        w)
            Source_Table_Schema="edw_dw"
            ;;
        *)
            Source_Table_Schema="edw_tmp"
            ;;
        esac
    fi

    #---------------------------------------------------------------------------
    #   Target_Table_Schema 생성
    #---------------------------------------------------------------------------
    Table_Prefix=`expr substr $Target_Table_Lower 1 1`
    Table_Prefix_2=`expr substr $Target_Table_Lower 1 4`

    if [[ $Table_Prefix_2 = "etl_" ]]; then
            Target_Table_Schema="edw_meta"
    else
        case $Table_Prefix in
        d)
            Target_Table_Schema="edw_dda"
            ;;
        w)
            Target_Table_Schema="edw_dw"
            ;;
        *)
            Target_Table_Schema="edw_tmp"
            ;;
        esac
    fi

    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ Make Upsert SQL Script ] $Upsert_Script"
    func_PrintLog "*-----------------------------------------------------------------------------*/"
    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Making upsert script Start."

    #---------------------------------------------------------------------------
    #   Catalog 정보 예
    #---------------------------------------------------------------------------
    #   table_name, column_id, column_name, data_type_full, data_type_org, data_type_alias, data_length_full, data_length, data_scale, data_display, pk_yn, null_yn, dk_yn
    #---------------------------------------------------------------------------
    #   dw_etl_test_01|1|char_1|character(10)|character|character|(10)|10|0|10|Y|N|Y
    #   dw_etl_test_01|2|varchar_1|character varying(10)|character varying|varchar|(10)|10|0|10|Y|N|N
    #   dw_etl_test_01|3|numeric_1|numeric(10,0)|numeric|numeric|(10,0)|10|0|12|Y|N|N
    #   dw_etl_test_01|4|varchar_2|character varying(20)|character varying|varchar|(20)|20|0|20|N|Y|N
    #---------------------------------------------------------------------------

    #---------------------------------------------------------------------------
    #   Source_Table Array 생성 : src_key_columns, src_nonkey_columns, src_columns
    #---------------------------------------------------------------------------
    set -A src_key_columns
    set -A src_nonkey_columns
    set -A src_columns

####    declare -a src_key_columns
####    declare -a src_nonkey_columns
####    declare -a src_columns

    i=0
    j=0
    k=0

    func_GetColumnInfo $Source_Table_Lower $Source_Catalog

    grep ^$Source_Table_Lower $Source_Catalog | while read LINE
    do
        column_name=$(echo $LINE | cut -d\| -f3)
        pk_yn=$(echo $LINE | cut -d\| -f11)

        if [[ $pk_yn = "Y" ]]; then
            src_key_columns[$i]=$column_name
            i=$((i + 1))
        else
            src_nonkey_columns[$j]=$column_name
            j=$((j + 1))
        fi

        src_columns[$k]=$column_name

        k=$((k + 1))
    done

    rm -f $Source_Catalog

    #---------------------------------------------------------------------------
    #   Target_Table Array 생성 : tgt_key_columns, tgt_nonkey_columns, tgt_columns
    #---------------------------------------------------------------------------
    set -A tgt_key_columns
    set -A tgt_nonkey_columns
    set -A tgt_columns

####    declare -a tgt_key_columns
####    declare -a tgt_nonkey_columns
####    declare -a tgt_columns

    i=0
    j=0
    k=0

    func_GetColumnInfo $Target_Table_Lower $Target_Catalog

    grep ^$Target_Table_Lower $Target_Catalog | while read LINE
    do
        column_name=$(echo $LINE | cut -d\| -f3)
        pk_yn=$(echo $LINE | cut -d\| -f11)

        if [[ $pk_yn = "Y" ]]; then
            tgt_key_columns[$i]=$column_name
            i=$((i + 1))
        else
            tgt_nonkey_columns[$j]=$column_name
            j=$((j + 1))
        fi

        tgt_columns[$k]=$column_name

        k=$((k + 1))
    done

    rm -f $Target_Catalog

    #---------------------------------------------------------------------------
    #   1. echo generation info.
    #---------------------------------------------------------------------------
    Current_Timestamp=`date +"%Y-%m-%d %H:%M:%S"`

    echo "/*" > $Temp_Script
    echo "* Generated by load_gp.sh at $Current_Timestamp " >> $Temp_Script
    echo "*/" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   2. join delete
    #---------------------------------------------------------------------------
    #-------------------------------------------------------
    #   di(= delete and insert)
    #-------------------------------------------------------
    if [[ $Upsert_Method = "di" ]]; then
        #-----------------------------------------------------------------------
        #   2-1. Transaction 처리를 묶기 위하여 begin; 추가
        #-----------------------------------------------------------------------
        echo "begin;" >> $Temp_Script
        echo "" >> $Temp_Script

        #-----------------------------------------------------------------------
        #   2-2. DELETE 구문 생성
        #-----------------------------------------------------------------------
        echo "DELETE  FROM $Target_Table_Schema.$Target_Table_Lower AS T " >> $Temp_Script
        echo " USING  " >> $Temp_Script
        echo "        $Source_Table_Schema.$Source_Table_Lower AS S " >> $Temp_Script
        echo " WHERE  " >> $Temp_Script

        i=0

        while [[ $i -lt ${#tgt_key_columns[*]} ]]
        do
            if [[ $i -eq 0 ]]; then
                echo "        T.${tgt_key_columns[$i]} = S.${tgt_key_columns[$i]}" >> $Temp_Script
            else
                echo "   AND  T.${tgt_key_columns[$i]} = S.${tgt_key_columns[$i]}" >> $Temp_Script
            fi

            i=$((i + 1))
        done

        echo ";" >> $Temp_Script
        echo ""  >> $Temp_Script
    fi


    #---------------------------------------------------------------------------
    #   3. insert ~ select -- fact columns to zero and load_date_time to sysdate
    #---------------------------------------------------------------------------
    echo "INSERT INTO  $Target_Table_Schema.$Target_Table_Lower " >> $Temp_Script
    echo "( " >> $Temp_Script

    k=0

    while [[ $k -lt ${#tgt_columns[*]} ]]
    do
        if [[ $k -eq 0 ]]; then
            echo "        ${tgt_columns[$k]}" >> $Temp_Script
        else
            echo "      , ${tgt_columns[$k]}" >> $Temp_Script
        fi

        k=$((k + 1))
    done

    #---------------------------------------------------------------------------
    echo ") " >> $Temp_Script
    echo "SELECT  " >> $Temp_Script

    k=0

    while [[ $k -lt ${#src_columns[*]} ]]
    do
        if [[ $k -eq 0 ]]; then
            echo "        X.${src_columns[$k]}" >> $Temp_Script
        else
            echo "      , X.${src_columns[$k]}" >> $Temp_Script
        fi

        k=$((k + 1))
    done

    #---------------------------------------------------------------------------
    echo "  FROM  (" >> $Temp_Script
    echo "        SELECT  " >> $Temp_Script

    k=0

    while [[ $k -lt ${#src_columns[*]} ]]
    do
        if [[ $k -eq 0 ]]; then
            echo "                S.${src_columns[$k]}" >> $Temp_Script
        else
            echo "              , S.${src_columns[$k]}" >> $Temp_Script
        fi

        k=$((k + 1))
    done
    #---------------------------------------------------------------------------
         echo -n "              , row_number() over (partition by " >> $Temp_Script

         i=0

         while [[ $i -lt ${#tgt_key_columns[*]} ]]
         do
             if [[ $i -eq 0 ]]; then
                 echo -n "S.${tgt_key_columns[$i]}" >> $Temp_Script
             else
                 echo -n ", S.${tgt_key_columns[$i]}" >> $Temp_Script
             fi

             i=$((i + 1))
         done

         echo " order by 1) AS row_number" >> $Temp_Script
    #---------------------------------------------------------------------------

    echo "          FROM  " >> $Temp_Script
    echo "                $Source_Table_Schema.$Source_Table_Lower S " >> $Temp_Script

    #---------------------------------------------------------------------------
    #   di(= delete and insert)
    #---------------------------------------------------------------------------
    if [[ $Upsert_Method = "di" ]]; then
        echo "        ) X" >> $Temp_Script
        echo " WHERE  " >> $Temp_Script
        echo "        X.row_number = 1" >> $Temp_Script
        echo ";" >> $Temp_Script

        #-----------------------------------------------------------------------
        #   3-9. Transaction 처리를 묶기 위하여 end; 추가
        #-----------------------------------------------------------------------
        echo "" >> $Temp_Script
        echo "end;" >> $Temp_Script

    #---------------------------------------------------------------------------
    #   io(= insert only for not matched key)
    #---------------------------------------------------------------------------
    else
        echo "                LEFT OUTER JOIN" >> $Temp_Script
        echo "                $Target_Table_Schema.$Target_Table_Lower T " >> $Temp_Script
        echo "            ON  " >> $Temp_Script

        i=0

        while [[ $i -lt ${#tgt_key_columns[*]} ]]
        do
            if [[ $i -eq 0 ]]; then
                echo "                S.${tgt_key_columns[$i]} = T.${tgt_key_columns[$i]}" >> $Temp_Script
            else
                echo "           AND  S.${tgt_key_columns[$i]} = T.${tgt_key_columns[$i]}" >> $Temp_Script
            fi

            i=$((i + 1))
        done

        echo "         WHERE   " >> $Temp_Script
        echo "                T.${tgt_key_columns[0]} IS NULL" >> $Temp_Script
        echo "        ) X" >> $Temp_Script
        echo " WHERE  " >> $Temp_Script
        echo "        X.row_number = 1" >> $Temp_Script
        echo ";" >> $Temp_Script
    fi

    echo "" >> $Temp_Script
    echo "/* __end__ */" >> $Temp_Script

    mv $Temp_Script $Upsert_Script

    rm -f $Source_Catalog $Target_Catalog

    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Made upsert script End."
}


#-------------------------------------------------------------------------------
#   Function : func_TruncateTable ->
#-------------------------------------------------------------------------------
func_TruncateTable()
{
    typeset Target_Table_Lower=$1
    typeset Target_Schema=$2
    typeset Table_Owner_Check="/tmp/$Target_Table_Lower.$$.chk"
    typeset Table_Owner=""

    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ Truncate Table ] ${Target_Schema}.${Target_Table_Lower}"
    func_PrintLog "*-----------------------------------------------------------------------------*/"
    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Truncate Table Start."

    #---------------------------------------------------------------------------
    #   테이블 소유자 조회
    #---------------------------------------------------------------------------
    $GP_SQL_EXE -AtX -h $GP_HOST -d $GP_DB -U $GP_LOAD_USER -c "SELECT tableowner FROM pg_tables WHERE tablename = '${Target_Table_Lower}' ;" > $Table_Owner_Check

    Table_Owner=`cat $Table_Owner_Check`

    rm -f $Table_Owner_Check

    #---------------------------------------------------------------------------
    #   Greenplum Backup 시 Lock 발생하지 않도록, Truncate 기능을 Delete 구문으로 변경함
    #
    #   테이블 소유자 계정으로 접속하여 DELETE 실행 (단, edwdba 소유인 경우 edwdw2 계정으로 실행 )
    #---------------------------------------------------------------------------
    if [[ $Table_Owner = "edwdba" || $Table_Owner = "edwdba_dev" ]]; then
        $GP_SQL_EXE -h $GP_HOST -d $GP_DB -U $GP_LOAD_USER -c "DELETE FROM ${Target_Schema}.${Target_Table_Lower} ;" >> $Log_File
    else
        $GP_SQL_EXE -h $GP_HOST -d $GP_DB -U $Table_Owner -c "DELETE FROM ${Target_Schema}.${Target_Table_Lower} ;" >> $Log_File
    fi

    Exit_Code=$?

    if [[ $Exit_Code = 0 ]]; then
        func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Truncate Table End. Succeeded. Exit Code = $Exit_Code"
    else
        func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Truncate Table End. Failed. Exit Code = $Exit_Code"
        exit $Exit_Code
    fi
}

#-------------------------------------------------------------------------------
#   Function : func_Backup_GPLoadDataFiles -> gpload 데이터 파일 백업
#-------------------------------------------------------------------------------
func_Backup_GPLoadDataFiles()
{
    typeset Current_Timestamp
    typeset FILE=""
    typeset Data_File=""
    typeset Backup_File=""

    Current_Timestamp=`date +'%Y%m%d%H%M%S'`

    #---------------------------------------------------------------------------
    #   GPLOAD INPUT SOURCE FILE 백업 디렉토리로 이동
    #---------------------------------------------------------------------------
    FILE=`echo ${Data_File_List[0]} | rev | cut -d/ -f1 | rev`

    Data_File="$Data_Directory/$FILE"
    Backup_File="$Data_Directory/$FILE.$Current_Timestamp"

    func_PrintLog ""
    func_PrintLog "/*------------------------------------------------------------------------------"
    func_PrintLog "*  [ backup & compress ] $Data_File"
    func_PrintLog "*-----------------------------------------------------------------------------*/"
    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> backup & compresss data files Start."
    func_PrintLog "    cp $Data_File $Backup_File"
    func_PrintLog "    gzip $Backup_File"

    cp $Data_File $Backup_File
    gzip $Backup_File

    Exit_Code=$?

    if [[ $Exit_Code = 0 ]]; then
        func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> backup & compresss data files End. Succeeded. Exit Code = $Exit_Code"
    else
        func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> backup & compresss data files End. Failed. Exit Code = $Exit_Code"
        exit $Exit_Code
    fi

    func_PrintLog ""
}


################################################################################
#   Base Environment Variables
################################################################################
Command_Line="$0 $*"
Current_Timestamp=`date +'%Y%m%d%H%M%S'`
Option_Argument=""
Target_Schema=""
Load_Method="Delimiter"
Upsert_Method="di"
Truncate_Target_YN="Y"
############################################################
#   CHANGE ME START
############################################################
Null_Character="*"
GP_ERROR_LIMIT=0

#-------------------------------------------------------------------------------
#   Greenplum environment variables.
#-------------------------------------------------------------------------------
. /dbclient1/gpcli/greenplum-clients-4.3.8.1/greenplum_clients_path.sh
. /dbclient1/gpcli/greenplum-loaders-4.3.8.1/greenplum_loaders_path.sh
############################################################
#   CHANGE ME END
############################################################


################################################################################
#   Parse Options
################################################################################
while getopts :heb:a:Tp:u:i:n:xf:l:D: OPTION
do
    case $OPTION in
    h) func_PrintUsage 0
        ;;
    e) OptionFlag_e="Y"
        ;;
    b) OptionFlag_b="Y"
        Before_SQL="$OPTARG"
        ;;
    a) OptionFlag_a="Y"
        After_SQL="$OPTARG"
        ;;
    T) Truncate_Target_YN="N"
        ;;
    p) Option_Argument="$OPTARG"
        ;;
    u) Upsert_Table="$OPTARG"
        Upsert_Table_Upper=`echo $Upsert_Table | tr a-z A-Z`
        Upsert_Table_Lower=`echo $Upsert_Table | tr A-Z a-z`
        Upsert_Method="di"  ## delete and insert
        ;;
    i) Upsert_Table="$OPTARG"
        Upsert_Table_Upper=`echo $Upsert_Table | tr a-z A-Z`
        Upsert_Table_Lower=`echo $Upsert_Table | tr A-Z a-z`
        Upsert_Method="io"  ## insert only for not matched key
        ;;
    n) Null_Character="$OPTARG"
        ;;
    x) Load_Method="Fixed"
        ;;
    f) Data_Files="$OPTARG"
        ;;
    l) OptionFlag_l="Y"
        GP_ERROR_LIMIT="$OPTARG"
        ;;
    D) Data_Directory="$OPTARG"
        case $Data_Directory in
        [\\/]* | ?:[\\/]*) ;;
        *) echo "$0: Data Directory must be given in absolute path."; exit 1 ;;
        esac
        ;;
    :) echo "$0: $OPTARG option require option argument but missing."
        func_PrintUsage 1
        ;;
    \?) echo "$0: Invalid option \"$OPTARG\" given."
        func_PrintUsage 1
        ;;
    esac
done
shift $((OPTIND - 1))


################################################################################
#   Set Working Variable
################################################################################
#-------------------------------------------------------------------------------
#   Target_Table : 타겟 테이블명
#-------------------------------------------------------------------------------
if [[ $# -ne 1 ]]; then
    echo "$0: Target table is not given.
    For more information run 'load_gp.sh -h'"
    exit 1
else
    Target_Table="$1"
fi

Target_Table_Upper=`echo $Target_Table | tr a-z A-Z`
Target_Table_Lower=`echo $Target_Table | tr A-Z a-z`

Table_Prefix=`expr substr $Target_Table_Lower 1 1`
Table_Prefix_2=`expr substr $Target_Table_Lower 1 4`

#-------------------------------------------------------------------------------
#   Target_Table 첫문자 기준으로 Target_Schema, Target_Schema_Abbr 설정
#-------------------------------------------------------------------------------
if [[ $Table_Prefix_2 = "etl_" ]]; then
        Target_Schema_Abbr="meta"
        Target_Schema="edw_meta"
else
    case $Table_Prefix in
    d)
        Target_Schema_Abbr="dda"
        Target_Schema="edw_dda"
        ;;
    w)
        Target_Schema_Abbr="dw"
        Target_Schema="edw_dw"
        ;;
    *)
        Target_Schema_Abbr="tmp"
        Target_Schema="edw_tmp"
        ;;
    esac
fi

#-------------------------------------------------------------------------------
#   작업 디렉토리 및 파일명 설정
#-------------------------------------------------------------------------------
############################################################
#   CHANGE ME START
############################################################
Home_Directory="/edwdata"
Shell_Home_Directory="$Home_Directory/script"

case $Target_Schema_Abbr in
dda) GPFDIST_PORT="8083"
    ;;
dw) GPFDIST_PORT="8084"
    ;;
*) GPFDIST_PORT="8085"
    ;;
esac

GP_SQL_EXE="psql"
GP_HOST="12.30.48.86"
GP_DB="kgedwdb"

case $Target_Schema in
edw_dda)
    GP_USER="edwdw"
    ;;
edw_dw | edw_tmp)
    GP_USER="edwdw"
    ;;
*)
    GP_USER="edwdw"
    ;;
esac


GP_LOAD_USER="edwdw"
GP_PORT="5432"
#-------------------------------------------------------------------------------
# 아래의 GP_LOCAL_HOST Fail-Over 설정에 따름
# GP_LOCAL_HOST="172.30.8.203"
#-------------------------------------------------------------------------------
GP_PORT_RANGE="9001, 9081"
############################################################
#   CHANGE ME END
############################################################


Log_Directory="$Shell_Home_Directory/log"
Script_Directory="$Home_Directory/dw/$Target_Schema_Abbr/script"
Data_Directory="$Home_Directory/dw/$Target_Schema_Abbr/data"

Get_GP_Column_Info_Shell="$Shell_Home_Directory/get_gp_col_info.sh"
Run_SQL_Shell="$Shell_Home_Directory/run_gp_sql.sh"
Run_GP_Load="gpload -v -f"

GP_TEMP_SCHEMA="edw_tmp"

GP_LOAD_TABLE="${Target_Table_Lower}"
GP_ERROR_TABLE="edw_err.gpload_error"

#-------------------------------------------------------------------------------
#   Greenplum Catalog 정보
#-------------------------------------------------------------------------------
GP_Catalog_Curr="$Shell_Home_Directory/gp_col_info.curr"
GP_Catalog_Prev="$Shell_Home_Directory/gp_col_info.prev"

#-------------------------------------------------------------------------------
#   GP_LOCAL_HOST Fail-Over 설정 for YML File
#
#   (정상 172.30.8.x NIC 살아있을 때) kihubapp / (Fail-Over 172.30.8.x NIC 죽었을 때 172.30.12.x NIC로 전환) kihubapp-2
#   (정상 172.30.8.x NIC 살아있을 때) kihubaps / (Fail-Over 172.30.8.x NIC 죽었을 때 172.30.12.x NIC로 전환) kihubaps-2
#   (정상 172.30.8.x NIC 살아있을 때) kgdevdb3 / (Fail-Over 172.30.8.x NIC 죽었을 때 172.30.12.x NIC로 전환) 없음
#-------------------------------------------------------------------------------
export LANG=C

HOSTNAME=`hostname`

############################################################
#   CHANGE ME START
# temporary datastage hostname > IP
############################################################
GP_LOCAL_HOST=$HOSTNAME
############################################################
#   CHANGE ME END
############################################################


#-------------------------------------------------------------------------------
#   Data_File_List  Array 생성  --> "-f" 옵션 참고
#-------------------------------------------------------------------------------
typeset -A Data_File_List

#### declare -a Data_File_List

if [[ -z $Data_Files ]]; then
    Data_File_List[0]="$Data_Directory/${Target_Table_Lower}.out"
else
    IFS_ORIG=$IFS
    IFS=,

    typeset -i i=0

    for FILE in $Data_Files
    do
        case $FILE in
        [\\/]* | ?:[\\/]*)
            Data_File_List[$i]="$FILE"
            ;;
        *)
            Data_File_List[$i]="$Data_Directory/$FILE"
            ;;
        esac

        i=$((i + 1))
    done

    IFS=$IFS_ORIG
fi


################################################################################
#   Load_Script 생성 기준 : -f 옵션을 통해 지정한 파일명이 타겟테이블과 다른 경우, -f 파일명 기준 Load_Script 생성
################################################################################
FILE=`echo ${Data_File_List[0]} | rev | cut -d/ -f1 | rev | cut -d. -f1`

if [[ $FILE = $Target_Table_Lower ]]; then
    Load_Script_Temp=$Target_Table_Lower
else
    Load_Script_Temp=$FILE
fi


if [[ $Load_Method = "Fixed" ]]; then
    Load_Script="$Script_Directory/load_$Load_Script_Temp.sql"
else
    Load_Script="$Script_Directory/load_$Load_Script_Temp.yml"
fi

Load_Script_Fprint="$Load_Script_Temp.$$.finger"


Log_File="$Log_Directory/load-$Load_Script_Temp-$Current_Timestamp.log"

if [[ ! -z $Upsert_Table ]]; then
    Upsert_Script="$Script_Directory/ups_$Upsert_Table_Lower-using-$Target_Table_Lower.sql"
fi


#-------------------------------------------------------------------------------
#   After_SQL, Before_SQL  sql script file명이 절대경로로 주어지지 않은 경우, Script_Directory에 존재하는 것으로 가정
#-------------------------------------------------------------------------------
if [[ -n $After_SQL ]]; then
    case $After_SQL in
    [\\/]* | ?:[\\/]*)
        ;;
    *)
        After_SQL="$Script_Directory/$After_SQL"
        ;;
    esac
fi

if [[ -n $Before_SQL ]]; then
    case $Before_SQL in
    [\\/]* | ?:[\\/]*)
        ;;
    *)
        Before_SQL="$Script_Directory/$Before_SQL"
        ;;
    esac
fi


#-------------------------------------------------------------------------------
#   "-e" 옵션이 있는 경우, 작업 파일명 설정
#-------------------------------------------------------------------------------
if [[ $OptionFlag_e = "Y" ]]; then
    Delete_SQL="$Script_Directory/del_$Target_Table_Lower.sql"

    Truncate_Target_YN="N"
fi


#-------------------------------------------------------------------------------
#   (혹시나) 상대경로 참조가 있는 경우를 고려하여, 쉘 홈디렉토리로 이동
#-------------------------------------------------------------------------------
cd $Shell_Home_Directory

#-------------------------------------------------------------------------------
#   func_PrintLog
#-------------------------------------------------------------------------------
func_PrintLog "[INFO] ICONFIG:ID:`id`"
func_PrintLog "[INFO] ICONFIG:HOME:`echo $HOME`"


################################################################################
#   Function : func_main --> load_gp.sh 실행
################################################################################
func_main()
{
    ############################################################################
    #   load_gp.sh 실행결과 Output은 "Log_File =  로그파일명" 이어야 함
    #
    #   로그파일에 Debug 메시지를 넣기 위해서는 반드시 func_PrintLog() 함수를 사용할 것
    ############################################################################
    echo -n "Log_File = $Log_File"
    #---------------------------------------------------------------------------

    func_PrintLog ""
    func_PrintLog "/*----------------------------------------------------------------------------*/"
    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> Start loading."
    func_PrintLog ""
    func_PrintLog "    Command Line ▶ $Command_Line"

    #---------------------------------------------------------------------------
    #   -b 옵션인 경우, Before_SQL 실행  --> Before_SQL 존재하지 않더라도 -b 옵션이면 실행하도록 TO-BE 변경
    #---------------------------------------------------------------------------
    if [[ $OptionFlag_b = "Y" ]]; then
        func_RunSQL $Before_SQL $Target_Schema
    fi

    #---------------------------------------------------------------------------
    #   -e 옵션인 경우, Delete_SQL 실행  --> Delete_SQL 존재하지 않더라도 -e 옵션이면 실행하도록 TO-BE 변경
    #---------------------------------------------------------------------------
    if [[ $OptionFlag_e = "Y" ]]; then
        func_RunSQL $Delete_SQL $Target_Schema
    fi

    #---------------------------------------------------------------------------
    #   타겟 테이블 기준 로딩할 load_타겟테이블.yml 또는 load_타겟테이블.sql 파일 생성
    #
    #   ==> "GP_LOCAL_HOST Fail-Over 설정 for YML File" 항상 적용되어 yml 파일이 매번 생성되도록 변경
    #---------------------------------------------------------------------------
    # func_IsNeedMakeLoadScript $Load_Script $Target_Table_Lower $Load_Script_Fprint
    #
    # if [[ $? = 0 ]]; then
    #     if [[ $Load_Method = "Fixed" ]]; then
    #         func_MakeLoadScript_Fixed $Load_Script $Target_Table_Lower $Load_Script_Fprint
    #     else
    #         func_MakeLoadScript_Delimiter $Load_Script $Target_Table_Lower $Load_Script_Fprint
    #     fi
    # fi
    #---------------------------------------------------------------------------
    if [[ $Load_Method = "Fixed" ]]; then
        func_MakeLoadScript_Fixed $Load_Script $Target_Table_Lower $Load_Script_Fprint
    else
        func_MakeLoadScript_Delimiter $Load_Script $Target_Table_Lower $Load_Script_Fprint
    fi

    #---------------------------------------------------------------------------
    #   (default) Truncate Table = "Y"
    #   (예외조건) 1. -T 옵션인 경우. Truncate Table = "N"
    #              2. -e 옵션인 경우. Truncate Table = "N". Delete_SQL 실행
    #---------------------------------------------------------------------------
    if [[ $Truncate_Target_YN = "Y" ]]; then
        func_TruncateTable $Target_Table_Lower $Target_Schema
    fi

    #---------------------------------------------------------------------------
    #   Greenplum Load_Script 실행
    #---------------------------------------------------------------------------
    if [[ $Load_Method = "Fixed" ]]; then
        #-----------------------------------------------------------------------
        #   Greenplum gpfdist 데몬 Start
        #-----------------------------------------------------------------------
        func_gpfdistDaemonStart

        #-----------------------------------------------------------------------
        #   $Shell_Home_Directory/run_gp_sql.sh -p 파라미터리스트 load_타겟테이블.sql 타겟스키마
        #-----------------------------------------------------------------------
        func_RunSQL $Load_Script $Target_Schema
    else
        #-----------------------------------------------------------------------
        #   gpload -v -f load_타겟테이블.yml
        #-----------------------------------------------------------------------
        func_RunGpLoad $Load_Script $Target_Schema
    fi


    #---------------------------------------------------------------------------
    #   -u 옵션(= delete/insert ) 또는 -i 옵션(= insert only for not matched key )인 경우, Upsert_Script 생성 및 실행
    #
    #   Upsert_Method : di(= delete and insert)
    #                   io(= insert only for not matched key)
    #---------------------------------------------------------------------------
    if [[ ! -z $Upsert_Table ]]; then
        #-----------------------------------------------------------------------
        #   Source_Table(= Target_Table )의 데이터를 이용하여 Target_Table(= Upsert_Table )의 데이터를 upsert하는 스크립트를 생성
        #-----------------------------------------------------------------------
        func_MakeUpsertScript $Upsert_Script $Target_Table_Lower $Upsert_Table_Lower $Upsert_Method

        #-----------------------------------------------------------------------
        #   $Shell_Home_Directory/run_gp_sql.sh -p 파라미터리스트 Upsert_Script.sql 타겟스키마
        #-----------------------------------------------------------------------
        func_RunSQL $Upsert_Script $Target_Schema
    fi

    #---------------------------------------------------------------------------
    #   -a 옵션인 경우, After_SQL 실행   --> After_SQL 존재하지 않더라도 -a 옵션이면 실행하도록 TO-BE 변경
    #---------------------------------------------------------------------------
    if [[ $OptionFlag_a = "Y" ]]; then
        func_RunSQL $After_SQL $Target_Schema
    fi

    #---------------------------------------------------------------------------
    #   GPLOAD INPUT SOURCE FILE 백업
    #---------------------------------------------------------------------------
    func_Backup_GPLoadDataFiles


    func_PrintLog "[$0] "`date +"%Y-%m-%d %H:%M:%S"`" --> End loading."
    func_PrintLog "/*----------------------------------------------------------------------------*/"

    exit 0
}

################################################################################
#   Function Call --> func_main --> load_gp.sh 실행
################################################################################
func_main

#-------------------------------------------------------------------------------
#   End of Line
#-------------------------------------------------------------------------------
