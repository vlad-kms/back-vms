#!/bin/bash

USE_DATE_LOG=1

help() {
  echo -e '
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
      -t, --lifetime          время хранения архива в формате:
                                1m  - хранить месяцев,
                                1d  - хранить дней,
                                1c  - хранить количество файлов,
                                d   - не удалаяются устаревшие копии
                              (по умолчанию: 1m, 1 месяц)
      -l, --log               файл для записи лога, если не указан, то не логировать (по умолчанию: '', нет файла для логирования, не вести логи)
      -p, --no-compression    архивировать SNAPSHOT или нет (по умолчанию: 0, архивировать)
      --dry-run               не выполнять команды фактически, только выводить их на экран (по умолчанию: 0, выполнять команды)
      --no-remove-tmp         не удалять временные файлы после архивирования (по умолчанию: 0, удалять врвеменные файлы)
      --debug                 режим отладки (по умолчанию: 0, режим отладки выключен)

    Описание JSON файла конфигурации:
      {
          // Обязательная секция со значениями по-умолчанию.
          // Если в секции VM (контейнера) нет такого ключа, то значение будем брать из этой секции
          "default": {
            "Enabled": "True",          // включено или нет резервирование
            "LifeTime": "1m",           // удалять (или нет) и срок жизни устаревших резервных копий)
            "AddNameVMToDest": "True",  // добавить имя VM постфиксом к DEST
            "Destination": "1m",        // удалять (или нет): "/mnt/test/vms", // путь куда будем складывать резервные копии
            "Compression": "True",      // включить или нет сжатие
            "Source": "test/ds1/back",  // полный путь к VOLUME (DATASET)
            "Debug": "False",           // вывод отладочной информации
            "DryRun": "False",          // не выполнять фактически команды
            "CreateSnapshot": "True",   // создавать снапшоты или брать последний из ранее созданных
            "NoRemoveTemp": "False",    // не удалять временные файлы
            "Datasets": []              // массив datasets данной VM для резервирования.
                                        // если он пустой (size=0), то dataset == имени секции (VM)
          },
          // секция конкретной vm (container) для резервирования
          // здесь параметр
          "dev-deb-001": {
            "Debug": "True",
            "DryRun": "True"
          },
          "dev-deb-003": {
              "Enabled": "False"
          }
      }
  '
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
  # логирование
  if [[ -n "$_log_file_" ]]; then
    echo -e "${str_dt}${1}" >> "$_log_file_"
  fi
}

_upper() {
  local s=$1
  printf "${s^^}"
}

_lower() {
  local s=$1
  printf "${s,,}"
}

