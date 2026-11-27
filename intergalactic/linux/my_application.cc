#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

#include <filesystem> 
using namespace std;
using namespace std::filesystem;

namespace {

constexpr char kAppIconChannelName[] = "chat.intergalactic.app/app_icon";

gboolean set_window_icon_from_asset(GtkWindow* window,
                                    const std::string& asset_path) {
  path execDir = canonical(read_symlink("/proc/self/exe")).parent_path();
  path iconPath = execDir / "data/flutter_assets" / asset_path;

  if (!exists(iconPath)) {
    return FALSE;
  }

  GError* error = nullptr;
  gtk_window_set_icon_from_file(window, iconPath.c_str(), &error);

  if (error != nullptr) {
    g_error_free(error);
    return FALSE;
  }

  gtk_window_set_default_icon_from_file(iconPath.c_str(), nullptr);
  return TRUE;
}

void app_icon_method_call_handler(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "setAppIcon") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* asset_path_value =
      args == nullptr ? nullptr : fl_value_lookup_string(args, "assetPath");

  if (self->window == nullptr || asset_path_value == nullptr ||
      fl_value_get_type(asset_path_value) != FL_VALUE_TYPE_STRING) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid_arguments",
                                     "Expected a string assetPath", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  const std::string asset_path = fl_value_get_string(asset_path_value);
  const auto didSetIcon = set_window_icon_from_asset(self->window, asset_path);

  g_autoptr(FlMethodResponse) response = didSetIcon
      ? FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)))
      : FL_METHOD_RESPONSE(fl_method_error_response_new(
            "set_icon_failed", "Failed to update window icon", nullptr));
  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* app_icon_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  
  gtk_window_set_title(window, "Inter Galactic");
  
  const string iconFilename = "assets/images/app_icon/app_icon_rounded.png";
  path execDir = canonical(read_symlink("/proc/self/exe")).parent_path();
  path iconPath = execDir / "data/flutter_assets" / iconFilename;
  gtk_window_set_icon_from_file(GTK_WINDOW(window), iconPath.c_str(), NULL);

  gtk_window_set_default_size(window, 1280, 720);
  gtk_widget_show(GTK_WIDGET(window));

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->app_icon_channel =
      fl_method_channel_new(messenger, kAppIconChannelName,
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->app_icon_channel, app_icon_method_call_handler, self, nullptr);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  
  *exit_status = 0;

  return TRUE;
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->app_icon_channel);
  self->window = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->app_icon_channel = nullptr;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);



  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
