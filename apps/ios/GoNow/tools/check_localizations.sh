#!/bin/sh
set -eu

catalog="apps/ios/GoNow/GoNow/Localization/Localizable.xcstrings"
activity_catalog="apps/ios/GoNow/GoNow/Localization/ActivityMap.xcstrings"
info_catalog="apps/ios/GoNow/GoNow/Localization/InfoPlist.xcstrings"
required_locales='ru en en-US de fr es pt-BR zh-Hans'

jq -e . "$catalog" >/dev/null
jq -e . "$activity_catalog" >/dev/null
jq -e . "$info_catalog" >/dev/null

for locale in $required_locales; do
  for checked_catalog in "$catalog" "$activity_catalog" "$info_catalog"; do
    if ! jq -e --arg locale "$locale" '.strings | to_entries | all(.value.localizations[$locale].stringUnit.value | type == "string" and length > 0)' "$checked_catalog" >/dev/null; then
      echo "Missing an explicit translated value for $locale in $checked_catalog" >&2
      exit 1
    fi
  done
done

for checked_catalog in "$catalog" "$activity_catalog"; do
  if ! jq -e '.strings | to_entries | all(.key as $key | .value.localizations | to_entries | all(.value.stringUnit.value != $key))' "$checked_catalog" >/dev/null; then
    echo "A translation still exposes its semantic key in $checked_catalog" >&2
    exit 1
  fi

  if ! jq -e '
    def placeholders: [scan("%(?:[0-9]+\\$)?(?:@|lld|ld|d|f)")];
    .strings
    | to_entries
    | all(
        .value as $entry
        | ($entry.localizations.en.stringUnit.value | placeholders | sort) as $source
        | ($entry.localizations | to_entries
            | all((.value.stringUnit.value | placeholders | sort) == $source))
      )
  ' "$checked_catalog" >/dev/null; then
    echo "A translation does not preserve the source placeholders in $checked_catalog" >&2
    exit 1
  fi
done

echo "Localization catalogs are valid; every key has all 8 explicit locales."