get_json_value() {
  local json_file="$1"
  local section="$2"
  local _key="$3"
  local required="$4"
  local default="$5"
  debug "get_json_value (json_file: $json_file, section: $section, _key: $_key, required: $required, default: $default)"
  # section обрамить ""
  [[ ! "$section" =~ ^\"(.*)$ ]] && section="\"$section\""
  if [ ! -f "$json_file" ]; then
    echo "ERROR: File $json_file not found" 1>&2
    exit 1
  fi
  # проверить наличие параметра $2 (section)
  if [[ -n "$section" ]]; then
    # считать значение из json файла в .section.key
    local _value="$(jq -r ".$section.$_key" "$json_file" | sed -E 's/^\s*$//p')"
  else
    # считать значение из json файла в .key, т.е. в корне json файла
    local _value="$(jq -r "$_key" "$json_file" | sed -E 's/^\s*$//p')"
  fi
  if [[ -z "$_value" ]] || [[ "$_value" == "null" ]]; then
    # подготовить значение по-умолчанию.
    # Если передан параметр $4 (default), то вернуть это значение
    # Если не передан параметр $4 (default), то считать из json файла в секции .default.$_key и вернуть это значение и exit 0
    # Иначе вернуть пустую строку и exit 1
    if [ -z "$default" ]; then
      default="$(jq -r ".default.$_key" "$json_file" | sed -E 's/^\s*$//p')"
    fi
    if [[ -z "$default" ]] || [[ "$default" == "null" ]]; then
      if [[ $required -ne 0 ]]; then
        echo "ERROR: значение $_key не может быть неопределенным" >&2
        exit 1
      else
        default=''
      fi
    fi
    echo "$default"
  else
    echo "$_value"
  fi
}

backup_one_ds () {
  # резервирование одного VOLUME (DATASET)
  # $1  - $nvm                  ; имя VOLUME (DATASET)
  # $2  - $dest                 ; папка назначения
  # $3  - $src                  ; source VOLUME (DATASET)
  # $4  - $_debug               ; отладка
  # $5  - $_dry_run_            ; не выполнять фактически команды
  # $6  - $_create_sn_          ; создавать SNAPSHOT
  # $7  - $_no_remove_tmp_      ; не удалять временные файлы
  # $8  - $_lifetime_           ; имя файла логов
  # $9  - $_compression_        ; время жизни резервных копий
  # $10 - $_add_namevm_to_dest_ ; добавлять к DEST имя VM
  debug "BEGIN BACKUP VOLUME (DATASET) ======================================================="
  local _l_nvm_="$1"
  local _l_dest_="$2"
  local _l_src_="$3"
  local _l_debug_=$4
  local _l_dry_run_=$5
  local _l_create_sn_=$6
  local _l_no_remove_tmp_=$7
  local _l_lifetime_="$8"
  local _l_compression_=${9}
  local _l_add_namevm_to_dest_=${10}
  debug "_l_nvm_: ${_l_nvm_}"
  debug "_l_dest_: ${_l_dest_}"
  debug "_l_src_: ${_l_src_}"
  debug "_l_debug_: ${_l_debug_}"
  debug "_l_dry_run_: ${_l_dry_run_}"
  debug "_l_create_sn_: ${_l_create_sn_}"
  debug "_l_no_remove_tmp_: ${_l_no_remove_tmp_}"
  debug "_l_lifetime_: ${_l_lifetime_}"
  debug "_l_compression_: ${_l_compression_}"
  debug "_l_add_namevm_to_dest_: ${_l_add_namevm_to_dest_}"

  local nsp=""
  if zfs list -t all -r "${_l_src_}/${_l_nvm_}" 1>/dev/null 2>/dev/null; then
    # есть dataset с именем $nvm
    if [[ ${_l_create_sn_} -ne 0 ]]; then
      # создать snapshot, если указан параметр --create-snapshot
      local name_sn_auto="${_l_nvm_}$(date +"@auto-%Y-%m-%d_%H-%M")"
      debug "name_sn_auto: ${name_sn_auto}"
      nsp="${_l_src_}/${name_sn_auto}"
      debug "Create snapshot ${nsp}"
      if [[ $_l_dry_run_ -ne 0 ]]; then
        debug "%%% CMD %%% ::: zfs snapshot ${_l_src_}/${name_sn_auto}"
        #echo "zfs snapshot ${_l_src_}/${name_sn_auto}"
      else
        zfs snapshot "${nsp}"
        if [ $? -ne 0 ]; then
          echo "Error create snapshot ${nsp}"
          exit 1
        fi
      fi
    else
      # не требуется создавать SNAPSHOT
      # ищем последний (по дате создания) Snapshot
      nsp=$(zfs list -t snapshot -r -o name "${_l_src_}/${_l_nvm_}" | grep -v NAME | sort -k1 | tail -n 1)
    fi
    [ -z $nsp ] && {
      debug "Snapshot not exists. Abort execution."; exit 1
    } || debug "Snapshot exists (nsp): $nsp"
    local nsp_only=$(basename $nsp)
    debug "Snapshot name only (nsp_only): $nsp_only"
    
    # Пишем VOLUME в файл
    local dest_file="${_l_dest_}/${nsp_only}.zfs"
    debug "Save snapshot ${nsp} into file ${dest_file}"
    if [[ ${_l_dry_run_} -ne 0 ]]; then
      debug "%%% CMD %%% ::: zfs send \"$nsp\" > \"${dest_file}\""
      #echo "zfs send \"$nsp\" > \"${dest_file}\""
    else
      zfs send "$nsp" > "${dest_file}"
    fi
    # архивируем, если аргумент _compression_ != 0
    if [[ $_l_compression_ -eq 1 ]]; then
      if [[ $_l_no_remove_tmp_ -ne 0 ]]; then
        local flag_remove=""
      else
        local flag_remove="--remove-files"
      fi
      local dest_file_arc="${dest_file}.tgz"
      # проверить существование файла архива, и если есть то удалить
      if [[ -e "$dest_file_arc" ]]; then
        rm --force "$dest_file_arc"
      fi
      # архивируем файл резервной копии
      debug "Archiving the backup copy ${dest_file} to file ${dest_file_arc}"
      if [[ $_l_dry_run_ -ne 0 ]]; then
        debug "%%% CMD %%% ::: tar -cvzf \"${dest_file_arc}\" $flag_remove \"${dest_file}\""
        #echo "tar -cvzf \"${dest_file_arc}\" $flag_remove \"${dest_file}\""
      else
        tar -cvzf "${dest_file_arc}" $flag_remove "${dest_file}" 1> /dev/null 2> /dev/null
      fi
    fi
  else
    echo "Cannot open ${_l_src_}/${_l_nvm_}: dataset does not exis"
  fi
  debug "END BACKUP VOLUME (DATASET) ========================================================="
}

backup_from_config () {
  # $1 - имя файла конфигурации
  #   Глобальные переменные, если определены, то будут значениями по-умолчанию
  #   $dest           - папка назначения
  #   $src            - source VOLUME (DATASET)
  #   $_debug_        - отладка
  #   $_dry_run_      - выполнять фактически команды
  #   $_create_sn_    - создавать SNAPSHOT
  #   $_no_remove_tmp_  - не удалять временные файлы
  #   $_log_file_     - имя файла логов
  #   $_lifetime_     - время жизни резервных копий
  #   $_compression_  - архивировать или нет резервные копии
  
  [[ -z $1 ]] && {
    echo "Не передано имя файла конфигурации" 1>&2
    exit 1
  }
  [[ ! -f $1 ]] && {
    echo "Файл конфигурации ${1} не существует" 1>&2
    exit 1
  }
  local cfg="${1}"
  # проверить синтаксис JSON файла
  debug "Проверить синтаксис JSON файла конфигурации ${cgf}"
  if ! jq '.' "${cfg}" 2>&1 > /dev/null ; then
    err=$(jq '.' "${cfg}" 2>&1)
    echo -e "ERROR: ошибка синтаксиса JSON файла ${cfg}\n    ${err}" >&2;
    exit 1
  fi
  # считать все ключи верхнего уровня и преобразовать в массив bash,
  # т.е. это VM's (containers) для резервного копирования
  debug "Считать имена всех VM для резервирования и преобразовать в массив bash"
  local keys=($(jq 'keys[]' "${cfg}"))
  debug "Общее количество VM, кандидатов на резервирование: $((${#keys[*]} - 1))"
  vm_count=0
  for v in ${keys[@]}; do
    if [[ "$v" != "\"default\"" ]]; then
      debug "--- Подготовка к резервированию ${v}"
      # убрать обрамляющие двойные кавычки, если они есть
      local _v1=$(echo "$v" | sed -En 's/^["]?([^"]*)["]?$/\1/p')
      local _curr_enabled=$(_lower "$(get_json_value "$cfg" "$v" "Enabled" 1)")
      local _curr_lifetime=$(_lower "$(get_json_value "$cfg" "$v" "LifeTime" 1 "${_lifetime_}")")
      local _curr_destination=$(get_json_value "$cfg" "$v"  "Destination" 1 "${dest}")
      local _curr_compression=$(_lower "$(get_json_value "$cfg" "$v" "Compression" 1 "${_compression_}")")
      if [[ "$_curr_compression" == "true" ]]; then
        _curr_compression=1
      elif [[ "$_curr_compression" == "false" ]]; then
        _curr_compression=0
      #else
      #  _curr_compression=$_curr_compression
      fi
      local _curr_source=$(get_json_value "$cfg" "$v" "Source" 1 "${src}")
      local _curr_debug=$(_lower "$(get_json_value "$cfg" "$v" "Debug" 1 "$_debug_")")
      if [[ "$_curr_debug" == "true" ]]; then
        _curr_debug=1
      elif [[ "$_curr_debug" == "false" ]]; then
        _curr_debug=0
      fi
      local _curr_dry_run=$(_lower "$(get_json_value "$cfg" "$v" "DryRun" 1 "$_dry_run_")")
      if [[ "$_curr_dry_run" == "true" ]]; then
        _curr_dry_run=1
      elif [[ "$_curr_dry_run" == "false" ]]; then
        _curr_dry_run=0
      fi
      local _curr_create_sn=$(_lower "$(get_json_value "$cfg" "$v" "CreateSnapshot" 1 "$_create_sn_")")
      if [[ "$_curr_create_sn" == "true" ]]; then
        _curr_create_sn=1
      elif [[ "$_curr_create_sn" == "false" ]]; then
        _curr_create_sn=0
      fi
      local _curr_no_remove_tmp=$(_lower "$(get_json_value "$cfg" "$v" "NoRemoveTemp" 1 "$_no_remove_tmp_")")
      if [[ "$_curr_no_remove_tmp" == "true" ]]; then
        _curr_no_remove_tmp=1
      elif [[ "$_curr_no_remove_tmp" == "true" ]]; then
        _curr_no_remove_tmp=0
      fi
      local _curr_datasets=($(echo "$(get_json_value "$cfg" "$v" "Datasets" 1)" | jq '.[]'))
      local _curr_add_namevm_to_dest=$(_lower "$(get_json_value "$cfg" "$v" "AddNameVMToDest" 1 "$_add_namevm_to_dest")")
      if [[ "$_curr_add_namevm_to_dest" == "true" ]]; then
        _curr_add_namevm_to_dest=1
      elif [[ "$_curr_add_namevm_to_dest" == "true" ]]; then
        _curr_add_namevm_to_dest=0
      fi
      local _curr_name=''
      # Если требуется, то добавлять имя VM к DESTINATION
      [[ $_curr_add_namevm_to_dest -ne 0 ]] && {
        _curr_destination="${_curr_destination}/${_v1}"

        if [[ ${_curr_dry_run} -ne 0 ]]; then
          debug "%%% CMD %%% ::: mkdir -p \"${_curr_destination}\""
          #echo "zfs send \"$nsp\" > \"${dest_file}\""
        else
          mkdir -p "${_curr_destination}"
        fi
      }
      #
      debug "_curr_enabled: $_curr_enabled"
      debug "_curr_lifetime: $_curr_lifetime"
      debug "_curr_destination: $_curr_destination"
      debug "_curr_compression: $_curr_compression"
      debug "_curr_source :$_curr_source"
      debug "_curr_debug: $_curr_debug"
      debug "_curr_dry_run: $_curr_dry_run"
      debug "_curr_create_sn: $_curr_create_sn"
      debug "_curr_no_remove_tmp: $_curr_no_remove_tmp"
      debug "_curr_datasets: ${_curr_datasets[*]}"
      debug "_curr_add_namevm_to_dest: ${_curr_add_namevm_to_dest}"
      # Эта VM подлежит резервированию
      if [[ "$_curr_enabled" == 'true' ]]; then
        debug "Данная VM ${v} подлежит резервированию"
        if [[ ${#_curr_datasets[*]} -eq 0 ]]; then
          _curr_datasets=($v)
        fi
        local _ds_=''
        for _ds_ in ${_curr_datasets[@]}; do
          # убрать обрамляющие двойные кавычки, если они есть
          _ds_=$(echo "$_ds_" | sed -En 's/^["]?([^"]*)["]?$/\1/p')
          debug "Резервируем VOLUME (DATASET) $_ds_"
          if [[ "$(basename "$_ds_")" != "$_ds_" ]]; then
            _curr_source=$(dirname "$_ds_");
            _curr_name=$(basename "$_ds_")
          else
            _curr_name="$_ds_"
          fi
          # $1  - $_curr_name         ; имя VOLUME (DATASET)
          # $2  - $_curr_destination  ; папка назначения
          # $3  - $_curr_source       ; source VOLUME (DATASET)
          # $4  - $_curr_debug        ; отладка
          # $5  - $_curr_dry_run      ; не выполнять фактически команды
          # $6  - $_curr_create_sn    ; создавать SNAPSHOT
          # $7  - $_curr_no_remove_tmp; не удалять временные файлы
          # $8  - $_curr_lifetime     ; время жизни резервных копий
          # $9  - $_curr_compression  ; архивировать или нет резервные копии
          # $10 - $_curr_add_namevm_to_dest ; добавлять к DEST имя VM
          debug "backup_one_ds
                          nvm:\"$_curr_name\"
                          dest:\"$_curr_destination\"
                          src:\"$_curr_source\"
                          debug:$_curr_debug
                          dry_run:$_curr_dry_run
                          create_sn:$_curr_create_sn
                          no_remove_tmp:$_curr_no_remove_tmp
                          lifitime:\"$_curr_lifetime\"
                          compression:$_curr_compression
                          add_namevm_to_dest:$_curr_add_namevm_to_dest"
          backup_one_ds \
            "$_curr_name" \
            "$_curr_destination" \
            "$_curr_source" \
            $_curr_debug \
            $_curr_dry_run \
            $_curr_create_sn \
            $_curr_no_remove_tmp \
            "$_curr_lifetime" \
            $_curr_compression \
            $_curr_add_namevm_to_dest
        done
        # инкремент счетчика зарезервированных VM
        vm_count=$(( ${vm_count} + 1 ))
      fi
    fi
  done
  debug "Количество зарезервированных VM: ${vm_count}"
  #local json_file="$1"
  #local section="$2"
  #local _key="$3"
  #local default="$4"

}

######################################################################################
######################################################################################
######################################################################################
[ -z $(which jq) ] && {
  echo -e "ERROR: не существует команды jq. Сначала установите пакет jq, например:\n  apt install jq\n    ||\n  apk add jq" >&2
  exit 1
}
if ! args=$(getopt -u -o 'hn:d:s:cl:g:t:pa' --long 'help,name:,dest:,source:,debug,create-snapshot,dry-run,no-remove-tmp,log:,config:,lifetime:,no-compression,add-namevm-to-dest' -- "$@"); then
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
      _debug_=1
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
    '-a' | '--add-namevm-to-dest')
      _add_namevm_to_dest_=1
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
  _add_namevm_to_dest_=${_add_namevm_to_dest_:=0}
fi

debug " BEGIN ========================================================"
debug "_use_config_: $_use_config_; $([ $_use_config_ -eq 0 ] && echo "режим резервирования VOLUME" || echo "режим резервирования по файлу конфигурации")"
debug "_config_: $_config_"
debug "Name VOL: $nvm"

debug "Source: $src"
debug "Destination path:= $dest"
debug "dry-run: $_dry_run_"
debug "debug: $_debug_"
debug "_create_sn_: $_create_sn_"
debug "_no_remove_: $_no_remove_tmp_"
debug "_log_file_: $_log_file_"
debug "_lifetime_: $_lifetime_"
debug "_compression_: $_compression_"
debug "_add_namevm_to_dest_: $_add_namevm_to_dest_"

if [ $_use_config_ -eq 1 ]; then
  # резервируем по JSON файлу конфигурации
  debug "Резервируем все DATASET's из JSON файлу конфигурации ${_config_}"
  backup_from_config "${_config_}"
else
  # резервируем по имени VOLUME (DATSET) и аргументам командной строки, игнорируя JSON файл конфигурации
  debug "Резервируем VOLUME (DATASET) ${src}/${nvm}"
  # $1  - $nvm            ; имя VOLUME (DATASET)
  # $2  - $dest           ; папка назначения
  # $3  - $src            ; source VOLUME (DATASET)
  # $4  - $_debug_        ; отладка
  # $5  - $_dry_run_      ; не выполнять фактически команды
  # $6  - $_create_sn_    ; создавать SNAPSHOT
  # $7  - $_no_remove_tmp_  ; не удалять временные файлы
  # $8  - $_lifetime_     ; время жизни резервных копий
  # $9  - $_compression_  ; архивировать или нет резервные копии
  # $10 - $_add_namevm_to_dest_ ; добавлять к DEST имя VM
  backup_one_ds "$nvm" "$dest" "$src" $_debug_ $_dry_run_ $_create_sn_ $_no_remove_tmp_ "$_lifetime_" $_compression_ $_add_namevm_to_dest_
fi

exit 0
