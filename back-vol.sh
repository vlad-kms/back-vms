#!/bin/bash

USE_DATE_LOG=1

# получить ключи верхнего уровня
#jq 'keys' cron-bvm.json
# получить все ключи в секции dev-deb-001
#jq '."dev-deb-001" | keys[]' cron-vm.json
#jq '."dev-deb-001".sect1 | keys[]' cron-vm.json

help() {
  echo -e "
  Usage:
    backup-volume.sh --name NAME_VM --source SRC_VOL --dest DST_DIR
  
    Params:
      -h, --help              показать справку и выйти
      -g, --config            имя JSON файла конфигурации для VM и CONTAINERS которые требуется резервировать (по умолчанию: cron-vm.json)
      -n, --name              имя VOLUME для резервного копирования.
                              Если имя не пустое, то резервирование только этой VOLUME, DATASOURCE с переданными в командной строке аргументами.
                              Если имя пустое, то резервируются все VM и CONTAINERS из конфигурационного файла. Остальные аргументы, если переданы,
                              служат значениями по умолчанию для соответствующих параметров из файла конфигурации.
      -d, --dest              путь к каталогу, в который будет сохранен архив (по умолчанию: /mnt/base-pool/vms/backup)
      -s, --source            путь к источнику для резервного копирования (по умолчанию: base-pool/vms)
      -c, --create-snapshot   создать snapshot перед резервным копированием (по умолчанию: 0, не создавать SNAPSHOT)
      -t, --lifetime          время хранения архива в формате: 1m (количество месяцев), 1d (количество дней), 1c (количество файлов) (по умолчанию: 1m, 1 месяц)
      -l, --log               файл для записи лога, если не указан, то не логировать (по умолчанию: '', нет файла для логирования, не вести логи)
      -p, --no-compression    архивировать SNAPSHOT или нет (по умолчанию: 0, архивировать)
      --dry-run               не выполнять команды фактически, только выводить их на экран (по умолчанию: 0, выполнять команды)
      --no-remove-tmp         не удалять временные файлы после архивирования (по умолчанию: 0, удалять врвеменные файлы)
      --debug                 режим отладки (по умолчанию: 0, режим отладки выключен)
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
  if [[ -n "$_log_file_" ]]; then
    echo -e "${str_dt}${1}" >> "$_log_file_"
  fi
}

backup_one_ds () {
  # резервирование одного VOLUME (DATASET)
  # используются глобальные переменные:
  #   $nvm  - имя VOLUME (DATASET)
  #   $dest   - папка назначения
  #   $src    - source VOLUME (DATASET)
  #   $_debug_  - отладка
  #   $_dry_run_  - не выполнять фактически команды
  #   $_create_sn_  - создавать SNAPSHOT
  #   $_no_remove_tmp_  - не удалять временные файлы
  #   $_log_file_ - имя файла логов
  #   $_lifetime_ - время жизни резервных копий
  #   $_compression_  - архивировать или нет резервные копии
  if zfs list -t all -r "${src}/${nvm}" 1>/dev/null 2>/dev/null; then
    # есть dataset с именем $nvm
    if [ $_create_sn_ -ne 0 ]; then
      # создать snapshot, если указан параметр --create-snapshot
      local name_sn_auto="${nvm}$(date +"@auto-%Y-%m-%d_%H-%M")"
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
}

######################################################################################
######################################################################################
######################################################################################

if ! args=$(getopt -u -o 'hn:d:s:cl:g:t:p' --long 'help,name:,dest:,source:,debug,create-snapshot,dry-run,no-remove-tmp,log:,config:,lifetime:,no-compression' -- "$@"); then
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
    '-g' | '--config')
      _config_="$2"
      shift 2
      ;;
    '-t' | '--lifetime')
      _lifetime_=$2
      shift 2
      ;;
    '-p' | '--no-compression')
      _compression_=0
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
  _use_config_=1
  _config_=${_config_:='cron-vm.json'}
else
  _use_config_=0
  _config_=${_config_:='cron-vm.json'}
  dest=${dest:='/mnt/base-pool/backup'}
  src=${src:='base-pool/vms'}
  _debug_=${_debug_:=0}
  _dry_run_=${_dry_run_:=0}
  _create_sn_=${_create_sn_:=0}
  _no_remove_tmp_=${_no_remove_tmp_:=0}
  _log_file_=${_log_file_:=''}
  _lifetime_=${_lifetime_:='1m'}
  _compression_=${_compression_:=1}
  if [ $_no_remove_tmp_ -ne 0 ]; then
    flag_remove=""
  else
    flag_remove="--remove-files"
  fi
fi

debug " BEGIN ========================================================"
debug "_use_config_: $_use_config_; $([ $_use_config_ -eq 0 ] && echo "режим резервирования VOLUME" || echo "режим резервирования по файлу конфигурации")"
debug "_config_: $_config_"
debug "Name VOL: $nvm"

debug "Source Snapshot: $src"
debug "Destination path: $dest"
debug "dry-run: $_dry_run_"
debug "debug: $_debug_"
debug "create-sn: $_create_sn_"
debug "_no_remove_tmp_: $_no_remove_tmp_"
debug "_log_file_: $_log_file_"
debug "_lifetime_: $_lifetime_"
debug "_compression_: $_compression_"

if [ $_use_config_ -eq 1 ]; then
  # резервируем по JSON файлу конфигурации
  echo "резервируем по JSON файлу конфигурации"
else
  # резервируем по имени VOLUME (DATSET) и аргументам командной строки, игнорируя JSON файл конфигурации
  backup_one_ds
fi



exit 0


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
