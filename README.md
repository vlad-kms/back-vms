Создание snapshot'ов резервных копий-файлов dataset'ов на файловой системе zfs.
usage:
    back-vol.sh --config <FILENAME.JSON>
    back-vol.sh
        --name <NAME_DATASET>
        --dest <PATH_DESTINATION>
        --source <DATASET_SOURCE>
        --lifetime <STR_LIFETIME>
        --log <FILENAME_LOG>
        --create-snapshot
        --no-compression
        --dry-run
        --no-remove-tmp
        --debug
    , где
        <FILENAME.JSON>     - имя JSON файла конфигурации для VM и CONTAINERS которые требуется резервировать (по умолчанию: cron-vm.json)
        <NAME_DATASET>      - имя DATASET для резервного копирования.
        <PATH_DESTINATION>  - путь к каталогу, в который будет сохранен архив (по умолчанию: /mnt/base-pool/vms/backup)
        <DATASET_SOURCE>    - путь к источнику для резервного копирования (по умолчанию: base-pool/vms)
        <STR_LIFETIME>      - время хранения архива в формате:
                                1m  - хранить месяцев,
                                1d  - хранить дней,
                                1w  - хранить недель,
                                d   - не удалаяются устаревшие копии
                              (по умолчанию: 1m, 1 месяц)
        <FILENAME_LOG>      - файл для записи лога, если не указан, то не логировать (по умолчанию: , нет файла для логирования, не вести логи)
