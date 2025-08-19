#!/bin/bash

#echo "$(cat cron-bvm.json | jq '.default.asdf')" | sed -E 's/^(\")\s*(\")$/\1\2/p'
# echo "$(cat cron-bvm.json | jq '.default.asdf' | sed -E 's/^(\")\s*(\")$/\1\2/p')"

get_json_value() {
  local json_file="$1"
  local section="$2"
  local _key="$3"
  local default="$4"
  # section обрамить ""
  [[ ! "$section" =~ ^\"(.*)$ ]] && section="\"$section\""
  if [ ! -f "$json_file" ]; then
    echo "File $json_file not found" 1>&2
    echo ""
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
    # Если передан параметр $4 (default), то вернуть это значение и exit 0
    # Если не передан параметр $4 (default), то считать из json файла в секции .default.$_key и вернуть это значение и exit 0
    # Иначе вернуть пустую строку и exit 1
    if [ -z "$default" ]; then
      default="$(jq -r ".default.$_key" "$json_file" | sed -E 's/^\s*$//p')"
    fi
    if [[ -z "$default" ]] || [[ "$default" == "null" ]]; then
      echo ""
    else
      echo "$default"
    fi
  else
    echo "$_value"
  fi
}

# s=$(get_json_value cron-bvm.json "default" "asdf")
# [ -z "$s" ] && echo "res: $s" || echo "$s"
# s=$(get_json_value cron-bvm.json "default" "asd")
# [ -z "$s" ] && echo "res: null" || echo "$s"
# s=$(get_json_value cron-bvm.json "default" "asd" "default_value")
# [ -z "$s" ] && echo "res: null" || echo "$s"

# получить ключи верхнего уровня
#jq 'keys' cron-bvm.json
# получить все ключи в секции dev-deb-001
#jq '."dev-deb-001" | keys[]' cron-vm.json
#jq '."dev-deb-001".sect1 | keys[]' cron-vm.json

jq '."dev-deb-001"' "./cron-vm-deb.json"
vm=dev-deb-001
echo "$vm.Compression: $(get_json_value cron-vm-deb.json "$vm" "Compression")"
echo "$vm.dryRun: $(get_json_value cron-vm-deb.json "$vm" "dryRun")"
echo "$vm.DryRun: $(get_json_value cron-vm-deb.json "$vm" "DryRun")"
echo "$vm.Datasets: $(get_json_value cron-vm-deb.json "$vm" "Datasets")"
echo '---'
ar1=($(get_json_value cron-vm-deb.json "$vm" "Datasets"))
echo "${ar1[0]}"
echo "${ar1[1]}"
echo "Array size: ${#ar1[*]}"