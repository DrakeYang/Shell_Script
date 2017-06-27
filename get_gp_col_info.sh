#!/bin/bash
################################################################################
#                                                                              #
#  Shell name  : get_gp_col_info.sh
#                                                                              #
#  Description : Greenplum 의 테이블 정보(테이블명, 컬럼명, 도메인명, Width, Scale, PK여부, Nullability)를 구한다.
#                                                                              #
#  example     : get_gp_col_info.sh [options] Target_Table_Lower
#  example     : get_gp_col_info.sh -s -t w_gr
#                                                                              #
################################################################################
#                                                                              #
#  Change Description.                                                         #
#  --------------------------------------------------------------------------- #
#  Date       Author   Ver    Description                                      #
#  +--------- +------  +----- +----------------------------------------------- #
#  2016.06.29 DFIBiz   0.11   DataStage 11.3.1.2 for Linux Upgrade             #
#  2012.07.18 DFIBiz   0.10   Initial Release                                  #
#                                                                              #
################################################################################

#-------------------------------------------------------------------------------
#   Function : func_PrintUsage -> 사용방법 출력
#-------------------------------------------------------------------------------
func_PrintUsage()
{
    typeset Exit_Code=$1

    echo "
  Usage : get_gp_col_info.sh [-hs]

  Greenplum의 테이블 정보(테이블명, 컬럼명, Width, Scale, PK여부, Nullability)를 구해온다.

  Options:
  -h                    Show this help and exit.

  -s                    Print results to STDOUT.

  -t Target_Table_Lower Catalog 정보를 구할 대상 테이블을 지정.
"

    exit $Exit_Code
}

#-------------------------------------------------------------------------------
#   Function : func_PrintLog -> 로그파일에 기록
#-------------------------------------------------------------------------------
func_PrintLog()
{
    if [[ $Print_stdout_YN = "N" ]]; then
         echo "$*" >> $Log_File
    fi
}


################################################################################
#   Base Environment Variables
################################################################################
############################################################
#   CHANGE ME START
############################################################
Home_Directory="/edwdata"
Shell_Home_Directory="$Home_Directory/script"

GP_Catalog_Curr="$Shell_Home_Directory/gp_col_info.curr"
GP_Catalog_Prev="$Shell_Home_Directory/gp_col_info.prev"
GP_Catalog_Out="$Shell_Home_Directory/gp_col_info.dat"

GP_SQL_EXE="psql"
Print_stdout_YN="N"

Time_Stamp=`date +%Y%m%d%H%M%S`
Log_File="$Shell_Home_Directory/log/`basename $0`.$Time_Stamp"
Backup_Directory="$Shell_Home_Directory/_history"

GP_Host="12.30.48.86"
GP_User="edwdw"
GP_DB="kgedwdb"

cd $Shell_Home_Directory
############################################################
#   CHANGE ME END
############################################################

