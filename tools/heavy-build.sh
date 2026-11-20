#!/usr/bin/env bash
# Очередь тяжёлых сборок Xraygram: на одном Маке одновременно компилирует
# только одна тема (macOS / iOS / Android), остальные ждут.
#
#   tools/heavy-build.sh <кто> <команда> [аргументы...]
#   tools/heavy-build.sh status
#
# Пример: tools/heavy-build.sh android ./gradlew assembleAfatStandaloneRelease
#
# Держать замок нужно только на долгие шаги (первая сборка, полная пересборка,
# зависимости). Короткие инкрементальные сборки (секунды) можно без него.
# Замок — каталог upstream/.heavy-build.lock (mkdir атомарен), внутри owner.
# Если процесс-владелец умер, замок снимается автоматически.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/upstream/.heavy-build.lock"
mkdir -p "$ROOT/upstream"

owner() { cat "$LOCK/owner" 2>/dev/null; }

if [[ "${1:-}" == "status" ]]; then
	if [[ -d "$LOCK" ]]; then echo "занято: $(owner)"; else echo "свободно"; fi
	exit 0
fi

[[ $# -ge 2 ]] || { echo "usage: $0 <кто> <команда...> | status" >&2; exit 2; }
WHO="$1"; shift

waited=0
while ! mkdir "$LOCK" 2>/dev/null; do
	pid="$(owner | awk '{print $2}')"
	if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
		echo "heavy-build: замок от умершего процесса ($(owner)), снимаю" >&2
		rm -rf "$LOCK"
		continue
	fi
	if (( waited % 60 == 0 )); then
		echo "heavy-build: [$WHO] жду, сейчас собирает: $(owner)" >&2
	fi
	sleep 5
	waited=$((waited + 5))
done

(( waited > 0 )) && echo "heavy-build: [$WHO] дождался очереди через ${waited} с" >&2

# Команду запускаем дочерним процессом и пишем в замок ЕЁ pid: если этот скрипт
# убьют (SIGKILL, закрыли терминал), замок остаётся занятым, пока жива сама сборка.
"$@" &
child=$!
echo "$WHO $child $(date '+%F %T') $*" > "$LOCK/owner"
trap 'kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; rm -rf "$LOCK"; exit 143' INT TERM HUP
wait "$child"
rc=$?
rm -rf "$LOCK"
# Бюджет места (docs/orchestration.md «Место на диске»): после каждой тяжёлой сборки — предупреждение.
"$(dirname "$0")/cleanup.sh" size 2>/dev/null | grep -q "ПРЕВЫШЕН" && \
	echo "heavy-build: upstream/ больше бюджета — сообщи оркестратору (tools/cleanup.sh)" >&2
exit $rc
