#!/usr/bin/env sh

## Updated version maintained on https://github.com/nyxnor/scripts/blob/master/toc.sh

## Produces Table of Contents (ToC) for simple markdown files
## Requirement: header is set by hashtag '#'
## $1 = FILE.md

red="\033[31m"
nocolor="\033[0m"

error_msg(){ printf %s"${red}ERROR: ${1}\n${nocolor}" >&2; exit 1; }

test -f "${1}" || error_msg "file '${1}' doesn't exist"

trap 'rm -f toc.tmp' EXIT INT

line_count=0
while IFS="$(printf '\n')" read -r line; do
  line_count=$((line_count+1))
  ## extract code blocks
  code="${code:-0}"
  [ "${code}" -eq 0 ] && printf '%s\n' "${line_count}:${line}" | grep "^${line_count}:.*# "
  case "${line}" in
    *\`\`\`*)
      case "${code}" in
        1) code=0;;
        0|*) code=1;;
      esac
    ;;
  esac
done < "${1}" > toc.tmp


while IFS="$(printf '\n')" read -r line; do
  ## get line number
  line_number="$(printf '%s\n' "${line}" | cut -d ":" -f1)"
  ## remove hashtag from line to be compared later if it is repeated
  line_clean="$(printf '%s\n' "${line}" | sed "s/.*\# //")"
  ## save header to cache to check later if it was already printed
  # shellcheck disable=SC2030
  line_cache="$(printf '%s\n%s\n' "${line_cache}" "${line}")"
  ## check if header was already printed before and if positive, save all repeated headers
  ## if positive, insert link index
  line_repeated="$(printf '%s\n' "${line_cache}" | grep -c -- ".*# ${line_clean}$")"
  line_repeated_index=""
  ## first line does not have '-n', just the first repeated line (second occurence), starting with '-1'. So we consider the occurrence-1.
  [ "${line_repeated}" -ge 2 ] && line_repeated_index="-$((line_repeated-1))"
  ## if it is the second time line has repeated, save first and second occurrence
  if [ "${line_repeated}" -eq 2 ]; then
    line_first_occurrence="$(printf '%s\n' "${line_cache}" | grep -- ".*# ${line_clean}$" | head -n 1)"
    line_repeated_cache="$(printf '%s\n%s\n' "${line_first_occurrence}" "${line}")"
  ## if it is the third or greater time line has repeated, save lines from before (1st and 2nd occurrence) plus add current lines
  elif [ "${line_repeated}" -gt 2 ]; then
    line_repeated_cache="$(printf '%s\n%s\n' "${line_repeated_cache}" "${line}")"
  fi
  ## clean header that have link reference
  line_md="$(printf '%s\n' "${line}" | sed "s/${line_number}://;s|](.*||;s|\[||;s/\]//g")"
  ## set header indentation
  line_md="$(printf '%s\n' "${line_md}" | sed "s|######|            -|;s|#####|         -|;s|####|      -|;s|###|    -|;s|##|  -|;s|#|-|")"
  ## set link content
  line_content="$(printf '%s\n' "${line_md}" | sed "s/.*- /#/;s| |-|g;s|'||g;s|]||g;s/|/-/g" | tr "[:upper:]" "[:lower:]" | tr -cd "[:alnum:]-_" | tr -d ".")"
  ## set link reference
  line_md="$(printf '%s\n' "${line_md}" | sed "s|- |- [|;s|$|](#${line_content}${line_repeated_index})|")"
  ## print header
  printf '%s\n' "${line_md}"
done < toc.tmp

[ -n "${line_repeated_cache}" ] &&
  printf %s"\n\nWARN: Some headers are repeated, the hiperlinks are correctly indexed. If you think this is an error, review these lines:headers:\n${line_repeated_cache}\n"