################################################################################
#   Parse Options
################################################################################
while getopts :hst:o: OPTION
do
    case $OPTION in
    h) func_PrintUsage 0
        ;;
    s) Print_stdout_YN="Y"
        ;;
    t) Target_Table_Lower="$OPTARG"
        ;;
    :) echo "$0: $OPTARG Option require option argument but missing."
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
if [[ $# -gt 0 ]]; then
    echo "$0: Invalid number of arguments given."
    func_PrintUsage 1
fi

Temp_SQL="/tmp/$Target_Table_Lower.$$.sql"
trap "rm -f $Temp_SQL; exit 2" 2 3 9 10 11 15 24

#-------------------------------------------------------------------------------
#   기존 파일 백업
#-------------------------------------------------------------------------------
if [[ $Print_stdout_YN = "N" ]] && [[ -f $GP_Catalog_Curr ]]; then
    if [[ -f $GP_Catalog_Prev ]]; then
        cp $GP_Catalog_Prev ${Backup_Directory}/gp_col_info.prev.$Time_Stamp
        func_PrintLog "Copied $GP_Catalog_Prev to ${Backup_Directory}/gp_col_info.prev.$Time_Stamp"
    fi

    cp $GP_Catalog_Curr $GP_Catalog_Prev
    func_PrintLog "Copied $GP_Catalog_Curr to $GP_Catalog_Prev"
fi

#-------------------------------------------------------------------------------
#   SQL Script를 실행
#-------------------------------------------------------------------------------
if [[ -z $Target_Table_Lower ]]; then
    func_PrintLog "Executing $GP_SQL_EXE -AtX -h $GP_Host -U $GP_User -d $GP_DB < $Shell_Home_Directory/get_gp_col_info.sql > $GP_Catalog_Out"

    $GP_SQL_EXE -AtX -h $GP_Host -U $GP_User -d $GP_DB < $Shell_Home_Directory/get_gp_col_info.sql > $GP_Catalog_Out

    Exit_Code=$?

else
    func_PrintLog "Making SQL script $Temp_SQL for $Target_Table_Lower ..."

    cat <<EOF > $Temp_SQL
select
                x.table_name
        ||'|'|| x.column_id
        ||'|'|| x.column_name
        ||'|'|| x.data_type_full
        ||'|'|| x.data_type_org
        ||'|'|| x.data_type_alias
        ||'|'|| x.data_length_full
        ||'|'|| x.data_length
        ||'|'|| case when x.data_scale = '' then '0' else x.data_scale end
        ||'|'|| case when x.data_type_org = 'numeric'                       then cast(cast(case when x.data_length = '' then '0' else x.data_length end as int) + 2 as text)
                     when x.data_type_org = 'timestamp without time zone'   then cast('23' as text)
                                                                            else x.data_length
                 end
        ||'|'|| x.pk_yn
        ||'|'|| x.null_yn
        ||'|'|| x.dk_yn as gp_col_info
  from  (
          select
                  c.relname                                                     as table_name
                , row_number() over (partition by c.relname order by a.attnum)  as column_id
                , a.attname                                                     as column_name
                , pg_catalog.format_type(a.atttypid, a.atttypmod)               as data_type_full
                , split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 1) as data_type_org
                , split_part(replace(replace(pg_catalog.format_type(a.atttypid, a.atttypmod), 'character varying', 'varchar'), 'timestamp without time zone', 'timestamp'), '(', 1) as data_type_alias
                , case when pg_catalog.format_type(a.atttypid, a.atttypmod) in ('timestamp without time zone', 'integer') then ''
                       else '('|| split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2)
                  end as data_length_full
                , split_part(replace(split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2), ')', ''), ',', 1) as data_length
                , split_part(replace(split_part(pg_catalog.format_type(a.atttypid, a.atttypmod), '(', 2), ')', ''), ',', 2) as data_scale
                , case when a.attnum = ANY(con.conkey) then 'Y' else 'N' end                                  as pk_yn
                , case when a.attnotnull or (t.typtype = 'd'::"char" and t.typnotnull) then 'N' else 'Y' end  as null_yn
                , case when d.attrnums is not null then 'Y' else 'N' end                                      as dk_yn
            from
                  pg_class      c
            join  pg_namespace  n on c.relnamespace = n.oid
            join  pg_attribute  a on c.oid = a.attrelid and a.attnum >= 0
            join  pg_type       t on a.atttypid = t.oid
            left  outer join pg_partition_rule      pr  on c.oid = pr.parchildrelid
            left  outer join gp_distribution_policy d   on c.oid = d.localoid and a.attnum = ANY (d.attrnums)
            left  outer join pg_constraint          con on c.oid = con.conrelid
           where
                  c.relkind   = 'r'
             and  pr.parchildrelid is null
             and  n.nspname   in ('edw_dda', 'edw_dw', 'edw_meta')
             and  ( con.contype = 'p' or con.contype is null)
             and  c.relname   = '$Target_Table_Lower'
        ) x
order by
        x.table_name
      , x.column_id
EOF

    func_PrintLog "Executing $Temp_SQL ..."

    $GP_SQL_EXE -AtX -h $GP_Host -U $GP_User -d $GP_DB < $Temp_SQL > $GP_Catalog_Out

    Exit_Code=$?

    rm -f $Temp_SQL
fi


func_PrintLog "Exit Code = $Exit_Code"

if [[ $Exit_Code != 0 ]]; then
    exit $Exit_Code
fi


#-------------------------------------------------------------------------------
#   SQL 실행결과에 Timing, Header 정보 포함되어 있으면, 이를 삭제하고 생성
#-------------------------------------------------------------------------------
Header_On_YN="N"

if head -3 $GP_Catalog_Out | grep "\----------" >/dev/null; then
    Header_On_YN="Y"
fi

if [[ $Print_stdout_YN = "Y" ]]; then
    if [[ $Header_On_YN = "Y" ]]; then
        sed '1,3d' $GP_Catalog_Out | sed '$d' | sed '$d' | sed '$d' | tr -d "'"
    else
        tr -d "'" < $GP_Catalog_Out
    fi
else
    if [[ -z $Target_Table_Lower ]]; then
        if [[ $Header_On_YN = "Y" ]]; then
            sed '1,3d' $GP_Catalog_Out | sed '$d' | sed '$d' | sed '$d' | tr -d "'" > $GP_Catalog_Curr
        else
            tr -d "'" < $GP_Catalog_Out > $GP_Catalog_Curr
        fi
        func_PrintLog "Made $GP_Catalog_Curr"
    else
        if [[ $Header_On_YN = "Y" ]]; then
            sed '1,3d' $GP_Catalog_Out | sed '$d' | sed '$d' | sed '$d' | tr -d "'" > $GP_Catalog_Curr.$Target_Table_Lower
        else
            tr -d "'" < $GP_Catalog_Out > $GP_Catalog_Curr.$Target_Table_Lower
        fi
        func_PrintLog "Made $GP_Catalog_Curr.$Target_Table_Lower"
    fi
fi

exit

#-------------------------------------------------------------------------------
#   End of Line
#-------------------------------------------------------------------------------
