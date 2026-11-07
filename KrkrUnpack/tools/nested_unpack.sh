#!/usr/bin/env bash
# 电脑端的等价实现：递归剥壳，只留 krkr 需要的 .xp3/.tjs
# 依赖：p7zip（brew install p7zip / apt install p7zip-full）
set -euo pipefail

IN="${1:?用法: nested_unpack.sh <文件.zip|mp4|rar|7z> [输出目录]}"
OUT="${2:-./out}"
TMP="$(mktemp -d)"

mkdir -p "$OUT"
cp "$IN" "$TMP/input.bin"

# 打印真实格式（不信后缀）
echo "== 文件头 =="
xxd -l 16 "$TMP/input.bin"

depth=1
cur="$TMP/input.bin"
while [[ $depth -le 5 ]]; do
  dir="$TMP/L$depth"
  mkdir -p "$dir"
  if ! 7z x -y -o"$dir" "$cur" >/dev/null 2>&1; then
    echo "第 $depth 层解压失败（可能是分卷 RAR，或需要密码 -p<密码>）"
    break
  fi
  echo "第 $depth 层解压完成"

  # 找下一层压缩包
  next="$(find "$dir" -maxdepth 2 -type f \( -iname '*.rar' -o -iname '*.zip' -o -iname '*.7z' -o -iname '*.mp4' -o -iname '*.tar' -o -iname '*.gz' \) | head -1)"
  [[ -z "$next" ]] && break

  # 如果解出来只有一个压缩包、且它不是伪装本体的 mp4，就继续
  cur="$next"
  depth=$((depth + 1))
done

# 收集 .xp3 / .tjs
find "$TMP" -type f \( -iname '*.xp3' -o -iname '*.tjs' \) -exec cp {} "$OUT"/ \;

echo "== 结果 =="
ls -lh "$OUT"
echo "把 $OUT 里的文件打进 zip，再丢给 VNPlayer 导入"
