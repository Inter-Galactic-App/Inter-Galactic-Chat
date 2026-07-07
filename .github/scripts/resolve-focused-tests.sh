#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: resolve-focused-tests.sh <changed-file-list> <resolved-test-list>" >&2
  exit 2
fi

changed_file_list="$1"
resolved_test_list="$2"
project_path="${PROJECT_PATH:-intergalactic}"

if [[ ! -f "$changed_file_list" ]]; then
  echo "::error::Changed-file list does not exist: $changed_file_list" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

declare -a focused_tests=()
run_all_configured=false

add_test() {
  local test_path="$1"
  test_path="${test_path//$'\r'/}"
  test_path="${test_path//\\//}"
  test_path="${test_path#./}"
  test_path="${test_path#${project_path}/}"

  if [[ "$test_path" != test/*_test.dart ]]; then
    echo "::error::Focused test mapping must resolve to a project-relative test path: $test_path" >&2
    exit 1
  fi

  focused_tests+=("$test_path")
}

add_test_glob() {
  local pattern="$1"
  local matched=false
  local match

  shopt -s nullglob globstar
  for match in "$project_path"/$pattern; do
    if [[ -f "$match" ]]; then
      add_test "$match"
      matched=true
    fi
  done
  shopt -u nullglob globstar

  if [[ "$matched" == false ]]; then
    echo "::error::Focused test glob did not match any files: $pattern" >&2
    exit 1
  fi
}

add_voip_tests() {
  add_test_glob "test/client/components/voip/*_test.dart"
  add_test_glob "test/client/components/voip/**/*_test.dart"
}

add_notification_tests() {
  add_test "test/client/components/push_notification/notification_response_handler_test.dart"
  add_test "test/client/components/push_notification/notification_companion_controller_test.dart"
  add_test "test/service/background_service_notifications/background_matrix_wake_limiter_test.dart"
}

add_activity_tests() {
  add_test_glob "test/client/components/activity/*_test.dart"
  add_test "test/ui/organisms/activity/local_activity_panel_test.dart"
}

add_onboarding_demo_tests() {
  add_test "test/ui/onboarding/onboarding_service_test.dart"
  add_test "test/ui/onboarding/onboarding_page_test.dart"
  add_test "test/ui/onboarding/help_tutorial_page_test.dart"
  add_test "test/client/demo/demo_client_test.dart"
}

add_url_media_tests() {
  add_test "test/client/components/url_preview/matrix_url_preview_component_test.dart"
  add_test "test/client/attachment_test.dart"
  add_test "test/config/gif_api_key_store_test.dart"
  add_test "test/ui/molecules/message_input/message_input_emoticon_test.dart"
  add_test "test/ui/molecules/timeline_events/timeline_diagnostics_visibility_test.dart"
  add_test "test/ui/molecules/room_timeline_widget/mobile_chat_scroll_physics_test.dart"
  add_test "test/ui/molecules/room_timeline_widget/room_timeline_widget_view_test.dart"
  add_test "test/photo_album/photo_album_entry_test.dart"
  add_test "test/client/components/soundboard/soundboard_models_test.dart"
}

add_settings_theme_ui_tests() {
  add_test "test/ui/pages/settings/settings_search_test.dart"
  add_test "test/ui/pages/settings/categories/account/settings_category_account_test.dart"
  add_test "test/ui/pages/settings/categories/app/settings_category_app_test.dart"
  add_test "test/ui/pages/settings/categories/app/theme_settings/custom_theme_editor_test.dart"
  add_test "test/config/preferences_theme_test.dart"
  add_test "test/ui/atoms/tiamat_button_layout_test.dart"
  add_test "test/ui/atoms/context_menu_hot_reload_test.dart"
  add_test "test/ui/organisms/background_task_view_test.dart"
}

add_matrix_room_tests() {
  add_test "test/client/components/direct_messages/matrix_direct_messages_component_test.dart"
  add_test "test/client/room_event_settings_test.dart"
  add_test "test/config/message_background_preferences_test.dart"
  add_test "test/client/components/url_preview/matrix_url_preview_component_test.dart"
}

add_diagnostics_tests() {
  add_test "test/client/bug_report/bug_report_service_test.dart"
  add_test "test/debug/diagnostic_log_store_test.dart"
  add_test "test/debug/log_redactor_test.dart"
  add_test "test/ui/molecules/timeline_events/timeline_diagnostics_visibility_test.dart"
}

add_update_download_shortcut_tests() {
  add_test "test/utils/update_checker_test.dart"
  add_test "test/utils/download_utils_test.dart"
  add_test "test/utils/system_wide_shortcuts/navigation_shortcut_test.dart"
  add_test "test/utils/system_wide_shortcuts/system_wide_shortcuts_test.dart"
}

add_space_category_tests() {
  add_test "test/client/space_room_categories_test.dart"
}

add_all_configured_tests() {
  add_voip_tests
  add_notification_tests
  add_activity_tests
  add_onboarding_demo_tests
  add_url_media_tests
  add_settings_theme_ui_tests
  add_matrix_room_tests
  add_diagnostics_tests
  add_update_download_shortcut_tests
  add_space_category_tests
}

while IFS= read -r changed_file || [[ -n "$changed_file" ]]; do
  changed_file="${changed_file//$'\r'/}"
  changed_file="${changed_file//\\//}"
  changed_file="${changed_file#./}"

  if [[ -z "$changed_file" ]]; then
    continue
  fi

  case "$changed_file" in
    .github/workflows/static-analysis.yml|\
    .github/scripts/resolve-focused-tests.sh|\
    analysis_options.yaml|\
    "$project_path"/analysis_options.yaml|\
    pubspec.yaml|\
    pubspec.lock|\
    "$project_path"/pubspec.yaml|\
    "$project_path"/pubspec.lock|\
    */pubspec.yaml|\
    */pubspec.lock)
      run_all_configured=true
      ;;
  esac

  case "$changed_file" in
    "$project_path"/test/*_test.dart|"$project_path"/test/**/*_test.dart)
      add_test "${changed_file#${project_path}/}"
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/components/voip/*|\
    "$project_path"/lib/client/matrix/components/voip/*|\
    "$project_path"/lib/client/matrix/components/voip_room/*|\
    "$project_path"/lib/ui/organisms/call_view/*|\
    plugins/intergalactic_noise_suppression/*|\
    plugins/intergalactic_windows_share/*)
      add_voip_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/components/push_notification/*|\
    "$project_path"/lib/client/matrix/components/push_notifications/*|\
    "$project_path"/lib/service/background_service.dart|\
    "$project_path"/lib/service/background_service_notifications/*|\
    "$project_path"/lib/ui/windows/notification_companion/*|\
    "$project_path"/lib/ui/pages/settings/categories/app/notification_settings/*|\
    "$project_path"/android/app/src/main/*)
      add_notification_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/components/activity/*|\
    "$project_path"/lib/client/matrix/components/user_presence/*|\
    "$project_path"/lib/ui/organisms/activity/*|\
    "$project_path"/lib/ui/pages/settings/categories/app/activity_settings_page.dart)
      add_activity_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/ui/onboarding/*|\
    "$project_path"/lib/ui/pages/settings/categories/help/help_tutorial_page.dart|\
    "$project_path"/lib/client/demo/*)
      add_onboarding_demo_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/attachment.dart|\
    "$project_path"/lib/client/matrix/matrix_attachment.dart|\
    "$project_path"/lib/client/components/url_preview/*|\
    "$project_path"/lib/client/matrix/components/url_preview/*|\
    "$project_path"/lib/client/components/gif/*|\
    "$project_path"/lib/client/matrix/components/gif/*|\
    "$project_path"/lib/config/gif_api_key_store.dart|\
    "$project_path"/lib/ui/molecules/gif_picker.dart|\
    "$project_path"/lib/ui/molecules/message_input.dart|\
    "$project_path"/lib/ui/molecules/message_input/*|\
    "$project_path"/lib/ui/molecules/url_preview_widget.dart|\
    "$project_path"/lib/ui/molecules/timeline_events/*|\
    "$project_path"/lib/ui/molecules/room_timeline_widget/*|\
    "$project_path"/lib/ui/atoms/message_attachment.dart|\
    "$project_path"/lib/ui/organisms/attachment_processor/*|\
    "$project_path"/lib/client/components/soundboard/*)
      add_url_media_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/ui/pages/settings/*|\
    "$project_path"/lib/config/theme_config*|\
    "$project_path"/lib/config/custom_theme*|\
    "$project_path"/lib/config/preferences.dart|\
    "$project_path"/lib/ui/organisms/background_task_view/*|\
    tiamat/lib/atoms/*)
      add_settings_theme_ui_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/space_room_categories.dart|\
    "$project_path"/lib/ui/atoms/space_list.dart|\
    "$project_path"/lib/ui/pages/settings/categories/space/settings_category_space.dart|\
    "$project_path"/lib/ui/pages/settings/categories/space/space_categories_settings_page.dart)
      add_space_category_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/matrix/matrix_client.dart|\
    "$project_path"/lib/client/matrix/matrix_room.dart|\
    "$project_path"/lib/client/room.dart|\
    "$project_path"/lib/client/room_event_settings.dart|\
    "$project_path"/lib/client/components/direct_messages/*|\
    "$project_path"/lib/client/matrix/components/direct_messages/*|\
    "$project_path"/lib/client/matrix/timeline_events/*)
      add_matrix_room_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/client/bug_report/*|\
    "$project_path"/lib/debug/*|\
    "$project_path"/lib/diagnostic/*|\
    "$project_path"/lib/ui/pages/fatal_error/*|\
    "$project_path"/lib/ui/pages/settings/categories/developer/log_page.dart|\
    "$project_path"/lib/ui/pages/settings/categories/help/report_bug_page.dart)
      add_diagnostics_tests
      ;;
  esac

  case "$changed_file" in
    "$project_path"/lib/utils/download_utils.dart|\
    "$project_path"/lib/utils/update_checker*|\
    "$project_path"/lib/utils/shortcuts_manager*|\
    "$project_path"/lib/utils/system_wide_shortcuts/*|\
    "$project_path"/lib/ui/pages/setup/menus/check_for_updates.dart|\
    "$project_path"/lib/ui/pages/settings/categories/app/shortcut_settings/*)
      add_update_download_shortcut_tests
      ;;
  esac
done < "$changed_file_list"

if [[ "$run_all_configured" == true ]]; then
  focused_tests=()
  add_all_configured_tests
fi

mkdir -p "$(dirname "$resolved_test_list")"
printf '%s\n' "${focused_tests[@]}" | awk 'NF' | sort -u > "$resolved_test_list"

missing=false
while IFS= read -r test_path || [[ -n "$test_path" ]]; do
  if [[ ! -f "$project_path/$test_path" ]]; then
    echo "::error::Focused test mapping is stale; missing $project_path/$test_path" >&2
    missing=true
  fi
done < "$resolved_test_list"

if [[ "$missing" == true ]]; then
  exit 1
fi

count="$(wc -l < "$resolved_test_list" | tr -d ' ')"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "count=$count" >> "$GITHUB_OUTPUT"
  echo "path=$resolved_test_list" >> "$GITHUB_OUTPUT"
fi

if [[ "$count" -eq 0 ]]; then
  echo "No focused Flutter tests selected."
else
  echo "Focused Flutter tests:"
  cat "$resolved_test_list"
fi
