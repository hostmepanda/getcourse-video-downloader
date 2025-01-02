#!/usr/bin/env bash
# Simple script to download videos from GetCourse.ru
# on Linux/*BSD
# Dependencies: bash, coreutils, curl, grep

set -eu
set +f
set -o pipefail

if [ ! -f "$0" ]
then
	a0="$0"
else
	a0="bash $0"
fi

_echo_help(){
	echo "
Первым аргументом должна быть ссылка на плей-лист, найденная в исходном коде страницы сайта GetCourse.
Пример: <video id=\"vgc-player_html5_api\" data-master=\"нужная ссылка\" ... />.
Вторым аргументом должен быть путь к файлу для сохранения скачанного видео, рекомендуемое расширение — ts.
Пример: \"Как скачать видео с GetCourse.ts\"
Скопируйте ссылку и запустите скрипт, например, так:
$a0 \"эта_ссылка\" \"Как скачать видео с GetCourse.ts\"
Инструкция с графическими иллюстрациями здесь: https://github.com/mikhailnov/getcourse-video-downloader
О проблемах в работе сообщайте сюда: https://github.com/mikhailnov/getcourse-video-downloader/issues
"
}

tmpdir="$(umask 077 && mktemp -d)"
export TMPDIR="$tmpdir"
trap 'rm -fr "$tmpdir"' EXIT

if [ -z "${1:-}" ] || \
   [ -z "${2:-}" ] || \
   [ -z "${3:-}" ] || \
   [ -n "${4:-}" ]
then
	_echo_help
	exit 1
fi
URL="$1"
SOUND_LIST="$2"
result_file="$3"

main_playlist="$(mktemp)"
curl -L --output "$main_playlist" "$URL"
second_playlist="$(mktemp)"
# Бывает (я встречал) 2 варианта видео
# Может быть, можно проверять [[ "$URL" =~ .*".m3u8".* ]]
# *.bin то же самое, что *.ts
if grep -qE '^https?:\/\/.*\.(ts|bin)' "$main_playlist" 2>/dev/null
then
	# В плей-листе перечислены напрямую ссылки на фрагменты видео
	# (если запустили проигрывание, зашли в инструменты разработчика Chromium -> Network,
	# нашли файл m3u8 и скопировали ссылку на него)
	cp "$main_playlist" "$second_playlist"
else
	# В плей-листе перечислены ссылки на плей-листы частей видео а разных разрешениях,
	# последним идет самое большое разрешение, его и скачиваем
	tail="$(tail -n1 "$main_playlist")"
	if ! [[ "$tail" =~ ^https?:// ]]; then
		echo "В содержимом заданной ссылки нет прямых ссылок на файлы *.bin (*.ts) (первый вариант),"
		echo "также последняя строка в ней не содержит ссылки на другой плей-лист (второй вариант)."
		echo "Либо указана неправильная ссылка, либо GetCourse изменил алгоритмы."
		echo "Если уверены, что дело в изменившихся алгоритмах GetCourse, опишите проблему здесь:"
		echo "https://github.com/mikhailnov/getcourse-video-downloader/issues (на русском)."
		exit 1
	fi
	curl -L --output "$second_playlist" "$tail"
fi

# Извлечение base_url из входной ссылки
BASE_URL="$(dirname "$tail")/"

MERGED_VIDEO="$tmpdir/merged_video.temp"
MERGED_AUDIO="$tmpdir/merged_audio.temp"

# Входной файл с плейлистом
INPUT_FILE="$second_playlist"
# Выходной файл со списком ссылок
OUTPUT_FILE="$tmpdir/output_links"

# Убедимся, что выходной файл пустой
echo "" > "$OUTPUT_FILE"

# Чтение входного файла и обработка строк
while IFS= read -r line; do
  # Проверяем, заканчивается ли строка на .ts
  if [[ $line == *.ts ]]; then
    # Формируем полный URL и записываем в выходной файл
    echo "${BASE_URL}${line}" >> "$OUTPUT_FILE"
  fi
done < "$INPUT_FILE"

INPUT_FILE="$OUTPUT_FILE"

c=0
while read -r line
do
	if ! [[ "$line" =~ ^http ]]; then continue; fi
	curl --retry 12 -L --output "${tmpdir}/$(printf '%05d' "$c").ts" "$line"
	c=$((++c))
done < "$INPUT_FILE"

cat "$tmpdir"/*.ts > "$MERGED_VIDEO"

SOUND_BASE_URL="$(dirname "$SOUND_LIST")/"
SOUND_OUTPUT_FILE="$tmpdir/sound_links"
SOUND_PLAYLIST="$tmpdir/sound.m3u8"

curl -L --output "$SOUND_PLAYLIST" "$SOUND_LIST"

while IFS= read -r line; do
  # Проверяем, заканчивается ли строка на .ts
  if [[ $line == *.acc ]]; then
    # Формируем полный URL и записываем в выходной файл
    echo "${SOUND_BASE_URL}${line}" >> "$SOUND_OUTPUT_FILE"
  fi
done < "$SOUND_PLAYLIST"

c=0
while read -r line
do
	if ! [[ "$line" =~ ^http ]]; then continue; fi
	curl --retry 12 -L --output "${tmpdir}/$(printf '%05d' "$c").acc" "$line"
	c=$((++c))
done < "$SOUND_OUTPUT_FILE"

cat "$tmpdir"/*.acc > "$MERGED_AUDIO"

echo "Скачивание завершено. Обработка видео и звука"
echo "Совмещаем видео и звук..."

ffmpeg -i "$MERGED_VIDEO" -i "$MERGED_AUDIO" -c:v copy -c:a aac "$result_file"

echo "Готово. Результат здесь:
$result_file"