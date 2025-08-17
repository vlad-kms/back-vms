#!/bin/bash
# backup to yandex cloud

# получить ключи верхнего уровня
#jq 'keys' cron-bvm.json

USE_DATE_LOG=1

help() {
  echo "
  Usage:
    backup-volume.sh --name NAME_VM --source SRC_VOL --dest DST_DIR
    Params:
      -h, --help             показать справку и выйти
      -g, --config           имя JSON файла конфигурации для VM и CONTAINERS которые требуется резервировать (по умолчанию: cron-vm.json)
      -n, --name             имя VOLUME для резервного копирования
      -d, --dest             путь к каталогу, в который будет сохранен архив
      -s, --source           путь к источнику для резервного копирования
      -c, --create-snapshot  создать snapshot перед резервным копированием

      -l, --log              файл для записи лога, если не указан, то не логировать
      --dry-run              не выполнять команды фактически, только выводить их на экран
      --no-remove-tmp        не удалять временные файлы после архивирования
      --debug                режим отладки
  "
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
  if [[ -n "$_log_file"_ ]]; then
    echo -e "${str_dt}${1}" >> "$_log_file_"
  fi
}

get_json_value() {
  local json_file="$1"
  local section="$2"
  local _key="$3"
  local default="$4"

  if [ ! -f "$json_file" ]; then
    echo "File $json_file not found" 1>&2
    echo ""
    exit 1
  fi

  # local _value=""

  # проверить наличие параметра $2 (section)
  if [[ -n "$section" ]]; then
    # считать значение из json файла в .section.key
    local _value="$(jq -r ".$section.$_key" "$json_file" | sed -E 's/^\s*$//p')"
  else
    # считать значение из json файла в .key, т.е. в корне json файла
    local _value="$(jq -r "$_key" "$json_file" | sed -E 's/^\s*$//p')"
  fi
  if [[ -z "$_value" ]]; then
    # подготовить значение по-умолчанию.
    # Если передан параметр $4 (default), то вернуть это значение и exit 0
    # Если не передан параметр $4 (default), то считать из json файла в секции .default.$_key и вернуть это значение и exit 0
    # Иначе вернуть пустую строку и exit 1
    if [ -z "$default" ]; then
      default="$(jq -r ".default.$_key" "$json_file" | sed -E 's/^\s*$//p')"
    fi
    if [[ -z "$default" ]]; then
      echo ""
      exit 1
    else
      echo "$default"
    fi
  else
    echo "$_value"
  fi
  exit 0
}

######################################################################################
######################################################################################
######################################################################################

if ! args=$(getopt -u -o 'hn:d:s:cl:' --long 'help,name:,dest:,source:,debug,create-snapshot,dry-run,no-remove-tmp,log:' -- "$@"); then
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
      dest=$2;
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
    '--no-remove-tmp')
      _no_remove_tmp_=1
      shift
      ;;
    '-l' | '--log')
      _log_file_="$2"
      shift 2
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
_no_remove_tmp_=${_no_remove_tmp_:=0}
_log_file_=${_log_file_:=''}

if [ $_no_remove_tmp_ -ne 0 ]; then
  flag_remove=""
else
  flag_remove="--remove-files"
fi

debug " BEGIN ========================================================"
debug "Name VOL: $nvm"
debug "Source Snapshot: $src"
debug "Destination0 path: $dest"
debug "dry-run: $_dry_run_"
debug "create-sn: $_create_sn_"
debug "_no_remove_tmp_: $_no_remove_tmp_"
debug "_log_file_: $_log_file_"


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
    # не существует файла архива
    if [ $_dry_run_ -ne 0 ]; then
      echo "zfs send \"$nsp\" > \"${dest_file}\" && tar -cvzf \"${dest_file_arc}\" $flag_remove \"${dest_file}\""
    else
      debug "Send snapshot ${nsp} to file ${dest_file_arv}"
      #zfs send "$nsp" > "${dest_file}" && tar -cvzf "${dest_file_arc}" --remove-files "${dest_file}" 1> /dev/null 2> /dev/null
      zfs send "$nsp" > "${dest_file}" && tar -cvzf "${dest_file_arc}" $flag_remove "${dest_file}" 1> /dev/null 2> /dev/null
    fi
  else
    debug "File ${dest_file_arc} already exists"
  fi
else
  echo "Cannot open ${src}/${nvm}: dataset does not exis"
fi
debug " END =========================================================="

exit 0
