#!/bin/bash
# backup to yandex cloud

USE_DATE_LOG=1

help() {
  str="
  Usage:
    back-to-ya.sh --name NAME_VM --source SRC_VOL --dest DST_DIR
  "
  echo $str
}

debug() {
  if [[ "$USE_DATE_LOG" -ne 0 ]]; then
    str_dt=$(date +"%Y-%m-%d %H:%M:%S")
  else
    str_dt=""
  fi
  if [[ -n "$str_dt" ]]; then
    str_dt="${str_dt}:\t"
  fi
  if [[ $_debug_ -ne 0 ]]; then
    echo -e "${str_dt}${1}" 1>&2
  fi
}

if ! args=$(getopt -u -o 'hn:d:s:c' --long 'help,name:,dest:,source:,debug,create-snapshot,dry-run' -- "$@"); then
  help;
  exit 1
fi
# shellcheck disable=SC2086
set -- $args
i=0
for i; do
  case "$i" in
    '-h' | '--help')
      help;
      exit 0;
      ;;
    '-n' | '--name')
      nvm=$2
      shift 2
      ;;
    '-d' | '--dest')
      dest_=$2;
      shift 2
      ;;
    '-s' | '--source')
      src=$2;
      shift 2
      ;;
    '-c' | '--create-snapshot')
      _create_sn_=1;
      shift
      ;;
    '--debug')
      _debug_=1;
      shift
      ;;
    '--dry-run')
      _dry_run_=1;
      shift
      ;;
    else)
      echo "Неверный параметр:" 1>&2
      echo -e "\t$i" 1>&2
      help;
      exit 0
      ;;
  esac
done

if [ -z $nvm ]; then
  echo "Не указано обязательное имя VOLUME "
  exit 1
fi
dest=${dest:='/mnt/base-pool/yandex/backup/tn'}
src=${src:='base-pool/vms'}
_debug_=${_debug_:=0}
_dry_run_=${_dry_run_:=0}
_create_sn_=${_create_sn_:=0}

debug " BEGIN ========================================================"
debug "Name VOL: $nvm"
debug "Source Snapshot: $src"
debug "Destination0 path: $dest"
debug "dry-run: $_dry_run_"
debug "create-sn: $_create_sn_"

if zfs list -t all -r "${src}/${nvm}" 1>/dev/null 2>/dev/null; then
  # есть dataset с именем $nvm
  if [ $_create_sn_ -ne 0 ]; then
    # создать snapshot, если укзана параметр --create-snapshot
    name_sn_auto="${nvm}$(date +"@auto-%Y-%m-%d_%H-%M")"
    debug "name_sn_auto: ${name_sn_auto}"
    nsp="${src}/${name_sn_auto}"
    if [ $_dry_run_ -ne 0 ]; then
      echo "zfs snapshot ${src}/${name_sn_auto}"
    else
      debug "Create snapshot ${nsp}"
      zfs snapshot "${nsp}"
      if [ $? -ne 0 ]; then
        echo "Error create snapshot ${nsp}"
        exit 1
      fi
    fi
  else
    # не требуется создавать SNAPSHOT
    # ищем последний (по дате создания) Snapshot
    nsp=$(zfs list -t snapshot -r -o name "${src}/${nvm}" | grep -v NAME | sort -k1 | tail -n 1)
  fi
  debug "Snapshot exists (nsp): $nsp"
  nsp_only=$(basename $nsp)
  debug "Snapshot name only (nsp_only): $nsp_only"
  
  # Пишем VOLUME в файл
  dest_file="${dest}/${nsp_only}.zfs"
  dest_file_arc="${dest}/${nsp_only}.zfs.tgz"
  # проверить существование файла архива, и если есть то пропустить
  if [ ! -e "$dest_file_arc" ]; then
    # не существetn файла архива
    if [ $_dry_run_ -ne 0 ]; then
      echo "zfs send \"$nsp\" > \"${dest_file}\" && tar -cvzf \"${dest_file_arc}\" --remove-files \"${dest_file}\""
    else
      debug "Send snapshot ${nsp} to file ${dest_file_arv}"
      zfs send "$nsp" > "${dest_file}" && tar -cvzf "${dest_file_arc}" --remove-files "${dest_file}" 1> /dev/null 2> /dev/null
    fi
  else
    debug "File ${dest_file_arc} already exists"
  fi
else
  echo "Cannot open ${src}/${nvm}: dataset does not exis"
fi
debug " END =========================================================="

exit 0
